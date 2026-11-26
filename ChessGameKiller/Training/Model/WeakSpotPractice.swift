import Foundation

/// Practice for one of the things to work on: the player's own positions of that kind
/// first, then more of the same kind.
extension SessionPlan {
    /// The most of the player's own positions in one practice.
    static let ownPositionLimit = 5
    /// How long a practice runs, their own positions and the rest together.
    static let weakSpotLength = 8

    /// The positions saved from the player's games that are this kind of mistake and still
    /// open, the ones due soonest first.
    static func ownPositions(for spot: CoachReport.Leak, in mistakes: [GameMistake]) -> [GameMistake] {
        mistakes
            .filter { !$0.fixed && spot.positions.holds($0) }
            .sorted { $0.due != $1.due ? $0.due < $1.due : $0.id < $1.id }
    }

    /// Their own positions first, then `more`: Leo's drills or real puzzles of the same kind.
    /// With none of their own it is `more` alone.
    static func practice(_ spot: CoachReport.Leak, mistakes: [GameMistake], more: SessionPlan?) -> SessionPlan? {
        let own = ownPositions(for: spot, in: mistakes).prefix(ownPositionLimit)
        guard !own.isEmpty else { return more }
        let first = own.map { SessionItem(content: .mistake($0), role: .review) }
        // What follows gives up its warm-up (their own positions were one) and keeps its easy finish.
        let rest = (more?.items ?? []).suffix(weakSpotLength - first.count)
        return SessionPlan(title: spot.headline, focus: more?.focus, lesson: more?.lesson, items: first + rest,
                           headline: spot.headline, symbol: spot.area.symbol,
                           reason: "Your own positions first, then puzzles of the same kind.")
    }
}
