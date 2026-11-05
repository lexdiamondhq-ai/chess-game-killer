import ActivityKit
import Foundation

/// Keeps Today's Move on the Lock Screen and in the Dynamic Island while it's still open today:
/// it goes up when the app opens and the move isn't done, and comes down once it is, at midnight,
/// or when a game takes the Lock Screen. iOS's own switch turns it off (Settings, Chess Game
/// Killer, Live Activities).
@MainActor
final class DailyActivityKeeper {
    static let shared = DailyActivityKeeper()

    private var activity: Activity<DailyActivityAttributes>?

    /// Brings it up to date: call it whenever the daily habit changes and when the app opens.
    func follow(daily: DailyStore, now: Date = .now, calendar: Calendar = .current) {
        adoptLeftover()
        guard let plan = Self.plan(puzzle: daily.puzzle(on: now), done: daily.isDone(on: now),
                                   streak: daily.streakDays(on: now), gameShowing: LiveGameKeeper.shared.isShowing,
                                   now: now, calendar: calendar) else {
            end()
            return
        }
        if let activity, activity.attributes != plan.puzzle {
            // Yesterday's puzzle: a new one replaces it.
            end()
        }
        if let activity {
            guard activity.content.state != plan.state else { return }
            let content = ActivityContent(state: plan.state, staleDate: plan.puzzle.resets)
            Task { await activity.update(content) }
            return
        }
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }
        do {
            activity = try Activity.request(attributes: plan.puzzle,
                                            content: ActivityContent(state: plan.state, staleDate: plan.puzzle.resets),
                                            pushType: nil)
        } catch {
            NSLog("Today's Move Live Activity did not start: %@", error.localizedDescription)
        }
    }

    /// Takes it off the Lock Screen at once.
    func end() {
        adoptLeftover()
        for running in Activity<DailyActivityAttributes>.activities {
            Task { await running.end(nil, dismissalPolicy: .immediate) }
        }
        activity = nil
    }

    /// What should show: nothing once the move is done, while a game is on the Lock Screen, or
    /// with no puzzle; otherwise today's puzzle and the streak.
    static func plan(puzzle: DailyPuzzle?, done: Bool, streak: Int, gameShowing: Bool,
                     now: Date, calendar: Calendar) -> (puzzle: DailyActivityAttributes, state: DailyActivityAttributes.ContentState)? {
        guard let puzzle, !done, !gameShowing else { return nil }
        let midnight = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: now))
            ?? now.addingTimeInterval(24 * 60 * 60)
        return (DailyActivityAttributes(puzzle: puzzle, resets: midnight), .init(streak: streak))
    }

    /// One started by an earlier run of the app is still up: keep following it.
    private func adoptLeftover() {
        if activity == nil {
            activity = Activity<DailyActivityAttributes>.activities.first { $0.activityState == .active }
        }
    }
}
