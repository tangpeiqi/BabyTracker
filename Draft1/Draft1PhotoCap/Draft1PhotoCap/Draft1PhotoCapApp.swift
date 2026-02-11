//
//  Draft1PhotoCapApp.swift
//  Draft1PhotoCap
//
//  Created by Peiqi Tang on 2/10/26.
//

import SwiftUI
import MWDATCore        // Wearables core (registration, devices, permissions)
import MWDATCamera      // Camera streaming + photo capture

/// Main entry point for the app.
/// - Configures the Wearables SDK on launch
/// - Holds a shared `GlassesManager`
/// - Handles URL callbacks from the Meta AI app
@main
struct RayBanPhotoCaptureApp: App {
    // Shared manager for all SwiftUI views
    @StateObject private var glassesManager = GlassesManager()

    init() {
        // Configure the Wearables SDK once at app launch.
        // This reads configuration from Info.plist (MWDAT dictionary).
        do {
            try Wearables.configure()
        } catch {
            // In a production app you might show a nicer error UI.
            print("Failed to configure Wearables SDK: \(error)")
        }
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                // Inject the glasses manager into the SwiftUI environment
                .environmentObject(glassesManager)
                // Handle URL callbacks from the Meta AI app
                .onOpenURL { url in
                    handleIncomingURL(url)
                }
        }
    }

    /// Handle deep links / callbacks from the Meta AI app.
    /// The DAT SDK inspects the URL and finishes registration / permissions flows.
    private func handleIncomingURL(_ url: URL) {
        guard
            let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
            components.queryItems?.contains(where: { $0.name == "metaWearablesAction" }) == true
        else {
            return
        }

        Task {
            do {
                let handled = try await Wearables.shared.handleUrl(url)
                if !handled {
                    print("URL not handled by Wearables SDK: \(url)")
                }
            } catch {
                print("Error handling URL in Wearables SDK: \(error)")
            }
        }
    }
}
