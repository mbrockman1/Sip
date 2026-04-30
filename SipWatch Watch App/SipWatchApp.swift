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
                .onOpenURL { url in
                    print("Opened from mirrored Live Activity: \(url)")
                    // You don't actually have to do anything here,
                    // the modifier just has to exist to accept the handshake!
                }
        }
    }
}
