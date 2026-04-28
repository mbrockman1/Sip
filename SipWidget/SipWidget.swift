import WidgetKit
import SwiftUI
import ActivityKit
import AppIntents

@main
struct SipWidgetBundle: WidgetBundle {
    var body: some Widget {
        SipLiveActivity()
        SipHomeWidget()
    }
}

// MARK: - Live Activity & Dynamic Island
struct SipLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: HydrationAttributes.self) { context in
            LockScreenView(context: context)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    HStack {
                        Image(systemName: "drop.fill").foregroundColor(.cyan)
                        Text("Sip").font(.headline)
                    }
                    .padding(.top, 4)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    IslandLiveText(context: context)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    IslandBottomView(context: context)
                }
            } compactLeading: {
                Image(systemName: "drop.fill").foregroundColor(.cyan)
            } compactTrailing: {
                // FIXED: Vertical bar graph instead of clipping circle
                VerticalCompactBar(context: context)
            } minimal: {
                VerticalCompactBar(context: context)
            }
        }
    }
}

// Fixed mini vertical bar for the side of the Dynamic Island
struct VerticalCompactBar: View {
    let context: ActivityViewContext<HydrationAttributes>
    var body: some View {
        TimelineView(.periodic(from: context.state.lastDrinkTimestamp, by: 60)) { timeline in
            let current = HydrationMath.currentLevel(intake: context.state.currentIntake, lastDrink: context.state.lastDrinkTimestamp, now: timeline.date)
            let fillRatio = min(1.0, current / context.state.dailyGoal)
            
            HStack(alignment: .bottom, spacing: 2) {
                Capsule().fill(Color.cyan.opacity(0.3)).frame(width: 4, height: 16)
                Capsule().fill(Color.cyan.opacity(0.6)).frame(width: 4, height: 16 * max(0.2, fillRatio))
                Capsule().fill(Color.cyan).frame(width: 4, height: 16 * fillRatio)
            }
        }
    }
}

struct IslandLiveText: View {
    let context: ActivityViewContext<HydrationAttributes>
    var body: some View {
        TimelineView(.periodic(from: context.state.lastDrinkTimestamp, by: 60)) { timeline in
            let current = HydrationMath.currentLevel(intake: context.state.currentIntake, lastDrink: context.state.lastDrinkTimestamp, now: timeline.date)
            Text(HydrationMath.formatLabel(amount: current, isOunces: context.state.isOunces))
                .font(.subheadline.bold().monospacedDigit()).foregroundColor(.cyan).padding(.top, 4)
        }
    }
}

struct IslandBottomView: View {
    let context: ActivityViewContext<HydrationAttributes>
    var body: some View {
        TimelineView(.periodic(from: context.state.lastDrinkTimestamp, by: 60)) { timeline in
            let current = HydrationMath.currentLevel(intake: context.state.currentIntake, lastDrink: context.state.lastDrinkTimestamp, now: timeline.date)
            let fillRatio = min(1.0, current / context.state.dailyGoal)
            let amount1 = context.state.isOunces ? 236.588 : 250.0
            let label1 = context.state.isOunces ? "+ 8 oz" : "+ 250 ml"
            let amount2 = context.state.isOunces ? 473.176 : 500.0
            let label2 = context.state.isOunces ? "+ 16 oz" : "+ 500 ml"
            
            VStack(spacing: 12) {
                GeometryReader { proxy in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Color.gray.opacity(0.3))
                        Capsule().fill(Color.cyan)
                            .frame(width: max(0, proxy.size.width * fillRatio))
                            .animation(.spring(), value: fillRatio)
                    }
                }.frame(height: 12).padding(.horizontal, 4)
                
                HStack(spacing: 12) {
                    Button(intent: LogWaterIntent(amount: amount1)) {
                        Text(label1).font(.caption.bold()).frame(maxWidth: .infinity).padding(.vertical, 8)
                            .background(Color.cyan.opacity(0.2)).foregroundColor(.cyan).cornerRadius(8)
                    }
                    Button(intent: LogWaterIntent(amount: amount2)) {
                        Text(label2).font(.caption.bold()).frame(maxWidth: .infinity).padding(.vertical, 8)
                            .background(Color.cyan.opacity(0.2)).foregroundColor(.cyan).cornerRadius(8)
                    }
                }
            }.padding(.bottom, 8).padding(.top, 4)
        }
    }
}

// MARK: - Lock Screen (Premium Background)
struct LockScreenView: View {
    let context: ActivityViewContext<HydrationAttributes>
    var body: some View {
        TimelineView(.periodic(from: context.state.lastDrinkTimestamp, by: 60)) { timeline in
            let current = HydrationMath.currentLevel(intake: context.state.currentIntake, lastDrink: context.state.lastDrinkTimestamp, now: timeline.date)
            let fillRatio = min(1.0, current / context.state.dailyGoal)
            let amount1 = context.state.isOunces ? 236.588 : 250.0
            let label1 = context.state.isOunces ? "+ 8 oz" : "+ 250 ml"
            let amount2 = context.state.isOunces ? 473.176 : 500.0
            let label2 = context.state.isOunces ? "+ 16 oz" : "+ 500 ml"
            
            VStack(spacing: 16) {
                HStack(spacing: 16) {
                    ZStack(alignment: .bottom) {
                        Capsule().fill(Color.gray.opacity(0.3))
                        Capsule().fill(Color.cyan).frame(height: 50 * fillRatio).animation(.spring(), value: fillRatio)
                    }.frame(width: 14, height: 50)
                    
                    VStack(alignment: .leading) {
                        Text("Hydration").font(.headline).foregroundColor(.primary)
                        Text(HydrationMath.formatLabel(amount: current, isOunces: context.state.isOunces))
                            .font(.subheadline.monospacedDigit()).foregroundColor(.cyan)
                    }
                    Spacer()
                }
                HStack(spacing: 12) {
                    Button(intent: LogWaterIntent(amount: amount1)) {
                        Text(label1).font(.caption.bold()).frame(maxWidth: .infinity).padding(.vertical, 8)
                            .background(Color.cyan.opacity(0.2)).foregroundColor(.cyan).cornerRadius(8)
                    }
                    Button(intent: LogWaterIntent(amount: amount2)) {
                        Text(label2).font(.caption.bold()).frame(maxWidth: .infinity).padding(.vertical, 8)
                            .background(Color.cyan.opacity(0.2)).foregroundColor(.cyan).cornerRadius(8)
                    }
                }
            }
            .padding()
            // PREMIUM FIX: Uses a native frosted glass material background instead of transparent
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 24))
            .padding(.horizontal, 4)
        }
    }
}

// MARK: - Home Widgets
struct TideProvider: TimelineProvider {
    func placeholder(in context: Context) -> HydrationEntry { HydrationEntry(date: Date()) }
    func getSnapshot(in context: Context, completion: @escaping (HydrationEntry) -> ()) { completion(HydrationEntry(date: Date())) }
    func getTimeline(in context: Context, completion: @escaping (Timeline<HydrationEntry>) -> ()) {
        completion(Timeline(entries:[HydrationEntry(date: Date())], policy: .after(Date().addingTimeInterval(3600))))
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
        .supportedFamilies([.systemSmall, .accessoryCircular])
    }
}

struct HomeWidgetView: View {
    var entry: HydrationEntry
    @Environment(\.widgetFamily) var family
    
    @AppStorage("currentIntakeML", store: Constants.defaults) var currentIntakeML: Double = 0
    @AppStorage("dailyGoalML", store: Constants.defaults) var dailyGoalML: Double = 2000
    @AppStorage("isOunces", store: Constants.defaults) var isOunces: Bool = false
    
    var body: some View {
        let lastDrink = Constants.defaults.object(forKey: "lastDrinkTimestamp") as? Date ?? Date()
        let current = HydrationMath.currentLevel(intake: currentIntakeML, lastDrink: lastDrink, now: Date())
        let fillRatio = min(1.0, current / dailyGoalML)
        let amount1 = isOunces ? 236.588 : 250.0
        let label1 = isOunces ? "+ 8 oz" : "+ 250 ml"
        let isGoalMet = current >= dailyGoalML
        
        if family == .accessoryCircular {
            if isGoalMet {
                Image(systemName: "checkmark.circle.fill").foregroundColor(.green)
            } else {
                Gauge(value: fillRatio) { Image(systemName: "drop.fill") }.gaugeStyle(.accessoryCircular).tint(.cyan)
            }
        } else {
            if isGoalMet {
                VStack(spacing: 8) {
                    Image(systemName: "checkmark.circle.fill").font(.title).foregroundColor(.green)
                    Text("Goal Hit!").font(.headline)
                }
            } else {
                VStack(alignment: .leading) {
                    HStack {
                        ZStack(alignment: .bottom) {
                            Capsule().fill(Color.gray.opacity(0.2))
                            Capsule().fill(Color.cyan).frame(height: 50 * fillRatio)
                        }.frame(width: 12, height: 50)
                        
                        VStack(alignment: .leading) {
                            Text(HydrationMath.formatLabel(amount: current, isOunces: isOunces)).font(.headline)
                            Text("Level").font(.caption).foregroundColor(.secondary)
                        }
                    }
                    Spacer()
                    Button(intent: LogWaterIntent(amount: amount1)) {
                        Text(label1).font(.caption.bold()).frame(maxWidth: .infinity).padding(.vertical, 6)
                            .background(Color.cyan.opacity(0.2)).foregroundColor(.cyan).cornerRadius(8)
                    }
                }
            }
        }
    }
}
