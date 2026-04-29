//
//  ContentView.swift
//  SipWatch Watch App
//

import SwiftUI
import WidgetKit
import WatchConnectivity // Needed to check if iPhone is reachable

struct WatchContentView: View {
    // 1. FIXED: Removed the () causing the crash, and renamed to 'manager'
    @EnvironmentObject var manager: WatchManager

    var body: some View {
        // 2. FIXED: Uses the actual variables from WatchManager
        TimelineView(.periodic(from: manager.lastDrinkTimestamp, by: 30)) { context in
            
            // 3. FIXED: Re-wired the math to use the WatchMath struct
            let current = WatchMath.currentLevel(intake: manager.currentIntakeML, lastDrink: manager.lastDrinkTimestamp, now: context.date)
            let safeGoal = manager.dailyGoalML > 0 ? manager.dailyGoalML : 2000
            let fill = min(1.0, max(0.0, current / safeGoal))
            let mins = context.date.timeIntervalSince(manager.lastDrinkTimestamp) / 60
            
            // 4. Safely grab missing states (Streak, iPhone connection, etc.)
            let streak = UserDefaults.standard.integer(forKey: "currentStreak")
            let goalAdjustedBy = UserDefaults.standard.double(forKey: "goalAdjustedBy")
            let isPhoneReachable = WCSession.default.isReachable
            
            let btn1Amount = manager.isOunces ? 236.588 : 250.0
            let btn1Label = manager.isOunces ? "+ 8 oz" : "+ 250 ml"
            let btn2Amount = manager.isOunces ? 473.176 : 500.0
            let btn2Label = manager.isOunces ? "+ 16 oz" : "+ 500 ml"

            ScrollView {
                VStack(spacing: 10) {

                    // ── Level + streak ────────────────────────────────
                    HStack(alignment: .top) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(WatchMath.formatLabel(amount: current, isOunces: manager.isOunces))
                                .font(.system(size: 24, weight: .bold, design: .rounded))
                                .foregroundColor(.cyan)
                                .contentTransition(.numericText())
                            Text("of \(WatchMath.formatLabel(amount: manager.dailyGoalML, isOunces: manager.isOunces))")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                        Spacer()
                        VStack(alignment: .trailing, spacing: 1) {
                            if streak > 0 {
                                Text(streak >= 7 ? "🔥" : "💧")
                                    .font(.system(size: 16))
                                Text("\(streak)d")
                                    .font(.system(size: 10, weight: .bold))
                                    .foregroundColor(.orange)
                            }
                            // Sync indicator
                            if !isPhoneReachable {
                                Image(systemName: "iphone.slash")
                                    .font(.system(size: 8))
                                    .foregroundColor(.secondary)
                            }
                        }
                    }

                    // ── Progress bar with % ───────────────────────────
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            Capsule().fill(Color.cyan.opacity(0.15))
                            Capsule()
                                .fill(LinearGradient(
                                    colors: fill >= 1 ? [.green, .green] : [.blue, .cyan],
                                    startPoint: .leading, endPoint: .trailing))
                                .frame(width: max(0, geo.size.width * fill))
                                .animation(.spring(response: 0.5), value: fill)
                            if fill > 0.12 {
                                Text("\(Int(fill * 100))%")
                                    .font(.system(size: 9, weight: .bold))
                                    .foregroundColor(.white)
                                    .padding(.leading, 6)
                            }
                        }
                    }
                    .frame(height: 16)

                    // ── Decay + adaptive ──────────────────────────────
                    HStack(spacing: 6) {
                        Circle()
                            .fill(mins < 30 ? Color.green : mins < 90 ? Color.yellow : Color.orange)
                            .frame(width: 5, height: 5)
                        Text(mins < 60 ? "\(Int(mins))m ago" : "\(Int(mins)/60)h ago")
                            .font(.system(size: 9))
                            .foregroundColor(.secondary)
                        Image(systemName: "arrow.down")
                            .font(.system(size: 7))
                            .foregroundColor(.cyan.opacity(0.6))
                        Text("−1 ml/min")
                            .font(.system(size: 9))
                            .foregroundColor(.secondary)
                        Spacer()
                        if goalAdjustedBy > 0 {
                            Image(systemName: "thermometer.sun.fill")
                                .font(.system(size: 10))
                                .foregroundColor(.orange)
                        }
                    }

                    // ── Log buttons ──────
                    HStack(spacing: 6) {
                        Button(action: { manager.addDrink(amountML: btn1Amount) }) {
                            Text(btn1Label)
                                .font(.system(size: 13, weight: .bold))
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 8)
                                .background(Color.cyan.opacity(0.15))
                                .foregroundColor(.cyan)
                                .cornerRadius(10)
                        }
                        .buttonStyle(.plain)

                        Button(action: { manager.addDrink(amountML: btn2Amount) }) {
                            Text(btn2Label)
                                .font(.system(size: 13, weight: .bold))
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 8)
                                .background(Color.cyan.opacity(0.28))
                                .foregroundColor(.cyan)
                                .cornerRadius(10)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(8)
            }
        }
    }
}
