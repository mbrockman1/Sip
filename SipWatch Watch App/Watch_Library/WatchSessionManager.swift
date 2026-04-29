//
//  WatchSessionManager.swift
//  sip-dynamic-hydration
//
//  Created by Michael Brockman on 4/29/26.
//


//
//  WatchSessionManager.swift
//  SipWatch Watch App (Watch App target ONLY)
//
//  Responsibilities:
//  - Receive state from phone via applicationContext and sendMessage
//  - Expose state as @Published so WatchContentView updates automatically
//  - Send drink-log messages to phone with reply handler for instant UI update
//  - Fall back to last known state if phone is unreachable
//

import Foundation
import WatchConnectivity
import WatchKit
import WidgetKit
import Combine

@MainActor
class WatchSessionManager: NSObject, ObservableObject {

    static let shared = WatchSessionManager()

    // MARK: - Published State (drives WatchContentView)
    @Published var currentIntakeML: Double = 0
    @Published var goalML: Double = 2000
    @Published var lastDrinkDate: Date = Date()
    @Published var isOunces: Bool = false
    @Published var streak: Int = 0
    @Published var goalAdjustedBy: Double = 0
    @Published var adaptiveReason: String = ""
    @Published var btn1Amount: Double = 250.0
    @Published var btn2Amount: Double = 500.0
    @Published var btn1Label: String = "+ 250 ml"
    @Published var btn2Label: String = "+ 500 ml"
    @Published var isPhoneReachable: Bool = false
    @Published var lastSyncDate: Date? = nil

    // MARK: - Computed live level (decays in real time)
    func liveLevel(at date: Date = Date()) -> Double {
        HydrationMath.currentLevel(intake: currentIntakeML, lastDrink: lastDrinkDate, now: date)
    }

    func fillRatio(at date: Date = Date()) -> Double {
        HydrationMath.fillRatio(current: liveLevel(at: date), goal: goalML)
    }

    private var session: WCSession?
    private override init() { super.init() }

    // MARK: - Setup

    func start() {
        guard WCSession.isSupported() else { return }
        let session = WCSession.default
        session.delegate = self
        session.activate()
        self.session = session

        // Apply any context that arrived before activation
        applyContext(session.receivedApplicationContext)
    }

    // MARK: - Log drink (sends to phone, updates local state immediately for snappy UI)

    func logDrink(amountML: Double) {
        WKInterfaceDevice.current().play(.click)

        // Optimistic local update — UI feels instant even before phone responds
        let newLevel = liveLevel() + amountML
        currentIntakeML = newLevel
        lastDrinkDate = Date()
        WidgetCenter.shared.reloadAllTimelines()

        let message: [String: Any] = [
            PhoneSessionManager.Keys.logDrinkAmount: amountML
        ]

        if let session = session, session.isReachable {
            // Phone is awake — send with reply handler so we get confirmed state back
            session.sendMessage(message, replyHandler: { [weak self] reply in
                Task { @MainActor in
                    // Apply confirmed state from phone (HealthKit-accurate)
                    if let confirmed = reply[PhoneSessionManager.Keys.currentIntakeML] as? Double {
                        self?.currentIntakeML = confirmed
                    }
                    if let ts = reply[PhoneSessionManager.Keys.lastDrinkDate] as? TimeInterval {
                        self?.lastDrinkDate = Date(timeIntervalSince1970: ts)
                    }
                    WidgetCenter.shared.reloadAllTimelines()
                }
            }, errorHandler: { _ in
                // Phone didn't respond — keep optimistic local state, will sync on next context update
            })
        } else {
            // Phone not reachable — queue via transferUserInfo (guaranteed delivery when phone wakes)
            session?.transferUserInfo(message)
        }
    }

    // MARK: - Apply incoming state

    private func applyContext(_ context: [String: Any]) {
        guard !context.isEmpty else { return }

        if let v = context[PhoneSessionManager.Keys.currentIntakeML] as? Double { currentIntakeML = v }
        if let v = context[PhoneSessionManager.Keys.goalML] as? Double            { goalML = v }
        if let v = context[PhoneSessionManager.Keys.lastDrinkDate] as? TimeInterval {
            lastDrinkDate = Date(timeIntervalSince1970: v)
        }
        if let v = context[PhoneSessionManager.Keys.isOunces] as? Bool            { isOunces = v }
        if let v = context[PhoneSessionManager.Keys.streak] as? Int               { streak = v }
        if let v = context[PhoneSessionManager.Keys.goalAdjustedBy] as? Double    { goalAdjustedBy = v }
        if let v = context[PhoneSessionManager.Keys.adaptiveReason] as? String    { adaptiveReason = v }
        if let v = context[PhoneSessionManager.Keys.btn1Amount] as? Double        { btn1Amount = v }
        if let v = context[PhoneSessionManager.Keys.btn2Amount] as? Double        { btn2Amount = v }
        if let v = context[PhoneSessionManager.Keys.btn1Label] as? String         { btn1Label = v }
        if let v = context[PhoneSessionManager.Keys.btn2Label] as? String         { btn2Label = v }

        lastSyncDate = Date()
        WidgetCenter.shared.reloadAllTimelines()
    }
}

// MARK: - WCSessionDelegate

extension WatchSessionManager: WCSessionDelegate {

    nonisolated func session(
        _ session: WCSession,
        activationDidCompleteWith activationState: WCSessionActivationState,
        error: Error?
    ) {
        guard activationState == .activated else { return }
        Task { @MainActor in
            self.isPhoneReachable = session.isReachable
            // Apply any context already waiting
            self.applyContext(session.receivedApplicationContext)
        }
    }

    // Instant message from phone (app is foregrounded on both)
    nonisolated func session(
        _ session: WCSession,
        didReceiveMessage message: [String: Any]
    ) {
        Task { @MainActor in self.applyContext(message) }
    }

    nonisolated func session(
        _ session: WCSession,
        didReceiveMessage message: [String: Any],
        replyHandler: @escaping ([String: Any]) -> Void
    ) {
        Task { @MainActor in
            self.applyContext(message)
            replyHandler(["status": "ok"])
        }
    }

    // Background context update from phone (most common sync path)
    nonisolated func session(
        _ session: WCSession,
        didReceiveApplicationContext applicationContext: [String: Any]
    ) {
        Task { @MainActor in self.applyContext(applicationContext) }
    }

    // Queued drink log from watch delivered when phone becomes reachable
    nonisolated func session(
        _ session: WCSession,
        didReceiveUserInfo userInfo: [String: Any]
    ) {
        // Phone side handles this via its own delegate — on watch we just acknowledge
    }

    nonisolated func sessionReachabilityDidChange(_ session: WCSession) {
        Task { @MainActor in self.isPhoneReachable = session.isReachable }
    }
}
