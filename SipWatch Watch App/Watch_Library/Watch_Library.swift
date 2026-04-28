//
//  SipWatchApp.swift
//  SipWatch Extension
//
//  Add this file to a new watchOS App target in Xcode.
//  Set the Watch App's App Group to match Constants.appGroup.
//  In the watchOS target's Info.plist add WKBackgroundModes: workout-processing
//

import SwiftUI
import WidgetKit
import ClockKit


// MARK: - Watch Log Button
struct WatchLogButton: View {
    let label: String
    let amount: Double
    let isOunces: Bool
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

// MARK: - Complication Provider (WidgetKit on watchOS)

import WidgetKit

struct WatchHydrationEntry: TimelineEntry {
    let date: Date
    let currentML: Double
    let goalML: Double
    let lastDrink: Date
    let isOunces: Bool
    let streak: Int
}

struct SipWatchProvider: TimelineProvider {
    func placeholder(in context: Context) -> WatchHydrationEntry {
        WatchHydrationEntry(date: Date(), currentML: 1200, goalML: 2000, lastDrink: Date(), isOunces: false, streak: 3)
    }

    func getSnapshot(in context: Context, completion: @escaping (WatchHydrationEntry) -> Void) {
        completion(makeEntry())
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<WatchHydrationEntry>) -> Void) {
        let entry = makeEntry()
        // Refresh every 5 minutes to keep decay accurate
        let next = Date().addingTimeInterval(5 * 60)
        completion(Timeline(entries: [entry], policy: .after(next)))
    }

    private func makeEntry() -> WatchHydrationEntry {
        let d = Constants.defaults
        let savedGoal = d.double(forKey: "dailyGoalML")
        return WatchHydrationEntry(
            date: Date(),
            currentML: d.double(forKey: "currentIntakeML"),
            goalML: savedGoal == 0 ? 2000 : savedGoal,
            lastDrink: d.object(forKey: "lastDrinkTimestamp") as? Date ?? Date(),
            isOunces: d.bool(forKey: "isOunces"),
            streak: StreakManager.computeStreak()
        )
    }
}

