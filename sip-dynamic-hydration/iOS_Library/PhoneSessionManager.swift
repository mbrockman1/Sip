//
//  PhoneSessionManager.swift
//  sip-dynamic-hydration (iPhone target ONLY)
//
//  Responsibilities:
//  - Push full hydration state to watch whenever anything changes
//  - Receive drink-log messages from watch and forward to HydrationManager
//  - Handle watch reachability changes by resending current state
//

import Foundation
import WatchConnectivity
import Combine

@MainActor
class PhoneSessionManager: NSObject, ObservableObject {

    static let shared = PhoneSessionManager()

    // Keys used in WatchConnectivity payloads — single source of truth
    struct Keys {
        static let currentIntakeML   = "currentIntakeML"
        static let goalML            = "goalML"
        static let lastDrinkDate     = "lastDrinkDate"
        static let isOunces          = "isOunces"
        static let streak            = "streak"
        static let goalAdjustedBy    = "goalAdjustedBy"
        static let adaptiveReason    = "adaptiveReason"
        static let btn1Amount        = "btn1Amount"
        static let btn2Amount        = "btn2Amount"
        static let btn1Label         = "btn1Label"
        static let btn2Label         = "btn2Label"
        // Message from watch → phone
        static let logDrinkAmount    = "logDrinkAmount"
    }

    private var session: WCSession?
    private weak var manager: HydrationManager?
    private var cancellables = Set<AnyCancellable>()

    private override init() { super.init() }

    // MARK: - Setup

    /// Call this once from the app entry point, passing the HydrationManager.
    func start(manager: HydrationManager) {
        guard WCSession.isSupported() else { return }
        self.manager = manager
        let session = WCSession.default
        session.delegate = self
        session.activate()
        self.session = session

        // Observe every state change on HydrationManager and push to watch
        manager.$currentIntakeML
            .debounce(for: .milliseconds(300), scheduler: RunLoop.main)
            .sink { [weak self] _ in self?.pushStateToWatch() }
            .store(in: &cancellables)

        manager.$dailyGoalML
            .debounce(for: .milliseconds(300), scheduler: RunLoop.main)
            .sink { [weak self] _ in self?.pushStateToWatch() }
            .store(in: &cancellables)

        manager.$isOunces
            .sink { [weak self] _ in self?.pushStateToWatch() }
            .store(in: &cancellables)

        manager.$lastDrinkTimestamp
            .debounce(for: .milliseconds(300), scheduler: RunLoop.main)
            .sink { [weak self] _ in self?.pushStateToWatch() }
            .store(in: &cancellables)

        manager.$currentStreak
            .sink { [weak self] _ in self?.pushStateToWatch() }
            .store(in: &cancellables)

        manager.$goalAdjustedBy
            .sink { [weak self] _ in self?.pushStateToWatch() }
            .store(in: &cancellables)

        manager.$customButtons
            .sink { [weak self] _ in self?.pushStateToWatch() }
            .store(in: &cancellables)
    }

    // MARK: - Push state to watch

    func pushStateToWatch() {
        guard let session = session,
              session.activationState == .activated,
              let manager = manager else { return }

        // Build button labels from manager's current buttons + unit setting
        let btns = manager.logButtons  // [(amount, label)]
        let btn1 = btns.count > 0 ? btns[0] : (amount: 250.0, label: "+ 250 ml")
        let btn2 = btns.count > 1 ? btns[1] : (amount: 500.0, label: "+ 500 ml")

        let context: [String: Any] = [
            Keys.currentIntakeML:  manager.currentIntakeML,
            Keys.goalML:           manager.dailyGoalML,
            Keys.lastDrinkDate:    manager.lastDrinkTimestamp.timeIntervalSince1970,
            Keys.isOunces:         manager.isOunces,
            Keys.streak:           manager.currentStreak,
            Keys.goalAdjustedBy:   manager.goalAdjustedBy,
            Keys.adaptiveReason:   manager.adaptiveReason,
            Keys.btn1Amount:       btn1.amount,
            Keys.btn2Amount:       btn2.amount,
            Keys.btn1Label:        btn1.label,
            Keys.btn2Label:        btn2.label,
        ]

        // applicationContext: persisted, delivered when watch wakes — primary sync mechanism
        try? session.updateApplicationContext(context)

        // sendMessage: instant delivery if watch is reachable and awake
        if session.isReachable {
            session.sendMessage(context, replyHandler: nil, errorHandler: nil)
        }
    }
}

// MARK: - WCSessionDelegate

extension PhoneSessionManager: WCSessionDelegate {

    nonisolated func session(
        _ session: WCSession,
        activationDidCompleteWith activationState: WCSessionActivationState,
        error: Error?
    ) {
        guard activationState == .activated else { return }
        // Push current state as soon as session activates
        Task { @MainActor in self.pushStateToWatch() }
    }

    nonisolated func sessionDidBecomeInactive(_ session: WCSession) {}
    nonisolated func sessionDidDeactivate(_ session: WCSession) {
        session.activate() // Required for watch switching
    }

    // Watch became reachable — send fresh state immediately
    nonisolated func sessionReachabilityDidChange(_ session: WCSession) {
        guard session.isReachable else { return }
        Task { @MainActor in self.pushStateToWatch() }
    }

    // Receive drink log from watch
    nonisolated func session(
        _ session: WCSession,
        didReceiveMessage message: [String: Any]
    ) {
        guard let amount = message[Keys.logDrinkAmount] as? Double else { return }
        Task { @MainActor in
            self.manager?.addDrink(amountML: amount)
        }
    }

    nonisolated func session(
        _ session: WCSession,
        didReceiveMessage message: [String: Any],
        replyHandler: @escaping ([String: Any]) -> Void
    ) {
        guard let amount = message[Keys.logDrinkAmount] as? Double else {
            replyHandler(["status": "error"])
            return
        }
        Task { @MainActor in
            self.manager?.addDrink(amountML: amount)
            // Send back updated state immediately so watch display refreshes
            let mgr = self.manager
            replyHandler([
                PhoneSessionManager.Keys.currentIntakeML: mgr?.currentIntakeML ?? 0,
                PhoneSessionManager.Keys.lastDrinkDate:   Date().timeIntervalSince1970,
                "status": "ok"
            ])
        }
    }
}