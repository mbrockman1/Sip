import SwiftUI
import Combine
import ActivityKit
import HealthKit
import UserNotifications
import WeatherKit
import CoreLocation
import WatchConnectivity
import WidgetKit

struct DailyIntake: Identifiable {
    let id = UUID()
    let date: Date
    let amountML: Double
    var goalML: Double = 2000
}
typealias LogButtonTuple = (amount: Double, label: String)

@MainActor
class HydrationManager: NSObject, ObservableObject, WCSessionDelegate {

    @Published var dailyGoalML: Double = 2000 { didSet { Constants.defaults.set(dailyGoalML, forKey: "dailyGoalML"); ensureActivityRunning(forceUpdate: true); pushStateToWatch() } }
    @Published var baseGoalML: Double = 2000 {
            didSet {
                Constants.defaults.set(baseGoalML, forKey: "baseGoalML")
                // 🌟 FORCE RECALCULATION when base changes
                if useAdaptiveGoals {
                    Task { @MainActor in await refreshAdaptiveGoal(force: true) }
                } else {
                    dailyGoalML = baseGoalML
                }
            }
        }
    
    var todayGoalML: Double {
        if useAdaptiveGoals {
            return baseGoalML + goalAdjustedBy
        } else {
            return baseGoalML
        }
    }

        // Update the function signature to accept a 'force' parameter
        func refreshAdaptiveGoal(force: Bool = false) async {
            if !useAdaptiveGoals {
                goalAdjustedBy = 0
                return
            }
            let lastAdjustKey = "adaptiveAdjustDate"

            // Only fetch fresh weather/activity if we haven't today OR if forced
            if !force {
                if let lastDate = Constants.defaults.object(forKey: lastAdjustKey) as? Date,
                   Calendar.current.isDateInToday(lastDate) { return }
            }

            var totalBumpML: Double = 0
            if let weather = await fetchWeatherBump() { totalBumpML += weather.ml }
            if let activity = await fetchActivityBump() { totalBumpML += activity.ml }
            
            var reasons: [String] = []

            if let weatherBump = await fetchWeatherBump() { totalBumpML += weatherBump.ml; reasons.append(weatherBump.reason) }
            if let activityBump = await fetchActivityBump() { totalBumpML += activityBump.ml; reasons.append(activityBump.reason) }
            
            // Apply the new base + bumps
            dailyGoalML = baseGoalML + totalBumpML
            goalAdjustedBy = totalBumpML
            adaptiveReason = reasons.joined(separator: " & ")
            
            Constants.defaults.set(totalBumpML, forKey: "goalAdjustedBy")
            Constants.defaults.set(adaptiveReason, forKey: "adaptiveReason")
            Constants.defaults.set(Date(), forKey: lastAdjustKey)
            
            ensureActivityRunning(forceUpdate: true)
            refreshDailySummary()
            pushStateToWatch()
        }
    @Published var currentIntakeML: Double = 0 { didSet { Constants.defaults.set(currentIntakeML, forKey: "currentIntakeML") } }
    @Published var isOunces: Bool = false { didSet { Constants.defaults.set(isOunces, forKey: "isOunces"); ensureActivityRunning(forceUpdate: true); pushStateToWatch() } }
    @Published var lastDrinkTimestamp: Date = Date() { didSet { Constants.defaults.set(lastDrinkTimestamp, forKey: "lastDrinkTimestamp") } }

    @Published var currentStreak: Int = 0
    @Published var milestoneBadge: String? = nil
    @Published var useAdaptiveGoals: Bool = false {
        didSet {
            Constants.defaults.set(useAdaptiveGoals, forKey: "useAdaptiveGoals")
            if useAdaptiveGoals {
                Task { await refreshAdaptiveGoal(force: true) }
            } else {
                // Clear adjustments when toggling off
                goalAdjustedBy = 0
            }
            ensureActivityRunning(forceUpdate: true)
        }
    }
    @Published var goalAdjustedBy: Double = 0 {
        didSet { ensureActivityRunning(forceUpdate: true) }
    }
    
    @Published var adaptiveReason: String = ""
    @Published var dailySummaryEnabled: Bool = true { didSet { Constants.defaults.set(dailySummaryEnabled, forKey: "dailySummaryEnabled"); if dailySummaryEnabled { scheduleDailySummary() } else { cancelDailySummary() } } }

    @Published var customButtons: [LogButton] = [LogButton(amountML: 100), LogButton(amountML: 250), LogButton(amountML: 500)] { didSet { saveButtons() } }
    var logButtons: [LogButtonTuple] { customButtons.map { (amount: $0.amountML, label: $0.label(isOunces: isOunces)) } }

    @Published var weeklyHistory: [DailyIntake] = []
    @Published var extendedHistory: [DailyIntake] = []
    @Published var todaysSamples: [HKQuantitySample] = []

    private let healthStore = HKHealthStore()
    private let waterType = HKQuantityType.quantityType(forIdentifier: .dietaryWater)!
    private let energyType = HKQuantityType.quantityType(forIdentifier: .activeEnergyBurned)!
    private let workoutType = HKObjectType.workoutType()
    private let locationManager = CLLocationManager()
    
    
    // Button array
    @Published var btnApp1: Double = 177.4 { didSet { Constants.defaults.set(btnApp1, forKey: "btnApp1") } }
    @Published var btnApp2: Double = 354.9 { didSet { Constants.defaults.set(btnApp2, forKey: "btnApp2") } }
    @Published var btnApp3: Double = 473.2  { didSet { Constants.defaults.set(btnApp3, forKey: "btnApp3") } }
    
    @Published var btnSmall: Double = 354.9 { didSet { Constants.defaults.set(btnSmall, forKey: "btnSmall"); WidgetCenter.shared.reloadAllTimelines() } }
    
    @Published var btnMed1: Double = 177.4  { didSet { Constants.defaults.set(btnMed1, forKey: "btnMed1"); WidgetCenter.shared.reloadAllTimelines() } }
    @Published var btnMed2: Double = 354.9  { didSet { Constants.defaults.set(btnMed2, forKey: "btnMed2"); WidgetCenter.shared.reloadAllTimelines() } }
    @Published var btnMed3: Double = 473.2 { didSet { Constants.defaults.set(btnMed3, forKey: "btnMed3"); WidgetCenter.shared.reloadAllTimelines() } }
    
    @Published var btnLive1: Double = 177.4 { didSet { Constants.defaults.set(btnLive1, forKey: "btnLive1"); ensureActivityRunning(forceUpdate: true) } }
    @Published var btnLive2: Double = 354.9 { didSet { Constants.defaults.set(btnLive2, forKey: "btnLive2"); ensureActivityRunning(forceUpdate: true) } }
    @Published var btnLive3: Double = 473.2 { didSet { Constants.defaults.set(btnLive3, forKey: "btnLive3"); ensureActivityRunning(forceUpdate: true) } }
    
    @Published var btnWatch1: Double = 236.588 { didSet { Constants.defaults.set(btnWatch1, forKey: "btnWatch1"); pushStateToWatch() } }
    @Published var btnWatch2: Double = 473.176 { didSet { Constants.defaults.set(btnWatch2, forKey: "btnWatch2"); pushStateToWatch() } }

    override init() {
        super.init()
        reloadFromDefaults()
        currentStreak = StreakManager.computeStreak()
        checkMidnightReset()
        ensureActivityRunning()
        syncPendingAppGroupLogs()
        requestNotificationPermissions()
        if useAdaptiveGoals { Task { await refreshAdaptiveGoal() } }
        if dailySummaryEnabled { scheduleDailySummary() }
        
        if WCSession.isSupported() {
            WCSession.default.delegate = self
            WCSession.default.activate()
        }
    }
    
    func pushStateToWatch() {
        if WCSession.isSupported() && WCSession.default.activationState == .activated {
            do {
                try WCSession.default.updateApplicationContext([
                    "isOunces": self.isOunces,
                    "dailyGoalML": self.dailyGoalML,
                    "currentIntakeML": self.currentIntakeML,
                    "lastDrinkTimestamp": self.lastDrinkTimestamp,
                    "btnWatch1": self.btnWatch1,
                    "btnWatch2": self.btnWatch2
                ])
            } catch {}
        }
    }
    
    // 🌟 INSTANT WATCH RECEIVER
    nonisolated func session(_ session: WCSession, didReceiveMessage message: [String : Any]) {
        if let amount = message["addDrink"] as? Double {
            Task { @MainActor in
                self.addDrink(amountML: amount) // Processes Watch tap instantly on Phone
            }
        }
    }
    
    nonisolated func session(_ session: WCSession, activationDidCompleteWith state: WCSessionActivationState, error: Error?) {}
    nonisolated func sessionDidBecomeInactive(_ session: WCSession) {}
    nonisolated func sessionDidDeactivate(_ session: WCSession) { WCSession.default.activate() }

    func reloadFromDefaults() {
        let d = Constants.defaults
        let savedGoal = d.double(forKey: "dailyGoalML")
        let savedBase = d.double(forKey: "baseGoalML")
        
        func loadBtn(_ key: String, def: Double) -> Double {
            let val = d.double(forKey: key)
            return val == 0 ? def : val
        }
        
        btnApp1 = loadBtn("btnApp1", def: 177.4)
        btnApp2 = loadBtn("btnApp2", def: 354.9)
        btnApp3 = loadBtn("btnApp3", def: 473.176)
        btnSmall = loadBtn("btnSmall", def: 354.9)
        btnMed1 = loadBtn("btnMed1", def: 177.4)
        btnMed2 = loadBtn("btnMed2", def: 354.9)
        btnMed3 = loadBtn("btnMed3", def: 473.176)
        btnLive1 = loadBtn("btnLive1", def: 177.4)
        btnLive2 = loadBtn("btnLive2", def: 354.9)
        btnLive3 = loadBtn("btnLive3", def: 473.176)
        btnWatch1 = loadBtn("btnWatch1", def: 236.588)
        btnWatch2 = loadBtn("btnWatch2", def: 473.176)
        
        baseGoalML = savedBase == 0 ? 2000 : savedBase
        dailyGoalML = savedGoal == 0 ? 2000 : savedGoal
        currentIntakeML = d.double(forKey: "currentIntakeML")
        isOunces = d.bool(forKey: "isOunces")
        lastDrinkTimestamp = d.object(forKey: "lastDrinkTimestamp") as? Date ?? Date()
        useAdaptiveGoals = d.bool(forKey: "useAdaptiveGoals")
        goalAdjustedBy = d.double(forKey: "goalAdjustedBy")
        adaptiveReason = d.string(forKey: "adaptiveReason") ?? ""
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

    func requestNotificationPermissions() { UNUserNotificationCenter.current().requestAuthorization(options:[.alert, .sound]) { _, _ in } }

    func scheduleDailySummary() {
        cancelDailySummary()
        let center = UNUserNotificationCenter.current()
        if let goalHitDate = Constants.defaults.object(forKey: "goalHitDate") as? Date, Calendar.current.isDateInToday(goalHitDate) { return }
        let content = buildSummaryNotificationContent()
        var components = DateComponents()
        components.hour = 21
        components.minute = 0
        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
        let request = UNNotificationRequest(identifier: "DailySummary", content: content, trigger: trigger)
        center.add(request) { _ in }
    }

    private func buildSummaryNotificationContent() -> UNMutableNotificationContent {
        let content = UNMutableNotificationContent()
        let current = HydrationMath.currentLevel(intake: currentIntakeML, lastDrink: lastDrinkTimestamp, now: Date())
        let pct = Int(min(1.0, current / max(1, dailyGoalML)) * 100)
        let remaining = max(0, dailyGoalML - current)

        content.title = pct >= 80 ? "Almost there! 💧" : pct >= 50 ? "Halfway there — keep drinking 💧" : "Don't forget to hydrate 💧"
        var body = "You're at \(pct)% of your goal."
        if remaining > 0 { body += " \(HydrationMath.formatLabel(amount: remaining, isOunces: isOunces)) more gets you there." }
        if goalAdjustedBy > 0 && !adaptiveReason.isEmpty { body += " Note: \(adaptiveReason) raised your goal today." }
        content.body = body
        content.sound = .default
        return content
    }

    func cancelDailySummary() { UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers:["DailySummary"]) }

    func refreshDailySummary() {
        guard dailySummaryEnabled else { return }
        if let goalHitDate = Constants.defaults.object(forKey: "goalHitDate") as? Date, Calendar.current.isDateInToday(goalHitDate) {
            cancelDailySummary()
            return
        }
        scheduleDailySummary()
    }

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
        fetchHistory(from: start, to: now) {[weak self] h in self?.extendedHistory = h }
    }

    private func fetchHistory(from start: Date, to end: Date, completion: @escaping ([DailyIntake]) -> Void) {
        var interval = DateComponents(); interval.day = 1
        let predicate = HKQuery.predicateForSamples(withStart: start, end: end, options: .strictStartDate)
        let query = HKStatisticsCollectionQuery(quantityType: waterType, quantitySamplePredicate: predicate, options: .cumulativeSum, anchorDate: start, intervalComponents: interval)
        query.initialResultsHandler = { [weak self] _, results, _ in
            guard let results = results, let self = self else { return }
            var history:[DailyIntake] = []
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
        let query = HKSampleQuery(sampleType: waterType, predicate: predicate, limit: HKObjectQueryNoLimit, sortDescriptors: [sort]) { [weak self] _, samples, _ in
            guard let samples = samples as? [HKQuantitySample], let self = self else { return }
            Task { @MainActor in
                self.todaysSamples = samples.reversed()
                
                var simLevel: Double = 0
                var simTime = startOfDay
                for sample in samples {
                    let amount = sample.quantity.doubleValue(for: HKUnit.literUnit(with: .milli))
                    simLevel = HydrationMath.currentLevel(intake: simLevel, lastDrink: simTime, now: sample.startDate) + amount
                    simTime = sample.startDate
                }
                self.currentIntakeML = simLevel
                self.lastDrinkTimestamp = simTime
                self.ensureActivityRunning(forceUpdate: true)
                self.pushStateToWatch()
            }
        }
        healthStore.execute(query)
    }

    func syncPendingAppGroupLogs() {
        guard HKHealthStore.isHealthDataAvailable() else { return }
        let pending = Constants.defaults.array(forKey: "pendingHKLogs") as? [Double] ?? []
        guard !pending.isEmpty else { return }
        for amount in pending {
            let sample = HKQuantitySample(type: waterType, quantity: HKQuantity(unit: HKUnit.literUnit(with: .milli), doubleValue: amount), start: Date(), end: Date())
            healthStore.save(sample) { _, _ in }
        }
        Constants.defaults.set([], forKey: "pendingHKLogs")
    }

    func addDrink(amountML: Double) {
        UIImpactFeedbackGenerator(style: .rigid).impactOccurred()
        let newLevel = HydrationMath.currentLevel(intake: currentIntakeML, lastDrink: lastDrinkTimestamp, now: Date()) + amountML
        currentIntakeML = newLevel
        lastDrinkTimestamp = Date()

        let sample = HKQuantitySample(type: waterType, quantity: HKQuantity(unit: HKUnit.literUnit(with: .milli), doubleValue: amountML), start: Date(), end: Date())
        healthStore.save(sample) { [weak self] success, _ in
            if success {
                Task { @MainActor in
                    self?.syncFromHealthKit() // 🌟 Fixes Undo Lag Instantly
                }
            }
        }

        if newLevel >= dailyGoalML {
            handleGoalAchieved()
        } else {
            ensureActivityRunning(forceUpdate: true)
            refreshDailySummary()
        }
        self.pushStateToWatch()
        WidgetCenter.shared.reloadAllTimelines() 
    }
    
    func undoLastDrink() {
        guard let lastSample = todaysSamples.first else { return }
        deleteSample(lastSample)
    }
    
    func deleteSample(_ sample: HKQuantitySample) {
        healthStore.delete(sample) { success, _ in
            if success { Task { @MainActor in self.syncFromHealthKit() } }
        }
    }

    private func handleGoalAchieved() {
        StreakManager.recordGoalHit()
        currentStreak = StreakManager.computeStreak()
        milestoneBadge = StreakManager.milestoneBadge(for: currentStreak)
        Constants.defaults.set(Date(), forKey: "goalHitDate")
        cancelDailySummary()

        Task {
            for activity in Activity<HydrationAttributes>.activities {
                await activity.end(ActivityContent(state: activity.content.state, staleDate: nil), dismissalPolicy: .immediate)
            }
            let content = UNMutableNotificationContent()
            content.title = "Goal Achieved! \(StreakManager.flameEmoji(for: currentStreak))"
            content.body = currentStreak > 1 ? "\(currentStreak)-day streak! See you tomorrow!" : "Goal hit. See you tomorrow!"
            content.sound = .default
            try? await UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: "GoalHit", content: content, trigger: nil))
        }
    }

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

    func ensureActivityRunning(forceUpdate: Bool = false) {
        if let goalHitDate = Constants.defaults.object(forKey: "goalHitDate") as? Date, Calendar.current.isDateInToday(goalHitDate) { return }

        let state = HydrationAttributes.ContentState(
            currentIntake: currentIntakeML,
            lastDrinkTimestamp: lastDrinkTimestamp,
            dailyGoal: dailyGoalML,
            isOunces: isOunces,
            streak: currentStreak,
            goalAdjustedBy: goalAdjustedBy,
            btnLive1: btnLive1,
            btnLive2: btnLive2,
            btnLive3: btnLive3,
        )
        if let activity = Activity<HydrationAttributes>.activities.first {
            Task { await activity.update(ActivityContent(state: state, staleDate: nil)) }
        } else {
            _ = try? Activity.request(attributes: HydrationAttributes(), content: ActivityContent(state: state, staleDate: nil), pushType: nil)
        }
    }

    func refreshAdaptiveGoal() async {
        guard useAdaptiveGoals else { return }
        let lastAdjustKey = "adaptiveAdjustDate"
        if let lastDate = Constants.defaults.object(forKey: lastAdjustKey) as? Date, Calendar.current.isDateInToday(lastDate) { return }

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
        refreshDailySummary()
        pushStateToWatch()

        let content = UNMutableNotificationContent()
        content.title = "Goal Updated 💧"
        content.body = "\(reasonText). We've added \(HydrationMath.formatLabel(amount: totalBumpML, isOunces: isOunces)) to your goal."
        content.sound = .default
        try? await UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: "AdaptiveGoal", content: content, trigger: nil))
    }
    
        func setLogButton(slot: Int, amountML: Double) {
            guard slot < customButtons.count else { return }
            customButtons[slot] = LogButton(amountML: amountML)
            ensureActivityRunning(forceUpdate: true)
        }

    private func resetGoalToBase() {
        dailyGoalML = baseGoalML
        goalAdjustedBy = 0
        adaptiveReason = ""
        Constants.defaults.set(0.0, forKey: "goalAdjustedBy")
        Constants.defaults.set("", forKey: "adaptiveReason")
        ensureActivityRunning(forceUpdate: true)
        pushStateToWatch()
    }

    private func fetchWeatherBump() async -> (ml: Double, reason: String)? {
        guard CLLocationManager.locationServicesEnabled() else { return nil }
        let auth = locationManager.authorizationStatus
        guard auth == .authorizedWhenInUse || auth == .authorizedAlways else { locationManager.requestWhenInUseAuthorization(); return nil }
        let location = locationManager.location ?? CLLocation(latitude: 37.7749, longitude: -122.4194)
        do {
            let weather = try await WeatherService.shared.weather(for: location)
            let tempC = weather.currentWeather.temperature.converted(to: .celsius).value
            if tempC > 37 { return (baseGoalML * 0.20, "Very hot today") }
            if tempC > 30 { return (baseGoalML * 0.15, "Hot day") }
        } catch {}
        return nil
    }

    private func fetchActivityBump() async -> (ml: Double, reason: String)? {
        guard HKHealthStore.isHealthDataAvailable() else { return nil }
        let predicate = HKQuery.predicateForSamples(withStart: Date().addingTimeInterval(-86400), end: Date(), options: .strictStartDate)
        return await withCheckedContinuation { continuation in
            let query = HKStatisticsQuery(quantityType: energyType, quantitySamplePredicate: predicate, options: .cumulativeSum) { _, result, _ in
                let kcal = result?.sumQuantity()?.doubleValue(for: .kilocalorie()) ?? 0
                if kcal > 600 { continuation.resume(returning: (self.baseGoalML * 0.20, "Heavy workout")) }
                else if kcal > 300 { continuation.resume(returning: (self.baseGoalML * 0.10, "Active day")) }
                else { continuation.resume(returning: nil) }
            }
            healthStore.execute(query)
        }
    }

    func dismissMilestoneBadge() { milestoneBadge = nil }
}
