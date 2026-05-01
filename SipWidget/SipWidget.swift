//
//  SipWidget.swift
//  SipWidget
//

import WidgetKit
import SwiftUI
import ActivityKit
import AppIntents

// MARK: - Shared Urgency System
// Single source of truth for color/urgency used across ALL widget surfaces

struct UrgencyStyle {
    let fillColor: Color        // bar / tube fill
    let accentColor: Color      // text, icons
    let iconName: String        // drop vs exclamationmark.triangle

    static func from(fillRatio: Double, minutesSince: Double) -> UrgencyStyle {
        if fillRatio >= 1.0 {
            return UrgencyStyle(fillColor: .green, accentColor: .green, iconName: "checkmark.circle.fill")
        }
        if minutesSince > 120 || fillRatio < 0.25 {
            // Overdue / critically low → orange
            return UrgencyStyle(fillColor: .orange, accentColor: .orange, iconName: "exclamationmark.drop.fill")
        }
        if minutesSince > 60 || fillRatio < 0.5 {
            // Getting low → yellow
            return UrgencyStyle(fillColor: .yellow, accentColor: .yellow, iconName: "drop.halffull")
        }
        // Healthy → cyan
        return UrgencyStyle(fillColor: .cyan, accentColor: .cyan, iconName: "drop.fill")
    }
}

// MARK: - Live Activity
 


struct SipLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: HydrationAttributes.self) { context in
            // Lock screen / banner
            LockScreenView(context: context)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    ExpandedLeadingView(context: context)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    ExpandedTrailingView(context: context)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    ExpandedBottomView(context: context)
                }
            } compactLeading: {
                // Always blue water drop — visible on black island
                Image(systemName: "drop.fill")
                    .foregroundStyle(.blue)
                    .font(.system(size: 12, weight: .semibold))
            } compactTrailing: {
                // Rising bar chart based on fill ratio
                CompactBarGraph(context: context)
                // CompactTrailingGauge(context: context)
            } minimal: {
                // Smallest slot — just the drop
                Image(systemName: "drop.fill")
                    .foregroundStyle(.blue)
                    .font(.system(size: 10, weight: .semibold))
            }
        }
        .supplementalActivityFamilies([.small])
    }
}

// MARK: - Compact Bar Graph (fills based on intake progress)
 
struct CompactBarGraph: View {
    let context: ActivityViewContext<HydrationAttributes>
 
    var body: some View {
        TimelineView(.periodic(from: context.state.lastDrinkTimestamp, by: 60)) { tl in
            let current = HydrationMath.currentLevel(
                intake: context.state.currentIntake,
                lastDrink: context.state.lastDrinkTimestamp,
                now: tl.date)
            let fill = HydrationMath.fillRatio(current: current, goal: context.state.dailyGoal)
 
            // Single bar configuration
            let maxH: CGFloat = 14
            let barWidth: CGFloat = 6
            
            // We calculate the current height based on progress,
            // ensuring it doesn't shrink below a tiny sliver or exceed maxH.
            let currentHeight = maxH * CGFloat(min(max(fill, 0.1), 1.0))
 
            VStack(alignment: .center) {
                ZStack(alignment: .bottom) {
                    // Background track (Gray/Low Opacity)
                    RoundedRectangle(cornerRadius: 2)
                        .fill(Color.white.opacity(0.2))
                        .frame(width: barWidth, height: maxH)
                    
                    // Foreground fill (Blue)
                    RoundedRectangle(cornerRadius: 2)
                        .fill(Color.blue)
                        .frame(width: barWidth, height: currentHeight)
                }
            }
        }
    }
}

//// MARK: - Compact Trailing: Arc Gauge (the key upgrade)

struct CompactTrailingGauge: View {
    let context: ActivityViewContext<HydrationAttributes>

    var body: some View {
        // Keeps the same update cadence as your bar graph
        TimelineView(.periodic(from: context.state.lastDrinkTimestamp, by: 60)) { tl in
            let current = HydrationMath.currentLevel(
                intake: context.state.currentIntake,
                lastDrink: context.state.lastDrinkTimestamp,
                now: tl.date
            )
            
            let fill = HydrationMath.fillRatio(current: current, goal: context.state.dailyGoal)
            
            // Calculate urgency styling based on the current timeline date
            let mins = tl.date.timeIntervalSince(context.state.lastDrinkTimestamp) / 60
            let style = UrgencyStyle.from(fillRatio: fill, minutesSince: mins)

            // The circular gauge replacement
            Gauge(value: max(0, min(fill, 1)), in: 0...1) {
                // Label is required by the initializer but hidden in accessoryCircularCapacity
                Text("Hydration")
            }
            .gaugeStyle(.accessoryCircularCapacity)
            .tint(style.fillColor)
            .frame(width: 22, height: 22) // Sized specifically for the Compact Trailing slot
        }
    }
}

// MARK: - Expanded: Leading
 
struct ExpandedLeadingView: View {
    let context: ActivityViewContext<HydrationAttributes>
 
    var body: some View {
        TimelineView(.periodic(from: context.state.lastDrinkTimestamp, by: 60)) { tl in
            let current = HydrationMath.currentLevel(
                intake: context.state.currentIntake,
                lastDrink: context.state.lastDrinkTimestamp,
                now: tl.date)
            let fill = HydrationMath.fillRatio(current: current, goal: context.state.dailyGoal)
            
            HStack(spacing: 8) { // Increased spacing slightly for separation
                // Compact liquid tube
                ZStack(alignment: .bottom) {
                    RoundedRectangle(cornerRadius: 3)
                        .fill(Color.blue.opacity(0.2))
                        .frame(width: 7, height: 28)
                    RoundedRectangle(cornerRadius: 3)
                        .fill(Color.blue)
                        .frame(width: 7, height: max(3, 28 * fill))
                }
 
                // App Title & Streak
                VStack(alignment: .leading, spacing: 1) {
                    Text("Sip").font(.caption.bold())
                    if context.state.streak > 0 {
                        Text("🔥\(context.state.streak)d")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundColor(.orange)
                    }
                }
                
                // 🌟 MOVED: Live Status & Goal
                VStack(alignment: .leading, spacing: 1) {
                    Text(HydrationMath.formatLabel(amount: current, isOunces: context.state.isOunces))
                        .font(.caption.bold().monospacedDigit())
                        .foregroundStyle(.blue)
                    
                    Text("of \(HydrationMath.formatLabel(amount: context.state.dailyGoal, isOunces: context.state.isOunces))")
                        .font(.system(size: 9))
                        .foregroundColor(.secondary)
                }
            }
            .padding(.leading, 4)
        }
    }
}


// MARK: - Expanded: Trailing
 
struct ExpandedTrailingView: View {
    let context: ActivityViewContext<HydrationAttributes>
 
    var body: some View {
        TimelineView(.periodic(from: context.state.lastDrinkTimestamp, by: 60)) { tl in
            let mins = tl.date.timeIntervalSince(context.state.lastDrinkTimestamp) / 60
 
            VStack(alignment: .trailing, spacing: 4) {
                // Time since last drink
                HStack(spacing: 2) {
                    Image(systemName: "clock").font(.system(size: 7))
                    Text(timeSinceLabel(mins: mins)).font(.system(size: 9))
                }
                .foregroundColor(.secondary)
 
                // Adaptive Goal Indicator
                if context.state.goalAdjustedBy > 0 {
                    Image(systemName: "thermometer.sun.fill")
                        .font(.system(size: 9))
                        .foregroundColor(.orange)
                }
            }
            .padding(.trailing, 4)
        }
    }
}
// MARK: - Expanded: Bottom (3 buttons from App Group, compact sizing)
 
struct ExpandedBottomView: View {
    let context: ActivityViewContext<HydrationAttributes>
    
 
    var body: some View {
        TimelineView(.periodic(from: context.state.lastDrinkTimestamp, by: 60)) { tl in
            let current = HydrationMath.currentLevel(
                intake: context.state.currentIntake,
                lastDrink: context.state.lastDrinkTimestamp,
                now: tl.date)
            let fill = HydrationMath.fillRatio(current: current, goal: context.state.dailyGoal)
            
            let amount1 = context.state.btnLive1
            let label1 = HydrationMath.formatLabel(amount: amount1, isOunces: context.state.isOunces)
            
            let amount2 = context.state.btnLive2
            let label2 = HydrationMath.formatLabel(amount: amount2, isOunces: context.state.isOunces)
            
            let amount3 = context.state.btnLive3
            let label3 = HydrationMath.formatLabel(amount: amount3, isOunces: context.state.isOunces)
 
            VStack(spacing: 8) {
                // Progress bar with % — slim
                GeometryReader { proxy in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Color.white.opacity(0.15))
                        Capsule()
                            .fill(LinearGradient(
                                colors: [.blue.opacity(0.7), .blue],
                                startPoint: .leading, endPoint: .trailing))
                            .frame(width: max(0, proxy.size.width * fill))
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
 
                // 3 log buttons — fixed small sizing, won't overflow
                HStack(spacing: 6) {
                    Button(intent: LogWaterIntent(amount: amount1)) {
                        Text(label1)
                            .font(.system(size: 11, weight: .bold))
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 7)
                            .foregroundColor(.blue)
                            .cornerRadius(8)
                    }
                    Button(intent: LogWaterIntent(amount: amount2)) {
                        Text(label2)
                            .font(.system(size: 11, weight: .bold))
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 7)
                            .foregroundColor(.blue)
                            .cornerRadius(8)
                    }
                    Button(intent: LogWaterIntent(amount: amount3)) {
                        Text(label3)
                            .font(.system(size: 11, weight: .bold))
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 7)
                            .foregroundColor(.blue)
                            .cornerRadius(8)
                    }
                    
                }
            }
            .padding(.horizontal, 4)
            .padding(.bottom, 4)
        }
    }
}

// MARK: - Compact Leading (urgency-aware icon)

struct CompactLeadingView: View {
    let context: ActivityViewContext<HydrationAttributes>

    var body: some View {
        TimelineView(.periodic(from: context.state.lastDrinkTimestamp, by: 60)) { tl in
            let current = HydrationMath.currentLevel(
                intake: context.state.currentIntake,
                lastDrink: context.state.lastDrinkTimestamp, now: tl.date)
            let fill = HydrationMath.fillRatio(current: current, goal: context.state.dailyGoal)
            let mins = tl.date.timeIntervalSince(context.state.lastDrinkTimestamp) / 60
            let style = UrgencyStyle.from(fillRatio: fill, minutesSince: mins)

            Image(systemName: style.iconName)
                .foregroundColor(style.accentColor)
                .font(.system(size: 12, weight: .semibold))
        }
    }
}

struct LockScreenView: View {
    let context: ActivityViewContext<HydrationAttributes>
    @Environment(\.activityFamily) var activityFamily
 
    var body: some View {
        TimelineView(.periodic(from: context.state.lastDrinkTimestamp, by: 60)) { tl in
            let current = HydrationMath.currentLevel(
                intake: context.state.currentIntake,
                lastDrink: context.state.lastDrinkTimestamp,
                now: tl.date)
            let fill = HydrationMath.fillRatio(current: current, goal: context.state.dailyGoal)
            let mins = tl.date.timeIntervalSince(context.state.lastDrinkTimestamp) / 60
            let btns = readLogButtons(isOunces: context.state.isOunces)
            
 
            // Branch: Watch Smart Stack gets its own compact layout
            if activityFamily == .small {
                WatchSmartStackView(
                    context: context,
                    current: current,
                    fill: fill,
                    mins: mins
                )
            } else {
                IPhoneLockScreenContent(
                    context: context,
                    current: current,
                    fill: fill,
                    mins: mins,
                    btns: btns
                )
            }
 
        }   // end if/else activityFamily
    }   // end TimelineView closure
}

struct IPhoneLockScreenContent: View {
    let context: ActivityViewContext<HydrationAttributes>
    let current: Double
    let fill: Double
    let mins: Double
    let btns: [(amount: Double, label: String)]
    

    var body: some View {
        let amount1 = context.state.btnLive1
        let label1 = HydrationMath.formatLabel(amount: amount1, isOunces: context.state.isOunces)
        let amount2 = context.state.btnLive2
        let label2 = HydrationMath.formatLabel(amount: amount2, isOunces: context.state.isOunces)
        let amount3 = context.state.btnLive3
        let label3 = HydrationMath.formatLabel(amount: amount3, isOunces: context.state.isOunces)
     
        VStack() {
            // Row 1: number | progress bar | streak
            
            HStack(alignment: .center, spacing: 10) {
                VStack(alignment: .leading, spacing: 1) {
                    Text(HydrationMath.formatLabel(amount: current, isOunces: context.state.isOunces))
                        .font(.system(size: 26, weight: .bold, design: .rounded).monospacedDigit())
                        .foregroundStyle(.blue)
                    Text("of \(HydrationMath.formatLabel(amount: context.state.dailyGoal, isOunces: context.state.isOunces))")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
                .frame(width: 80, alignment: .leading)
 
                VStack(alignment: .leading, spacing: 4) {
                    GeometryReader { proxy in
                        ZStack(alignment: .leading) {
                            Capsule().fill(Color.blue.opacity(0.15))
                            Capsule()
                                .fill(LinearGradient(
                                    colors: [.blue.opacity(0.75), .blue],
                                    startPoint: .leading, endPoint: .trailing))
                                .frame(width: max(0, proxy.size.width * fill))
                                .animation(.spring(response: 0.45), value: fill)
                            if fill > 0.1 {
                                Text("\(Int(fill * 100))%")
                                    .font(.system(size: 11, weight: .bold))
                                    .foregroundColor(.white)
                                    .padding(.leading, 8)
                            }
                        }
                    }
                    .frame(height: 10)

                    // Now naturally left-aligned under the bar
                    HStack(spacing: 10) {
                        HStack(spacing: 3) {
                            Image(systemName: "clock").font(.system(size: 9))
                            Text(timeSinceLabel(mins: mins)).font(.system(size: 11))
                        }
                        .foregroundColor(mins > 90 ? .orange : .secondary)
                        HStack(spacing: 3) {
                            Image(systemName: "arrow.down").font(.system(size: 9))
                            Text("−1 ml/min").font(.system(size: 11))
                        }
                        .foregroundColor(.secondary)
                        Spacer()
                    }
                }
 
                VStack(alignment: .trailing, spacing: 2) {
                    if context.state.streak > 0 {
                        HStack(spacing: 2) {
                            Text(StreakManager.flameEmoji(for: context.state.streak)).font(.system(size: 11))
                            Text("\(context.state.streak)d").font(.system(size: 10, weight: .bold)).foregroundColor(.orange)
                        }
                    }
                    if context.state.goalAdjustedBy > 0 {
                        Image(systemName: "thermometer.sun.fill").font(.system(size: 9)).foregroundColor(.orange)
                    }
                }
                .frame(width: 36, alignment: .trailing)
            }

 
            // Row 3: 3 log buttons
            HStack(spacing: 8) {
                Button(intent: LogWaterIntent(amount: amount1)) {
                    Text(label1)
                        .font(.system(size: 13, weight: .bold))
                        .lineLimit(1).minimumScaleFactor(0.75)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 9)
                        .foregroundColor(.blue)
                        .cornerRadius(10)
                }
                Button(intent: LogWaterIntent(amount: amount2)) {
                    Text(label2)
                        .font(.system(size: 13, weight: .bold))
                        .lineLimit(1).minimumScaleFactor(0.75)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 9)
                        .foregroundColor(.blue)
                        .cornerRadius(10)
                }
                Button(intent: LogWaterIntent(amount: amount3)) {
                    Text(label3)
                        .font(.system(size: 13, weight: .bold))
                        .lineLimit(1).minimumScaleFactor(0.75)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 9)
                        .foregroundColor(.blue)
                        .cornerRadius(10)
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }
}
 
// MARK: - Watch Smart Stack View (.small activityFamily)
// Compact card designed for the ~170x90pt Smart Stack slot
// Shows: level, progress bar with %, decay indicator, adaptive flag, 2 tap-to-log buttons
 
struct WatchSmartStackView: View {
    let context: ActivityViewContext<HydrationAttributes>
    let current: Double
    let fill: Double
    let mins: Double
 
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
 
            // Row 1: level number + streak/adaptive right-aligned
            HStack(alignment: .firstTextBaseline) {
                Text(HydrationMath.formatLabel(amount: current, isOunces: context.state.isOunces))
                    .font(.system(size: 22, weight: .bold, design: .rounded).monospacedDigit())
                    .foregroundStyle(.blue)
                Text("/ \(HydrationMath.formatLabel(amount: context.state.dailyGoal, isOunces: context.state.isOunces))")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                Spacer()
                HStack(spacing: 4) {
                    Text(timeSinceLabel(mins: mins))
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                }
            }
 
            // Row 2: progress bar with % inside
            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.blue.opacity(0.18))
                    Capsule()
                        .fill(LinearGradient(
                            colors: fill >= 1 ? [.green, .green] : [.blue, .cyan],
                            startPoint: .leading, endPoint: .trailing))
                        .frame(width: max(0, proxy.size.width * fill))
                        .animation(.spring(response: 0.45), value: fill)
                    if fill > 0.12 {
                        Text("\(Int(fill * 100))%")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundColor(.white)
                            .padding(.leading, 7)
                    }
                }
            }
            .frame(height: 18)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .widgetURL(URL(string: "sipwatch://open"))
    }
}

// MARK: - Lock Screen Tube (hero element)

struct LockScreenTube: View {
    let fillRatio: Double
    let accentColor: Color

    // Much bigger than before — this is the visual anchor
    private let width: CGFloat = 28
    private let height: CGFloat = 80

    var body: some View {
        ZStack(alignment: .bottom) {
            // Track
            RoundedRectangle(cornerRadius: width / 2)
                .fill(accentColor.opacity(0.12))
                .frame(width: width, height: height)

            // Liquid fill with gradient
            RoundedRectangle(cornerRadius: width / 2)
                .fill(LinearGradient(
                    colors: [accentColor, accentColor.opacity(0.6)],
                    startPoint: .bottom, endPoint: .top))
                .frame(width: width, height: max(6, height * fillRatio))
                .animation(.spring(response: 0.6, dampingFraction: 0.7), value: fillRatio)

            // Subtle shine line
            RoundedRectangle(cornerRadius: 2)
                .fill(Color.white.opacity(0.3))
                .frame(width: 4, height: max(0, height * fillRatio - 10))
                .offset(x: -6)
                .animation(.spring(response: 0.6, dampingFraction: 0.7), value: fillRatio)
        }
        .frame(width: width, height: height)
        // Tick marks on the side
        .overlay(alignment: .trailing) {
            VStack(spacing: 0) {
                ForEach([0.75, 0.5, 0.25], id: \.self) { pct in
                    Spacer()
                    Rectangle()
                        .fill(accentColor.opacity(fillRatio >= pct ? 0.6 : 0.2))
                        .frame(width: 5, height: 1)
                        .offset(x: 8)
                    if pct == 0.25 { Spacer() }
                }
            }
            .frame(height: height)
        }
    }
}

// MARK: - Home Widget (unchanged structure, urgency-aware colors added)

struct TideProvider: TimelineProvider {
    func placeholder(in context: Context) -> HydrationEntry { HydrationEntry(date: Date()) }
    func getSnapshot(in context: Context, completion: @escaping (HydrationEntry) -> Void) {
        completion(HydrationEntry(date: Date()))
    }
    func getTimeline(in context: Context, completion: @escaping (Timeline<HydrationEntry>) -> Void) {
        // Refresh every 15 min to track decay
        completion(Timeline(entries: [HydrationEntry(date: Date())],
                            policy: .after(Date().addingTimeInterval(15 * 60))))
    }
}

struct HydrationEntry: TimelineEntry { let date: Date }

struct SipHomeWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "SipHomeWidget", provider: TideProvider()) { entry in
            HomeWidgetView(entry: entry)
                .containerBackground(Color(UIColor.systemBackground), for: .widget)
        }
        .configurationDisplayName("Sip Tracker")
        .supportedFamilies([.systemSmall, .systemMedium, .accessoryCircular])
    }
}

struct HomeWidgetView: View {
    var entry: HydrationEntry
    @Environment(\.widgetFamily) var family
    
    @AppStorage("currentIntakeML", store: Constants.defaults) var currentIntakeML: Double = 0
    @AppStorage("dailyGoalML", store: Constants.defaults) var dailyGoalML: Double = 2000
    @AppStorage("isOunces", store: Constants.defaults) var isOunces: Bool = false
    
    @AppStorage("btnSmall", store: Constants.defaults) var btnSmall: Double = 354.9
    
    @AppStorage("btnMed1", store: Constants.defaults) var btnMed1: Double = 177.4
    @AppStorage("btnMed2", store: Constants.defaults) var btnMed2: Double = 354.9
    @AppStorage("btnMed3", store: Constants.defaults) var btnMed3: Double = 473.2
    
    var body: some View {
        let lastDrink = Constants.defaults.object(forKey: "lastDrinkTimestamp") as? Date ?? Date()
        let current = HydrationMath.currentLevel(intake: currentIntakeML, lastDrink: lastDrink, now: Date())
        let fillRatio = min(1.0, current / dailyGoalML)
        let isGoalMet = current >= dailyGoalML
        
        // Temporarily hardcoded for Part 1 (We will make these customizable in Part 2)
        let labelSmall = HydrationMath.formatLabel(amount: btnSmall, isOunces: isOunces)
        let labelMed1 = HydrationMath.formatLabel(amount: btnMed1, isOunces: isOunces)
        let labelMed2 = HydrationMath.formatLabel(amount: btnMed2, isOunces: isOunces)
        let labelMed3 = HydrationMath.formatLabel(amount: btnMed3, isOunces: isOunces)
        
        switch family {
        case .accessoryCircular:
            if isGoalMet {
                Image(systemName: "checkmark.circle.fill").foregroundColor(.green)
            } else {
                Gauge(value: fillRatio) { Image(systemName: "drop.fill") }.gaugeStyle(.accessoryCircular).tint(.cyan)
            }
            
        case .systemSmall:
            // 🌟 SMALL WIDGET: Vertical bar, centered, 1 button
            VStack {
                HStack(alignment: .bottom, spacing: 12) {
                    ZStack(alignment: .bottom) {
                        Capsule().fill(Color.gray.opacity(0.2))
                        Capsule().fill(Color.cyan).frame(height: 70 * fillRatio)
                    }.frame(width: 16, height: 70)
                    
                    VStack(alignment: .leading, spacing: 2) {
                        Text(HydrationMath.formatLabel(amount: current, isOunces: isOunces))
                            .font(.title3.bold())
                        Text("of \(HydrationMath.formatLabel(amount: dailyGoalML, isOunces: isOunces))")
                            .font(.caption2).foregroundColor(.secondary)
                    }
                    .padding(.bottom, 4)
                }
                
                Spacer()
                
                Button(intent: LogWaterIntent(amount: btnSmall)) {
                    Text(labelSmall).font(.caption.bold()).frame(maxWidth: .infinity).padding(.vertical, 8)
                        .background(Color.cyan.opacity(0.2)).foregroundColor(.cyan).cornerRadius(8)
                }
            }
            
        case .systemMedium:
            // 🌟 MEDIUM WIDGET: Horizontal bar, 2 buttons (Mirrors Live Activity)
            VStack(spacing: 12) {
                HStack {
                    Image(systemName: "drop.fill").foregroundColor(.cyan)
                    Text("Hydration").font(.headline)
                    Spacer()
                    Text(HydrationMath.formatLabel(amount: current, isOunces: isOunces))
                        .font(.headline.monospacedDigit()).foregroundColor(.cyan)
                }
                
                GeometryReader { proxy in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Color.gray.opacity(0.2))
                        Capsule().fill(Color.cyan).frame(width: max(0, proxy.size.width * fillRatio))
                    }
                }.frame(height: 12)
                
                HStack(spacing: 12) {
                    Button(intent: LogWaterIntent(amount: btnMed1)) {
                        Text(labelMed1).font(.caption.bold()).frame(maxWidth: .infinity).padding(.vertical, 8)
                            .background(Color.cyan.opacity(0.2)).foregroundColor(.cyan).cornerRadius(8)
                    }
                    Button(intent: LogWaterIntent(amount: btnMed2)) {
                        Text(labelMed2).font(.caption.bold()).frame(maxWidth: .infinity).padding(.vertical, 8)
                            .background(Color.cyan.opacity(0.2)).foregroundColor(.cyan).cornerRadius(8)
                    }
                    Button(intent: LogWaterIntent(amount: btnMed3)) {
                        Text(labelMed3).font(.caption.bold()).frame(maxWidth: .infinity).padding(.vertical, 8)
                            .background(Color.cyan.opacity(0.2)).foregroundColor(.cyan).cornerRadius(8)
                    }
                }
            }
            
        default:
            Text("Unsupported Widget")
        }
    }
}
