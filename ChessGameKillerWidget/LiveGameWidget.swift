import ActivityKit
import SwiftUI
import WidgetKit

/// Your game against a rival on the Lock Screen, in the Dynamic Island and in StandBy. The app
/// starts and updates it (LiveGameKeeper); the faces are drawn by LiveGameViews (Shared/LiveGame),
/// which the app's tests draw too. A tap anywhere, or Open board, opens the game.
struct LiveGameWidget: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: LiveGameAttributes.self) { context in
            LiveGameLockView(game: context.attributes, state: context.state)
                .activityBackgroundTint(LiveGamePalette.background.opacity(0.88))
                .activitySystemActionForegroundColor(LiveGamePalette.ink)
                .widgetURL(LiveGameLink.url)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    LiveGameIsland.Leading(game: context.attributes, state: context.state)
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
                LiveGameIsland.Minimal(game: context.attributes, state: context.state)
            }
            // Folded up, the portrait and the clock keep even margins from the island's rounded ends
            // and a little room on the camera's side. Left to the defaults, iOS set them so far in
            // that the portrait's inner half and the clock's first digit slid under the camera.
            .contentMargins(.leading, LiveGameIsland.endMargin, for: .compactLeading)
            .contentMargins(.trailing, LiveGameIsland.cameraMargin, for: .compactLeading)
            .contentMargins(.leading, LiveGameIsland.cameraMargin, for: .compactTrailing)
            .contentMargins(.trailing, LiveGameIsland.endMargin, for: .compactTrailing)
            .widgetURL(LiveGameLink.url)
            .keylineTint(context.attributes.light)
        }
    }
}

/// Today's Move on the Lock Screen and in the Dynamic Island until it's done. The app starts and
/// ends it (DailyActivityKeeper); the faces are in Shared/LiveGame/DailyActivity.swift.
struct DailyActivityWidget: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: DailyActivityAttributes.self) { context in
            DailyActivityLockView(puzzle: context.attributes, state: context.state)
                .activityBackgroundTint(LiveGamePalette.background.opacity(0.88))
                .activitySystemActionForegroundColor(LiveGamePalette.ink)
                .widgetURL(DailyActivityAttributes.link)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    DailyActivityIsland.Leading(puzzle: context.attributes)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    DailyActivityIsland.Trailing(state: context.state)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    DailyActivityIsland.Bottom(puzzle: context.attributes)
                }
            } compactLeading: {
                DailyActivityIsland.CompactLeading()
            } compactTrailing: {
                DailyActivityIsland.CompactTrailing(state: context.state)
            } minimal: {
                DailyActivityIsland.CompactLeading()
            }
            .contentMargins(.leading, LiveGameIsland.endMargin, for: .compactLeading)
            .contentMargins(.trailing, LiveGameIsland.cameraMargin, for: .compactLeading)
            .contentMargins(.leading, LiveGameIsland.cameraMargin, for: .compactTrailing)
            .contentMargins(.trailing, LiveGameIsland.endMargin, for: .compactTrailing)
            .widgetURL(DailyActivityAttributes.link)
            .keylineTint(LiveGamePalette.gold)
        }
    }
}
