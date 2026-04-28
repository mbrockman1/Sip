import SwiftUI

import SwiftUI
import Charts

struct ContentView: View {
    @EnvironmentObject var manager: HydrationManager
    @AppStorage("hasSeenOnboarding") var hasSeenOnboarding: Bool = false
    @State private var showingSettings = false

    var body: some View {
        if hasSeenOnboarding {
            NavigationView {
                ScrollView {
                    VStack(spacing: 24) {
                        
                        // 1. Sleek Today Dashboard
                        TimelineView(.periodic(from: manager.lastDrinkTimestamp, by: 60)) { context in
                            let current = HydrationMath.currentLevel(intake: manager.currentIntakeML, lastDrink: manager.lastDrinkTimestamp, now: context.date)
                            let fillRatio = min(1.0, current / manager.dailyGoalML)
                            let isGoalMet = current >= manager.dailyGoalML
                            
                            VStack(spacing: 8) {
                                Text("TODAY")
                                    .font(.caption.bold())
                                    .foregroundColor(.secondary)
                                
                                if isGoalMet {
                                    Image(systemName: "checkmark.circle.fill")
                                        .font(.system(size: 60))
                                        .foregroundColor(.green)
                                        .padding(.bottom, 8)
                                    Text("Goal Achieved")
                                        .font(.title2.bold())
                                } else {
                                    Text(HydrationMath.formatLabel(amount: current, isOunces: manager.isOunces))
                                        .font(.system(size: 48, weight: .bold, design: .rounded))
                                        .foregroundColor(.cyan)
                                    
                                    Text("of \(HydrationMath.formatLabel(amount: manager.dailyGoalML, isOunces: manager.isOunces))")
                                        .font(.headline)
                                        .foregroundColor(.secondary)
                                    
                                    GeometryReader { proxy in
                                        ZStack(alignment: .leading) {
                                            Capsule().fill(Color.gray.opacity(0.2))
                                            Capsule().fill(Color.cyan)
                                                .frame(width: max(0, proxy.size.width * fillRatio))
                                                .animation(.spring(response: 0.5, dampingFraction: 0.7), value: fillRatio)
                                        }
                                    }
                                    .frame(height: 16)
                                    .padding(.top, 12)
                                }
                            }
                            .padding(24)
                            .background(Color(UIColor.secondarySystemGroupedBackground))
                            .cornerRadius(20)
                        }
                        
                        // 2. Action Buttons
                        let amount1 = manager.isOunces ? 236.588 : 250.0
                        let label1 = manager.isOunces ? "+ 8 oz" : "+ 250 ml"
                        let amount2 = manager.isOunces ? 473.176 : 500.0
                        let label2 = manager.isOunces ? "+ 16 oz" : "+ 500 ml"
                        
                        HStack(spacing: 16) {
                            Button(action: { manager.addDrink(amountML: amount1) }) {
                                Text(label1).font(.headline.bold())
                                    .frame(maxWidth: .infinity).padding().background(Color.cyan.opacity(0.15)).foregroundColor(.cyan).cornerRadius(16)
                            }
                            Button(action: { manager.addDrink(amountML: amount2) }) {
                                Text(label2).font(.headline.bold())
                                    .frame(maxWidth: .infinity).padding().background(Color.cyan).foregroundColor(.white).cornerRadius(16)
                            }
                        }
                        
                        // 3. Native Apple Chart (Past 7 Days)
                        VStack(alignment: .leading, spacing: 16) {
                            Text("Past 7 Days")
                                .font(.headline)
                            
                            Chart {
                                ForEach(manager.weeklyHistory) { item in
                                    BarMark(
                                        x: .value("Day", item.date, unit: .day),
                                        y: .value("Intake", manager.isOunces ? (item.amountML / 29.5735) : item.amountML)
                                    )
                                    .foregroundStyle(Color.cyan.gradient)
                                    .cornerRadius(4)
                                }
                                
                                RuleMark(y: .value("Goal", manager.isOunces ? (manager.dailyGoalML / 29.5735) : manager.dailyGoalML))
                                    .lineStyle(StrokeStyle(lineWidth: 2, dash:[5, 5]))
                                    .foregroundStyle(.green)
                            }
                            .frame(height: 200)
                            .chartXAxis {
                                AxisMarks(values: .stride(by: .day)) { _ in
                                    AxisValueLabel(format: .dateTime.weekday(.abbreviated))
                                }
                            }
                        }
                        .padding(24)
                        .background(Color(UIColor.secondarySystemGroupedBackground))
                        .cornerRadius(20)
                        
                    }
                    .padding()
                }
                .background(Color(UIColor.systemGroupedBackground).edgesIgnoringSafeArea(.all))
                .navigationTitle("Summary")
                .navigationBarItems(trailing: Button(action: { showingSettings = true }) {
                    Image(systemName: "gearshape.fill").foregroundColor(.primary)
                })
                .sheet(isPresented: $showingSettings) { SettingsView().environmentObject(manager) }
            }
        } else {
            OnboardingView(manager: manager)
        }
    }
}
