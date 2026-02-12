import Foundation
import MWDATCamera
import MWDATCore
import SwiftData
import UIKit

@MainActor
final class WearablesManager: ObservableObject {
    @Published private(set) var registrationStateText: String = "unknown"
    @Published private(set) var cameraPermissionText: String = "unknown"
    @Published private(set) var connectedDeviceCount: Int = 0
    @Published private(set) var streamStateText: String = "stopped"
    @Published private(set) var isStreaming: Bool = false
    @Published private(set) var latestFrame: UIImage?
    @Published private(set) var latestPhotoCaptureAt: Date?
    @Published private(set) var lastCallbackHandledAt: Date?
    @Published private(set) var lastError: String?
    @Published private(set) var isBusy: Bool = false

    private var streamSession: StreamSession?
    private var streamStateToken: Any?
    private var videoFrameToken: Any?
    private var photoDataToken: Any?
    private var activityPipeline: ActivityPipeline?

    init(autoConfigure: Bool = true) {
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

        Task {
            do {
                _ = try await Wearables.shared.handleUrl(url)
                lastCallbackHandledAt = Date()
                lastError = nil
            } catch {
                lastError = "Failed to handle wearables callback: \(error.localizedDescription)"
            }
        }
    }

    func startRegistration() {
        isBusy = true
        defer { isBusy = false }

        do {
            try Wearables.shared.startRegistration()
            lastError = nil
        } catch {
            lastError = "Failed to start registration: \(error.localizedDescription)"
        }
    }

    func startUnregistration() {
        isBusy = true
        defer { isBusy = false }

        do {
            try Wearables.shared.startUnregistration()
            lastError = nil
        } catch {
            lastError = "Failed to start unregistration: \(error.localizedDescription)"
        }
    }

    func refreshCameraPermission() async {
        isBusy = true
        defer { isBusy = false }

        do {
            let status = try await Wearables.shared.checkPermissionStatus(.camera)
            cameraPermissionText = String(describing: status)
            lastError = nil
        } catch {
            lastError = "Failed to check camera permission: \(error.localizedDescription)"
        }
    }

    func requestCameraPermission() async {
        isBusy = true
        defer { isBusy = false }

        do {
            let status = try await Wearables.shared.requestPermission(.camera)
            cameraPermissionText = String(describing: status)
            lastError = nil
        } catch {
            lastError = "Failed to request camera permission: \(error.localizedDescription)"
        }
    }

    func startCameraStream() async {
        isBusy = true
        defer { isBusy = false }

        do {
            let session = try makeOrReuseSession()
            await session.start()
            lastError = nil
        } catch {
            lastError = "Failed to start camera stream: \(error.localizedDescription)"
        }
    }

    func stopCameraStream() async {
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

        session.capturePhoto(format: .jpeg)
    }

    private func observeWearablesState() {
        Task {
            for await state in Wearables.shared.registrationStateStream() {
                registrationStateText = String(describing: state)
            }
        }

        Task {
            for await devices in Wearables.shared.devicesStream() {
                connectedDeviceCount = devices.count
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
                self.streamStateText = String(describing: state)
                let normalized = self.streamStateText.lowercased()
                self.isStreaming = normalized == "streaming"
            }
        }

        videoFrameToken = session.videoFramePublisher.listen { [weak self] frame in
            guard let self, let image = frame.makeUIImage() else { return }
            Task { @MainActor in
                self.latestFrame = image
            }
        }

        photoDataToken = session.photoDataPublisher.listen { [weak self] photoData in
            guard let self else { return }
            Task { @MainActor in
                let capturedAt = Date()
                self.latestPhotoCaptureAt = capturedAt

                guard let pipeline = self.activityPipeline else {
                    self.lastError = "Activity pipeline is not configured."
                    return
                }

                do {
                    try await pipeline.processPhotoCapture(photoData: photoData.data, capturedAt: capturedAt)
                    self.lastError = nil
                } catch {
                    self.lastError = "Failed to process captured photo: \(error.localizedDescription)"
                }
            }
        }
    }

    private func configureWearables() {
        do {
            try Wearables.configure()
        } catch {
            lastError = "Failed to configure Wearables SDK: \(error.localizedDescription)"
            assertionFailure("Failed to configure Wearables SDK: \(error)")
        }
    }
}
