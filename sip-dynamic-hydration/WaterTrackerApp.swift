//
//  WaterTrackerApp.swift
//  sip-dynamic-hydration
//
//  Created by Michael Brockman on 4/27/26.
//


import SwiftUI


struct WaterTrackerApp: App {
    @StateObject var manager = HydrationManager()
    @Environment(\.scenePhase) var scenePhase
    @AppStorage("hasSeenOnboarding") var hasSeenOnboarding: Bool = false

    var body: some Scene {
        WindowGroup {
            if hasSeenOnboarding {
                MainView()
                    .environmentObject(manager)
                    .onChange(of: scenePhase) { oldPhase, newPhase in
                        if newPhase == .active {
                            manager.checkMidnightReset()
                            manager.syncPendingAppGroupLogs()
                            manager.syncFromHealthKit()
                        }
                    }
            } else {
                OnboardingView(manager: manager)
            }
        }
    }
}

struct MainView: View {
    @EnvironmentObject var manager: HydrationManager
    @State private var showingSettings = false
    
    var body: some View {
        NavigationView {
            VStack(spacing: 40) {
                TimelineView(.periodic(from: manager.lastDrinkTimestamp, by: 60)) { context in
                    let current = HydrationMath.currentLevel(intake: manager.currentIntakeML, lastDrink: manager.lastDrinkTimestamp, now: context.date)
                    let fillRatio = min(1.0, current / manager.dailyGoalML)
                    
                    VStack(spacing: 20) {
                        ZStack(alignment: .bottom) {
                            Capsule().fill(Color.gray.opacity(0.15)).frame(width: 100, height: 300)
                            Capsule().fill(LinearGradient(colors: [.blue, .cyan], startPoint: .bottom, endPoint: .top))
                                .frame(width: 100, height: max(0, 300 * fillRatio))
                                .animation(.spring(response: 0.5, dampingFraction: 0.7), value: fillRatio)
                        }
                        
                        VStack(spacing: 4) {
                            Text(HydrationMath.formatLabel(amount: current, isOunces: manager.isOunces))
                                .font(.system(size: 36, weight: .bold, design: .rounded))
                            Text("/ \(HydrationMath.formatLabel(amount: manager.dailyGoalML, isOunces: manager.isOunces))")
                                .font(.title3)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                
                HStack(spacing: 20) {
                    Button(manager.isOunces ? "+ 8 oz" : "+ 250 ml") { manager.addDrink(amountML: 250) }
                        .buttonStyle(WaterButtonStyle())
                    Button(manager.isOunces ? "+ 16 oz" : "+ 500 ml") { manager.addDrink(amountML: 500) }
                        .buttonStyle(WaterButtonStyle())
                }
            }
            .navigationBarItems(trailing: Button(action: { showingSettings = true }) {
                Image(systemName: "gearshape.fill").foregroundColor(.primary)
            })
            .sheet(isPresented: $showingSettings) { SettingsView().environmentObject(manager) }
        }
    }
}

// MARK: - Subviews & Styles
struct WaterButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline.bold())
            .foregroundColor(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(Color.blue)
            .cornerRadius(16)
            .scaleEffect(configuration.isPressed ? 0.95 : 1)
    }
}

struct OnboardingView: View {
    @ObservedObject var manager: HydrationManager
    @AppStorage("hasSeenOnboarding") var hasSeenOnboarding: Bool = false
    @State private var tab = 0
    
    var body: some View {
        TabView(selection: $tab) {
            VStack(spacing: 20) {
                Image(systemName: "drop.fill").font(.system(size: 80)).foregroundColor(.blue)
                Text("Hydration, Redefined").font(.largeTitle.bold())
                Text("Your body isn't a bucket. You process water constantly.").multilineTextAlignment(.center)
                Button("Next") { tab = 1 }.buttonStyle(WaterButtonStyle()).padding(.top)
            }.padding().tag(0)
            
            VStack(spacing: 20) {
                Image(systemName: "chart.xyaxis.line").font(.system(size: 80)).foregroundColor(.blue)
                Text("Live Tracking").font(.largeTitle.bold())
                Text("We use a smart decay model. As time passes, your water level slowly drains, showing your true hydration status.")
                Button("Connect Apple Health") {
                    manager.requestHealthKit()
                    tab = 2
                }.buttonStyle(WaterButtonStyle()).padding(.top)
            }.padding().tag(1)
            
            VStack(spacing: 20) {
                Image(systemName: "target").font(.system(size: 80)).foregroundColor(.blue)
                Text("Set Your Goal").font(.largeTitle.bold())
                Toggle("Use Ounces (oz)", isOn: $manager.isOunces).padding()
                Button("Get Started") { hasSeenOnboarding = true }.buttonStyle(WaterButtonStyle())
            }.padding().tag(2)
        }.tabViewStyle(.page)
    }
}

struct SettingsView: View {
    @EnvironmentObject var manager: HydrationManager
    
    var body: some View {
        NavigationView {
            Form {
                Section(header: Text("Preferences")) {
                    Toggle("Use Ounces (oz)", isOn: $manager.isOunces)
                    Stepper("Daily Goal: \(HydrationMath.formatLabel(amount: manager.dailyGoalML, isOunces: manager.isOunces))", value: $manager.dailyGoalML, in: 1000...5000, step: 250)
                }
                // Custom App Icon hook goes here
            }
            .navigationTitle("Settings")
        }
    }
}
