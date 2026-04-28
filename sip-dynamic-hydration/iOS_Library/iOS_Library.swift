//
//  iOS_Library.swift
//  sip-dynamic-hydration
//
//  Created by Michael Brockman on 4/28/26.
//

import Foundation
import AppIntents
import SwiftUI
import UserNotifications

import ActivityKit


// MARK: - Live Activity Attributes
struct HydrationAttributes: ActivityAttributes, Sendable {
    public struct ContentState: Codable, Hashable, Sendable {
        var currentIntake: Double
        var lastDrinkTimestamp: Date
        var dailyGoal: Double
        var isOunces: Bool
        var streak: Int           // 🔥 New: current streak for Live Activity
        var goalAdjustedBy: Double // New: how much goal was bumped today (0 = no bump)
    }
    var name: String = "SipTracker"
}

// MARK: - LogWaterIntent (Live Activity tap-to-log)
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
        let goalAdjustedBy = defaults.double(forKey: "goalAdjustedBy")

        let newLevel = HydrationMath.currentLevel(intake: currentIntake, lastDrink: lastDrink, now: Date()) + amount

        defaults.set(newLevel, forKey: "currentIntakeML")
        defaults.set(Date(), forKey: "lastDrinkTimestamp")

        // Queue for HealthKit sync when app opens
        var pending = defaults.array(forKey: "pendingHKLogs") as? [Double] ?? []
        pending.append(amount)
        defaults.set(pending, forKey: "pendingHKLogs")

        let streak = StreakManager.computeStreak()

        let state = HydrationAttributes.ContentState(
            currentIntake: newLevel,
            lastDrinkTimestamp: Date(),
            dailyGoal: dailyGoal,
            isOunces: defaults.bool(forKey: "isOunces"),
            streak: streak,
            goalAdjustedBy: goalAdjustedBy
        )

        if newLevel >= dailyGoal {
            // Record the streak hit
            StreakManager.recordGoalHit()
            defaults.set(Date(), forKey: "goalHitDate")

            // End Live Activity
            for activity in Activity<HydrationAttributes>.activities {
                await activity.end(ActivityContent(state: state, staleDate: nil), dismissalPolicy: .immediate)
            }

            // Goal notification
            let newStreak = StreakManager.computeStreak()
            let content = UNMutableNotificationContent()
            content.title = "Goal Achieved! \(StreakManager.flameEmoji(for: newStreak))"
            if let badge = StreakManager.milestoneBadge(for: newStreak) {
                content.body = "You earned: \(badge). See you tomorrow!"
            } else {
                content.body = newStreak > 1
                    ? "Day \(newStreak) streak! Keep it up. See you tomorrow!"
                    : "You hit your daily hydration goal. See you tomorrow!"
            }
            content.sound = .default
            try? await UNUserNotificationCenter.current().add(
                UNNotificationRequest(identifier: "GoalHit", content: content, trigger: nil)
            )
        } else {
            if Activity<HydrationAttributes>.activities.isEmpty {
                _ = try? Activity.request(
                    attributes: HydrationAttributes(),
                    content: ActivityContent(state: state, staleDate: nil),
                    pushType: nil
                )
            } else {
                for activity in Activity<HydrationAttributes>.activities {
                    await activity.update(ActivityContent(state: state, staleDate: nil))
                }
            }
        }
        return .result()
    }
}

