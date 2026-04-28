//
//  sip_dynamic_hydrationApp.swift
//  sip-dynamic-hydration
//
//  Created by Michael Brockman on 4/27/26.
//

import SwiftUI

@main
struct sip_dynamic_hydrationApp: App {
    @StateObject var manager = HydrationManager()
    @Environment(\.scenePhase) var scenePhase

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(manager)
                .onChange(of: scenePhase) { oldPhase, newPhase in
                    if newPhase == .active {
                        manager.checkMidnightReset()
                        manager.syncPendingAppGroupLogs()
                        manager.syncFromHealthKit()
                    }
                }
        }
    }
}
