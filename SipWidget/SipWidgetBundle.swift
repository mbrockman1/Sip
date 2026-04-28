//
//  SipWidgetBundle.swift
//  sip-dynamic-hydration
//
//  Created by Michael Brockman on 4/28/26.
//
import WidgetKit
import SwiftUI

@main
struct SipWidgetBundle: WidgetBundle {
    var body: some Widget {
        SipLiveActivity()
        SipHomeWidget()
    }
}
