import WidgetKit
import SwiftUI

// MARK: - 1. Data Model
struct WatchHydrationEntry: TimelineEntry {
    let date: Date
    let currentML: Double   // Raw intake from the app
    let lastDrink: Date     // Exact time of last drink
    let goalML: Double
    let isOunces: Bool
}

// MARK: - 2. Provider (Passes the raw data, no predicting)
struct SipWatchProvider: TimelineProvider {
    let sharedDefaults = UserDefaults(suiteName: "group.org.mjbapps.sip")!
    
    func placeholder(in context: Context) -> WatchHydrationEntry {
        WatchHydrationEntry(date: Date(), currentML: 1000, lastDrink: Date(), goalML: 2000, isOunces: false)
    }

    func getSnapshot(in context: Context, completion: @escaping (WatchHydrationEntry) -> Void) {
        completion(createEntry(for: Date()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<WatchHydrationEntry>) -> Void) {
        let entry = createEntry(for: Date())
        
        // 🌟 POLICY .never: We only give it one snapshot. The TimelineView in the UI
        // will handle the continuous live countdown. The watch app will force a
        // widget reload when you log a new drink!
        let timeline = Timeline(entries: [entry], policy: .never)
        completion(timeline)
    }
    
    private func createEntry(for date: Date) -> WatchHydrationEntry {
        let goal = sharedDefaults.double(forKey: "dailyGoalML")
        let rawLastDrink = sharedDefaults.object(forKey: "lastDrinkTimestamp") as? Date ?? Date()
        let rawIntake = sharedDefaults.double(forKey: "currentIntakeML")
        let isOunces = sharedDefaults.bool(forKey: "isOunces")
        
        // Handle midnight wipe so yesterday's data doesn't carry over in the morning
        let currentIntake = Calendar.current.isDateInToday(rawLastDrink) ? rawIntake : 0.0
        let lastDrink = Calendar.current.isDateInToday(rawLastDrink) ? rawLastDrink : date
        let safeGoal = goal > 0 ? goal : 2000
        
        return WatchHydrationEntry(date: date, currentML: currentIntake, lastDrink: lastDrink, goalML: safeGoal, isOunces: isOunces)
    }
}

// MARK: - 3. Local Math Helper
struct WidgetMath {
    static let ozMultiplier = 29.5735296
    
    static func currentLevel(intake: Double, lastDrink: Date, now: Date) -> Double {
        if !Calendar.current.isDate(lastDrink, inSameDayAs: now) { return 0.0 }
        let hoursPassed = max(0, now.timeIntervalSince(lastDrink)) / 3600.0
        let decay = hoursPassed * 60.0
        return max(0, intake - decay)
    }
    
    static func formatLabel(amount: Double, isOunces: Bool) -> String {
        let displayAmount = isOunces ? (amount / ozMultiplier) : amount
        let unit = isOunces ? "oz" : "ml"
        return "\(Int(round(displayAmount))) \(unit)"
    }
}

// MARK: - 4. UI (1:1 Mirror of the iPhone Live Activity)
struct SipComplicationView: View {
    var entry: WatchHydrationEntry
    @Environment(\.widgetFamily) var family

    var body: some View {
        // 🌟 TIMELINEVIEW: This ticks down minute-by-minute perfectly in sync with the iPhone!
        TimelineView(.periodic(from: entry.lastDrink, by: 60)) { context in
            
            let liveLevel = WidgetMath.currentLevel(intake: entry.currentML, lastDrink: entry.lastDrink, now: context.date)
            let fillRatio = min(1.0, max(0.0, liveLevel / entry.goalML))
            let isGoalMet = fillRatio >= 1.0
            let themeColor: Color = isGoalMet ? .green : .cyan
            let iconName = isGoalMet ? "checkmark.circle.fill" : "drop.fill"

            switch family {
            case .accessoryCircular, .accessoryCorner:
                Gauge(value: fillRatio) {
                    Image(systemName: iconName).foregroundColor(themeColor)
                } currentValueLabel: {
                    Text("\(Int(fillRatio * 100))%")
                }
                .gaugeStyle(.accessoryCircular)
                .tint(themeColor)

            case .accessoryRectangular:
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Hydration").font(.headline).foregroundColor(themeColor)
                        Text(WidgetMath.formatLabel(amount: liveLevel, isOunces: entry.isOunces))
                            .font(.title3.bold().monospacedDigit())
                    }
                    Spacer()
                    Gauge(value: fillRatio) {
                        Image(systemName: iconName).foregroundColor(themeColor)
                    }
                    .gaugeStyle(.accessoryCircular)
                    .tint(themeColor)
                }

            case .accessoryInline:
                Label("\(WidgetMath.formatLabel(amount: liveLevel, isOunces: entry.isOunces))", systemImage: iconName)
                    .foregroundColor(themeColor)

            default:
                Image(systemName: iconName).foregroundColor(themeColor)
            }
        }
    }
}

// MARK: - 5. Configuration
struct SipWatchComplication: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "SipWatchComplication", provider: SipWatchProvider()) { entry in
            SipComplicationView(entry: entry)
                .containerBackground(for: .widget) { Color.clear }
        }
        .configurationDisplayName("Sip Tracker")
        .description("A live hydration gauge.")
        .supportedFamilies([
            .accessoryCircular,
            .accessoryCorner,
            .accessoryRectangular,
            .accessoryInline
        ])
    }
}
