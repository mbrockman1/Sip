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
                    // We don't need PhoneSessionManager because 
                    // HydrationManager handles WCSession internally now!
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
                        
                        // Use the function now directly on the manager
                        manager.pushStateToWatch()
                    }
                }
        }
    }
}
