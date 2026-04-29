//
//  ContentView.swift
//  SipWatch Watch App
//

import SwiftUI
import WidgetKit
import Combine

struct WatchContentView: View {
    @State private var currentML: Double = 0
    @State private var goalML: Double = 2000
    @State private var lastDrink: Date = Date()
    @State private var isOunces: Bool = false
    @State private var streak: Int = 0
    @State private var goalAdjustedBy: Double = 0

    // Polls App Group every 30s so watch stays in sync with phone
    private let timer = Timer.publish(every: 30, on: .main, in: .common).autoconnect()

    // Clean static button amounts
    private var btn1Amount: Double { isOunces ? 354.88 : 250.0 }  // 12 oz / 250 ml
    private var btn2Amount: Double { isOunces ? 473.18 : 500.0 }  // 16 oz / 500 ml
    private var btn1Label:  String { isOunces ? "+12 oz" : "+250 ml" }
    private var btn2Label:  String { isOunces ? "+16 oz" : "+500 ml" }

    var body: some View {
        TimelineView(.periodic(from: lastDrink, by: 30)) { context in
            let current = HydrationMath.currentLevel(
                intake: currentML, lastDrink: lastDrink, now: context.date)
            let fill = HydrationMath.fillRatio(current: current, goal: goalML)
            let minsSince = context.date.timeIntervalSince(lastDrink) / 60

            ScrollView {
                VStack(spacing: 10) {

                    // Header: level + streak
                    HStack(alignment: .top) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(HydrationMath.formatLabel(amount: current, isOunces: isOunces))
                                .font(.system(size: 24, weight: .bold, design: .rounded))
                                .foregroundColor(.cyan)
                                .contentTransition(.numericText())
                            Text("of \(HydrationMath.formatLabel(amount: goalML, isOunces: isOunces))")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                        Spacer()
                        if streak > 0 {
                            VStack(alignment: .trailing, spacing: 1) {
                                Text(StreakManager.flameEmoji(for: streak))
                                    .font(.system(size: 16))
                                Text("\(streak)d")
                                    .font(.system(size: 10, weight: .bold))
                                    .foregroundColor(.orange)
                            }
                        }
                    }

                    // Progress bar with %
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            Capsule().fill(Color.cyan.opacity(0.15))
                            Capsule()
                                .fill(LinearGradient(
                                    colors: [.blue, .cyan],
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

                    // Decay + adaptive row
                    HStack(spacing: 6) {
                        Circle()
                            .fill(minsSince < 30 ? Color.green : minsSince < 90 ? Color.yellow : Color.orange)
                            .frame(width: 5, height: 5)
                        Text(timeSinceLabel(mins: minsSince))
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

                    // Log buttons
                    HStack(spacing: 6) {
                        Button(action: { logDrink(amountML: btn1Amount) }) {
                            Text(btn1Label)
                                .font(.system(size: 13, weight: .bold))
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 8)
                                .background(Color.cyan.opacity(0.15))
                                .foregroundColor(.cyan)
                                .cornerRadius(10)
                        }
                        .buttonStyle(.plain)

                        Button(action: { logDrink(amountML: btn2Amount) }) {
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
        .onAppear { reloadState() }
        .onReceive(timer) { _ in reloadState() }
    }

    private func reloadState() {
        let d = Constants.defaults
        let savedGoal = d.double(forKey: "dailyGoalML")
        goalML         = savedGoal == 0 ? 2000 : savedGoal
        currentML      = d.double(forKey: "currentIntakeML")
        isOunces       = d.bool(forKey: "isOunces")
        lastDrink      = d.object(forKey: "lastDrinkTimestamp") as? Date ?? Date()
        streak         = StreakManager.computeStreak()
        goalAdjustedBy = d.double(forKey: "goalAdjustedBy")
    }

    private func logDrink(amountML: Double) {
        WKInterfaceDevice.current().play(.click)
        let d = Constants.defaults
        let intake = d.double(forKey: "currentIntakeML")
        let ts = d.object(forKey: "lastDrinkTimestamp") as? Date ?? Date()
        let newLevel = HydrationMath.currentLevel(intake: intake, lastDrink: ts, now: Date()) + amountML
        d.set(newLevel, forKey: "currentIntakeML")
        d.set(Date(), forKey: "lastDrinkTimestamp")

        var pending = d.array(forKey: "pendingHKLogs") as? [Double] ?? []
        pending.append(amountML)
        d.set(pending, forKey: "pendingHKLogs")

        currentML = newLevel
        lastDrink = Date()
        WidgetCenter.shared.reloadAllTimelines()
    }
}
