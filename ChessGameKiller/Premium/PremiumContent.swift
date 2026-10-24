import Foundation

extension TrainingLibrary {
    /// Free players watch the course's first five lessons; Premium opens the rest.
    static let freeLessonCount = 5

    /// The first lessons of the course, in the order the course teaches them.
    var freeLessonIDs: [String] {
        Array(course.units.flatMap(\.lessons).prefix(Self.freeLessonCount))
    }

    func isFreeLesson(_ id: String) -> Bool {
        freeLessonIDs.contains(id)
    }
}

extension BoardTheme {
    /// The looks every player has. Each rival's board opens once that rival is beaten.
    static let freeLooks: Set<BoardTheme.ID> = [.gilded, .noir, .midnight]
}

/// Which rivals' boards the player has earned by beating them, remembered on this device
/// (saved games are trimmed to the newest 150, a win stays earned).
enum RivalBoardsEarned {
    static let key = "premium.rivalBoardsEarned"

    static func names(_ defaults: UserDefaults = .standard) -> Set<String> {
        Set(defaults.stringArray(forKey: key) ?? [])
    }

    /// Adds every rival beaten in these games.
    static func note(_ games: [SavedGame], defaults: UserDefaults = .standard) {
        let beaten = Set(games.filter { $0.result == .win }.map { $0.opponent.lowercased() })
        let all = names(defaults).union(beaten)
        if all.count != names(defaults).count {
            defaults.set(all.sorted(), forKey: key)
        }
    }

    /// Whether a look is open for this player.
    @MainActor
    static func opens(_ look: BoardTheme, premium: Premium = .shared, defaults: UserDefaults = .standard) -> Bool {
        if premium.opens(.boardLooks) || BoardTheme.freeLooks.contains(look.id) { return true }
        guard BoardTheme.rivals.contains(where: { $0.id == look.id }) else { return false }
        return names(defaults).contains(look.name.lowercased())
    }
}
