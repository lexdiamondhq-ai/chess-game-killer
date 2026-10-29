import Foundation
import UserNotifications

// Reminders from your army: at most one a day, at the hour the player usually plays, only on a
// day not done yet, and written from their own pieces and rivals ("Ghost hasn't fought in 3 days").
// They are local notifications planned ahead for the next three days and planned again whenever
// the app is opened or the day changes. So once a player leaves three in a row unanswered,
// nothing more comes until they open the app again. Nothing goes through a server.

/// What the reminders can talk about, gathered from the army, the games and the streak.
struct ReminderFacts: Equatable {
    var streak = 0
    var doneToday = false
    /// The army's best piece, by name ("Seraphine") or title ("your queen"), and its kind ("queen").
    var hero: String?
    var heroKind: String?
    /// The best piece close to its next rank: experience to go and the rank's name.
    var nearRank: (name: String, xp: Int, rank: String)?
    /// A piece held prisoner since it was lost on the line, and the rival holding it.
    var captive: (name: String, rival: String)?
    /// Days since the last game, if there was one.
    var daysSinceGame: Int?
    /// Today's Move, as a chess column says it: "White to play and mate in two."
    var puzzleHeadline: String?

    static func == (a: ReminderFacts, b: ReminderFacts) -> Bool {
        a.streak == b.streak && a.doneToday == b.doneToday && a.hero == b.hero && a.heroKind == b.heroKind
            && a.nearRank?.name == b.nearRank?.name && a.nearRank?.xp == b.nearRank?.xp
            && a.captive?.name == b.captive?.name && a.captive?.rival == b.captive?.rival
            && a.daysSinceGame == b.daysSinceGame && a.puzzleHeadline == b.puzzleHeadline
    }
}

/// One reminder, as it will show.
struct PlannedReminder: Equatable {
    let date: Date
    let title: String
    let body: String
}

enum DailyReminders {
    /// Settings: reminders on or off. On by default; nothing shows until the player allows notifications.
    static let enabledKey = "dailyReminders"
    /// Days planned ahead. Three unanswered and they stop until the app is opened.
    static let daysAhead = 3
    /// Every reminder's id starts with this, so planning again replaces only ours.
    static let idPrefix = "daily-reminder-"

    static func isOn(_ defaults: UserDefaults = .standard) -> Bool {
        defaults.object(forKey: enabledKey) as? Bool ?? true
    }

    // MARK: Planning

    /// The reminders for the next days at `hour`: none today once the day is done (or the hour
    /// has passed), then one a day. Each day says something different.
    static func plan(now: Date, hour: Int, facts: ReminderFacts, calendar: Calendar = .current) -> [PlannedReminder] {
        var plans: [PlannedReminder] = []
        let today = calendar.startOfDay(for: now)
        for offset in 0...daysAhead {
            guard plans.count < daysAhead,
                  let day = calendar.date(byAdding: .day, value: offset, to: today),
                  let at = calendar.date(bySettingHour: hour, minute: 0, second: 0, of: day) else { continue }
            if offset == 0, facts.doneToday { continue }
            // Not in the next quarter of an hour: the player is here now.
            guard at > now.addingTimeInterval(15 * 60) else { continue }
            let message = message(daysAway: offset, facts: facts, index: plans.count)
            plans.append(PlannedReminder(date: at, title: message.title, body: message.body))
        }
        return plans
    }

    /// What one reminder says. `daysAway` is how far ahead it is from now; `index` picks among the
    /// things worth saying, so the days don't repeat each other.
    static func message(daysAway: Int, facts: ReminderFacts, index: Int) -> (title: String, body: String) {
        // The streak is only promised where it surely still stands: later today when today isn't
        // done yet, or tomorrow when it is.
        let standing = facts.doneToday ? daysAway == 1 : daysAway == 0
        let streakThen = standing ? facts.streak : 0
        var options: [(title: String, body: String)] = []
        if let captive = facts.captive {
            options.append(("\(captive.rival) still holds \(captive.name)",
                            "Win one game against \(captive.rival) to bring \(captive.name) home."))
        }
        if streakThen > 0 {
            options.append(("Day \(streakThen + 1) is one move away",
                            "Today's Move, one game or three puzzles keeps your \(streakThen)-day streak."))
        }
        if let near = facts.nearRank {
            options.append(("\(near.name) is \(near.xp) XP from \(near.rank)",
                            "One good game could do it."))
        }
        if let hero = facts.hero, let days = facts.daysSinceGame.map({ $0 + daysAway }), days >= 2 {
            options.append(("\(hero) hasn't fought in \(days) days",
                            "Your \(facts.heroKind ?? "army") is ready when you are."))
        }
        // Then the everyday ones, three of them, so the days never say the same thing twice.
        let puzzle = facts.puzzleHeadline.map { "Today's Move: \($0)" } ?? "A new puzzle is waiting."
        options.append(("Today's Move is ready", daysAway == 0 ? puzzle : "A new puzzle every day. It takes a minute."))
        options.append(("A minute for chess?", "Today's Move is the same for everyone. See how you do."))
        options.append(("Your rivals are warming up", "Spark, Drift and the rest are ready when you are."))
        return options[min(index, options.count - 1)]
    }

    // MARK: The system

    /// Asks once for permission to send reminders. True when allowed.
    static func requestPermission() async -> Bool {
        (try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge])) ?? false
    }

    static func isAuthorized() async -> Bool {
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        switch settings.authorizationStatus {
        case .authorized, .provisional, .ephemeral: return true
        default: return false
        }
    }

    /// Replaces our pending reminders with `plans`; with reminders off or not allowed, clears them.
    static func schedule(_ plans: [PlannedReminder], defaults: UserDefaults = .standard) async {
        let center = UNUserNotificationCenter.current()
        let pending = await center.pendingNotificationRequests()
        center.removePendingNotificationRequests(withIdentifiers: pending.map(\.identifier).filter { $0.hasPrefix(idPrefix) })
        guard isOn(defaults), await isAuthorized() else { return }
        let calendar = Calendar.current
        for plan in plans {
            let content = UNMutableNotificationContent()
            content.title = plan.title
            content.body = plan.body
            content.sound = .default
            content.userInfo = ["link": "chessgamekiller://daily"]
            let parts = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: plan.date)
            let trigger = UNCalendarNotificationTrigger(dateMatching: parts, repeats: false)
            let id = idPrefix + DailyMoves.dayKey(plan.date, calendar: calendar)
            try? await center.add(UNNotificationRequest(identifier: id, content: content, trigger: trigger))
        }
    }
}
