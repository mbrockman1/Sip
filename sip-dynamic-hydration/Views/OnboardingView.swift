//
//  OnboardingView.swift
//  sip-dynamic-hydration
//
//  Created by Michael Brockman on 4/28/26.
//


import SwiftUI


// MARK: - Onboarding

struct OnboardingView: View {
    @ObservedObject var manager: HydrationManager
    @AppStorage("hasSeenOnboarding") var hasSeenOnboarding: Bool = false
    @State private var tab = 0

    var body: some View {
        TabView(selection: $tab) {

            // 0: Hook
            OnboardingPage(
                icon: "drop.fill", iconColor: .cyan,
                title: "Hydration, Redefined",
                bodyText: "Your body isn't a bucket. It processes water continuously — every hour you lose hydration even sitting still. Sip tracks your real level, not just what you've drank.",
                buttonLabel: "Next",
                action: { withAnimation { tab = 1 } }
            )
            .tag(0)

            // 1: Science
            VStack(spacing: 24) {
                Image(systemName: "chart.line.downtrend.xyaxis")
                    .font(.system(size: 80)).foregroundColor(.cyan)
                Text("Metabolic Decay Model").font(.largeTitle.bold())
                Text("Most apps count up. Sip counts *down* in real time. Your hydration level drains ~1 ml/min and only rises when you drink. This is how your body actually works.")
                    .multilineTextAlignment(.center).foregroundColor(.secondary)
                Button("Connect Apple Health") {
                    manager.requestHealthKit()
                    withAnimation { tab = 2 }
                }
                .buttonStyle(SipButtonStyle())
            }
            .padding(32)
            .tag(1)

            // 2: Smart Goals
            VStack(spacing: 24) {
                Image(systemName: "thermometer.sun.fill")
                    .font(.system(size: 80)).foregroundColor(.orange)
                Text("Smart Adaptive Goals").font(.largeTitle.bold())
                Text("Hot day? Hard workout? Sip automatically raises your daily target using WeatherKit and HealthKit. Your goal adapts to your life.")
                    .multilineTextAlignment(.center).foregroundColor(.secondary)
                Toggle("Smart Adaptive Goals", isOn: $manager.useAdaptiveGoals)
                    .padding()
                    .background(Color(UIColor.secondarySystemGroupedBackground))
                    .cornerRadius(12)
                Button("Next") { withAnimation { tab = 3 } }
                    .buttonStyle(SipButtonStyle())
            }
            .padding(32)
            .tag(2)

            // 3: Preferences
            VStack(spacing: 24) {
                Image(systemName: "target")
                    .font(.system(size: 80)).foregroundColor(.cyan)
                Text("Set Your Goal").font(.largeTitle.bold())
                VStack(spacing: 14) {
                    Toggle("Use Ounces (oz)", isOn: $manager.isOunces)
                    Stepper(
                        "Goal: \(HydrationMath.formatLabel(amount: manager.baseGoalML, isOunces: manager.isOunces))",
                        value: $manager.baseGoalML, in: 500...5000, step: 250
                    )
                    .onChange(of: manager.baseGoalML) { _, v in manager.dailyGoalML = v }
                }
                .padding()
                .background(Color(UIColor.secondarySystemGroupedBackground))
                .cornerRadius(12)
                Button("Get Started") { hasSeenOnboarding = true }
                    .buttonStyle(SipButtonStyle())
            }
            .padding(32)
            .tag(3)
        }
        .tabViewStyle(.page)
        .indexViewStyle(.page(backgroundDisplayMode: .always))
    }
}

struct OnboardingPage: View {
    let icon: String; let iconColor: Color
    let title: String; let bodyText: String
    let buttonLabel: String; let action: () -> Void

    var body: some View {
        VStack(spacing: 24) {
            Image(systemName: icon).font(.system(size: 80)).foregroundColor(iconColor)
            Text(title).font(.largeTitle.bold())
            Text(bodyText).multilineTextAlignment(.center).foregroundColor(.secondary)
            Button(buttonLabel, action: action).buttonStyle(SipButtonStyle())
        }
        .padding(32)
    }
}

typealias OnboardingButtonStyle = SipButtonStyle
typealias WaterButtonStyle = SipButtonStyle
