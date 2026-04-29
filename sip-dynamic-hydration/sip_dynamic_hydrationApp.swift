//
//  sip_dynamic_hydrationApp.swift
//  sip-dynamic-hydration
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
                .onAppear {
                    // Start WatchConnectivity — phone is the hub
                    PhoneSessionManager.shared.start(manager: manager)
                }
                .onChange(of: scenePhase) { _, newPhase in
                    if newPhase == .active {
                        manager.checkMidnightReset()
                        manager.syncPendingAppGroupLogs()
                        manager.syncFromHealthKit()
                        manager.refreshDailySummary()
                        if manager.useAdaptiveGoals {
                            Task { await manager.refreshAdaptiveGoal() }
                        }
                        // Push fresh state to watch whenever app foregrounds
                        PhoneSessionManager.shared.pushStateToWatch()
                    }
                }
        }
    }
}
