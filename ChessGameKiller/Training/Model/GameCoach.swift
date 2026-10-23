import Foundation
import Observation

/// The coach during a game against the computer. When a move shows a
/// pattern (a fork missed, a piece left hanging, a mate found) it says so in
/// a sentence, offers the lesson that teaches it, and saves real mistakes to
/// practice later: "your mistakes become your puzzles".
@MainActor
@Observable
final class GameCoach {
    /// What the coach is saying about the last move, if anything.
    private(set) var moment: CoachMoment?
    /// Set after "Try again", until the learner moves.
    private(set) var retrying: CoachMoment?
    /// Positions saved from the game in progress.
    private(set) var savedThisGame = 0
    /// Shown over the game when the learner asks for them.
    var presentedLesson: Lesson?
    var presentedSession: SessionPlan?

    @ObservationIgnored private var nextID = 0
    @ObservationIgnored private var lastReviewID: Int?
    @ObservationIgnored private var movesSincePraise = 99
    @ObservationIgnored private var praisedCastling = false

    /// Looks at a grade of one of the person's moves (nil clears what the coach is saying).
    /// `quietly` is for a grade nothing should be said about, like an older move graded late or
    /// a game played with grades off: a real mistake is still saved to practice.
    func observe(_ review: MoveReview?, in match: MatchController, store: TrainingStore, quietly: Bool = false) {
        guard let review else {
            moment = nil
            return
        }
        guard review.id != lastReviewID else { return }
        lastReviewID = review.id
        let found = MomentFinder.find(in: review)
        if quietly {
            if let found, !found.kind.isPraise, let skill = found.skill {
                store.recordGamePattern(skill: skill, found: false)
            }
            saveMistake(review, found: found, store: store)
            return
        }
        movesSincePraise += 1

        // The second try after "Try again".
        if let retry = retrying, review.fenBefore == retry.fen {
            retrying = nil
            if review.playedUCI == retry.best || [.best, .excellent, .checkmate].contains(review.grade) {
                if let skill = retry.skill { store.recordGamePattern(skill: skill, found: true) }
                show(MomentFinder.Found(kind: .fixedIt, skill: retry.skill, values: ["played": review.played]),
                     review: review, library: store.library)
                return
            }
        }
        retrying = nil

        if let found, found.kind.isPraise {
            // Praise waits its turn, and the end of a game is told by the board, not by the coach.
            let worthSaying = !match.isOver && (found.kind == .foundMate || movesSincePraise >= 4)
            let repeatCastle = found.kind == .castled && praisedCastling
            if worthSaying, !repeatCastle {
                movesSincePraise = 0
                if found.kind == .castled { praisedCastling = true }
                if let skill = found.skill { store.recordGamePattern(skill: skill, found: true) }
                show(found, review: review, library: store.library)
            } else {
                moment = nil
            }
        } else if let found {
            if let skill = found.skill { store.recordGamePattern(skill: skill, found: false) }
            show(found, review: review, library: store.library)
        } else {
            moment = nil
        }
        saveMistake(review, found: found, store: store)
    }

    /// Real mistakes go to practice, named after their pattern when there is one.
    private func saveMistake(_ review: MoveReview, found: MomentFinder.Found?, store: TrainingStore) {
        guard review.grade == .mistake || review.grade == .blunder,
              let fen = review.fenBefore, let best = review.bestUCI, let played = review.playedUCI else { return }
        let teaching = found.flatMap { $0.kind.isPraise ? nil : $0 }
        let title = teaching.map { Self.words(for: $0, library: store.library).title } ?? "Find the better move"
        if store.addMistake(fen: fen, best: best, played: played, skill: teaching?.skill ?? "", title: title) {
            savedThisGame += 1
        }
    }

    /// Takes the move back so the learner can look again.
    func tryAgain(in match: MatchController) {
        guard let moment, !moment.isPraise, match.canUndo else { return }
        retrying = moment
        self.moment = nil
        match.undo()
        // The tip was about an earlier move if the board isn't back where that move was played.
        if match.game.fen != moment.fen {
            retrying = nil
        }
    }

    func dismiss() {
        moment = nil
    }

    /// The lesson behind the current moment.
    func lesson(for moment: CoachMoment, in library: TrainingLibrary?) -> Lesson? {
        guard let library, let skillID = moment.skill, let skill = library.skill(skillID) else { return nil }
        return library.lesson(skill.lesson)
    }

    func watchLesson(for moment: CoachMoment, store: TrainingStore) {
        presentedLesson = lesson(for: moment, in: store.library)
    }

    func practiceMistakes(store: TrainingStore) {
        presentedSession = store.mistakesPlan()
    }

    /// A new game began: nothing said about the last one carries over.
    /// Call whenever `match.gameNumber` changes.
    func gameStarted() {
        moment = nil
        retrying = nil
        savedThisGame = 0
        movesSincePraise = 99
        praisedCastling = false
        lastReviewID = nil
    }

    // MARK: Private

    /// What the coach says about a moment: the course's words when it has them, the built-in ones otherwise.
    nonisolated static func words(for found: MomentFinder.Found, library: TrainingLibrary?) -> (title: String, detail: String) {
        let defaults = MomentFinder.defaultText(for: found.kind)
        let text = library?.moment(found.kind.rawValue)
        let title = MomentFinder.fill(text?.title ?? defaults.title, with: found.values)
        let detail = MomentFinder.fill(text?.detail ?? defaults.detail, with: found.values)
        // A placeholder left over means the course text asked for something this moment lacks.
        if title.contains("{") || detail.contains("{") {
            return (MomentFinder.fill(defaults.title, with: found.values), MomentFinder.fill(defaults.detail, with: found.values))
        }
        return (title, detail)
    }

    private func show(_ found: MomentFinder.Found, review: MoveReview, library: TrainingLibrary?) {
        let (title, detail) = Self.words(for: found, library: library)
        moment = CoachMoment(
            id: nextID, kind: found.kind, title: title, detail: detail, skill: found.skill,
            fen: review.fenBefore ?? "", best: review.bestUCI, played: review.playedUCI ?? ""
        )
        nextID += 1
    }
}
