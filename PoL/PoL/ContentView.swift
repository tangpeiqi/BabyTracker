//
//  ContentView.swift
//  PoL
//
//  Created by Peiqi Tang on 2/12/26.
//

import SwiftUI
import SwiftData

struct ContentView: View {
    private enum AppTab: Hashable {
        case summary
        case settings
        case activities
    }

    @EnvironmentObject private var wearablesManager: WearablesManager
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \ActivityEventRecord.timestamp, order: .reverse) private var timelineEvents: [ActivityEventRecord]
    @State private var selectedTab: AppTab = .summary

    var body: some View {
        TabView(selection: $selectedTab) {
            NavigationStack {
                Form {
                    Section {
                        Text("Summary dashboard is coming next.")
                            .foregroundStyle(.secondary)
                    }

                    Section("Quick Stats") {
                        let visibleEvents = timelineEvents.filter { !$0.isDeleted }
                        statusRow("Total Events", "\(visibleEvents.count)")
                        statusRow("Stream State", wearablesManager.streamStateText)
                    }
                }
                .navigationTitle("Summary")
            }
            .tabItem {
                Label("Summary", systemImage: "chart.bar")
            }
            .tag(AppTab.summary)

            NavigationStack {
                Form {
                    Section {
                        statusRow("Stream State", wearablesManager.streamStateText)

                        if wearablesManager.hasActiveStreamSession {
                            HStack(alignment: .top, spacing: 8) {
                                Image(systemName: "hand.tap.fill")
                                    .foregroundStyle(.blue)
                                Text("Tap once on the glasses touch pad when you are ready to log the activity, tap again to finish logging.")
                                    .font(.footnote.weight(.semibold))
                                    .foregroundStyle(.primary)
                            }
                            .padding(10)
                            .background(.blue.opacity(0.18))
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                        }
                    }

                    Section("Activity Timeline") {
                        let visibleEvents = timelineEvents.filter { !$0.isDeleted }
                        if visibleEvents.isEmpty {
                            Text("No activity events yet. End a segment to create one.")
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
                                    Text("Frames: \(event.frameCount.map(String.init) ?? "-")")
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
                .navigationTitle("Activities")
            }
            .tabItem {
                Label("Activities", systemImage: "list.bullet.rectangle")
            }
            .tag(AppTab.activities)

            NavigationStack {
                Form {
                    if let error = wearablesManager.lastError {
                        Section {
                            Text(error)
                                .foregroundStyle(.red)
                                .font(.footnote)
                        }
                    }

                    if !wearablesManager.isDeviceRegistered {
                        Section("Registration") {
                            Button("Register") {
                                Task {
                                    await wearablesManager.startRegistration()
                                }
                            }
                            .disabled(wearablesManager.isBusy)
                        }
                    }

                    if !wearablesManager.isCameraPermissionGranted {
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
                    }

                    Section("Camera Stream") {
                        Button("Start Stream") {
                            Task {
                                await wearablesManager.startCameraStream()
                            }
                        }
                        .disabled(wearablesManager.isBusy || wearablesManager.hasActiveStreamSession)

                        if wearablesManager.hasActiveStreamSession {
                            HStack(alignment: .top, spacing: 8) {
                                Image(systemName: "hand.tap.fill")
                                    .foregroundStyle(.orange)
                                Text("To get ready for the experience, tap once on the glasses touch pad to pause the streaming, then switch to the Activities tab.")
                                    .font(.footnote.weight(.semibold))
                                    .foregroundStyle(.primary)
                            }
                            .padding(10)
                            .background(.orange.opacity(0.18))
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                        }

                        Button("Stop Stream") {
                            Task {
                                await wearablesManager.stopCameraStream()
                            }
                        }
                        .disabled(wearablesManager.isBusy || !wearablesManager.hasActiveStreamSession)

                        Button("Capture Photo") {
                            wearablesManager.capturePhoto()
                        }
                        .disabled(wearablesManager.isBusy || !wearablesManager.isStreaming)
                    }

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
                    }

                    Section("Diagnostics") {
                        NavigationLink("Debug Logs") {
                            DebugLogsView()
                        }
                        NavigationLink("Live Preview") {
                            LivePreviewView()
                        }
                    }

                    if wearablesManager.isDeviceRegistered {
                        Section("Registration") {
                            Button("Unregister", role: .destructive) {
                                Task {
                                    await wearablesManager.startUnregistration()
                                }
                            }
                            .disabled(wearablesManager.isBusy)
                        }
                    }
                }
                .navigationTitle("Settings")
            }
            .tabItem {
                Label("Settings", systemImage: "gearshape")
            }
            .tag(AppTab.settings)
        }
        .onChange(of: selectedTab) { _, newValue in
            wearablesManager.setActivitiesTabActive(newValue == .activities)
        }
        .task {
            wearablesManager.configurePipelineIfNeeded(modelContext: modelContext)
            wearablesManager.setActivitiesTabActive(selectedTab == .activities)
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

}

private struct DebugLogsView: View {
    @EnvironmentObject private var wearablesManager: WearablesManager

    var body: some View {
        Form {
            Section("Debug Logs") {
                HStack {
                    Text("Button-Like Event")
                    Spacer()
                    Text(wearablesManager.buttonLikeEventDetected ? "detected" : "not detected")
                        .foregroundStyle(.secondary)
                }

                Button("Mark Manual Glasses Press") {
                    wearablesManager.markManualButtonPress()
                }

                Button("Clear Logs", role: .destructive) {
                    wearablesManager.clearDebugEvents()
                }
            }

            Section("Event List") {
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
        }
        .navigationTitle("Debug Logs")
    }

    private func formatDebugMetadata(_ metadata: [String: String]) -> String {
        metadata
            .sorted(by: { $0.key < $1.key })
            .map { "\($0.key)=\($0.value)" }
            .joined(separator: ", ")
    }
}

private struct LivePreviewView: View {
    @EnvironmentObject private var wearablesManager: WearablesManager

    var body: some View {
        Group {
            if let frame = wearablesManager.latestFrame {
                ScrollView {
                    Image(uiImage: frame)
                        .resizable()
                        .scaledToFit()
                        .frame(maxWidth: .infinity)
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                        .padding()
                }
            } else {
                ContentUnavailableView(
                    "No Live Preview Yet",
                    systemImage: "video.slash",
                    description: Text("Start streaming to load live frames.")
                )
            }
        }
        .navigationTitle("Live Preview")
    }
}

#Preview {
    ContentView()
        .environmentObject(WearablesManager(autoConfigure: false))
        .modelContainer(for: ActivityEventRecord.self, inMemory: true)
}
