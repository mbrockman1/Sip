//
//  SharedLogic.swift
//  sip-dynamic-hydration
//

import Foundation
import AppIntents
import SwiftUI
import UserNotifications


// MARK: - App Group Constants
struct Constants {
    static let appGroup = "group.org.mjbapps.sip"
    nonisolated(unsafe) static let defaults = UserDefaults(suiteName: appGroup)!
}

// MARK: - LogButton (shared: main app + widget both read/write this)
/// Codable so it survives encoding into App Group UserDefaults.
/// Defined here so the widget target can decode it without importing HydrationManager.
struct LogButton: Codable {
    var amountML: Double
 
    func label(isOunces: Bool) -> String {
        let display = isOunces ? (amountML / 29.5735) : amountML
        let unit = isOunces ? "oz" : "ml"
        return "+ \(Int(display.rounded())) \(unit)"
    }
}



// MARK: - Core Hydration Math
struct HydrationMath: Sendable {
    /// Metabolic decay: body processes ~60ml/hr continuously
    static func currentLevel(intake: Double, lastDrink: Date, now: Date) -> Double {
        let hoursPassed = max(0, now.timeIntervalSince(lastDrink)) / 3600.0
        let decay = hoursPassed * 60.0
        return max(0, intake - decay)
    }

    /// How many ml are being lost per hour right now (always 60)
    static let decayRatePerHour: Double = 60.0

    static func formatLabel(amount: Double, isOunces: Bool) -> String {
        let displayAmount = isOunces ? (amount / 29.5735) : amount
        let unit = isOunces ? "oz" : "ml"
        return "\(Int(displayAmount)) \(unit)"
    }

    /// Percentage of goal met, clamped 0–1
    static func fillRatio(current: Double, goal: Double) -> Double {
        guard goal > 0 else { return 0 }
        return min(1.0, current / goal)
    }
}

// MARK: - Streak Logic
struct StreakManager {
    /// Returns the current consecutive-day streak from persisted history.
    /// A day "counts" if the user logged >= their goal that day.
    static func computeStreak() -> Int {
        let defaults = Constants.defaults
        // goalHitDates: array of day-start timestamps stored as [Double] (timeIntervalSinceReferenceDate)
        let rawDates = defaults.array(forKey: "goalHitDates") as? [Double] ?? []
        let calendar = Calendar.current

        // Build a Set of day-start dates where goal was hit
        let hitDays: Set<Date> = Set(rawDates.compactMap { interval -> Date? in
            let date = Date(timeIntervalSinceReferenceDate: interval)
            return calendar.startOfDay(for: date)
        })

        var streak = 0
        var checkDate = calendar.startOfDay(for: Date())

        // Walk backwards from today (or yesterday if today not yet hit)
        // Start from today — if today is not yet hit, we still show yesterday's streak
        while hitDays.contains(checkDate) {
            streak += 1
            guard let prev = calendar.date(byAdding: .day, value: -1, to: checkDate) else { break }
            checkDate = prev
        }

        // If today not hit yet, check if yesterday starts the chain
        if streak == 0 {
            guard let yesterday = calendar.date(byAdding: .day, value: -1, to: calendar.startOfDay(for: Date())) else { return 0 }
            checkDate = yesterday
            while hitDays.contains(checkDate) {
                streak += 1
                guard let prev = calendar.date(byAdding: .day, value: -1, to: checkDate) else { break }
                checkDate = prev
            }
        }

        return streak
    }

    /// Call this when the user hits their daily goal
    static func recordGoalHit() {
        let defaults = Constants.defaults
        var rawDates = defaults.array(forKey: "goalHitDates") as? [Double] ?? []
        let today = Calendar.current.startOfDay(for: Date()).timeIntervalSinceReferenceDate
        if !rawDates.contains(today) {
            rawDates.append(today)
            defaults.set(rawDates, forKey: "goalHitDates")
        }
    }

    /// Flame emoji scale based on streak length
    static func flameEmoji(for streak: Int) -> String {
        switch streak {
        case 0: return "💧"
        case 1...2: return "🔥"
        case 3...6: return "🔥🔥"
        default: return "🔥🔥🔥"
        }
    }

    /// Badge label for milestone streaks
    static func milestoneBadge(for streak: Int) -> String? {
        switch streak {
        case 3: return "3-Day Streak 🏅"
        case 7: return "Hydration Pro 🏆"
        case 14: return "Hydration Elite 💎"
        case 30: return "Hydration Legend 🌊"
        default: return nil
        }
    }
}

func readLogButtons(isOunces: Bool) -> [(amount: Double, label: String)] {
    struct LogButtonCodable: Codable { var amountML: Double }
    let defaults = Constants.defaults
    if let data = defaults.data(forKey: "customButtons"),
       let saved = try? JSONDecoder().decode([LogButtonCodable].self, from: data) {
        return saved.map { btn in
            let display = isOunces ? (btn.amountML / 29.5735) : btn.amountML
            let unit    = isOunces ? "oz" : "ml"
            return (btn.amountML, "+\(Int(display.rounded())) \(unit)")
        }
    }
    // Default fallback
    let defaults2: [(Double, Double, String)] = isOunces
        ? [(100, 3.4, "3 oz"), (250, 8.5, "8 oz"), (500, 16.9, "17 oz")]
        : [(100, 100, "100 ml"), (250, 250, "250 ml"), (500, 500, "500 ml")]
    return defaults2.map { (ml, _, lbl) in (ml, "+\(lbl)") }
}


func timeSinceLabel(mins: Double) -> String {
    let m = Int(mins)
    if m < 1  { return "just now" }
    if m < 60 { return "\(m)m ago" }
    return "\(m/60)h \(m%60)m"
}

struct SipButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline.bold()).foregroundColor(.white)
            .frame(maxWidth: .infinity).padding(.vertical, 16)
            .background(Color.cyan).cornerRadius(16)
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
            .animation(.easeInOut(duration: 0.1), value: configuration.isPressed)
    }
}
