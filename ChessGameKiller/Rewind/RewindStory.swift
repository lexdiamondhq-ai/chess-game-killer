import Foundation

/// What Leo says at one stop of a rewound game. Every word comes from the engine's
/// verdict and the board itself (the pattern finder), never from guesswork.
struct RewindNote: Equatable {
    /// A short name for the moment, like "Missed fork".
    let tag: String
    let title: String
    let detail: String
    /// Whether this is a move to fix (or one to be proud of).
    let isLesson: Bool
    /// The training skill behind it, for "Practice this".
    let skill: String?

    static func make(for moment: SavedMoment, library: TrainingLibrary?) -> RewindNote {
        let grade = moment.moveGrade
        let isLesson = [.inaccuracy, .mistake, .blunder].contains(grade)
        if let found = MomentFinder.find(in: moment.review), found.kind.isPraise != isLesson {
            let words = GameCoach.words(for: found, library: library)
            return RewindNote(tag: tag(for: found.kind), title: words.title, detail: words.detail,
                              isLesson: isLesson, skill: found.skill)
        }
        let review = moment.review
        return RewindNote(tag: review.title, title: fallbackTitle(grade), detail: review.detail,
                          isLesson: isLesson, skill: nil)
    }

    static func tag(for kind: CoachMoment.Kind) -> String {
        switch kind {
        case .missedMate: return "Missed mate"
        case .allowedMate: return "Mate threat"
        case .hungPiece: return "Loose piece"
        case .allowedFork: return "Fork allowed"
        case .missedFreePiece: return "Free piece missed"
        case .missedFork: return "Missed fork"
        case .missedPin: return "Missed pin"
        case .missedSkewer: return "Missed skewer"
        case .earlyQueen: return "Early queen"
        case .foundMate: return "Checkmate"
        case .foundFork: return "Fork"
        case .foundFreePiece: return "Free piece"
        case .castled: return "Safe king"
        case .fixedIt: return "Rewritten"
        }
    }

    private static func fallbackTitle(_ grade: MoveReview.Grade) -> String {
        switch grade {
        case .checkmate: return "And that's mate."
        case .best: return "Exactly the engine's move."
        case .excellent: return "A strong move."
        case .good: return "A fine move."
        case .inaccuracy: return "A little advantage slipped here."
        case .mistake: return "This one cost you."
        case .blunder: return "This is where it got away."
        }
    }
}

/// How a ghost line ends, said in words rather than numbers.
enum GhostVerdict {
    /// The better line's result for the player, from the engine's score before the move,
    /// against what the move played actually led to.
    static func sentence(best: Double, played: Double) -> String {
        let gap = best - played
        let side: String
        switch best {
        case 0.6...: side = "you'd be winning"
        case 0.25..<0.6: side = "you'd be clearly better"
        case -0.15..<0.25: side = "the game would stay level"
        default: side = "you'd still be fighting"
        }
        if gap >= 0.3 { return "Instead, \(side). That's the game you could have had." }
        return "Instead, \(side). A smaller step, but a real one."
    }
}
