//
//  SettingsView.swift
//  sip-dynamic-hydration
//
//  Created by Michael Brockman on 4/28/26.
//

import SwiftUI

// MARK: - Settings Tab

struct SettingsView: View {
    @EnvironmentObject var manager: HydrationManager
    @AppStorage("hasSeenOnboarding") var hasSeenOnboarding: Bool = true

    var body: some View {
        NavigationView {
            Form {

                // ── Goal ──────────────────────────────────────────────
                Section(header: Text("Hydration Goal")) {
                    Toggle("Use Ounces (oz)", isOn: $manager.isOunces)

                    Stepper(
                        "Base Goal: \(HydrationMath.formatLabel(amount: manager.baseGoalML, isOunces: manager.isOunces))",
                        value: $manager.baseGoalML, in: 500...5000, step: 250
                    )
                    .onChange(of: manager.baseGoalML) { _, newVal in
                        if !manager.useAdaptiveGoals { manager.dailyGoalML = newVal }
                    }

                    if manager.useAdaptiveGoals && manager.goalAdjustedBy > 0 {
                        HStack {
                            Image(systemName: "thermometer.sun.fill").foregroundColor(.orange)
                            Text("Today's adjusted goal: \(HydrationMath.formatLabel(amount: manager.dailyGoalML, isOunces: manager.isOunces))")
                                .font(.caption).foregroundColor(.secondary)
                        }
                    }
                }

                // ── Log Buttons ───────────────────────────────────────
                Section(
                    header: Text("Quick Log Buttons"),
                    footer: Text("You can also long-press any button on the main screen to log a custom amount and optionally save it here.")
                ) {
                    ForEach(0..<manager.customButtons.count, id: \.self) { i in
                        HStack {
                            Text("Button \(i + 1)")
                                .foregroundColor(.secondary)
                                .frame(width: 72, alignment: .leading)
 
                            Slider(
                                value: Binding(
                                    get: { manager.customButtons[i].amountML },
                                    // Update local model live for preview,
                                    // but Live Activity is only poked on drag-end (onEditingChanged)
                                    set: { newVal in
                                        var btns = manager.customButtons
                                        btns[i] = LogButton(amountML: newVal)
                                        manager.customButtons = btns
                                        manager.saveButtons()
                                    }
                                ),
                                in: manager.isOunces ? 29.5...1183.0 : 50...1000.0,
                                step: manager.isOunces ? 29.5 : 50,
                                onEditingChanged: { editing in
                                    if !editing {
                                        // Drag ended — poke Live Activity once
                                        manager.ensureActivityRunning(forceUpdate: true)
                                    }
                                }
                            )
                            .tint(.cyan)
 
                            Text(manager.logButtons[i].label)
                                .font(.caption.bold())
                                .foregroundColor(.cyan)
                                .frame(width: 64, alignment: .trailing)
                        }
                    }
                }

                // ── Smart Goals ───────────────────────────────────────
                Section(
                    header: Text("Smart Adaptive Goals"),
                    footer: Text("Automatically raises your goal on hot days (WeatherKit) or after intense workouts (HealthKit). Requires location access.")
                ) {
                    Toggle("Adjust goal for weather & activity", isOn: $manager.useAdaptiveGoals)
                    if manager.useAdaptiveGoals {
                        Button("Refresh Now") { Task { await manager.refreshAdaptiveGoal() } }
                            .foregroundColor(.cyan)
                    }
                }

                // ── Notifications ─────────────────────────────────────
                Section(
                    header: Text("Notifications"),
                    footer: Text("The 9 PM summary mentions your current progress, weather-adjusted goal, and how long since your last sip.")
                ) {
                    Toggle("Daily 9 PM Summary", isOn: $manager.dailySummaryEnabled)
                }

                // ── Streak ────────────────────────────────────────────
                Section(header: Text("Streak")) {
                    HStack {
                        Text(StreakManager.flameEmoji(for: manager.currentStreak))
                        Text(manager.currentStreak > 0
                             ? "\(manager.currentStreak)-day streak"
                             : "No active streak")
                        Spacer()
                        if let badge = StreakManager.milestoneBadge(for: manager.currentStreak) {
                            Text(badge).font(.caption).foregroundColor(.orange)
                        }
                    }
                }

                // ── Health ────────────────────────────────────────────
                Section(header: Text("Apple Health")) {
                    Button("Re-connect Apple Health") { manager.requestHealthKit() }
                        .foregroundColor(.cyan)
                }

                // ── Reset ─────────────────────────────────────────────
                Section {
                    Button("Reset Onboarding") { hasSeenOnboarding = false }
                        .foregroundColor(.red)
                }
            }
            .navigationTitle("Settings")
        }
    }
}
