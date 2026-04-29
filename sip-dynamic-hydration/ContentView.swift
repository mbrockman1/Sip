//
//  ContentView.swift
//  sip-dynamic-hydration
//

import SwiftUI
import Charts

// MARK: - Root View

struct ContentView: View {
    @EnvironmentObject var manager: HydrationManager
    @AppStorage("hasSeenOnboarding") var hasSeenOnboarding: Bool = false

    var body: some View {
        if hasSeenOnboarding {
            SipTabView()
        } else {
            OnboardingView(manager: manager)
        }
    }
}

// MARK: - Tab Shell

struct SipTabView: View {
    @EnvironmentObject var manager: HydrationManager
    @State private var selectedTab: Int = 0

    var body: some View {
        TabView(selection: $selectedTab) {
            SipMainTab()
                .tabItem { Label("Sip", systemImage: selectedTab == 0 ? "drop.fill" : "drop") }
                .tag(0)

            SettingsView()
                .tabItem { Label("Settings", systemImage: "gearshape") }
                .tag(1)

            InfoView()
                .tabItem { Label("Info", systemImage: "info.circle") }
                .tag(2)
        }
        .tint(.cyan)
    }
}

// MARK: - Main Tab (gates on goal achieved)

struct SipMainTab: View {
    @EnvironmentObject var manager: HydrationManager

    /// True if the goal was hit today
    private var isGoalHitToday: Bool {
        guard let goalHitDate = Constants.defaults.object(forKey: "goalHitDate") as? Date else { return false }
        return Calendar.current.isDateInToday(goalHitDate)
    }

    var body: some View {
        if isGoalHitToday {
            DoneForTodayView()
        } else {
            SipDashboardView()
        }
    }
}



// MARK: - Hydration Tip Card (rotates daily)

struct HydrationTipCard: View {
    private static let tips: [String] = [
        "You lose ~0.5–1L overnight just breathing. Starting tomorrow with 500ml before coffee is one of the best habits you can build.",
        "Coffee is ~65% as hydrating as water due to its mild diuretic effect. It counts — just not 1-for-1.",
        "Alcohol suppresses ADH, causing your kidneys to release more water than they take in. Always hydrate alongside alcohol.",
        "Thirst is a lagging indicator — by the time you feel thirsty, you're already 1–2% dehydrated.",
        "Your skin, joints, kidneys, and cognitive performance all benefit measurably from consistent hydration.",
        "Electrolytes (sodium, potassium, magnesium) help your body retain and use the water you drink more efficiently.",
        "Drinking 500ml of water before a meal can reduce calorie intake by up to 13% in some studies.",
        "Muscle cramps during exercise are often a sign of combined fluid and electrolyte loss, not just dehydration.",
        "Your kidneys can process about 1 liter of fluid per hour — drinking much faster than that provides little benefit."
    ]

    private var tip: String {
        let dayOfYear = Calendar.current.ordinality(of: .day, in: .year, for: Date()) ?? 1
        return Self.tips[dayOfYear % Self.tips.count]
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Did you know?", systemImage: "lightbulb.fill")
                .font(.caption.bold())
                .foregroundColor(.yellow)
            Text(tip)
                .font(.caption)
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(14)
        .background(Color.yellow.opacity(0.07))
        .cornerRadius(14)
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.yellow.opacity(0.2), lineWidth: 1))
    }
}

// MARK: - History-Only Sheet (shown from Done screen)

struct HistoryOnlyView: View {
    @EnvironmentObject var manager: HydrationManager
    @Environment(\.dismiss) var dismiss

    var body: some View {
        NavigationView {
            ScrollView {
                HydrationChartCard()
                    .padding()
            }
            .background(Color(UIColor.systemGroupedBackground).ignoresSafeArea())
            .navigationTitle("History")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}

// MARK: - Dashboard (the actual main content when goal not hit)

struct SipDashboardView: View {
    @EnvironmentObject var manager: HydrationManager

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 16) {
                    if manager.goalAdjustedBy > 0 {
                        AdaptiveGoalBanner(
                            adjustedBy: manager.goalAdjustedBy,
                            reason: manager.adaptiveReason,
                            isOunces: manager.isOunces
                        )
                    }
                    if let badge = manager.milestoneBadge {
                        MilestoneBadgeView(badge: badge) { manager.dismissMilestoneBadge() }
                    }
                    HydrationChartCard()
                    TodayDashboardCard()
                    LogButtonRow()
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .padding(.bottom, 32)
            }
            .refreshable {
                manager.syncFromHealthKit()
            }
            .background(Color(UIColor.systemGroupedBackground).ignoresSafeArea())
            .navigationTitle("Sip")
            .navigationBarTitleDisplayMode(.large)
        }
    }
}

// MARK: - Today Dashboard Card

struct TodayDashboardCard: View {
    @EnvironmentObject var manager: HydrationManager
 
    private var nextMilestone: Int {
        [3, 7, 14, 30].first(where: { $0 > manager.currentStreak }) ?? (manager.currentStreak + 7)
    }
 
    var body: some View {
        TimelineView(.periodic(from: manager.lastDrinkTimestamp, by: 30)) { context in
            let current = HydrationMath.currentLevel(
                intake: manager.currentIntakeML,
                lastDrink: manager.lastDrinkTimestamp,
                now: context.date
            )
            let fillRatio = HydrationMath.fillRatio(current: current, goal: manager.dailyGoalML)
            let minsSince = context.date.timeIntervalSince(manager.lastDrinkTimestamp) / 60
 
            VStack(spacing: 0) {
                // ── Header row ────────────────────────────────────────
                HStack {
                    Label("TODAY", systemImage: "sun.max")
                        .font(.caption.bold()).foregroundColor(.secondary)
                    Spacer()
                    // Streak inline in header
                    HStack(spacing: 4) {
                        Text(StreakManager.flameEmoji(for: manager.currentStreak))
                            .font(.system(size: 14))
                        if manager.currentStreak > 0 {
                            Text("\(manager.currentStreak)d")
                                .font(.caption.bold())
                                .foregroundColor(.orange)
                        }
                    }
                    if manager.goalAdjustedBy > 0 {
                        Label("Adjusted", systemImage: "thermometer.sun.fill")
                            .font(.caption2.bold()).foregroundColor(.orange)
                            .padding(.leading, 6)
                    }
                }
                .padding(.bottom, 14)
 
                // ── Level + decay ─────────────────────────────────────
                HStack(alignment: .center, spacing: 18) {
                    LiquidFillTube(fillRatio: fillRatio, height: 110)
 
                    VStack(alignment: .leading, spacing: 8) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(HydrationMath.formatLabel(amount: current, isOunces: manager.isOunces))
                                .font(.system(size: 40, weight: .bold, design: .rounded))
                                .foregroundColor(.cyan)
                                .contentTransition(.numericText())
                            Text("of \(HydrationMath.formatLabel(amount: manager.dailyGoalML, isOunces: manager.isOunces))")
                                .font(.subheadline).foregroundColor(.secondary)
                        }
                        DecayIndicatorView(minutesSince: minsSince)
                    }
                    Spacer(minLength: 0)
                }
 
                // SipProgressBar(fillRatio: fillRatio).padding(.top, 14)
 
                // ── Streak subtitle ───────────────────────────────────
                HStack {
                    Text(manager.currentStreak == 0
                         ? "Hit your goal today to start a streak"
                         : "\(nextMilestone - manager.currentStreak) days to next badge")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Spacer()
                }
                .padding(.top, 8)
            }
            .padding(18)
            .background(Color(UIColor.secondarySystemGroupedBackground))
            .cornerRadius(20)
        }
    }
}

// MARK: - Reusable Sub-components

struct LiquidFillTube: View {
    let fillRatio: Double
    let height: CGFloat
    let width: CGFloat = 22

    var body: some View {
        ZStack(alignment: .bottom) {
            RoundedRectangle(cornerRadius: width / 2)
                .fill(Color.cyan.opacity(0.10))
                .frame(width: width, height: height)
            RoundedRectangle(cornerRadius: width / 2)
                .fill(LinearGradient(colors: [.blue.opacity(0.85), .cyan], startPoint: .bottom, endPoint: .top))
                .frame(width: width, height: max(6, height * fillRatio))
                .animation(.spring(response: 0.55, dampingFraction: 0.72), value: fillRatio)
        }
        .frame(width: width, height: height)
    }
}

struct SipProgressBar: View {
    let fillRatio: Double
    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.gray.opacity(0.15))
                Capsule()
                    .fill(LinearGradient(colors: [.cyan, .blue], startPoint: .leading, endPoint: .trailing))
                    .frame(width: max(0, proxy.size.width * fillRatio))
                    .animation(.spring(response: 0.5, dampingFraction: 0.7), value: fillRatio)
            }
        }
        .frame(height: 10)
    }
}

struct DecayIndicatorView: View {
    let minutesSince: Double

    private var timeLabel: String {
        let m = Int(minutesSince)
        if m < 1  { return "just now" }
        if m < 60 { return "\(m)m ago" }
        return "\(m / 60)h \(m % 60)m ago"
    }
    private var urgencyColor: Color {
        if minutesSince < 30 { return .green }
        if minutesSince < 90 { return .yellow }
        return .orange
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 5) {
                Circle().fill(urgencyColor).frame(width: 6, height: 6)
                Text("Last sip \(timeLabel)").font(.caption).foregroundColor(.secondary)
            }
            HStack(spacing: 4) {
                Image(systemName: "arrow.down").font(.caption2).foregroundColor(.cyan.opacity(0.6))
                Text("Draining −1 ml/min").font(.caption2).foregroundColor(.secondary)
            }
        }
        .padding(.vertical, 6).padding(.horizontal, 10)
        .background(Color(UIColor.tertiarySystemGroupedBackground))
        .cornerRadius(8)
    }
}


// MARK: - Log Button Row

struct LogButtonRow: View {
    @EnvironmentObject var manager: HydrationManager
    @State private var showCustomSheet = false
    @State private var longPressedSlot: Int = 1

    var body: some View {
        let buttons = manager.logButtons
        HStack(spacing: 10) {
            ForEach(0..<buttons.count, id: \.self) { i in
                let btn = buttons[i]
                Button(action: { manager.addDrink(amountML: btn.amount) }) {
                    Text(btn.label)
                        .font(i == 2 ? .headline.bold() : .subheadline.bold())
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(i == 2 ? Color.cyan : i == 1 ? Color.cyan.opacity(0.18) : Color.cyan.opacity(0.09))
                        .foregroundColor(i == 2 ? .white : .cyan)
                        .cornerRadius(14)
                }
                .simultaneousGesture(
                    LongPressGesture(minimumDuration: 0.5).onEnded { _ in
                        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                        longPressedSlot = i
                        showCustomSheet = true
                    }
                )
            }
        }
        .sheet(isPresented: $showCustomSheet) {
            CustomSipSheet(slot: longPressedSlot).environmentObject(manager)
        }
    }
}

// MARK: - Custom Sip Sheet

struct CustomSipSheet: View {
    @EnvironmentObject var manager: HydrationManager
    @Environment(\.dismiss) var dismiss
    let slot: Int
    @State private var customML: Double = 250
    @State private var saveToSlot = false

    var body: some View {
        NavigationView {
            VStack(spacing: 28) {
                VStack(spacing: 6) {
                    Text(HydrationMath.formatLabel(amount: customML, isOunces: manager.isOunces))
                        .font(.system(size: 52, weight: .bold, design: .rounded)).foregroundColor(.cyan)
                        .contentTransition(.numericText())
                    Text("drag to adjust").font(.caption).foregroundColor(.secondary)
                }
                .padding(.top, 8)

                VStack(spacing: 4) {
                    Slider(value: $customML,
                           in: manager.isOunces ? 29.5...1183.0 : 50...1500.0,
                           step: manager.isOunces ? 29.5 : 50).tint(.cyan)
                    HStack {
                        Text(manager.isOunces ? "1 oz" : "50 ml").font(.caption2).foregroundColor(.secondary)
                        Spacer()
                        Text(manager.isOunces ? "40 oz" : "1500 ml").font(.caption2).foregroundColor(.secondary)
                    }
                }
                .padding(.horizontal)

                let presets: [(Double, String)] = manager.isOunces
                    ? [(88.7,"3 oz"),(177.4,"6 oz"),(354.9,"12 oz"),(473.2,"16 oz")]
                    : [(100,"100 ml"),(250,"250 ml"),(350,"350 ml"),(500,"500 ml")]
                HStack(spacing: 8) {
                    ForEach(presets, id: \.0) { (amt, lbl) in
                        Button(lbl) { withAnimation { customML = amt } }
                            .font(.caption.bold())
                            .padding(.horizontal, 12).padding(.vertical, 8)
                            .background(abs(customML - amt) < 10 ? Color.cyan : Color.cyan.opacity(0.12))
                            .foregroundColor(abs(customML - amt) < 10 ? .white : .cyan)
                            .cornerRadius(20)
                    }
                }

                Toggle("Save as Button \(slot + 1)", isOn: $saveToSlot).padding(.horizontal)
                Spacer()

                Button(action: {
                    manager.addDrink(amountML: customML)
                    if saveToSlot { manager.setLogButton(slot: slot, amountML: customML) }
                    dismiss()
                }) {
                    Text("Log \(HydrationMath.formatLabel(amount: customML, isOunces: manager.isOunces))")
                        .font(.headline.bold()).foregroundColor(.white)
                        .frame(maxWidth: .infinity).padding(.vertical, 16)
                        .background(Color.cyan).cornerRadius(16)
                }
                .padding(.horizontal).padding(.bottom)
            }
            .navigationTitle("Custom Sip")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") { dismiss() }.foregroundColor(.secondary)
                }
            }
        }
        .onAppear { customML = manager.logButtons[slot].amount }
    }
}

// MARK: - History Chart Card

struct HydrationChartCard: View {
    @EnvironmentObject var manager: HydrationManager
    @State private var chartRange: ChartRange = .week
    @State private var selectedDay: DailyIntake? = nil
    enum ChartRange: String, CaseIterable { case week = "7D"; case month = "30D" }

    private var displayHistory: [DailyIntake] {
        chartRange == .week ? manager.weeklyHistory : manager.extendedHistory
    }
    private var averageML: Double {
        guard !displayHistory.isEmpty else { return 0 }
        return displayHistory.reduce(0) { $0 + $1.amountML } / Double(displayHistory.count)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("History").font(.headline)
                    Text("Avg \(Int((averageML / max(1, manager.dailyGoalML)) * 100))% of goal")
                        .font(.caption).foregroundColor(.secondary)
                }
                Spacer()
                Picker("", selection: $chartRange) {
                    ForEach(ChartRange.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented).frame(width: 96)
                .onChange(of: chartRange) { _, _ in
                    if chartRange == .month { manager.fetchExtendedHistory() }
                    selectedDay = nil
                }
            }

            if let sel = selectedDay {
                HStack {
                    Text(sel.date.formatted(.dateTime.weekday(.wide).month(.abbreviated).day()))
                        .font(.caption.bold())
                    Spacer()
                    Text(HydrationMath.formatLabel(amount: sel.amountML, isOunces: manager.isOunces))
                        .font(.caption.bold()).foregroundColor(.cyan)
                    Text("(\(Int(min(1, sel.amountML / max(1, manager.dailyGoalML)) * 100))%)")
                        .font(.caption).foregroundColor(.secondary)
                }
                .padding(.vertical, 6).padding(.horizontal, 10)
                .background(Color.cyan.opacity(0.10)).cornerRadius(8)
                .transition(.opacity.combined(with: .scale(scale: 0.97)))
            }

            Chart {
                ForEach(displayHistory) { item in
                    BarMark(
                        x: .value("Day", item.date, unit: .day),
                        y: .value("ml", manager.isOunces ? item.amountML / 29.5735 : item.amountML)
                    )
                    .foregroundStyle(item.amountML >= manager.dailyGoalML ? Color.green.gradient : Color.cyan.gradient)
                    .cornerRadius(5)
                    .opacity(selectedDay.map { Calendar.current.isDate($0.date, inSameDayAs: item.date) } ?? true ? 1.0 : 0.45)
                }
                RuleMark(y: .value("Goal", manager.isOunces ? manager.dailyGoalML / 29.5735 : manager.dailyGoalML))
                    .lineStyle(StrokeStyle(lineWidth: 1.5, dash: [5, 5]))
                    .foregroundStyle(.green.opacity(0.6))
                    .annotation(position: .top, alignment: .trailing) {
                        Text("Goal").font(.caption2).foregroundColor(.green.opacity(0.8))
                    }
                if displayHistory.count >= 3 {
                    ForEach(displayHistory) { item in
                        LineMark(
                            x: .value("Day", item.date, unit: .day),
                            y: .value("Avg", manager.isOunces ? averageML / 29.5735 : averageML)
                        )
                        .foregroundStyle(.orange.opacity(0.45))
                        .lineStyle(StrokeStyle(lineWidth: 1.5))
                    }
                }
            }
            .frame(height: 190)
            .chartXAxis {
                AxisMarks(values: .stride(by: chartRange == .week ? .day : .weekOfYear)) { _ in
                    AxisValueLabel(format: chartRange == .week
                        ? .dateTime.weekday(.abbreviated) : .dateTime.month(.abbreviated).day())
                }
            }
            .chartYAxis {
                AxisMarks { _ in
                    AxisValueLabel()
                    AxisGridLine(stroke: StrokeStyle(lineWidth: 0.4, dash: [3]))
                }
            }
            .chartOverlay { proxy in
                GeometryReader { geo in
                    Rectangle().fill(.clear).contentShape(Rectangle())
                        .gesture(DragGesture(minimumDistance: 0)
                            .onChanged { val in
                                let origin = geo[proxy.plotAreaFrame].origin
                                let loc = CGPoint(x: val.location.x - origin.x, y: val.location.y - origin.y)
                                if let date: Date = proxy.value(atX: loc.x) {
                                    selectedDay = displayHistory.first { Calendar.current.isDate($0.date, inSameDayAs: date) }
                                }
                            }
                            .onEnded { _ in
                                DispatchQueue.main.asyncAfter(deadline: .now() + 2) { withAnimation { selectedDay = nil } }
                            }
                        )
                }
            }

            HStack(spacing: 14) {
                LegendDot(color: .green,               label: "Goal hit")
                LegendDot(color: .cyan,                label: "Under goal")
                LegendDot(color: .orange.opacity(0.6), label: "Average")
            }
            .font(.caption2)
        }
        .padding(18)
        .background(Color(UIColor.secondarySystemGroupedBackground))
        .cornerRadius(20)
    }
}

struct LegendDot: View {
    let color: Color; let label: String
    var body: some View {
        HStack(spacing: 4) {
            Circle().fill(color).frame(width: 7, height: 7)
            Text(label).foregroundColor(.secondary)
        }
    }
}

// MARK: - Banners

struct AdaptiveGoalBanner: View {
    let adjustedBy: Double; let reason: String; let isOunces: Bool
    @State private var dismissed = false
    var body: some View {
        if !dismissed {
            HStack(spacing: 12) {
                Image(systemName: "thermometer.sun.fill").font(.title3).foregroundColor(.orange)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Goal Adjusted").font(.caption.bold())
                    Text("\(reason). +\(HydrationMath.formatLabel(amount: adjustedBy, isOunces: isOunces)) added.")
                        .font(.caption).foregroundColor(.secondary)
                }
                Spacer()
                Button(action: { withAnimation { dismissed = true } }) {
                    Image(systemName: "xmark").font(.caption).foregroundColor(.secondary)
                }
            }
            .padding(14).background(Color.orange.opacity(0.12)).cornerRadius(14)
            .transition(.opacity.combined(with: .move(edge: .top)))
        }
    }
}

struct MilestoneBadgeView: View {
    let badge: String; let onDismiss: () -> Void
    var body: some View {
        HStack(spacing: 14) {
            Text("🏆").font(.title2)
            VStack(alignment: .leading, spacing: 2) {
                Text("Badge Unlocked!").font(.caption.bold()).foregroundColor(.yellow)
                Text(badge).font(.subheadline.bold())
            }
            Spacer()
            Button("Dismiss", action: onDismiss).font(.caption).foregroundColor(.secondary)
        }
        .padding(14)
        .background(LinearGradient(colors: [.yellow.opacity(0.14), .orange.opacity(0.10)], startPoint: .leading, endPoint: .trailing))
        .cornerRadius(14)
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.yellow.opacity(0.35), lineWidth: 1))
        .transition(.opacity.combined(with: .scale(scale: 0.96)))
    }
}

// MARK: - Info Tab

struct InfoView: View {
    var body: some View {
        NavigationView {
            List {
                Section(header: Text("How Sip Works")) {
                    InfoRow(icon: "chart.line.downtrend.xyaxis", iconColor: .cyan, title: "Metabolic Decay Model",
                            bodyText: "Your body processes water continuously — roughly 1 ml per minute even at rest. Sip tracks your real hydration level in real time, not just what you've logged.")
                    InfoRow(icon: "thermometer.sun.fill", iconColor: .orange, title: "Smart Adaptive Goals",
                            bodyText: "On hot days or after heavy workouts, your body loses more fluid. Smart Goals automatically raises your daily target using WeatherKit and HealthKit.")
                    InfoRow(icon: "flame.fill", iconColor: .orange, title: "Streaks & Badges",
                            bodyText: "Hit your goal every day to build a streak. Milestones at 3, 7, 14, and 30 days unlock badges. Miss a day and it resets.")
                }
                Section(header: Text("Hydration Science")) {
                    InfoRow(icon: "mug.fill", iconColor: .brown, title: "Coffee & Caffeine",
                            bodyText: "Caffeinated drinks have a mild diuretic effect — roughly 60–70% as hydrating as water. They count, but never replace water.")
                    InfoRow(icon: "wineglass", iconColor: .purple, title: "Alcohol",
                            bodyText: "Alcohol suppresses ADH, causing increased urination and net dehydration. Beer, wine, and spirits are not hydration sources. Always drink water alongside alcohol.")
                    InfoRow(icon: "bolt.fill", iconColor: .yellow, title: "Electrolytes",
                            bodyText: "Exercise over 60 minutes depletes sodium, potassium, and magnesium. Water alone may not restore full hydration — electrolyte tablets help.")
                    InfoRow(icon: "leaf.fill", iconColor: .green, title: "Food Sources",
                            bodyText: "~20% of daily water intake comes from food. Watermelon, cucumbers, and soups are high in water. Sip's goal is calibrated for beverages only.")
                    InfoRow(icon: "moon.fill", iconColor: .indigo, title: "Overnight Loss",
                            bodyText: "You lose ~0.5–1L overnight through breathing and perspiration. 500ml of water first thing in the morning is one of the highest-leverage hydration habits.")
                }
                Section(header: Text("Legal & Privacy")) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Medical Disclaimer").font(.subheadline.bold())
                        Text("Sip is a wellness tool, not a medical device. The metabolic decay model is an approximation — not individualized advice. Consult a physician for personalized guidance, especially with kidney disease, heart failure, or diuretic medications.")
                            .font(.caption).foregroundColor(.secondary)
                    }.padding(.vertical, 4)
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Privacy").font(.subheadline.bold())
                        Text("All health data stays on your device and in your personal HealthKit account. Sip never transmits personal health data to any server. WeatherKit uses approximate location only.")
                            .font(.caption).foregroundColor(.secondary)
                    }.padding(.vertical, 4)
                }
                Section {
                    HStack {
                        Spacer()
                        VStack(spacing: 4) {
                            Text("Sip").font(.headline.bold()).foregroundColor(.cyan)
                            Text("Real hydration, tracked honestly.").font(.caption).foregroundColor(.secondary)
                            Text("v1.0").font(.caption2).foregroundColor(.secondary)
                        }
                        Spacer()
                    }.padding(.vertical, 8)
                }
            }
            .navigationTitle("Info")
        }
    }
}

struct InfoRow: View {
    let icon: String; let iconColor: Color; let title: String; let bodyText: String
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Image(systemName: icon).foregroundColor(iconColor).frame(width: 20)
                Text(title).font(.subheadline.bold())
            }
            Text(bodyText).font(.caption).foregroundColor(.secondary).fixedSize(horizontal: false, vertical: true)
        }
        .padding(.vertical, 5)
    }
}
