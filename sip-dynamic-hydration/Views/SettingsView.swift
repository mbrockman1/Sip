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
    
    @State private var manualInput: String = ""

    var body: some View {
        NavigationView {
            Form {

                // ── Goal ──────────────────────────────────────────────
                Section(header: Text("Hydration Goal")) {
                    Toggle("Use Ounces (oz)", isOn: $manager.isOunces)
                    
                    let displayGoal = manager.isOunces ? (manager.baseGoalML / 29.5735) : manager.baseGoalML
                    let stepAmount: Double = manager.isOunces ? 1.0 : 10.0 // 1 oz or 10ml steps

                    Stepper("Base Goal: \(Int(displayGoal)) \(manager.isOunces ? "oz" : "ml")",
                            value: Binding(
                                get: { displayGoal },
                                set: { newValue in
                                    manager.baseGoalML = manager.isOunces ? (newValue * 29.5735) : newValue
                                }
                            ),
                            in: (manager.isOunces ? 32.0 : 500.0)...(manager.isOunces ? 250.0 : 7500.0),
                            step: stepAmount)
                    
                    // 2. Manual Override (For exact numbers)
                    HStack {
                        TextField("Enter Custom Goal", text: $manualInput)
                            .keyboardType(.numberPad)
                        Button("Apply") {
                            if let val = Double(manualInput) {
                                // Save the base goal
                                manager.baseGoalML = manager.isOunces ? (val * 29.5735296) : val
                                
                                // 🌟 FORCE the adaptive engine to re-calculate based on the new base
                                if manager.useAdaptiveGoals {
                                    Task { await manager.refreshAdaptiveGoal(force: true) }
                                }
                                
                                manualInput = ""
                                hideKeyboard()
                            }
                        }
                    }
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
                
                NavigationLink("Manage Today's Logs", destination: HistoryView().environmentObject(manager))

                // ── Log Buttons ───────────────────────────────────────
                Section(header: Text("Quick Log Buttons")) {
                    NavigationLink("Configure Quick Buttons", destination: ButtonSettingsView().environmentObject(manager))
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

struct ButtonSettingsView: View {
    @EnvironmentObject var manager: HydrationManager
    
    var body: some View {
        Form {
            Section(header: Text("iPhone App")) {
                ButtonConfigRow(title: "Left Button", valueML: $manager.btnApp1, isOunces: manager.isOunces)
                ButtonConfigRow(title: "Middle Button", valueML: $manager.btnApp2, isOunces: manager.isOunces)
                ButtonConfigRow(title: "Right Button", valueML: $manager.btnApp3, isOunces: manager.isOunces)
            }
            Section(header: Text("Small Home Widget")) {
                ButtonConfigRow(title: "Main Button", valueML: $manager.btnSmall, isOunces: manager.isOunces)
            }
            Section(header: Text("Medium Home Widget")) {
                ButtonConfigRow(title: "Left Button", valueML: $manager.btnMed1, isOunces: manager.isOunces)
                ButtonConfigRow(title: "Middle Button", valueML: $manager.btnMed2, isOunces: manager.isOunces)
                ButtonConfigRow(title: "Right Button", valueML: $manager.btnMed3, isOunces: manager.isOunces)
            }
            Section(header: Text("Live Activity & Lock Screen")) {
                ButtonConfigRow(title: "Left Button", valueML: $manager.btnLive1, isOunces: manager.isOunces)
                ButtonConfigRow(title: "Middle Button", valueML: $manager.btnLive2, isOunces: manager.isOunces)
                ButtonConfigRow(title: "Right Button", valueML: $manager.btnLive3, isOunces: manager.isOunces)
            }
            Section(header: Text("Apple Watch")) {
                ButtonConfigRow(title: "Left Button", valueML: $manager.btnWatch1, isOunces: manager.isOunces)
                ButtonConfigRow(title: "Right Button", valueML: $manager.btnWatch2, isOunces: manager.isOunces)
            }
        }
        .navigationTitle("Quick Buttons")
    }
}

struct ButtonConfigRow: View {
    let title: String
    @Binding var valueML: Double
    let isOunces: Bool
    
    var body: some View {
        let displayVal = isOunces ? (valueML / HydrationMath.ozMultiplier) : valueML
        
        // Define ranges and steps based on units
        let range: ClosedRange<Double> = isOunces ? 2.0...64.0 : 50.0...2000.0
        let step: Double = isOunces ? 1.0 : 10.0 // 1oz steps or 10ml steps for smoothness
        
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(title)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                Spacer()
                // The value updates live as the user slides
                Text("\(Int(round(displayVal))) \(isOunces ? "oz" : "ml")")
                    .font(.system(.headline, design: .rounded))
                    .foregroundColor(.cyan)
            }
            
            Slider(value: Binding(
                get: { displayVal },
                set: { newVal in
                    // Convert the slider's display value back to ML for the logic engine
                    valueML = isOunces ? (newVal * HydrationMath.ozMultiplier) : newVal
                }
            ), in: range, step: step)
            .tint(.cyan) // Matches your app's theme
        }
        .padding(.vertical, 8)
    }
}

extension View {
    func hideKeyboard() {
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
    }
}
