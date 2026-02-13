//
//  PoLApp.swift
//  PoL
//
//  Created by Peiqi Tang on 2/12/26.
//

import SwiftUI
import SwiftData

@main
struct PoLApp: App {
    @StateObject private var wearablesManager = WearablesManager()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(wearablesManager)
                .onOpenURL { url in
                    wearablesManager.handleIncomingURL(url)
                }
        }
        .modelContainer(for: ActivityEventRecord.self)
    }
}
