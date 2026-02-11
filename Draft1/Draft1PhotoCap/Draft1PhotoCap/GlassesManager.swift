//
//  GlassesManager.swift
//  Draft1PhotoCap
//
//  Created by Peiqi Tang on 2/10/26.
//
import Foundation
import SwiftUI
import UIKit
import MWDATCore
import MWDATCamera
import Combine

/// An observable controller that:
/// - Manages registration and connection state with Ray‑Ban Meta glasses
/// - Requests camera permission on the glasses
/// - Creates and manages a `StreamSession`
/// - Listens to `photoDataPublisher` and converts photos to `UIImage`
/// - Exposes @Published properties for SwiftUI to display
final class GlassesManager: ObservableObject {
    // MARK: - Published properties used by the UI

    /// Latest photo captured from the glasses (displayed in the UI).
    @Published var latestPhoto: UIImage? = nil

    /// Human‑readable status text (shown under the title).
    @Published var statusText: String = "Not connected"

    /// Whether the app is currently registered with the user's glasses.
    @Published var isRegistered: Bool = false

    /// Whether at least one device is discovered and considered "connected".
    @Published var isConnected: Bool = false

    /// Whether the app is currently in the process of registering.
    @Published var isRegistering: Bool = false

    /// Whether a capture request is in flight.
    @Published var isCapturing: Bool = false

    /// Any basic error message for the user.
    @Published var errorMessage: String? = nil

    // MARK: - Private properties (SDK objects)

    private let wearables: WearablesInterface
    private var autoDeviceSelector: AutoDeviceSelector?
    private var streamSession: StreamSession?
    private var hasCameraPermission = false
    private var isRequestingCameraPermission = false
    private var permissionRetryCount = 0
    private let maxPermissionRetries = 3

    // Async tasks that listen to async streams from the SDK
    private var registrationTask: Task<Void, Never>?
    private var devicesTask: Task<Void, Never>?
    private var photoTask: Task<Void, Never>?

    private var photoListener: (any AnyListenerToken)? = nil
    private var stateListener: (any AnyListenerToken)? = nil
    private var errorListener: (any AnyListenerToken)? = nil

    // MARK: - Init / deinit

    init(wearables: WearablesInterface = Wearables.shared) {
        self.wearables = wearables

        // Start observing registration and devices as soon as the manager is created.
        startObservingRegistration()
        startObservingDevices()
    }

    deinit {
        registrationTask?.cancel()
        devicesTask?.cancel()
        photoTask?.cancel()
        photoListener = nil
        stateListener = nil
        errorListener = nil
        let session = streamSession
        Task { await session?.stop() }
    }

    // MARK: - Public API for the UI

    /// Called when the user taps "Connect Glasses".
    /// Starts the registration flow inside the Meta AI app.
    func startRegistration() {
        errorMessage = nil

        if isRegistered {
            if isConnected {
                statusText = "Already registered. Checking camera permission…"
                checkAndRequestCameraPermissionIfNeeded()
            } else {
                statusText = "Already registered. Waiting for glasses…"
            }
            return
        }

        if let configError = validateSDKConfiguration() {
            isRegistering = false   
            statusText = "Configuration issue"
            errorMessage = configError
            return
        }

        isRegistering = true
        statusText = "Opening Meta AI app to register…"

        Task {
            do {
                try await wearables.startRegistration()
                // The Meta AI app will open; once the user finishes,
                // your app will receive a URL callback handled in App.onOpenURL,
                // and the registrationStateStream will update automatically.
            } catch {
                DispatchQueue.main.async {
                    self.isRegistering = false
                    let message = error.localizedDescription.lowercased()
                    if message.contains("not installed")
                        || message.contains("cannot open")
                        || message.contains("not available")
                    {
                        self.statusText = "Meta AI app not available"
                        self.errorMessage = "Install or update the Meta AI app on your iPhone, then try again."
                    } else if message.contains("registrationerror.error0") {
                        self.statusText = "Registration failed"
                        self.errorMessage = "Registration could not start. Verify MWDAT settings: AppLinkURLScheme must match your callback scheme (sample format: scheme://), and ClientToken/MetaAppID must belong to this app."
                    } else {
                        self.errorMessage = "Failed to start registration: \(error.localizedDescription)"
                        self.statusText = "Registration failed"
                    }
                }
            }
        }
    }

    /// Called when the user taps "Capture Photo".
    /// Attempts to trigger a capture on the active stream session.
    func capturePhoto() {
        guard let session = streamSession else {
            errorMessage = "Camera session not ready yet."
            return
        }

        isCapturing = true
        statusText = "Capturing photo…"

        // Ensure the session is streaming before we capture.
        if session.state != .streaming {
            Task { await session.start() }
        }

        // Request a JPEG photo from the glasses.
        let accepted = session.capturePhoto(format: .jpeg)

        if !accepted {
            isCapturing = false
            statusText = "Capture could not start"
            errorMessage = "Capture request was not accepted. Is the device connected?"
        }
        // The actual photo will arrive asynchronously through photoDataPublisher.
    }

    // MARK: - Private helpers

    /// Start listening to registration state changes (registered / not registered).
    private func startObservingRegistration() {
        registrationTask = Task { [weak self] in
            guard let self else { return }

            // Async stream that emits RegistrationState values over time.
            for await state in wearables.registrationStateStream() {
                await MainActor.run {
                    switch state {
                    case .registered:
                        self.isRegistered = true
                        self.isRegistering = false
                        self.statusText = "Registered. Waiting for glasses…"
                        // Permission calls are reliable only once a device is connected.
                        if self.isConnected {
                            self.checkAndRequestCameraPermissionIfNeeded()
                        }
                    case .registering:
                        self.isRegistered = false
                        self.isRegistering = true
                        self.statusText = "Registering with glasses…"
                    default:
                        self.isRegistered = false
                        self.isRegistering = false
                        self.hasCameraPermission = false
                        self.permissionRetryCount = 0
                        self.teardownCameraSession()
                        self.statusText = "Not registered with glasses"
                    }
                }
            }
        }
    }

    /// Start listening to device list changes.
    /// When at least one device is available, we consider ourselves "connected".
    private func startObservingDevices() {
        devicesTask = Task { [weak self] in
            guard let self else { return }

            for await deviceIds in wearables.devicesStream() {
                await MainActor.run {
                    let hasDevices = !deviceIds.isEmpty
                    self.isConnected = hasDevices
                    if hasDevices {
                        self.statusText = "Glasses connected"
                        // Request permission first, then start camera streaming.
                        self.checkAndRequestCameraPermissionIfNeeded()
                    } else {
                        self.teardownCameraSession()
                        self.statusText = self.isRegistered
                            ? "Registered, waiting for glasses…"
                            : "Not connected"
                    }
                }
            }
        }
    }

    /// Checks camera permission status on the glasses, and if needed,
    /// requests it through the Meta AI app.
    private func checkAndRequestCameraPermissionIfNeeded() {
        guard isRegistered else { return }
        guard isConnected else {
            statusText = "Registered. Waiting for glasses…"
            return
        }
        guard !isRequestingCameraPermission else { return }

        isRequestingCameraPermission = true
        Task {
            defer { self.isRequestingCameraPermission = false }
            do {
                let status = try await wearables.checkPermissionStatus(.camera)

                switch status {
                case .granted:
                    await MainActor.run {
                        self.hasCameraPermission = true
                        self.permissionRetryCount = 0
                        self.errorMessage = nil
                        self.statusText = "Camera permission granted"
                        self.ensureCameraSessionStarted()
                    }
                default:
                    await MainActor.run {
                        self.statusText = "Requesting camera permission…"
                    }
                    // This opens the Meta AI app where the user can approve.
                    let newStatus = try await wearables.requestPermission(.camera)

                    await MainActor.run {
                        if newStatus == .granted {
                            self.hasCameraPermission = true
                            self.permissionRetryCount = 0
                            self.statusText = "Camera permission granted"
                            self.ensureCameraSessionStarted()
                        } else {
                            self.hasCameraPermission = false
                            self.statusText = "Camera permission not granted"
                            self.errorMessage = "Camera permission was not granted in Meta AI app."
                        }
                    }
                }
            } catch {
                await MainActor.run {
                    self.hasCameraPermission = false
                    let message = error.localizedDescription
                    if message.localizedCaseInsensitiveContains("PermissionError")
                        && self.permissionRetryCount < self.maxPermissionRetries
                    {
                        self.permissionRetryCount += 1
                        self.statusText = "Retrying camera permission…"
                        self.errorMessage = nil
                        self.schedulePermissionRetry()
                    } else {
                        self.errorMessage = "Camera permission error: \(message)"
                        self.statusText = "Camera permission error"
                    }
                }
            }
        }
    }

    /// Lazily creates the camera stream session and starts listening for photos.
    private func ensureCameraSessionStarted() {
        // Only create once.
        if streamSession == nil {
            let selector = AutoDeviceSelector(wearables: wearables)
            autoDeviceSelector = selector

            let session = StreamSession(deviceSelector: selector)
            streamSession = session

            // Observe session state/errors so we can keep streaming healthy.
            startSessionListeners(on: session)

            // Start listening for photos emitted from the glasses.
            startPhotoListener(on: session)
        }

        // Keep the stream active so physical shutter presses on glasses can
        // deliver photo data to photoDataPublisher.
        startSessionIfNeeded()
    }

    /// Stops and clears current camera session resources.
    private func teardownCameraSession() {
        let session = streamSession
        streamSession = nil
        autoDeviceSelector = nil
        photoListener = nil
        stateListener = nil
        errorListener = nil
        Task { await session?.stop() }
    }

    /// Retry permission check after a short delay to absorb transient SDK states.
    private func schedulePermissionRetry() {
        Task { [weak self] in
            try? await Task.sleep(nanoseconds: 1_000_000_000)
            self?.checkAndRequestCameraPermissionIfNeeded()
        }
    }

    /// Listen to the `photoDataPublisher` for incoming photos.
    private func startPhotoListener(on session: StreamSession) {
        // Subscribe to the announcer and handle incoming photos.
        photoListener = session.photoDataPublisher.listen { [weak self] (photoData: PhotoData) in
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                if let image = UIImage(data: photoData.data) {
                    self.latestPhoto = image
                    self.isCapturing = false
                    self.statusText = "Photo received"
                } else {
                    self.isCapturing = false
                    self.errorMessage = "Failed to decode photo data"
                    self.statusText = "Photo decode error"
                }
            }
        }
    }

    /// Observe stream session state + errors for diagnostics and UX status.
    private func startSessionListeners(on session: StreamSession) {
        stateListener = session.statePublisher.listen { [weak self] state in
            DispatchQueue.main.async {
                guard let self else { return }
                switch state {
                case .streaming:
                    if self.hasCameraPermission && self.isConnected {
                        self.statusText = "Glasses connected"
                    }
                case .waitingForDevice, .starting:
                    if self.isConnected {
                        self.statusText = "Starting camera stream…"
                    }
                case .paused:
                    self.statusText = "Stream paused"
                case .stopping, .stopped:
                    if self.isConnected && self.hasCameraPermission {
                        self.statusText = "Restarting camera stream…"
                        self.startSessionIfNeeded()
                    }
                }
            }
        }

        errorListener = session.errorPublisher.listen { [weak self] error in
            DispatchQueue.main.async {
                guard let self else { return }
                self.errorMessage = "Camera stream error: \(error)"
                self.statusText = "Camera stream error"
            }
        }
    }

    /// Start stream session when it's not currently active.
    private func startSessionIfNeeded() {
        guard let session = streamSession else { return }
        switch session.state {
        case .streaming, .starting, .waitingForDevice:
            break
        case .paused, .stopped, .stopping:
            Task { await session.start() }
        }
    }

    /// Quick local validation so tapping connect shows a clear message
    /// instead of silently failing due to placeholder SDK values.
    private func validateSDKConfiguration() -> String? {
        guard let mwdat = Bundle.main.object(forInfoDictionaryKey: "MWDAT") as? [String: Any] else {
            return "Missing MWDAT settings in Info.plist."
        }

        let clientToken = (mwdat["ClientToken"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if clientToken.isEmpty || clientToken == "YOUR_CLIENT_TOKEN_HERE" {
            return "MWDAT ClientToken is not set. Add your real token in Info.plist."
        }

        let metaAppID = (mwdat["MetaAppID"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if metaAppID.isEmpty || metaAppID == "0" {
            return "MWDAT MetaAppID is not set. Add your real Meta app ID in Info.plist."
        }

        let rawAppLinkScheme = (mwdat["AppLinkURLScheme"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if rawAppLinkScheme.isEmpty {
            return "MWDAT AppLinkURLScheme is not set."
        }

        // CameraAccess sample uses "scheme://". Accept both "scheme" and "scheme://".
        let appLinkScheme = rawAppLinkScheme.replacingOccurrences(of: "://", with: "")
        if appLinkScheme.isEmpty {
            return "MWDAT AppLinkURLScheme is invalid."
        }

        let configuredSchemes = ((Bundle.main.object(forInfoDictionaryKey: "CFBundleURLTypes") as? [[String: Any]]) ?? [])
            .flatMap { $0["CFBundleURLSchemes"] as? [String] ?? [] }

        if !configuredSchemes.contains(appLinkScheme) {
            return "MWDAT AppLinkURLScheme (\(appLinkScheme)) is not listed in CFBundleURLSchemes."
        }

        return nil
    }
}
