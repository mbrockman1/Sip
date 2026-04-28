//
//  HydrationManager.swift
//  sip-dynamic-hydration
//

import SwiftUI
import Combine
import ActivityKit
import HealthKit
import UserNotifications
import WeatherKit
import CoreLocation

// MARK: - Data Models

struct DailyIntake: Identifiable {
    let id = UUID()
    let date: Date
    let amountML: Double
    var goalML: Double = 2000
}


typealias LogButtonTuple = (amount: Double, label: String)

// MARK: - HydrationManager

@MainActor
class HydrationManager: ObservableObject {

    // MARK: Core State
    @Published var dailyGoalML: Double = 2000 {
        didSet { Constants.defaults.set(dailyGoalML, forKey: "dailyGoalML"); ensureActivityRunning(forceUpdate: true) }
    }
    @Published var baseGoalML: Double = 2000 {
        didSet { Constants.defaults.set(baseGoalML, forKey: "baseGoalML") }
    }
    @Published var currentIntakeML: Double = 0 {
        didSet { Constants.defaults.set(currentIntakeML, forKey: "currentIntakeML") }
    }
    @Published var isOunces: Bool = false {
        didSet { Constants.defaults.set(isOunces, forKey: "isOunces"); ensureActivityRunning(forceUpdate: true) }
    }
    @Published var lastDrinkTimestamp: Date = Date() {
        didSet { Constants.defaults.set(lastDrinkTimestamp, forKey: "lastDrinkTimestamp") }
    }

    // MARK: Streak
    @Published var currentStreak: Int = 0
    @Published var milestoneBadge: String? = nil

    // MARK: Adaptive Goals
    @Published var useAdaptiveGoals: Bool = false {
        didSet {
            Constants.defaults.set(useAdaptiveGoals, forKey: "useAdaptiveGoals")
            if useAdaptiveGoals { Task { await refreshAdaptiveGoal() } } else { resetGoalToBase() }
        }
    }
    @Published var goalAdjustedBy: Double = 0
    @Published var adaptiveReason: String = ""

    // MARK: Notifications
    @Published var dailySummaryEnabled: Bool = true {
        didSet {
            Constants.defaults.set(dailySummaryEnabled, forKey: "dailySummaryEnabled")
            if dailySummaryEnabled { scheduleDailySummary() } else { cancelDailySummary() }
        }
    }

    // MARK: Custom Log Buttons
    /// Three configurable buttons: small / medium / large
    @Published var customButtons: [LogButton] = [
        LogButton(amountML: 100),
        LogButton(amountML: 250),
        LogButton(amountML: 500)
    ] {
        didSet { saveButtons() }
    }

    /// Computed tuples used in the UI
    var logButtons: [LogButtonTuple] {
        customButtons.map { (amount: $0.amountML, label: $0.label(isOunces: isOunces)) }
    }

    func setLogButton(slot: Int, amountML: Double) {
        guard slot < customButtons.count else { return }
        customButtons[slot] = LogButton(amountML: amountML)
        // Poke the Live Activity so the widget re-renders and picks up
        // the freshly written customButtons from the App Group defaults.
        ensureActivityRunning(forceUpdate: true)
    }

    // MARK: History
    @Published var weeklyHistory: [DailyIntake] = []
    @Published var extendedHistory: [DailyIntake] = []

    // MARK: HealthKit
    private let healthStore = HKHealthStore()
    private let waterType = HKQuantityType.quantityType(forIdentifier: .dietaryWater)!
    private let energyType = HKQuantityType.quantityType(forIdentifier: .activeEnergyBurned)!
    private let workoutType = HKObjectType.workoutType()

    // MARK: Location
    private let locationManager = CLLocationManager()

    // MARK: Init

    init() {
        reloadFromDefaults()
        currentStreak = StreakManager.computeStreak()
        checkMidnightReset()
        ensureActivityRunning()
        syncPendingAppGroupLogs()
        requestNotificationPermissions()
        if useAdaptiveGoals { Task { await refreshAdaptiveGoal() } }
        if dailySummaryEnabled { scheduleDailySummary() }
    }

    // MARK: - Persistence

    func reloadFromDefaults() {
        let d = Constants.defaults
        let savedGoal = d.double(forKey: "dailyGoalML")
        let savedBase = d.double(forKey: "baseGoalML")
        baseGoalML        = savedBase == 0 ? 2000 : savedBase
        dailyGoalML       = savedGoal == 0 ? 2000 : savedGoal
        currentIntakeML   = d.double(forKey: "currentIntakeML")
        isOunces          = d.bool(forKey: "isOunces")
        lastDrinkTimestamp = d.object(forKey: "lastDrinkTimestamp") as? Date ?? Date()
        useAdaptiveGoals  = d.bool(forKey: "useAdaptiveGoals")
        goalAdjustedBy    = d.double(forKey: "goalAdjustedBy")
        adaptiveReason    = d.string(forKey: "adaptiveReason") ?? ""
        dailySummaryEnabled = d.object(forKey: "dailySummaryEnabled") as? Bool ?? true
        loadButtons()
    }

    func saveButtons() {
        if let data = try? JSONEncoder().encode(customButtons) {
            Constants.defaults.set(data, forKey: "customButtons")
        }
    }

    private func loadButtons() {
        guard let data = Constants.defaults.data(forKey: "customButtons"),
              let saved = try? JSONDecoder().decode([LogButton].self, from: data) else { return }
        customButtons = saved
    }

    // MARK: - Notifications

    func requestNotificationPermissions() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    // MARK: Daily Summary (9pm, context-aware)

    func scheduleDailySummary() {
        cancelDailySummary()
        // Schedule at 9 PM local time; content is personalized at fire time via a UNNotificationServiceExtension
        // For simplicity, we schedule with current context and reschedule each day on launch
        let center = UNUserNotificationCenter.current()

        // Check if goal already hit — if so, don't bother scheduling for today
        if let goalHitDate = Constants.defaults.object(forKey: "goalHitDate") as? Date,
           Calendar.current.isDateInToday(goalHitDate) { return }

        let content = buildSummaryNotificationContent()

        var components = DateComponents()
        components.hour = 21  // 9 PM
        components.minute = 0
        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
        let request = UNNotificationRequest(identifier: "DailySummary", content: content, trigger: trigger)

        center.add(request) { _ in }
    }

    private func buildSummaryNotificationContent() -> UNMutableNotificationContent {
        let content = UNMutableNotificationContent()
        let current = HydrationMath.currentLevel(
            intake: currentIntakeML,
            lastDrink: lastDrinkTimestamp,
            now: Date()
        )
        let pct = Int(min(1.0, current / max(1, dailyGoalML)) * 100)
        let remaining = max(0, dailyGoalML - current)

        // Title varies by progress
        if pct >= 80 {
            content.title = "Almost there! 💧"
        } else if pct >= 50 {
            content.title = "Halfway there — keep drinking 💧"
        } else {
            content.title = "Don't forget to hydrate 💧"
        }

        // Body: base message
        var body = "You're at \(pct)% of your goal."

        if remaining > 0 {
            body += " \(HydrationMath.formatLabel(amount: remaining, isOunces: isOunces)) more gets you there."
        }

        // Append context if relevant
        if goalAdjustedBy > 0 && !adaptiveReason.isEmpty {
            body += " Note: \(adaptiveReason) raised your goal today."
        }

        // Decay nudge if it's been a while
        let minsSince = Date().timeIntervalSince(lastDrinkTimestamp) / 60
        if minsSince > 120 {
            let hrs = Int(minsSince / 60)
            body += " You haven't sipped in \(hrs) hour\(hrs == 1 ? "" : "s") — your level is draining."
        }

        content.body = body
        content.sound = .default
        return content
    }

    func cancelDailySummary() {
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: ["DailySummary"])
    }

    /// Call this when the app becomes active — reschedule with fresh context
    func refreshDailySummary() {
        guard dailySummaryEnabled else { return }
        // Only reschedule if goal not yet hit today
        if let goalHitDate = Constants.defaults.object(forKey: "goalHitDate") as? Date,
           Calendar.current.isDateInToday(goalHitDate) {
            cancelDailySummary()
            return
        }
        scheduleDailySummary()
    }

    // MARK: - HealthKit

    func requestHealthKit() {
        guard HKHealthStore.isHealthDataAvailable() else { return }
        let readTypes: Set<HKObjectType> = [waterType, energyType, workoutType]
        healthStore.requestAuthorization(toShare: [waterType], read: readTypes) { success, _ in
            if success {
                self.healthStore.enableBackgroundDelivery(for: self.waterType, frequency: .immediate) { _, _ in }
                Task { @MainActor in
                    self.syncFromHealthKit()
                    if self.useAdaptiveGoals { await self.refreshAdaptiveGoal() }
                }
            }
        }
    }

    func fetchWeeklyHistory() {
        let cal = Calendar.current
        let now = Date()
        guard let start = cal.date(byAdding: .day, value: -6, to: cal.startOfDay(for: now)) else { return }
        fetchHistory(from: start, to: now) { [weak self] h in self?.weeklyHistory = h }
    }

    func fetchExtendedHistory() {
        let cal = Calendar.current
        let now = Date()
        guard let start = cal.date(byAdding: .day, value: -29, to: cal.startOfDay(for: now)) else { return }
        fetchHistory(from: start, to: now) { [weak self] h in self?.extendedHistory = h }
    }

    private func fetchHistory(from start: Date, to end: Date, completion: @escaping ([DailyIntake]) -> Void) {
        var interval = DateComponents(); interval.day = 1
        let predicate = HKQuery.predicateForSamples(withStart: start, end: end, options: .strictStartDate)
        let query = HKStatisticsCollectionQuery(quantityType: waterType, quantitySamplePredicate: predicate,
            options: .cumulativeSum, anchorDate: start, intervalComponents: interval)
        query.initialResultsHandler = { [weak self] _, results, _ in
            guard let results = results, let self = self else { return }
            var history: [DailyIntake] = []
            results.enumerateStatistics(from: start, to: end) { stats, _ in
                let total = stats.sumQuantity()?.doubleValue(for: HKUnit.literUnit(with: .milli)) ?? 0
                history.append(DailyIntake(date: stats.startDate, amountML: total, goalML: self.baseGoalML))
            }
            Task { @MainActor in completion(history) }
        }
        healthStore.execute(query)
    }

    func syncFromHealthKit() {
        fetchWeeklyHistory()
        fetchExtendedHistory()
        let startOfDay = Calendar.current.startOfDay(for: Date())
        let predicate = HKQuery.predicateForSamples(withStart: startOfDay, end: Date(), options: .strictStartDate)
        let sort = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: true)
        let query = HKSampleQuery(sampleType: waterType, predicate: predicate,
            limit: HKObjectQueryNoLimit, sortDescriptors: [sort]) { [weak self] _, samples, _ in
            guard let samples = samples as? [HKQuantitySample], let self = self else { return }
            Task { @MainActor in
                var simLevel: Double = 0
                var simTime = startOfDay
                for sample in samples {
                    let amount = sample.quantity.doubleValue(for: HKUnit.literUnit(with: .milli))
                    simLevel = HydrationMath.currentLevel(intake: simLevel, lastDrink: simTime, now: sample.startDate) + amount
                    simTime = sample.startDate
                }
                if simTime > self.lastDrinkTimestamp || samples.isEmpty {
                    self.currentIntakeML = simLevel
                    self.lastDrinkTimestamp = simTime
                    self.ensureActivityRunning(forceUpdate: true)
                }
            }
        }
        healthStore.execute(query)
    }

    func syncPendingAppGroupLogs() {
        guard HKHealthStore.isHealthDataAvailable() else { return }
        let pending = Constants.defaults.array(forKey: "pendingHKLogs") as? [Double] ?? []
        guard !pending.isEmpty else { return }
        for amount in pending {
            let sample = HKQuantitySample(type: waterType,
                quantity: HKQuantity(unit: HKUnit.literUnit(with: .milli), doubleValue: amount),
                start: Date(), end: Date())
            healthStore.save(sample) { _, _ in }
        }
        Constants.defaults.set([], forKey: "pendingHKLogs")
    }

    // MARK: - Core Drink Action

    func addDrink(amountML: Double) {
        UIImpactFeedbackGenerator(style: .rigid).impactOccurred()
        let newLevel = HydrationMath.currentLevel(intake: currentIntakeML, lastDrink: lastDrinkTimestamp, now: Date()) + amountML
        currentIntakeML = newLevel
        lastDrinkTimestamp = Date()

        let sample = HKQuantitySample(type: waterType,
            quantity: HKQuantity(unit: HKUnit.literUnit(with: .milli), doubleValue: amountML),
            start: Date(), end: Date())
        healthStore.save(sample) { [weak self] _, _ in
            Task { @MainActor in self?.fetchWeeklyHistory() }
        }

        if newLevel >= dailyGoalML {
            handleGoalAchieved()
        } else {
            ensureActivityRunning(forceUpdate: true)
            refreshDailySummary()  // Update summary with fresh progress
        }
    }

    private func handleGoalAchieved() {
        StreakManager.recordGoalHit()
        currentStreak = StreakManager.computeStreak()
        milestoneBadge = StreakManager.milestoneBadge(for: currentStreak)
        Constants.defaults.set(Date(), forKey: "goalHitDate")
        cancelDailySummary()  // Goal hit, no need for the nudge

        Task {
            for activity in Activity<HydrationAttributes>.activities {
                await activity.end(ActivityContent(state: activity.content.state, staleDate: nil), dismissalPolicy: .immediate)
            }
            let content = UNMutableNotificationContent()
            content.title = "Goal Achieved! \(StreakManager.flameEmoji(for: currentStreak))"
            if let badge = milestoneBadge {
                content.body = "You earned: \(badge). See you tomorrow!"
            } else {
                content.body = currentStreak > 1
                    ? "\(currentStreak)-day streak! Keep it up. See you tomorrow!"
                    : "You hit your daily hydration goal. See you tomorrow!"
            }
            content.sound = .default
            try? await UNUserNotificationCenter.current().add(
                UNNotificationRequest(identifier: "GoalHit", content: content, trigger: nil))
        }
    }

    // MARK: - Midnight Reset

    func checkMidnightReset() {
        if !Calendar.current.isDateInToday(lastDrinkTimestamp) {
            currentIntakeML = 0
            lastDrinkTimestamp = Date()
            goalAdjustedBy = 0
            adaptiveReason = ""
            Constants.defaults.set(0.0, forKey: "goalAdjustedBy")
            Constants.defaults.set("", forKey: "adaptiveReason")
            Constants.defaults.removeObject(forKey: "goalHitDate")
            if useAdaptiveGoals {
                dailyGoalML = baseGoalML
                Task { await refreshAdaptiveGoal() }
            }
            Task {
                for activity in Activity<HydrationAttributes>.activities {
                    await activity.end(ActivityContent(state: activity.content.state, staleDate: nil), dismissalPolicy: .immediate)
                }
            }
            ensureActivityRunning()
        }
        currentStreak = StreakManager.computeStreak()
        refreshDailySummary()
    }

    // MARK: - Live Activity

    func ensureActivityRunning(forceUpdate: Bool = false) {
        if let goalHitDate = Constants.defaults.object(forKey: "goalHitDate") as? Date,
           Calendar.current.isDateInToday(goalHitDate) { return }

        let state = HydrationAttributes.ContentState(
            currentIntake: currentIntakeML,
            lastDrinkTimestamp: lastDrinkTimestamp,
            dailyGoal: dailyGoalML,
            isOunces: isOunces,
            streak: currentStreak,
            goalAdjustedBy: goalAdjustedBy
        )
        if let activity = Activity<HydrationAttributes>.activities.first {
            Task { await activity.update(ActivityContent(state: state, staleDate: nil)) }
        } else {
            _ = try? Activity.request(attributes: HydrationAttributes(),
                content: ActivityContent(state: state, staleDate: nil), pushType: nil)
        }
    }

    // MARK: - Adaptive Goal Engine

    func refreshAdaptiveGoal() async {
        guard useAdaptiveGoals else { return }
        let lastAdjustKey = "adaptiveAdjustDate"
        if let lastDate = Constants.defaults.object(forKey: lastAdjustKey) as? Date,
           Calendar.current.isDateInToday(lastDate) { return }

        var totalBumpML: Double = 0
        var reasons: [String] = []

        if let weatherBump = await fetchWeatherBump() { totalBumpML += weatherBump.ml; reasons.append(weatherBump.reason) }
        if let activityBump = await fetchActivityBump() { totalBumpML += activityBump.ml; reasons.append(activityBump.reason) }
        guard totalBumpML > 0 else { return }

        let reasonText = reasons.joined(separator: " & ")
        dailyGoalML = baseGoalML + totalBumpML
        goalAdjustedBy = totalBumpML
        adaptiveReason = reasonText
        Constants.defaults.set(totalBumpML, forKey: "goalAdjustedBy")
        Constants.defaults.set(reasonText, forKey: "adaptiveReason")
        Constants.defaults.set(Date(), forKey: lastAdjustKey)
        ensureActivityRunning(forceUpdate: true)
        refreshDailySummary()  // Reschedule with updated goal context

        let content = UNMutableNotificationContent()
        content.title = "Goal Updated 💧"
        content.body = "\(reasonText). We've added \(HydrationMath.formatLabel(amount: totalBumpML, isOunces: isOunces)) to your goal."
        content.sound = .default
        try? await UNUserNotificationCenter.current().add(
            UNNotificationRequest(identifier: "AdaptiveGoal", content: content, trigger: nil))
    }

    private func resetGoalToBase() {
        dailyGoalML = baseGoalML
        goalAdjustedBy = 0
        adaptiveReason = ""
        Constants.defaults.set(0.0, forKey: "goalAdjustedBy")
        Constants.defaults.set("", forKey: "adaptiveReason")
        ensureActivityRunning(forceUpdate: true)
    }

    private func fetchWeatherBump() async -> (ml: Double, reason: String)? {
        guard CLLocationManager.locationServicesEnabled() else { return nil }
        let auth = locationManager.authorizationStatus
        guard auth == .authorizedWhenInUse || auth == .authorizedAlways else {
            locationManager.requestWhenInUseAuthorization(); return nil
        }
        let location = locationManager.location ?? CLLocation(latitude: 37.7749, longitude: -122.4194)
        do {
            let weather = try await WeatherService.shared.weather(for: location)
            let tempC = weather.currentWeather.temperature.converted(to: .celsius).value
            if tempC > 37 { return (baseGoalML * 0.20, "Very hot today (\(Int(tempC))°C)") }
            if tempC > 30 { return (baseGoalML * 0.15, "Hot day (\(Int(tempC))°C)") }
        } catch {}
        return nil
    }

    private func fetchActivityBump() async -> (ml: Double, reason: String)? {
        guard HKHealthStore.isHealthDataAvailable() else { return nil }
        let predicate = HKQuery.predicateForSamples(withStart: Date().addingTimeInterval(-86400), end: Date(), options: .strictStartDate)
        return await withCheckedContinuation { continuation in
            let query = HKStatisticsQuery(quantityType: energyType, quantitySamplePredicate: predicate, options: .cumulativeSum) { _, result, _ in
                let kcal = result?.sumQuantity()?.doubleValue(for: .kilocalorie()) ?? 0
                if kcal > 600 { continuation.resume(returning: (self.baseGoalML * 0.20, "Heavy workout (\(Int(kcal)) kcal)")) }
                else if kcal > 300 { continuation.resume(returning: (self.baseGoalML * 0.10, "Active day (\(Int(kcal)) kcal)")) }
                else { continuation.resume(returning: nil) }
            }
            healthStore.execute(query)
        }
    }

    // MARK: - Streak

    func dismissMilestoneBadge() { milestoneBadge = nil }
}
