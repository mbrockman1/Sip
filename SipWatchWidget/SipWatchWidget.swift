//
//  SipWatchWidget.swift
//  SipWatchWidget
//
//  Created by Michael Brockman on 4/28/26.
//

import WidgetKit
import SwiftUI

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

        // ── Circular: Gauge ─────────────────────────────────────────
        case .accessoryCircular:
            Gauge(value: fillRatio) {
                Image(systemName: "drop.fill")
            } currentValueLabel: {
                Text("\(Int(fillRatio * 100))%")
                    .font(.system(size: 11, weight: .bold, design: .rounded))
            }
            .gaugeStyle(.accessoryCircular)
            .tint(fillRatio >= 1 ? .green : .cyan)

        // ── Corner: Mini progress arc ────────────────────────────────
        case .accessoryCorner:
            ZStack {
                Image(systemName: fillRatio >= 1 ? "checkmark.circle.fill" : "drop.fill")
                    .foregroundColor(fillRatio >= 1 ? .green : .cyan)
            }
            .widgetLabel {
                Gauge(value: fillRatio) {
                    EmptyView()
                }
                .gaugeStyle(.accessoryLinear)
                .tint(fillRatio >= 1 ? .green : .cyan)
            }

        // ── Rectangular: Level + streak ──────────────────────────────
        case .accessoryRectangular:
            HStack(spacing: 8) {
                // Mini tube
                ZStack(alignment: .bottom) {
                    RoundedRectangle(cornerRadius: 4).fill(Color.cyan.opacity(0.2)).frame(width: 8, height: 36)
                    RoundedRectangle(cornerRadius: 4)
                        .fill(LinearGradient(colors: [.blue, .cyan], startPoint: .bottom, endPoint: .top))
                        .frame(width: 8, height: max(2, 36 * fillRatio))
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(HydrationMath.formatLabel(amount: liveLevel, isOunces: entry.isOunces))
                        .font(.system(size: 14, weight: .bold, design: .rounded))
                        .foregroundColor(.cyan)
                    Text("of \(HydrationMath.formatLabel(amount: entry.goalML, isOunces: entry.isOunces))")
                        .font(.system(size: 10)).foregroundColor(.secondary)
                    if entry.streak > 0 {
                        Text(StreakManager.flameEmoji(for: entry.streak) + " \(entry.streak)d")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundColor(.orange)
                    }
                }
                Spacer()
            }

        // ── Inline: Text only ────────────────────────────────────────
        case .accessoryInline:
            Text("💧 \(HydrationMath.formatLabel(amount: liveLevel, isOunces: entry.isOunces)) / \(Int(fillRatio * 100))%")

        default:
            Image(systemName: "drop.fill").foregroundColor(.cyan)
        }
    }
}

// MARK: - Watch Complication Views

struct SipWatchComplication: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "SipWatchComplication", provider: SipWatchProvider()) { entry in
            SipComplicationView(entry: entry)
                .containerBackground(.black, for: .widget)
        }
        .configurationDisplayName("Sip")
        .supportedFamilies([
            .accessoryCircular,
            .accessoryCorner,
            .accessoryRectangular,
            .accessoryInline
        ])
    }
}



