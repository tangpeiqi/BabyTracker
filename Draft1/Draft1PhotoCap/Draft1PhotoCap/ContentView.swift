//
//  ContentView.swift
//  Draft1PhotoCap
//
//  Created by Peiqi Tang on 2/10/26.
//

import SwiftUI

/// Main single‑screen UI for the app.
/// - Shows a title
/// - Shows connection / registration status
/// - Has a big area for the latest photo
/// - Provides "Connect Glasses" and "Capture Photo" buttons
struct ContentView: View {
    // Access the shared GlassesManager injected from the app.
    @EnvironmentObject var  glassesManager: GlassesManager

    var body: some View {
        VStack(spacing: 24) {
            // Title
            Text("Ray-Ban Photo Capture")
                .font(.largeTitle.bold())
                .multilineTextAlignment(.center)
                .padding(.top, 32)

            // Connection + registration status
            HStack(spacing: 8) {
                // Simple colored dot to indicate connection
                Circle()
                    .fill(glassesManager.isConnected ? Color.green : Color.gray)
                    .frame(width: 12, height: 12)

                Text(glassesManager.statusText)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.leading)
            }
            .padding(.horizontal)

            // Big image display area
            ZStack {
                RoundedRectangle(cornerRadius: 16)
                    .fill(Color(.secondarySystemBackground))

                if let image = glassesManager.latestPhoto {
                    // Show latest captured photo
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFit()
                        .clipShape(RoundedRectangle(cornerRadius: 16))
                        .padding(8)
                } else {
                    // Placeholder when no photo yet
                    VStack(spacing: 8) {
                        Image(systemName: "photo.on.rectangle.angled")
                            .font(.system(size: 40))
                            .foregroundColor(.secondary)
                        Text("No photo captured yet")
                            .font(.body)
                            .foregroundColor(.secondary)
                    }
                }
            }
            .frame(maxWidth: .infinity)
            .aspectRatio(3 / 4, contentMode: .fit)
            .padding(.horizontal)

            // Buttons
            VStack(spacing: 12) {
                // Connect / Register button
                Button(action: {
                    glassesManager.startRegistration()
                }) {
                    HStack {
                        Image(systemName: "link")
                        Text(glassesManager.isRegistered ? "Reconnect Glasses" : "Connect Glasses")
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .disabled(glassesManager.isRegistering)

                // Capture Photo button
                Button(action: {
                    glassesManager.capturePhoto()
                }) {
                    HStack {
                        Image(systemName: "camera.aperture")
                        Text(glassesManager.isCapturing ? "Capturing…" : "Capture Photo")
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .disabled(!glassesManager.isConnected || glassesManager.isCapturing)
            }
            .padding(.horizontal)

            // Basic error display if something goes wrong
            if let error = glassesManager.errorMessage {
                Text(error)
                    .font(.footnote)
                    .foregroundColor(.red)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
            }

            Spacer()
        }
        .padding(.bottom, 24)
    }
}
