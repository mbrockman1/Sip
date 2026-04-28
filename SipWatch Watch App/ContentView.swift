//
//  ContentView.swift
//  SipWatch Watch App
//
//  Created by Michael Brockman on 4/28/26.
//

import SwiftUI
import WidgetKit

// MARK: - Watch Main View

struct WatchContentView: View {
    // Read directly from shared App Group defaults
    @State private var currentML: Double = 0
    @State private var goalML: Double = 2000
    @State private var lastDrink: Date = Date()
    @State private var isOunces: Bool = false
    @State private var streak: Int = 0

    private var liveLevel: Double {
        HydrationMath.currentLevel(intake: currentML, lastDrink: lastDrink, now: Date())
    }
    private var fillRatio: Double {
        HydrationMath.fillRatio(current: liveLevel, goal: goalML)
    }

    var body: some View {
        TimelineView(.periodic(from: lastDrink, by: 60)) { context in
            let current = HydrationMath.currentLevel(intake: currentML, lastDrink: lastDrink, now: context.date)
            let fill = HydrationMath.fillRatio(current: current, goal: goalML)

            ScrollView {
                VStack(spacing: 12) {

                    // ── Level display ────────────────────────────────
                    HStack(spacing: 10) {
                        // Liquid tube
                        ZStack(alignment: .bottom) {
                            RoundedRectangle(cornerRadius: 6).fill(Color.cyan.opacity(0.15))
                                .frame(width: 10, height: 60)
                            RoundedRectangle(cornerRadius: 6)
                                .fill(LinearGradient(colors: [.blue, .cyan], startPoint: .bottom, endPoint: .top))
                                .frame(width: 10, height: max(3, 60 * fill))
                                .animation(.spring(response: 0.5, dampingFraction: 0.7), value: fill)
                        }

                        VStack(alignment: .leading, spacing: 2) {
                            Text(HydrationMath.formatLabel(amount: current, isOunces: isOunces))
                                .font(.system(size: 22, weight: .bold, design: .rounded))
                                .foregroundColor(.cyan)
                            Text("of \(HydrationMath.formatLabel(amount: goalML, isOunces: isOunces))")
                                .font(.caption2).foregroundColor(.secondary)
                            // Decay indicator
                            HStack(spacing: 3) {
                                Image(systemName: "arrow.down").font(.system(size: 8)).foregroundColor(.cyan.opacity(0.7))
                                Text("−1 ml/min").font(.system(size: 9)).foregroundColor(.secondary)
                            }
                        }
                    }

                    // ── Progress bar ─────────────────────────────────
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            Capsule().fill(Color.gray.opacity(0.2))
                            Capsule()
                                .fill(LinearGradient(colors: [.cyan, .blue], startPoint: .leading, endPoint: .trailing))
                                .frame(width: max(0, geo.size.width * fill))
                                .animation(.spring(), value: fill)
                        }
                    }
                    .frame(height: 6)

                    // ── Streak ───────────────────────────────────────
                    if streak > 0 {
                        HStack(spacing: 4) {
                            Text(StreakManager.flameEmoji(for: streak)).font(.caption)
                            Text("\(streak)d streak").font(.caption2).foregroundColor(.orange)
                        }
                    }

                    // ── Log buttons ──────────────────────────────────
                    let amt1 = isOunces ? 236.588 : 250.0
                    let lbl1 = isOunces ? "+8 oz" : "+250 ml"
                    let amt2 = isOunces ? 473.176 : 500.0
                    let lbl2 = isOunces ? "+16 oz" : "+500 ml"

                    HStack(spacing: 8) {
                        WatchLogButton(label: lbl1, amount: amt1, isOunces: isOunces, onLog: logDrink)
                        WatchLogButton(label: lbl2, amount: amt2, isOunces: isOunces, onLog: logDrink)
                    }
                }
                .padding(8)
            }
        }
        .onAppear { reloadState() }
    }

    private func reloadState() {
        let d = Constants.defaults
        let savedGoal = d.double(forKey: "dailyGoalML")
        goalML     = savedGoal == 0 ? 2000 : savedGoal
        currentML  = d.double(forKey: "currentIntakeML")
        isOunces   = d.bool(forKey: "isOunces")
        lastDrink  = d.object(forKey: "lastDrinkTimestamp") as? Date ?? Date()
        streak     = StreakManager.computeStreak()
    }

    private func logDrink(amountML: Double) {
        WKInterfaceDevice.current().play(.click)
        let d = Constants.defaults
        let intake = d.double(forKey: "currentIntakeML")
        let ts = d.object(forKey: "lastDrinkTimestamp") as? Date ?? Date()
        let newLevel = HydrationMath.currentLevel(intake: intake, lastDrink: ts, now: Date()) + amountML
        d.set(newLevel, forKey: "currentIntakeML")
        d.set(Date(), forKey: "lastDrinkTimestamp")

        // Queue for HealthKit sync when phone app opens
        var pending = d.array(forKey: "pendingHKLogs") as? [Double] ?? []
        pending.append(amountML)
        d.set(pending, forKey: "pendingHKLogs")

        currentML = newLevel
        lastDrink = Date()

        // Reload complication
        WidgetCenter.shared.reloadAllTimelines()
    }
}
