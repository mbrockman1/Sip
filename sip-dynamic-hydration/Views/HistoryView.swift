//
//  HistoryView.swift
//  sip-dynamic-hydration
//
//  Created by Michael Brockman on 4/29/26.
//
import SwiftUI
import HealthKit

struct HistoryView: View {
    @EnvironmentObject var manager: HydrationManager
    
    var body: some View {
        List {
            Section(header: Text("Today's Apple Health Logs")) {
                if manager.todaysSamples.isEmpty {
                    Text("No water logged today.")
                        .foregroundColor(.secondary)
                }
                
                ForEach(manager.todaysSamples, id: \.uuid) { sample in
                    let ml = sample.quantity.doubleValue(for: HKUnit.literUnit(with: .milli))
                    HStack {
                        VStack(alignment: .leading) {
                            Text(HydrationMath.formatLabel(amount: ml, isOunces: manager.isOunces))
                                .font(.headline)
                            Text(sample.startDate, style: .time)
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                }
                .onDelete { indexSet in
                    for index in indexSet {
                        manager.deleteSample(manager.todaysSamples[index])
                    }
                }
            }
        }
        .navigationTitle("Log History")
    }
}
