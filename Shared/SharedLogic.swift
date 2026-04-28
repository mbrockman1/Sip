//
//  Constants.swift
//  sip-dynamic-hydration
//
//  Created by Michael Brockman on 4/27/26.
//


import Foundation
import ActivityKit
import AppIntents
import SwiftUI

// MARK: - App Group Constants
struct Constants {
    static let appGroup = "group.org.mjbapps.sip-dynamic-"
    nonisolated(unsafe) static let defaults = UserDefaults(suiteName: appGroup)!
}

struct HydrationAttributes: ActivityAttributes, Sendable {
    public struct ContentState: Codable, Hashable, Sendable {
        var currentIntake: Double
        var lastDrinkTimestamp: Date
        // MOVED TO STATE: This allows the Dynamic Island to update units instantly!
        var dailyGoal: Double
        var isOunces: Bool
    }
    var name: String = "SipTracker"
}

struct HydrationMath: Sendable {
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


struct LogWaterIntent: LiveActivityIntent {
    static var title: LocalizedStringResource = "Log Water"
    @Parameter(title: "Amount (ML)") var amount: Double
    
    init() {}
    init(amount: Double) { self.amount = amount }
    
    func perform() async throws -> some IntentResult {
        let defaults = Constants.defaults
        let currentIntake = defaults.double(forKey: "currentIntakeML")
        let lastDrink = defaults.object(forKey: "lastDrinkTimestamp") as? Date ?? Date()
        let dailyGoal = defaults.double(forKey: "dailyGoalML") == 0 ? 2000 : defaults.double(forKey: "dailyGoalML")
        
        let newLevel = HydrationMath.currentLevel(intake: currentIntake, lastDrink: lastDrink, now: Date()) + amount
        
        defaults.set(newLevel, forKey: "currentIntakeML")
        defaults.set(Date(), forKey: "lastDrinkTimestamp")
        
        var pending = defaults.array(forKey: "pendingHKLogs") as? [Double] ?? []
        pending.append(amount)
        defaults.set(pending, forKey: "pendingHKLogs")
        
        let state = HydrationAttributes.ContentState(
            currentIntake: newLevel,
            lastDrinkTimestamp: Date(),
            dailyGoal: dailyGoal,
            isOunces: defaults.bool(forKey: "isOunces")
        )
        
        // GOAL ACHIEVED LOGIC
        if newLevel >= dailyGoal {
            defaults.set(Date(), forKey: "goalHitDate")
            
            // Kill Activity
            for activity in Activity<HydrationAttributes>.activities {
                await activity.end(ActivityContent(state: state, staleDate: nil), dismissalPolicy: .immediate)
            }
            
            // Send Notification
            let content = UNMutableNotificationContent()
            content.title = "Goal Achieved! 💧"
            content.body = "You hit your daily hydration goal. See you tomorrow!"
            content.sound = .default
            try? await UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: "GoalHit", content: content, trigger: nil))
            
        } else {
            // Update Activity if Goal NOT hit
            if Activity<HydrationAttributes>.activities.isEmpty {
                _ = try? Activity.request(attributes: HydrationAttributes(), content: ActivityContent(state: state, staleDate: nil), pushType: nil)
            } else {
                for activity in Activity<HydrationAttributes>.activities {
                    await activity.update(ActivityContent(state: state, staleDate: nil))
                }
            }
        }
        return .result()
    }
}
