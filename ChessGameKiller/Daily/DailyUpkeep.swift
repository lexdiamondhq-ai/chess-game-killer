import Foundation
import UserNotifications
import WidgetKit

/// Keeps the widget and the reminders in step with the daily habit: after every change, when the
/// app opens and when it goes away. Reads the army and the games for what the reminders say.
@MainActor
enum DailyUpkeep {
    /// The widget's kind, as the extension names it (DailyMoveWidget.kind).
    static let widgetKind = "DailyMove"

    static func refresh(daily: DailyStore, army: ArmyStore, lastGame: Date?, now: Date = .now) {
        let hero = army.hero
        daily.snapshot(hero: hero?.name, heroRank: hero?.rank.title).write()
        WidgetCenter.shared.reloadTimelines(ofKind: widgetKind)
        let plans = DailyReminders.plan(now: now, hour: daily.usualHour,
                                        facts: facts(daily: daily, army: army, lastGame: lastGame, now: now))
        Task { await DailyReminders.schedule(plans) }
    }

    /// What the reminders can talk about, from the streak, the army and the last game.
    static func facts(daily: DailyStore, army: ArmyStore, lastGame: Date?, now: Date = .now,
                      calendar: Calendar = .current) -> ReminderFacts {
        var facts = ReminderFacts()
        facts.streak = daily.streakDays(on: now)
        facts.doneToday = daily.isDone(on: now)
        facts.puzzleHeadline = daily.puzzle(on: now)?.headline
        if let hero = army.hero {
            facts.hero = hero.name
            facts.heroKind = hero.slot.kind.word
            let record = army.record(for: hero.slot)
            // Close to the next rank: worth a nudge.
            if let next = hero.rank.next, next.threshold - record.xp <= 15 {
                facts.nearRank = (hero.name, next.threshold - record.xp, next.title)
            }
        }
        if let captive = army.army.captives.min(by: { $0.key.rawValue < $1.key.rawValue }),
           let rival = MatchController.Level(rawValue: captive.value)?.rival.name {
            facts.captive = (army.displayName(of: captive.key), rival)
        }
        if let lastGame {
            facts.daysSinceGame = calendar.dateComponents([.day], from: calendar.startOfDay(for: lastGame),
                                                          to: calendar.startOfDay(for: now)).day
        }
        return facts
    }
}

/// Opening Today's Move from outside the game screen: the widget (chessgamekiller://daily) and
/// a tapped reminder. The game screen listens and opens it.
@MainActor
enum DailyLink {
    static let url = URL(string: "chessgamekiller://daily")!
    static let notification = Notification.Name("ChessGameKiller.openDailyMove")
    /// Asked for before the game screen was there to hear it: it opens once it appears.
    static var pending = false

    nonisolated static func matches(_ url: URL) -> Bool {
        guard url.scheme?.lowercased() == "chessgamekiller" else { return false }
        if url.host?.lowercased() == "daily" { return true }
        return url.pathComponents.filter { $0 != "/" }.first?.lowercased() == "daily"
    }

    static func open() {
        pending = true
        NotificationCenter.default.post(name: notification, object: nil)
    }
}

/// Opens Today's Move when a reminder is tapped, and lets a reminder show while the app is open.
final class DailyNotificationDelegate: NSObject, UNUserNotificationCenterDelegate {
    static let shared = DailyNotificationDelegate()

    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse,
                                withCompletionHandler completionHandler: @escaping () -> Void) {
        if response.notification.request.identifier.hasPrefix(DailyReminders.idPrefix) {
            Task { @MainActor in DailyLink.open() }
        }
        completionHandler()
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification,
                                withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        // The player is in the app already: no banner over the game.
        completionHandler([])
    }
}
