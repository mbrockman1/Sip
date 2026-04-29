import SwiftUI

@main
struct SipWatchApp: App {
    // FIXED: Changed from WatchSessionManager to WatchManager
    @StateObject var manager = WatchManager()
    @Environment(\.scenePhase) var scenePhase

    var body: some Scene {
        WindowGroup {
            WatchContentView()
                .environmentObject(manager)
                .onAppear {
                    manager.requestAuthorization()
                }
                .onChange(of: scenePhase) { newPhase in
                    if newPhase == .active {
                        manager.fetchTodayData()
                    }
                }
                .onOpenURL { _ in }
        }
    }
}
