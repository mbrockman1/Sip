//
//  SharedLogic.swift
//  sip-dynamic-hydration
//

import Foundation
import AppIntents
import SwiftUI
import UserNotifications
import WidgetKit


// MARK: - App Group Constants
struct Constants {
    static let appGroup = "group.org.mjbapps.sip"
    static let defaults: UserDefaults = UserDefaults(suiteName: appGroup)!
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
    static let ozMultiplier = 29.5735296
    
    static func currentLevel(intake: Double, lastDrink: Date, now: Date) -> Double {
        let hoursPassed = max(0, now.timeIntervalSince(lastDrink)) / 3600.0
        let decay = hoursPassed * 60.0
        return max(0, intake - decay)
    }

    static let decayRatePerHour: Double = 60.0

    static func formatLabel(amount: Double, isOunces: Bool) -> String {
        let displayAmount = isOunces ? (amount / 29.5735) : amount
        let unit = isOunces ? "oz" : "ml"
        return "\(Int(round(displayAmount))) \(unit)" 
    }

    /// Percentage of goal met, clamped 0–1
    static func fillRatio(current: Double, goal: Double) -> Double {
        guard goal > 0 else { return 0 }
        return min(1.0, current / goal)
    }
}

// MARK: - Streak Logic
struct StreakManager {
    static let defaults = Constants.defaults
    
    
    static func computeStreak() -> Int {
        let lastHit = defaults.object(forKey: "lastGoalHitDate") as? Date ?? Date.distantPast
        let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: Calendar.current.startOfDay(for: Date()))!
        
        // If they didn't hit it yesterday or today, streak is broken
        if !Calendar.current.isDate(lastHit, inSameDayAs: yesterday) && !Calendar.current.isDateInToday(lastHit) {
            defaults.set(0, forKey: "currentStreak")
            return 0
        }
        return defaults.integer(forKey: "currentStreak")
    }
    

    static func recordGoalHit() {
        let today = Calendar.current.startOfDay(for: Date())
        let lastHit = defaults.object(forKey: "lastGoalHitDate") as? Date ?? Date.distantPast
        
        // If we already hit it today, don't increment
        if Calendar.current.isDateInToday(lastHit) { return }
        
        // If yesterday, increment streak. If not, reset to 1.
        let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: today)!
        if Calendar.current.isDate(lastHit, inSameDayAs: yesterday) {
            let current = defaults.integer(forKey: "currentStreak")
            defaults.set(current + 1, forKey: "currentStreak")
        } else {
            defaults.set(1, forKey: "currentStreak")
        }
        defaults.set(today, forKey: "lastGoalHitDate")
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
