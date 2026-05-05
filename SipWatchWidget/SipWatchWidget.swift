import WidgetKit
import SwiftUI

// MARK: - 1. Data Model
struct WatchHydrationEntry: TimelineEntry {
    let date: Date
    let currentML: Double
    let lastDrink: Date
    let goalML: Double
    let isOunces: Bool
}

// MARK: - 2. Provider (Reads from Watch App Group)
struct SipWatchProvider: TimelineProvider {
    // 🌟 CORRECTED APP GROUP to match your project
    let sharedDefaults = UserDefaults(suiteName: "group.org.mjbapps.sip")!
    
    func placeholder(in context: Context) -> WatchHydrationEntry {
        WatchHydrationEntry(date: Date(), currentML: 1000, lastDrink: Date(), goalML: 2000, isOunces: false)
    }

    func getSnapshot(in context: Context, completion: @escaping (WatchHydrationEntry) -> Void) {
        completion(createEntry(for: Date()))
    }
    
    func getTimeline(in context: Context, completion: @escaping (Timeline<WatchHydrationEntry>) -> Void) {
        let currentDate = Date()
        let entry = createEntry(for: currentDate)
        
        // 🌟 FIXED BUDGET DRAIN: We only ask the system to refresh at Midnight.
        // The UI handles the minute-by-minute decay for free!
        let midnight = Calendar.current.nextDate(after: currentDate, matching: DateComponents(hour: 0, minute: 0), matchingPolicy: .nextTime)!
        let timeline = Timeline(entries: [entry], policy: .after(midnight))
        completion(timeline)
    }

    private func createEntry(for date: Date) -> WatchHydrationEntry {
            let sharedDefaults = UserDefaults(suiteName: "group.org.mjbapps.sip-dynamic-hydration")!
            let goal = sharedDefaults.double(forKey: "dailyGoalML")
            let lastDrink = sharedDefaults.object(forKey: "lastDrinkTimestamp") as? Date ?? Date()
            
            // 🌟 THE MIDNIGHT AUTO-RESET FOR WIDGETS
            // If the date in UserDefaults is not today, force the widget to show 0
            let currentIntake: Double
            let actualLastDrink: Date
            
            if !Calendar.current.isDateInToday(lastDrink) {
                currentIntake = 0
                actualLastDrink = date // Pretend the "last drink" was now
            } else {
                currentIntake = sharedDefaults.double(forKey: "currentIntakeML")
                actualLastDrink = lastDrink
            }
            
            return WatchHydrationEntry(
                date: date,
                currentML: currentIntake,
                lastDrink: actualLastDrink,
                goalML: goal > 0 ? goal : 2000,
                isOunces: sharedDefaults.bool(forKey: "isOunces")
            )
        }
}

struct WidgetMath {
    static let ozMultiplier = 29.5735296 // 🌟 Fixed precision
    
    static func currentLevel(intake: Double, lastDrink: Date, now: Date) -> Double {
        if !Calendar.current.isDate(lastDrink, inSameDayAs: now) { return 0.0 }
        let hoursPassed = max(0, now.timeIntervalSince(lastDrink)) / 3600.0
        let decay = hoursPassed * 60.0
        return max(0, intake - decay)
    }
    
    static func formatLabel(amount: Double, isOunces: Bool) -> String {
        let displayAmount = isOunces ? (amount / ozMultiplier) : amount
        let unit = isOunces ? "oz" : "ml"
        return "\(Int(round(displayAmount))) \(unit)" // 🌟 Fixed: Added round()
    }
}

struct SipComplicationView: View {
    var entry: WatchHydrationEntry
    @Environment(\.widgetFamily) var family

    var body: some View {
        // 🌟 FIXED BUDGET DRAIN: Wraps the UI in TimelineView so it animates locally!
        TimelineView(.periodic(from: entry.lastDrink, by: 60)) { timeline in
            
            let liveLevel = WidgetMath.currentLevel(intake: entry.currentML, lastDrink: entry.lastDrink, now: timeline.date)
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
// (Ensure your SipWatchWidgetBundle.swift is still pointing to 'SipWatchComplication')
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
