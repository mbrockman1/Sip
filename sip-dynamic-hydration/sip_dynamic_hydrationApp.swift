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
                .onChange(of: scenePhase) { _, newPhase in
                    if newPhase == .active {
                        manager.checkMidnightReset()
                        manager.syncPendingAppGroupLogs()
                        manager.syncFromHealthKit()
                        manager.refreshDailySummary()   // Reschedule with fresh context
                        if manager.useAdaptiveGoals {
                            Task { await manager.refreshAdaptiveGoal() }
                        }
                    }
                }
        }
    }
}
