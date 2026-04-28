//
//  SipWidgetLiveActivity.swift
//  SipWidget
//
//  Created by Michael Brockman on 4/27/26.
//

import ActivityKit
import WidgetKit
import SwiftUI

struct SipWidgetAttributes: ActivityAttributes {
    public struct ContentState: Codable, Hashable {
        // Dynamic stateful properties about your activity go here!
        var emoji: String
    }

    // Fixed non-changing properties about your activity go here!
    var name: String
}

struct SipWidgetLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: SipWidgetAttributes.self) { context in
            // Lock screen/banner UI goes here
            VStack {
                Text("Hello \(context.state.emoji)")
            }
            .activityBackgroundTint(Color.cyan)
            .activitySystemActionForegroundColor(Color.black)

        } dynamicIsland: { context in
            DynamicIsland {
                // Expanded UI goes here.  Compose the expanded UI through
                // various regions, like leading/trailing/center/bottom
                DynamicIslandExpandedRegion(.leading) {
                    Text("Leading")
                }
                DynamicIslandExpandedRegion(.trailing) {
                    Text("Trailing")
                }
                DynamicIslandExpandedRegion(.bottom) {
                    Text("Bottom \(context.state.emoji)")
                    // more content
                }
            } compactLeading: {
                Text("L")
            } compactTrailing: {
                Text("T \(context.state.emoji)")
            } minimal: {
                Text(context.state.emoji)
            }
            .widgetURL(URL(string: "http://www.apple.com"))
            .keylineTint(Color.red)
        }
    }
}

extension SipWidgetAttributes {
    fileprivate static var preview: SipWidgetAttributes {
        SipWidgetAttributes(name: "World")
    }
}

extension SipWidgetAttributes.ContentState {
    fileprivate static var smiley: SipWidgetAttributes.ContentState {
        SipWidgetAttributes.ContentState(emoji: "😀")
     }
     
     fileprivate static var starEyes: SipWidgetAttributes.ContentState {
         SipWidgetAttributes.ContentState(emoji: "🤩")
     }
}

#Preview("Notification", as: .content, using: SipWidgetAttributes.preview) {
   SipWidgetLiveActivity()
} contentStates: {
    SipWidgetAttributes.ContentState.smiley
    SipWidgetAttributes.ContentState.starEyes
}
