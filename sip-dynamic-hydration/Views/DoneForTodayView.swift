//
//  DoneForTodayView.swift
//  sip-dynamic-hydration
//
//  Created by Michael Brockman on 4/28/26.
//
import SwiftUI

// MARK: - Done for Today View

struct DoneForTodayView: View {
    @EnvironmentObject var manager: HydrationManager
    @State private var showHistory = false
    @State private var pulse = false

    /// Time until midnight
    private var timeUntilMidnight: String {
        let cal = Calendar.current
        let now = Date()
        guard let midnight = cal.nextDate(after: now, matching: DateComponents(hour: 0, minute: 0), matchingPolicy: .nextTime) else { return "" }
        let diff = Int(midnight.timeIntervalSince(now))
        let h = diff / 3600
        let m = (diff % 3600) / 60
        if h > 0 { return "\(h)h \(m)m" }
        return "\(m)m"
    }

    var body: some View {
        NavigationView {
            ZStack {
                // Background gradient — calm, done, satisfied
                LinearGradient(
                    colors: [
                        Color(UIColor.systemGroupedBackground),
                        Color.cyan.opacity(0.06)
                    ],
                    startPoint: .top, endPoint: .bottom
                )
                .ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 32) {

                        Spacer().frame(height: 20)

                        // ── Hero ──────────────────────────────────────
                        VStack(spacing: 16) {
                            ZStack {
                                // Outer glow ring
                                Circle()
                                    .fill(Color.cyan.opacity(0.08))
                                    .frame(width: 140, height: 140)
                                    .scaleEffect(pulse ? 1.08 : 1.0)
                                    .animation(.easeInOut(duration: 2).repeatForever(autoreverses: true), value: pulse)

                                Circle()
                                    .fill(Color.cyan.opacity(0.14))
                                    .frame(width: 115, height: 115)

                                Image(systemName: "checkmark.circle.fill")
                                    .font(.system(size: 64))
                                    .foregroundStyle(
                                        LinearGradient(colors: [.cyan, .blue], startPoint: .top, endPoint: .bottom)
                                    )
                                    .symbolEffect(.bounce, value: true)
                            }
                            .onAppear { pulse = true }

                            Text("You're done for today.")
                                .font(.title.bold())

                            Text("Goal achieved. Your body is well hydrated.\nSee you tomorrow.")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                                .multilineTextAlignment(.center)
                        }

                        // ── Stats row ─────────────────────────────────
                        HStack(spacing: 0) {
                            DoneStatCell(
                                icon: "drop.fill",
                                iconColor: .cyan,
                                value: HydrationMath.formatLabel(amount: manager.dailyGoalML, isOunces: manager.isOunces),
                                label: "Goal hit"
                            )
                            Divider().frame(height: 44)
                            DoneStatCell(
                                icon: StreakManager.flameEmoji(for: manager.currentStreak) == "💧" ? "flame.fill" : "flame.fill",
                                iconColor: .orange,
                                value: manager.currentStreak > 0 ? "\(manager.currentStreak)" : "—",
                                label: manager.currentStreak == 1 ? "day streak" : "day streak"
                            )
                            Divider().frame(height: 44)
                            DoneStatCell(
                                icon: "moon.stars.fill",
                                iconColor: .indigo,
                                value: timeUntilMidnight,
                                label: "until reset"
                            )
                        }
                        .padding(.vertical, 16)
                        .background(Color(UIColor.secondarySystemGroupedBackground))
                        .cornerRadius(20)

                        // ── Milestone badge (if just earned) ─────────
                        if let badge = manager.milestoneBadge {
                            HStack(spacing: 14) {
                                Text("🏆").font(.title2)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Badge Unlocked!").font(.caption.bold()).foregroundColor(.yellow)
                                    Text(badge).font(.subheadline.bold())
                                }
                                Spacer()
                                Button("✕") { manager.dismissMilestoneBadge() }
                                    .font(.caption).foregroundColor(.secondary)
                            }
                            .padding(14)
                            .background(LinearGradient(colors: [.yellow.opacity(0.14), .orange.opacity(0.10)], startPoint: .leading, endPoint: .trailing))
                            .cornerRadius(14)
                            .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.yellow.opacity(0.35), lineWidth: 1))
                        }

                        // ── Motivational tip ──────────────────────────
                        HydrationTipCard()

                        // ── View history button ───────────────────────
                        Button(action: { showHistory = true }) {
                            Label("View Today's History", systemImage: "chart.bar.fill")
                                .font(.subheadline.bold())
                                .foregroundColor(.cyan)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 14)
                                .background(Color.cyan.opacity(0.10))
                                .cornerRadius(14)
                        }

                        Spacer().frame(height: 8)
                    }
                    .padding(.horizontal, 20)
                }
            }
            .navigationTitle("Today")
            .navigationBarTitleDisplayMode(.inline)
            .sheet(isPresented: $showHistory) {
                HistoryOnlyView().environmentObject(manager)
            }
        }
    }
}

// MARK: - Done Stat Cell

struct DoneStatCell: View {
    let icon: String
    let iconColor: Color
    let value: String
    let label: String

    var body: some View {
        VStack(spacing: 4) {
            Image(systemName: icon).foregroundColor(iconColor).font(.system(size: 16))
            Text(value).font(.system(size: 17, weight: .bold, design: .rounded))
            Text(label).font(.caption2).foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
    }
}
