//
//  ContentView.swift
//  SipWatch Watch App
//
//  Driven entirely by WatchSessionManager — no App Group reads, no timers.
//  State arrives via WatchConnectivity and decays locally via TimelineView.
//

import SwiftUI
import WidgetKit

struct WatchContentView: View {
    @EnvironmentObject var session: WatchSessionManager

    var body: some View {
        TimelineView(.periodic(from: session.lastDrinkDate, by: 30)) { context in
            let current = session.liveLevel(at: context.date)
            let fill    = session.fillRatio(at: context.date)
            let mins    = context.date.timeIntervalSince(session.lastDrinkDate) / 60

            ScrollView {
                VStack(spacing: 10) {

                    // ── Level + streak ────────────────────────────────
                    HStack(alignment: .top) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(HydrationMath.formatLabel(amount: current, isOunces: session.isOunces))
                                .font(.system(size: 24, weight: .bold, design: .rounded))
                                .foregroundColor(.cyan)
                                .contentTransition(.numericText())
                            Text("of \(HydrationMath.formatLabel(amount: session.goalML, isOunces: session.isOunces))")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                        Spacer()
                        VStack(alignment: .trailing, spacing: 1) {
                            if session.streak > 0 {
                                Text(StreakManager.flameEmoji(for: session.streak))
                                    .font(.system(size: 16))
                                Text("\(session.streak)d")
                                    .font(.system(size: 10, weight: .bold))
                                    .foregroundColor(.orange)
                            }
                            // Sync indicator
                            if !session.isPhoneReachable {
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
                        Text(timeSinceLabel(mins: mins))
                            .font(.system(size: 9))
                            .foregroundColor(.secondary)
                        Image(systemName: "arrow.down")
                            .font(.system(size: 7))
                            .foregroundColor(.cyan.opacity(0.6))
                        Text("−1 ml/min")
                            .font(.system(size: 9))
                            .foregroundColor(.secondary)
                        Spacer()
                        if session.goalAdjustedBy > 0 {
                            Image(systemName: "thermometer.sun.fill")
                                .font(.system(size: 10))
                                .foregroundColor(.orange)
                        }
                    }

                    // ── Log buttons (labels from phone settings) ──────
                    HStack(spacing: 6) {
                        Button(action: { session.logDrink(amountML: session.btn1Amount) }) {
                            Text(session.btn1Label)
                                .font(.system(size: 13, weight: .bold))
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 8)
                                .background(Color.cyan.opacity(0.15))
                                .foregroundColor(.cyan)
                                .cornerRadius(10)
                        }
                        .buttonStyle(.plain)

                        Button(action: { session.logDrink(amountML: session.btn2Amount) }) {
                            Text(session.btn2Label)
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
