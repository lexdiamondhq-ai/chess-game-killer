import ActivityKit
import SwiftUI
import WidgetKit

/// Your game against a rival on the Lock Screen, in the Dynamic Island and in StandBy. The app
/// starts and updates it (LiveGameKeeper); the faces are drawn by LiveGameViews (Shared/LiveGame),
/// which the app's tests draw too. A tap anywhere opens the game.
struct LiveGameWidget: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: LiveGameAttributes.self) { context in
            LiveGameLockView(game: context.attributes, state: context.state)
                .activityBackgroundTint(LiveGamePalette.background.opacity(0.78))
                .activitySystemActionForegroundColor(LiveGamePalette.ink)
                .widgetURL(LiveGameLink.url)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    LiveGameIsland.Leading(game: context.attributes)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    LiveGameIsland.Trailing(game: context.attributes, state: context.state)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    LiveGameIsland.Bottom(game: context.attributes, state: context.state)
                }
            } compactLeading: {
                LiveGameIsland.CompactLeading(game: context.attributes)
            } compactTrailing: {
                LiveGameIsland.CompactTrailing(game: context.attributes, state: context.state)
            } minimal: {
                LiveGameIsland.CompactLeading(game: context.attributes)
            }
            // Folded up, the orb and the clock keep even margins from the island's rounded ends
            // and a little room on the camera's side. Left to the defaults, iOS set them so far in
            // that the orb's inner half and the clock's first digit slid under the camera.
            .contentMargins(.leading, LiveGameIsland.endMargin, for: .compactLeading)
            .contentMargins(.trailing, LiveGameIsland.cameraMargin, for: .compactLeading)
            .contentMargins(.leading, LiveGameIsland.cameraMargin, for: .compactTrailing)
            .contentMargins(.trailing, LiveGameIsland.endMargin, for: .compactTrailing)
            .widgetURL(LiveGameLink.url)
            .keylineTint(context.attributes.light)
        }
    }
}
