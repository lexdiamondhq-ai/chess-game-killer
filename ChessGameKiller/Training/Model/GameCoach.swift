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

    /// Looks at the coach's latest review. Call whenever `match.review` changes.
    func observe(_ review: MoveReview?, in match: MatchController, store: TrainingStore) {
        guard match.setup.opponent == .computer else {
            moment = nil
            return
        }
        guard let review else {
            moment = nil
            return
        }
        guard review.id != lastReviewID else { return }
        lastReviewID = review.id
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

        let found = MomentFinder.find(in: review)
        if let found, found.kind.isPraise {
            let worthSaying = found.kind == .foundMate || movesSincePraise >= 4
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

        // Real mistakes go to practice, named after their pattern when there is one.
        if review.grade == .mistake || review.grade == .blunder,
           let fen = review.fenBefore, let best = review.bestUCI, let played = review.playedUCI {
            let teaching = found.flatMap { $0.kind.isPraise ? nil : $0 }
            let title = teaching == nil ? "Find the better move" : (moment?.title ?? "Find the better move")
            if store.addMistake(fen: fen, best: best, played: played, skill: teaching?.skill ?? "", title: title) {
                savedThisGame += 1
            }
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

    func practice(_ moment: CoachMoment, store: TrainingStore) {
        guard let skillID = moment.skill, let skill = store.library?.skill(skillID) else { return }
        presentedSession = store.practicePlan(for: skill)
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

    private func show(_ found: MomentFinder.Found, review: MoveReview, library: TrainingLibrary?) {
        let defaults = MomentFinder.defaultText(for: found.kind)
        let text = library?.moment(found.kind.rawValue)
        var title = MomentFinder.fill(text?.title ?? defaults.title, with: found.values)
        var detail = MomentFinder.fill(text?.detail ?? defaults.detail, with: found.values)
        // A placeholder left over means the course text asked for something this moment lacks.
        if title.contains("{") || detail.contains("{") {
            title = MomentFinder.fill(defaults.title, with: found.values)
            detail = MomentFinder.fill(defaults.detail, with: found.values)
        }
        moment = CoachMoment(
            id: nextID, kind: found.kind, title: title, detail: detail, skill: found.skill,
            fen: review.fenBefore ?? "", best: review.bestUCI, played: review.playedUCI ?? ""
        )
        nextID += 1
    }
}
