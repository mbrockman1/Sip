import Foundation
import HealthKit
import WatchConnectivity
import SwiftUI
import Combine
import WidgetKit

struct WatchMath {
    static func currentLevel(intake: Double, lastDrink: Date, now: Date) -> Double {
        let hoursPassed = max(0, now.timeIntervalSince(lastDrink)) / 3600.0
        let decay = hoursPassed * 60.0
        return max(0, intake - decay)
    }
    
    static func formatLabel(amount: Double, isOunces: Bool) -> String {
        let displayAmount = isOunces ? (amount / 29.5735) : amount
        let unit = isOunces ? "oz" : "ml"
        return "\(Int(displayAmount)) \(unit)"
    }
}

@MainActor
class WatchManager: NSObject, ObservableObject, WCSessionDelegate {
    
    // 🌟 MUST USE APP GROUP SO THE COMPLICATION CAN READ THIS DATA
    let sharedDefaults = UserDefaults(suiteName: "group.org.mjbapps.sip")!
    
    @Published var dailyGoalML: Double
    @Published var currentIntakeML: Double
    @Published var isOunces: Bool
    @Published var lastDrinkTimestamp: Date
    
    @Published var btnWatch1: Double
    @Published var btnWatch2: Double
    
    let healthStore = HKHealthStore()
    let waterType = HKQuantityType.quantityType(forIdentifier: .dietaryWater)!
    
    override init() {
        self.dailyGoalML = sharedDefaults.double(forKey: "dailyGoalML") == 0 ? 2000 : sharedDefaults.double(forKey: "dailyGoalML")
        self.currentIntakeML = sharedDefaults.double(forKey: "currentIntakeML")
        self.isOunces = sharedDefaults.bool(forKey: "isOunces")
        self.lastDrinkTimestamp = sharedDefaults.object(forKey: "lastDrinkTimestamp") as? Date ?? Date()
        self.btnWatch1 = sharedDefaults.double(forKey: "btnWatch1") == 0 ? 236.588 : sharedDefaults.double(forKey: "btnWatch1")
        self.btnWatch2 = sharedDefaults.double(forKey: "btnWatch2") == 0 ? 473.176 : sharedDefaults.double(forKey: "btnWatch2")
        
        super.init()
        if WCSession.isSupported() {
            WCSession.default.delegate = self
            WCSession.default.activate()
        }
    }
    
    func requestAuthorization() {
        guard HKHealthStore.isHealthDataAvailable() else { return }
        healthStore.requestAuthorization(toShare:[waterType], read:[waterType]) { success, _ in
            if success { Task { @MainActor in self.fetchTodayData() } }
        }
    }
    
    func fetchTodayData() {
        let startOfDay = Calendar.current.startOfDay(for: Date())
        let predicate = HKQuery.predicateForSamples(withStart: startOfDay, end: Date(), options: .strictStartDate)
        let sortDescriptor = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: true)
        
        let query = HKSampleQuery(sampleType: waterType, predicate: predicate, limit: HKObjectQueryNoLimit, sortDescriptors: [sortDescriptor]) { _, samples, _ in
            guard let samples = samples as?[HKQuantitySample] else { return }
            Task { @MainActor in
                var simLevel: Double = 0
                var simTime = startOfDay
                for sample in samples {
                    let amount = sample.quantity.doubleValue(for: HKUnit.literUnit(with: .milli))
                    simLevel = WatchMath.currentLevel(intake: simLevel, lastDrink: simTime, now: sample.startDate) + amount
                    simTime = sample.startDate
                }
                self.updateLocalState(intake: simLevel, timestamp: simTime)
            }
        }
        healthStore.execute(query)
    }
    
    func addDrink(amountML: Double) {
        WKInterfaceDevice.current().play(.click)
        
        // Optimistic UI update
        let newLevel = WatchMath.currentLevel(intake: currentIntakeML, lastDrink: lastDrinkTimestamp, now: Date()) + amountML
        updateLocalState(intake: newLevel, timestamp: Date())
        
        // 🌟 INSTANT SYNC: Tells the iPhone to do the saving and math!
        if WCSession.default.isReachable {
            WCSession.default.sendMessage(["addDrink": amountML], replyHandler: nil)
        } else {
            // Fallback if iPhone is out of range
            let sample = HKQuantitySample(type: waterType, quantity: HKQuantity(unit: HKUnit.literUnit(with: .milli), doubleValue: amountML), start: Date(), end: Date())
            healthStore.save(sample) { _, _ in
                WidgetCenter.shared.reloadAllTimelines()
            }
        }
    }
    
    private func updateLocalState(intake: Double, timestamp: Date) {
        self.currentIntakeML = intake
        self.lastDrinkTimestamp = timestamp
        sharedDefaults.set(intake, forKey: "currentIntakeML")
        sharedDefaults.set(timestamp, forKey: "lastDrinkTimestamp")
        WidgetCenter.shared.reloadAllTimelines() // 🌟 Forces Complication to update
    }
    
    // MARK: - WCSession Delegate
    nonisolated func session(_ session: WCSession, activationDidCompleteWith state: WCSessionActivationState, error: Error?) {}
    
    nonisolated func session(_ session: WCSession, didReceiveApplicationContext applicationContext:[String : Any]) {
        Task { @MainActor in
            if let isOunces = applicationContext["isOunces"] as? Bool {
                self.isOunces = isOunces
                sharedDefaults.set(isOunces, forKey: "isOunces")
            }
            if let goal = applicationContext["dailyGoalML"] as? Double {
                self.dailyGoalML = goal
                sharedDefaults.set(goal, forKey: "dailyGoalML")
            }
            // 🌟 Receive live data from iPhone
            if let intake = applicationContext["currentIntakeML"] as? Double,
               let timestamp = applicationContext["lastDrinkTimestamp"] as? Date {
                self.updateLocalState(intake: intake, timestamp: timestamp)
            }
            if let b1 = applicationContext["btnWatch1"] as? Double { self.btnWatch1 = b1; sharedDefaults.set(b1, forKey: "btnWatch1") }
            if let b2 = applicationContext["btnWatch2"] as? Double { self.btnWatch2 = b2; sharedDefaults.set(b2, forKey: "btnWatch2") }
        }
    }
}
