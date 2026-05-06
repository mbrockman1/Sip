import SwiftUI
import WidgetKit

@main
struct SipWatchApp: App {
    @StateObject var manager = WatchManager()
    @Environment(\.scenePhase) var scenePhase

    var body: some Scene {
        WindowGroup {
            WatchContentView()
                .environmentObject(manager)
                .onAppear {
                    manager.requestAuthorization()
                }
                .onChange(of: scenePhase) { _, newPhase in
                    if newPhase == .active {
                        manager.requestSyncFromPhone()
                        manager.fetchTodayData()
                    }
                }
                .onOpenURL { url in
                    print("Opened from mirrored Live Activity: \(url)")
                }
        }
    }
}
