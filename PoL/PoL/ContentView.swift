//
//  ContentView.swift
//  PoL
//
//  Created by Peiqi Tang on 2/12/26.
//

import SwiftUI
import SwiftData

struct ContentView: View {
    @EnvironmentObject private var wearablesManager: WearablesManager
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \ActivityEventRecord.timestamp, order: .reverse) private var timelineEvents: [ActivityEventRecord]

    var body: some View {
        NavigationStack {
            Form {
                Section("Wearables Status") {
                    statusRow("Registration", wearablesManager.registrationStateText)
                    statusRow("Camera Permission", wearablesManager.cameraPermissionText)
                    statusRow("Connected Devices", "\(wearablesManager.connectedDeviceCount)")
                    statusRow("Stream State", wearablesManager.streamStateText)
                    statusRow("MWDAT Config", wearablesManager.configSummary)

                    if let callbackDate = wearablesManager.lastCallbackHandledAt {
                        statusRow("Last Callback", callbackDate.formatted(date: .abbreviated, time: .standard))
                    }
                    if let captureDate = wearablesManager.latestPhotoCaptureAt {
                        statusRow("Last Photo", captureDate.formatted(date: .abbreviated, time: .standard))
                    }

                    if let error = wearablesManager.lastError {
                        Text(error)
                            .foregroundStyle(.red)
                            .font(.footnote)
                    }
                }

                Section("Registration") {
                    Button("Start Registration") {
                        Task {
                            await wearablesManager.startRegistration()
                        }
                    }
                    .disabled(wearablesManager.isBusy)

                    Button("Start Unregistration", role: .destructive) {
                        Task {
                            await wearablesManager.startUnregistration()
                        }
                    }
                    .disabled(wearablesManager.isBusy)
                }

                Section("Camera Permission") {
                    Button("Check Camera Permission") {
                        Task {
                            await wearablesManager.refreshCameraPermission()
                        }
                    }
                    .disabled(wearablesManager.isBusy)

                    Button("Request Camera Permission") {
                        Task {
                            await wearablesManager.requestCameraPermission()
                        }
                    }
                    .disabled(wearablesManager.isBusy)
                }

                Section("Camera Stream") {
                    Button("Start Stream") {
                        Task {
                            await wearablesManager.startCameraStream()
                        }
                    }
                    .disabled(wearablesManager.isBusy || wearablesManager.isStreaming)

                    Button("Stop Stream") {
                        Task {
                            await wearablesManager.stopCameraStream()
                        }
                    }
                    .disabled(wearablesManager.isBusy || !wearablesManager.isStreaming)

                    Button("Capture Photo") {
                        wearablesManager.capturePhoto()
                    }
                    .disabled(wearablesManager.isBusy || !wearablesManager.isStreaming)
                }

                Section("Button Probe (Debug)") {
                    statusRow(
                        "Button-Like Event",
                        wearablesManager.buttonLikeEventDetected ? "detected" : "not detected"
                    )

                    Button("Mark Manual Glasses Press") {
                        wearablesManager.markManualButtonPress()
                    }

                    Button("Clear Probe Log", role: .destructive) {
                        wearablesManager.clearDebugEvents()
                    }

                    if wearablesManager.debugEvents.isEmpty {
                        Text("No wearable events logged yet.")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(wearablesManager.debugEvents) { event in
                            VStack(alignment: .leading, spacing: 4) {
                                HStack {
                                    Text(event.name)
                                        .font(.subheadline)
                                        .fontWeight(.semibold)
                                    if event.isManualMarker {
                                        Text("Manual Marker")
                                            .font(.caption2)
                                            .padding(.horizontal, 6)
                                            .padding(.vertical, 2)
                                            .background(.blue.opacity(0.15))
                                            .clipShape(Capsule())
                                    } else if event.isButtonLike {
                                        Text("Button-Like")
                                            .font(.caption2)
                                            .padding(.horizontal, 6)
                                            .padding(.vertical, 2)
                                            .background(.orange.opacity(0.2))
                                            .clipShape(Capsule())
                                    }
                                    Spacer()
                                    Text(event.timestamp.formatted(date: .omitted, time: .standard))
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                if !event.metadata.isEmpty {
                                    Text(formatDebugMetadata(event.metadata))
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            .padding(.vertical, 2)
                        }
                    }
                }

                if let frame = wearablesManager.latestFrame {
                    Section("Live Preview") {
                        Image(uiImage: frame)
                            .resizable()
                            .scaledToFit()
                            .frame(maxWidth: .infinity)
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                    }
                }

                Section("Activity Timeline") {
                    let visibleEvents = timelineEvents.filter { !$0.isDeleted }
                    if visibleEvents.isEmpty {
                        Text("No activity events yet. Capture a photo to create one.")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(visibleEvents) { event in
                            VStack(alignment: .leading, spacing: 4) {
                                HStack {
                                    Text(event.label.displayName)
                                        .font(.headline)
                                    if event.needsReview {
                                        Text("Needs Review")
                                            .font(.caption)
                                            .padding(.horizontal, 6)
                                            .padding(.vertical, 2)
                                            .background(.yellow.opacity(0.2))
                                            .clipShape(Capsule())
                                    }
                                }
                                Text(event.timestamp.formatted(date: .abbreviated, time: .standard))
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                                Text("Confidence: \(event.confidence.formatted(.number.precision(.fractionLength(2))))")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                Text(event.rationaleShort)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            .padding(.vertical, 2)
                        }
                    }
                }
            }
            .navigationTitle("DAT Debug")
            .task {
                wearablesManager.configurePipelineIfNeeded(modelContext: modelContext)
            }
        }
    }

    @ViewBuilder
    private func statusRow(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label)
            Spacer()
            Text(value)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.trailing)
        }
    }

    private func formatDebugMetadata(_ metadata: [String: String]) -> String {
        metadata
            .sorted(by: { $0.key < $1.key })
            .map { "\($0.key)=\($0.value)" }
            .joined(separator: ", ")
    }
}

#Preview {
    ContentView()
        .environmentObject(WearablesManager(autoConfigure: false))
        .modelContainer(for: ActivityEventRecord.self, inMemory: true)
}
