import Combine
import Foundation
import MWDATCamera
import MWDATCore
import SwiftData
import UIKit

struct WearablesDebugEvent: Identifiable {
    let id = UUID()
    let timestamp: Date
    let name: String
    let metadata: [String: String]
    let isButtonLike: Bool
    let isManualMarker: Bool
}

@MainActor
final class WearablesManager: ObservableObject {
    @Published private(set) var registrationStateText: String = "unknown"
    @Published private(set) var cameraPermissionText: String = "unknown"
    @Published private(set) var connectedDeviceCount: Int = 0
    @Published private(set) var configSummary: String = ""
    @Published private(set) var streamStateText: String = "stopped"
    @Published private(set) var isStreaming: Bool = false
    @Published private(set) var latestFrame: UIImage?
    @Published private(set) var latestPhotoCaptureAt: Date?
    @Published private(set) var lastCallbackHandledAt: Date?
    @Published private(set) var lastError: String?
    @Published private(set) var isBusy: Bool = false
    @Published private(set) var debugEvents: [WearablesDebugEvent] = []
    @Published private(set) var buttonLikeEventDetected: Bool = false

    private var streamSession: StreamSession?
    private var streamStateToken: Any?
    private var videoFrameToken: Any?
    private var photoDataToken: Any?
    private var activityPipeline: ActivityPipeline?
    private var previousStreamStateNormalized: String?
    private var lastAppInitiatedSessionControlAt: Date?
    private var lastVideoFrameLogAt: Date?
    private let debugEventLimit: Int = 60

    init(autoConfigure: Bool = true) {
        configSummary = readMWDATConfigSummary()
        if autoConfigure {
            configureWearables()
        }
        observeWearablesState()
    }

    func configurePipelineIfNeeded(modelContext: ModelContext) {
        guard activityPipeline == nil else { return }
        let store = SwiftDataActivityStore(modelContext: modelContext)
        activityPipeline = ActivityPipeline(
            inferenceClient: MockInferenceClient(),
            store: store
        )
    }

    func handleIncomingURL(_ url: URL) {
        guard url.scheme == "polmeta" else { return }
        guard isWearablesActionURL(url) else { return }
        recordDebugEvent(
            "incoming_url",
            metadata: ["host": url.host ?? "<none>", "path": url.path]
        )

        Task {
            do {
                _ = try await Wearables.shared.handleUrl(url)
                lastCallbackHandledAt = Date()
                lastError = nil
                recordDebugEvent("handle_url_success")
                await refreshCameraPermission()
            } catch let error as WearablesHandleURLError {
                lastError = "Failed to handle wearables callback: \(error.description)"
                recordDebugEvent("handle_url_error", metadata: ["error": error.description])
            } catch let error as RegistrationError {
                lastError = "Failed to handle wearables callback: \(error.description)"
                recordDebugEvent("handle_url_error", metadata: ["error": error.description])
            } catch {
                lastError = formatError("Failed to handle wearables callback", error)
                recordDebugEvent("handle_url_error", metadata: ["error": error.localizedDescription])
            }
        }
    }

    func startRegistration() async {
        guard registrationStateText.lowercased() != "registering" else { return }
        recordDebugEvent("start_registration_requested")

        isBusy = true
        defer { isBusy = false }

        guard canOpenMetaAIApp() else {
            lastError = "Failed to start registration: Meta AI app is not available via fb-viewapp://. Install/update Meta AI app and verify LSApplicationQueriesSchemes."
            return
        }

        do {
            try await Wearables.shared.startRegistration()
            lastError = nil
        } catch let error as RegistrationError {
            lastError = "Failed to start registration: \(error.description)"
        } catch {
            lastError = formatError("Failed to start registration", error)
        }
    }

    func startUnregistration() async {
        recordDebugEvent("start_unregistration_requested")
        isBusy = true
        defer { isBusy = false }

        guard canOpenMetaAIApp() else {
            lastError = "Failed to start unregistration: Meta AI app is not available via fb-viewapp://."
            return
        }

        do {
            try await Wearables.shared.startUnregistration()
            lastError = nil
        } catch let error as UnregistrationError {
            lastError = "Failed to start unregistration: \(error.description)"
        } catch {
            lastError = formatError("Failed to start unregistration", error)
        }
    }

    func refreshCameraPermission() async {
        recordDebugEvent("check_camera_permission_requested")
        isBusy = true
        defer { isBusy = false }

        do {
            let status = try await Wearables.shared.checkPermissionStatus(.camera)
            cameraPermissionText = String(describing: status)
            lastError = nil
        } catch {
            lastError = formatError("Failed to check camera permission", error)
        }
    }

    func requestCameraPermission() async {
        recordDebugEvent("request_camera_permission_requested")
        isBusy = true
        defer { isBusy = false }

        do {
            let status = try await Wearables.shared.requestPermission(.camera)
            cameraPermissionText = String(describing: status)
            lastError = nil
        } catch {
            lastError = formatError("Failed to request camera permission", error)
        }
    }

    func startCameraStream() async {
        lastAppInitiatedSessionControlAt = Date()
        recordDebugEvent("start_stream_requested")
        isBusy = true
        defer { isBusy = false }

        do {
            let status = try await Wearables.shared.checkPermissionStatus(.camera)
            cameraPermissionText = String(describing: status)
            if !isPermissionGranted(status) {
                let requested = try await Wearables.shared.requestPermission(.camera)
                cameraPermissionText = String(describing: requested)
                guard isPermissionGranted(requested) else {
                    lastError = "Camera permission not granted. Complete permission flow in Meta AI app and retry."
                    return
                }
            }

            let session = try makeOrReuseSession()
            await session.start()
            lastError = nil
        } catch {
            lastError = formatError("Failed to start camera stream", error)
        }
    }

    func stopCameraStream() async {
        lastAppInitiatedSessionControlAt = Date()
        recordDebugEvent("stop_stream_requested")
        isBusy = true
        defer { isBusy = false }

        guard let session = streamSession else { return }
        await session.stop()
    }

    func capturePhoto() {
        guard let session = streamSession, isStreaming else {
            lastError = "Capture requires an active streaming session."
            return
        }

        recordDebugEvent("capture_photo_requested")
        session.capturePhoto(format: .jpeg)
    }

    func markManualButtonPress() {
        recordDebugEvent("manual_button_press_marker", isManualMarker: true)
    }

    func clearDebugEvents() {
        debugEvents.removeAll()
        buttonLikeEventDetected = false
    }

    private func observeWearablesState() {
        Task {
            for await state in Wearables.shared.registrationStateStream() {
                registrationStateText = String(describing: state)
                recordDebugEvent(
                    "registration_state",
                    metadata: ["value": registrationStateText]
                )
            }
        }

        Task {
            for await devices in Wearables.shared.devicesStream() {
                connectedDeviceCount = devices.count
                recordDebugEvent(
                    "devices_changed",
                    metadata: ["count": "\(connectedDeviceCount)"]
                )
            }
        }
    }

    private func makeOrReuseSession() throws -> StreamSession {
        if let existing = streamSession {
            return existing
        }

        let selector = AutoDeviceSelector(wearables: Wearables.shared)
        let config = StreamSessionConfig(
            videoCodec: .raw,
            resolution: .low,
            frameRate: 24
        )
        let session = StreamSession(streamSessionConfig: config, deviceSelector: selector)
        bindSessionCallbacks(session)
        streamSession = session
        return session
    }

    private func bindSessionCallbacks(_ session: StreamSession) {
        streamStateToken = session.statePublisher.listen { [weak self] state in
            guard let self else { return }
            Task { @MainActor in
                let previous = self.previousStreamStateNormalized
                self.streamStateText = String(describing: state)
                let normalized = self.streamStateText.lowercased()
                let isButtonLike = self.isLikelyUserGestureTransition(
                    from: previous,
                    to: normalized
                )
                self.isStreaming = normalized == "streaming"
                self.previousStreamStateNormalized = normalized
                self.recordDebugEvent(
                    "stream_state",
                    metadata: ["from": previous ?? "<none>", "to": normalized],
                    isButtonLike: isButtonLike
                )
            }
        }

        videoFrameToken = session.videoFramePublisher.listen { [weak self] frame in
            guard let self, let image = frame.makeUIImage() else { return }
            Task { @MainActor in
                self.latestFrame = image
                let now = Date()
                if let lastLogAt = self.lastVideoFrameLogAt, now.timeIntervalSince(lastLogAt) < 1 {
                    return
                }
                self.lastVideoFrameLogAt = now
                self.recordDebugEvent("video_frame")
            }
        }

        photoDataToken = session.photoDataPublisher.listen { [weak self] photoData in
            guard let self else { return }
            Task { @MainActor in
                let capturedAt = Date()
                self.latestPhotoCaptureAt = capturedAt
                self.recordDebugEvent(
                    "photo_data",
                    metadata: ["bytes": "\(photoData.data.count)"]
                )

                guard let pipeline = self.activityPipeline else {
                    self.lastError = "Activity pipeline is not configured."
                    return
                }

                do {
                    try await pipeline.processPhotoCapture(photoData: photoData.data, capturedAt: capturedAt)
                    self.lastError = nil
                    self.recordDebugEvent("photo_pipeline_success")
                } catch {
                    self.lastError = self.formatError("Failed to process captured photo", error)
                    self.recordDebugEvent(
                        "photo_pipeline_error",
                        metadata: ["error": error.localizedDescription]
                    )
                }
            }
        }
    }

    private func isLikelyUserGestureTransition(from: String?, to: String) -> Bool {
        guard from == "streaming", to == "paused" || to == "stopped" else {
            return false
        }
        if let lastControlAt = lastAppInitiatedSessionControlAt {
            let elapsed = Date().timeIntervalSince(lastControlAt)
            if elapsed < 2 {
                return false
            }
        }
        return true
    }

    private func recordDebugEvent(
        _ name: String,
        metadata: [String: String] = [:],
        isButtonLike: Bool = false,
        isManualMarker: Bool = false
    ) {
        let event = WearablesDebugEvent(
            timestamp: Date(),
            name: name,
            metadata: metadata,
            isButtonLike: isButtonLike,
            isManualMarker: isManualMarker
        )
        debugEvents.insert(event, at: 0)
        if debugEvents.count > debugEventLimit {
            debugEvents.removeLast(debugEvents.count - debugEventLimit)
        }
        if isButtonLike {
            buttonLikeEventDetected = true
        }
    }

    private func isPermissionGranted(_ status: PermissionStatus) -> Bool {
        String(describing: status).lowercased() == "granted"
    }

    private func isWearablesActionURL(_ url: URL) -> Bool {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            return false
        }
        return components.queryItems?.contains(where: { $0.name == "metaWearablesAction" }) == true
    }

    private func canOpenMetaAIApp() -> Bool {
        guard let url = URL(string: "fb-viewapp://") else { return false }
        return UIApplication.shared.canOpenURL(url)
    }

    private func readMWDATConfigSummary() -> String {
        guard
            let config = Bundle.main.object(forInfoDictionaryKey: "MWDAT") as? [String: Any]
        else {
            return "MWDAT missing"
        }

        let scheme = (config["AppLinkURLScheme"] as? String) ?? "<missing>"
        let appId = (config["MetaAppID"] as? String) ?? "<missing>"
        let teamId = (config["TeamID"] as? String) ?? "<missing>"
        let clientTokenRaw = (config["ClientToken"] as? String) ?? "<missing>"
        let tokenState: String
        if clientTokenRaw.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            tokenState = "empty"
        } else if clientTokenRaw.contains("$(") {
            tokenState = "unresolved"
        } else {
            tokenState = "set"
        }
        return "scheme=\(scheme), appId=\(appId), teamId=\(teamId), clientToken=\(tokenState)"
    }

    private func formatError(_ prefix: String, _ error: Error) -> String {
        let nsError = error as NSError
        return "\(prefix): \(error.localizedDescription) [\(nsError.domain):\(nsError.code)]"
    }

    private func configureWearables() {
        do {
            try Wearables.configure()
        } catch {
            lastError = formatError("Failed to configure Wearables SDK", error)
            assertionFailure("Failed to configure Wearables SDK: \(error)")
        }
    }
}
