//
//  SipWatchApp.swift
//  SipWatch Watch App
//
//  Target: Watch App ONLY
//

import SwiftUI
import WatchKit
import WidgetKit

@main
struct SipWatchApp: App {
    // WatchSessionManager is the single source of truth on the watch
    @StateObject private var session = WatchSessionManager.shared

    var body: some Scene {
        WindowGroup {
            WatchContentView()
                .environmentObject(session)
                .onAppear { session.start() }
        }
    }
}
