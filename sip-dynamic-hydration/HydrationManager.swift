import SwiftUI
import Combine
import ActivityKit
import HealthKit
import UserNotifications

struct DailyIntake: Identifiable {
    let id = UUID()
    let date: Date
    let amountML: Double
}

@MainActor
class HydrationManager: ObservableObject {
    @Published var dailyGoalML: Double = 2000 {
        didSet {
            Constants.defaults.set(dailyGoalML, forKey: "dailyGoalML")
            ensureActivityRunning(forceUpdate: true)
        }
    }
    @Published var currentIntakeML: Double = 0 {
        didSet { Constants.defaults.set(currentIntakeML, forKey: "currentIntakeML") }
    }
    @Published var isOunces: Bool = false {
        didSet {
            Constants.defaults.set(isOunces, forKey: "isOunces")
            ensureActivityRunning(forceUpdate: true)
        }
    }
    @Published var lastDrinkTimestamp: Date = Date() {
        didSet { Constants.defaults.set(lastDrinkTimestamp, forKey: "lastDrinkTimestamp") }
    }
    
    @Published var weeklyHistory: [DailyIntake] = []
    
    private let healthStore = HKHealthStore()
    private let waterType = HKQuantityType.quantityType(forIdentifier: .dietaryWater)!
    
    init() {
        reloadFromDefaults()
        checkMidnightReset()
        ensureActivityRunning()
        syncPendingAppGroupLogs()
        requestNotificationPermissions()
    }
    
    func reloadFromDefaults() {
        let savedGoal = Constants.defaults.double(forKey: "dailyGoalML")
        self.dailyGoalML = savedGoal == 0 ? 2000 : savedGoal
        self.currentIntakeML = Constants.defaults.double(forKey: "currentIntakeML")
        self.isOunces = Constants.defaults.bool(forKey: "isOunces")
        self.lastDrinkTimestamp = Constants.defaults.object(forKey: "lastDrinkTimestamp") as? Date ?? Date()
    }
    
    func requestNotificationPermissions() {
        UNUserNotificationCenter.current().requestAuthorization(options:[.alert, .sound]) { _, _ in }
    }
    
    func requestHealthKit() {
        guard HKHealthStore.isHealthDataAvailable() else { return }
        healthStore.requestAuthorization(toShare: [waterType], read: [waterType]) { success, _ in
            if success {
                self.healthStore.enableBackgroundDelivery(for: self.waterType, frequency: .immediate) { _, _ in }
                Task { @MainActor in
                    self.syncFromHealthKit()
                }
            }
        }
    }
    
    func fetchWeeklyHistory() {
        let calendar = Calendar.current
        let now = Date()
        let startOfToday = calendar.startOfDay(for: now)
        guard let startOfWeek = calendar.date(byAdding: .day, value: -6, to: startOfToday) else { return }
        
        let predicate = HKQuery.predicateForSamples(withStart: startOfWeek, end: now, options: .strictStartDate)
        var interval = DateComponents()
        interval.day = 1
        
        let query = HKStatisticsCollectionQuery(quantityType: waterType, quantitySamplePredicate: predicate, options: .cumulativeSum, anchorDate: startOfWeek, intervalComponents: interval)
        
        query.initialResultsHandler = { _, results, _ in
            guard let results = results else { return }
            var history: [DailyIntake] = []
            results.enumerateStatistics(from: startOfWeek, to: now) { statistics, _ in
                let total = statistics.sumQuantity()?.doubleValue(for: HKUnit.literUnit(with: .milli)) ?? 0
                history.append(DailyIntake(date: statistics.startDate, amountML: total))
            }
            Task { @MainActor in self.weeklyHistory = history }
        }
        healthStore.execute(query)
    }
    
    func syncFromHealthKit() {
        fetchWeeklyHistory()
        
        let startOfDay = Calendar.current.startOfDay(for: Date())
        let predicate = HKQuery.predicateForSamples(withStart: startOfDay, end: Date(), options: .strictStartDate)
        let sortDescriptor = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: true)
        
        let query = HKSampleQuery(sampleType: waterType, predicate: predicate, limit: HKObjectQueryNoLimit, sortDescriptors:[sortDescriptor]) { _, samples, _ in
            guard let samples = samples as? [HKQuantitySample] else { return }
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
        healthStore.save(sample) { _, _ in
            Task { @MainActor in self.fetchWeeklyHistory() }
        }
        
        if newLevel >= dailyGoalML {
            Constants.defaults.set(Date(), forKey: "goalHitDate")
            Task {
                for activity in Activity<HydrationAttributes>.activities {
                    await activity.end(ActivityContent(state: activity.content.state, staleDate: nil), dismissalPolicy: .immediate)
                }
                
                let content = UNMutableNotificationContent()
                content.title = "Goal Achieved! 💧"
                content.body = "You hit your daily hydration goal. See you tomorrow!"
                content.sound = .default
                try? await UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: "GoalHit", content: content, trigger: nil))
            }
        } else {
            ensureActivityRunning(forceUpdate: true)
        }
    }
    
    func checkMidnightReset() {
        if !Calendar.current.isDateInToday(lastDrinkTimestamp) {
            currentIntakeML = 0
            lastDrinkTimestamp = Date()
            Constants.defaults.removeObject(forKey: "goalHitDate")
            Task {
                for activity in Activity<HydrationAttributes>.activities {
                    await activity.end(ActivityContent(state: activity.content.state, staleDate: nil), dismissalPolicy: .immediate)
                }
            }
            ensureActivityRunning()
        }
    }
    
    func ensureActivityRunning(forceUpdate: Bool = false) {
        if let goalHitDate = Constants.defaults.object(forKey: "goalHitDate") as? Date, Calendar.current.isDateInToday(goalHitDate) {
            return // Goal achieved, keep activity hidden
        }
        
        let state = HydrationAttributes.ContentState(
            currentIntake: currentIntakeML,
            lastDrinkTimestamp: lastDrinkTimestamp,
            dailyGoal: dailyGoalML,
            isOunces: isOunces
        )
        if let activity = Activity<HydrationAttributes>.activities.first {
            Task { await activity.update(ActivityContent(state: state, staleDate: nil)) }
        } else {
            _ = try? Activity.request(attributes: HydrationAttributes(), content: ActivityContent(state: state, staleDate: nil), pushType: nil)
        }
    }
}
