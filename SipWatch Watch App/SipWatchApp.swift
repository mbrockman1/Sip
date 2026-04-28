//
//  SipWatchApp 2.swift
//  sip-dynamic-hydration
//
//  Created by Michael Brockman on 4/28/26.
//


import SwiftUI
import WatchKit
import WidgetKit
import ClockKit

// MARK: - Watch App Entry Point

@main
struct SipWatchApp: App {
    @WKApplicationDelegateAdaptor(SipWatchDelegate.self) var delegate

    var body: some Scene {
        WindowGroup {
            WatchContentView()
        }
    }
}

class SipWatchDelegate: NSObject, WKApplicationDelegate {
    func applicationDidBecomeActive() {
        // Reload complications on wake
        CLKComplicationServer.sharedInstance().reloadComplicationDescriptors()
        WidgetCenter.shared.reloadAllTimelines()
    }
}