//
//  SipWatchWidget.swift
//  SipWatchWidget
//

import WidgetKit
import SwiftUI

// MARK: - Complication View

struct SipComplicationView: View {
    var entry: WatchHydrationEntry
    @Environment(\.widgetFamily) var family

    private var liveLevel: Double {
        HydrationMath.currentLevel(intake: entry.currentML, lastDrink: entry.lastDrink, now: entry.date)
    }
    private var fillRatio: Double {
        HydrationMath.fillRatio(current: liveLevel, goal: entry.goalML)
    }

    var body: some View {
        switch family {

        // Circular — gauge arc with % in center
        case .accessoryCircular:
            Gauge(value: fillRatio) {
                Image(systemName: "drop.fill")
                    .foregroundColor(fillRatio >= 1 ? .green : .cyan)
            } currentValueLabel: {
                Text("\(Int(fillRatio * 100))%")
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .foregroundColor(fillRatio >= 1 ? .green : .cyan)
            }
            .gaugeStyle(.accessoryCircular)
            .tint(fillRatio >= 1 ? .green : .cyan)

        // Corner — drop icon + linear gauge label
        case .accessoryCorner:
            Image(systemName: fillRatio >= 1 ? "checkmark.circle.fill" : "drop.fill")
                .foregroundColor(fillRatio >= 1 ? .green : .cyan)
                .widgetLabel {
                    Gauge(value: fillRatio) { EmptyView() }
                        .gaugeStyle(.accessoryLinear)
                        .tint(fillRatio >= 1 ? .green : .cyan)
                }

        // Rectangular — mirrors TodayDashboardCard layout
        // Level (large) | progress bar | streak | decay | adaptive
        case .accessoryRectangular:
            VStack(alignment: .leading, spacing: 4) {

                // Row 1: level + streak
                HStack(alignment: .firstTextBaseline) {
                    Text(HydrationMath.formatLabel(amount: liveLevel, isOunces: entry.isOunces))
                        .font(.system(size: 16, weight: .bold, design: .rounded))
                        .foregroundColor(.cyan)
                    Text("of \(HydrationMath.formatLabel(amount: entry.goalML, isOunces: entry.isOunces))")
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                    Spacer()
                    if entry.streak > 0 {
                        HStack(spacing: 2) {
                            Text(StreakManager.flameEmoji(for: entry.streak))
                                .font(.system(size: 10))
                            Text("\(entry.streak)d")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundColor(.orange)
                        }
                    }
                }

                // Row 2: progress bar with %
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Color.cyan.opacity(0.2))
                        Capsule()
                            .fill(LinearGradient(
                                colors: fillRatio >= 1
                                    ? [.green, .green]
                                    : [.blue, .cyan],
                                startPoint: .leading, endPoint: .trailing))
                            .frame(width: max(0, geo.size.width * fillRatio))
                        if fillRatio > 0.15 {
                            Text("\(Int(fillRatio * 100))%")
                                .font(.system(size: 8, weight: .bold))
                                .foregroundColor(.white)
                                .padding(.leading, 5)
                        }
                    }
                }
                .frame(height: 12)

                // Row 3: decay + adaptive goal
                HStack(spacing: 6) {
                    let mins = entry.date.timeIntervalSince(entry.lastDrink) / 60
                    Circle()
                        .fill(mins < 30 ? Color.green : mins < 90 ? Color.yellow : Color.orange)
                        .frame(width: 5, height: 5)
                    Text(timeSinceLabel(mins: mins))
                        .font(.system(size: 9))
                        .foregroundColor(.secondary)
                    if entry.goalAdjustedBy > 0 {
                        Image(systemName: "thermometer.sun.fill")
                            .font(.system(size: 9))
                            .foregroundColor(.orange)
                        Text("+\(HydrationMath.formatLabel(amount: entry.goalAdjustedBy, isOunces: entry.isOunces))")
                            .font(.system(size: 9))
                            .foregroundColor(.orange)
                    }
                }
            }
            .padding(.horizontal, 2)

        // Inline — compact text
        case .accessoryInline:
            if fillRatio >= 1 {
                Label("Goal hit!", systemImage: "checkmark.circle.fill")
            } else {
                Label(
                    "\(HydrationMath.formatLabel(amount: liveLevel, isOunces: entry.isOunces)) · \(Int(fillRatio * 100))%",
                    systemImage: "drop.fill"
                )
            }

        default:
            Image(systemName: "drop.fill").foregroundColor(.cyan)
        }
    }
}

// MARK: - Widget

struct SipWatchComplication: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "SipWatchComplication", provider: SipWatchProvider()) { entry in
            SipComplicationView(entry: entry)
                // No black background — let the watch face control it
                .containerBackground(for: .widget) { Color.clear }
        }
        .configurationDisplayName("Sip")
        .description("Live hydration level")
        .supportedFamilies([
            .accessoryCircular,
            .accessoryCorner,
            .accessoryRectangular,
            .accessoryInline
        ])
    }
}
