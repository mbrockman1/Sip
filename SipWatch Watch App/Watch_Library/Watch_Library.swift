//
//  Watch_Library.swift
//  SipWatch Extension
//
//  Add to BOTH the Watch App target and the Watch Widget Extension target.
//

import SwiftUI
import WidgetKit
import ClockKit

// MARK: - Watch Log Button

struct WatchLogButton: View {
    let label: String
    let amount: Double
    let onLog: (Double) -> Void

    var body: some View {
        Button(action: { onLog(amount) }) {
            Text(label)
                .font(.system(size: 13, weight: .bold))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
                .background(Color.cyan.opacity(0.2))
                .foregroundColor(.cyan)
                .cornerRadius(10)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Timeline Entry
// goalAdjustedBy added so rectangular complication can show adaptive info

struct WatchHydrationEntry: TimelineEntry {
    let date: Date
    let currentML: Double
    let goalML: Double
    let lastDrink: Date
    let isOunces: Bool
    let streak: Int
    let goalAdjustedBy: Double
}

// MARK: - Timeline Provider

struct SipWatchProvider: TimelineProvider {
    func placeholder(in context: Context) -> WatchHydrationEntry {
        WatchHydrationEntry(
            date: Date(), currentML: 1200, goalML: 2000,
            lastDrink: Date().addingTimeInterval(-1800),
            isOunces: false, streak: 3, goalAdjustedBy: 0
        )
    }

    func getSnapshot(in context: Context, completion: @escaping (WatchHydrationEntry) -> Void) {
        completion(makeEntry())
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<WatchHydrationEntry>) -> Void) {
        let test = UserDefaults(suiteName: "group.org.mjbapps.sip")
        print("Widget defaults test:", test?.string(forKey: "isOunces") ?? "NIL — App Group not accessible")
         
        let entry = makeEntry()
        // Refresh every 5 minutes — keeps decay reading accurate
        let next = Date().addingTimeInterval(5 * 60)
        completion(Timeline(entries: [entry], policy: .after(next)))
    }

    private func makeEntry() -> WatchHydrationEntry {
        let d = Constants.defaults
        let savedGoal = d.double(forKey: "dailyGoalML")
        return WatchHydrationEntry(
            date: Date(),
            currentML:      d.double(forKey: "currentIntakeML"),
            goalML:         savedGoal == 0 ? 2000 : savedGoal,
            lastDrink:      d.object(forKey: "lastDrinkTimestamp") as? Date ?? Date(),
            isOunces:       d.bool(forKey: "isOunces"),
            streak:         StreakManager.computeStreak(),
            goalAdjustedBy: d.double(forKey: "goalAdjustedBy")
        )
    }
}
