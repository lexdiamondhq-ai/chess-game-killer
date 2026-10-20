import ChessKit
import Foundation

/// A moment in a game worth a word from the coach: a pattern the learner
/// found, missed or walked into.
struct CoachMoment: Identifiable, Equatable {
    enum Kind: String, CaseIterable {
        // Teaching moments, most urgent first.
        case missedMate
        case allowedMate
        case hungPiece
        case allowedFork
        case missedFreePiece
        case missedFork
        case missedPin
        case missedSkewer
        case earlyQueen
        // Praise.
        case foundMate
        case foundFork
        case foundFreePiece
        case castled
        case fixedIt

        var isPraise: Bool {
            switch self {
            case .foundMate, .foundFork, .foundFreePiece, .castled, .fixedIt: return true
            default: return false
            }
        }
    }

    let id: Int
    let kind: Kind
    let title: String
    let detail: String
    /// The skill this is about. Its lesson is the one to watch.
    let skill: String?
    /// The position before the learner's move.
    let fen: String
    /// The engine's move there, in engine notation.
    let best: String?
    let played: String

    var isPraise: Bool { kind.isPraise }
}

/// Names the pattern behind a move, from the coach's review of it.
/// Plain board geometry plus the engine's two opinions (its best move, and
/// the opponent's best reply): enough to say *why* in a sentence.
enum MomentFinder {
    struct Found: Equatable {
        let kind: CoachMoment.Kind
        let skill: String?
        /// Words for the text: played, best, reply, piece, square, targets, n.
        let values: [String: String]
    }

    static func find(in review: MoveReview) -> Found? {
        guard
            let fenBefore = review.fenBefore, let fenAfter = review.fenAfter,
            let playedUCI = review.playedUCI, let played = Notation.squares(of: playedUCI),
            let before = BoardGeometry(fen: fenBefore), let after = BoardGeometry(fen: fenAfter),
            let mover = before.piece(at: played.from)
        else { return nil }

        var values = ["played": review.played]
        if let best = review.best { values["best"] = best }
        if let reply = review.reply, let san = Notation.san(of: reply, fen: fenAfter) { values["reply"] = san }

        switch review.grade {
        case .checkmate:
            return Found(kind: .foundMate, skill: nil, values: values)
        case .best, .excellent:
            return praise(played: played, mover: mover, before: before, after: after, values: values)
        case .good:
            return nil
        case .inaccuracy, .mistake, .blunder:
            return lesson(review: review, played: played, mover: mover, before: before, after: after,
                          fenBefore: fenBefore, values: values)
        }
    }

    // MARK: Teaching moments

    private static func lesson(
        review: MoveReview,
        played: (from: Square, to: Square),
        mover: Piece,
        before: BoardGeometry,
        after: BoardGeometry,
        fenBefore: String,
        values: [String: String]
    ) -> Found? {
        let me = mover.color
        let serious = review.grade != .inaccuracy
        var values = values

        // A forced mate, missed.
        if case .mate(let n)? = review.before, n > 0, n <= 3, review.best != nil {
            if case .mate(let still)? = review.evaluation, still > 0 {
                // Still mating, just slower: not worth a lecture.
            } else {
                values["n"] = "\(n)"
                return Found(kind: .missedMate, skill: n == 1 ? "mate-in-1" : "mate-in-2", values: values)
            }
        }

        // Walked into a mate.
        if case .mate(let n)? = review.evaluation, n < 0, n >= -3, values["reply"] != nil {
            var alreadyLost = false
            if case .mate(let m)? = review.before, m <= 0 { alreadyLost = true }
            if !alreadyLost {
                values["n"] = "\(-n)"
                let skill = isBackRank(review.reply, on: after, defender: me) ? "back-rank" : "threats"
                return Found(kind: .allowedMate, skill: skill, values: values)
            }
        }

        // Left a piece where it can be taken.
        if serious, let reply = review.reply, values["reply"] != nil, let hit = Notation.squares(of: reply),
           let victim = after.piece(at: hit.to), victim.color == me, victim.kind != .king, after.isHanging(hit.to) {
            values["piece"] = BoardGeometry.name(victim.kind)
            values["square"] = hit.to.notation
            return Found(kind: .hungPiece, skill: "safety", values: values)
        }

        // Let them fork two pieces.
        if serious, let reply = review.reply, values["reply"] != nil, let hit = Notation.squares(of: reply) {
            let next = after.applying(uci: reply)
            if let forker = next.piece(at: hit.to), forker.color != me {
                let targets = sortedByValue(next.forkTargets(from: hit.to), on: next)
                if targets.count >= 2 {
                    values["piece"] = BoardGeometry.name(forker.kind)
                    values["square"] = hit.to.notation
                    values["targets"] = names(targets, on: next)
                    return Found(kind: .allowedFork, skill: "forks", values: values)
                }
            }
        }

        // Something better was there: a free piece, a fork, a pin or a skewer.
        // The words say "wasn't protected", so only a truly undefended piece counts.
        if let bestUCI = review.bestUCI, bestUCI != review.playedUCI, values["best"] != nil,
           let best = Notation.squares(of: bestUCI) {
            if let target = before.piece(at: best.to), target.color != me, !before.isDefended(best.to, by: target.color) {
                values["piece"] = BoardGeometry.name(target.kind)
                values["square"] = best.to.notation
                return Found(kind: .missedFreePiece, skill: "free-pieces", values: values)
            }

            let next = before.applying(uci: bestUCI)
            if let striker = next.piece(at: best.to) {
                let targets = sortedByValue(next.forkTargets(from: best.to), on: next)
                if targets.count >= 2 {
                    values["piece"] = BoardGeometry.name(striker.kind)
                    values["targets"] = names(targets, on: next)
                    return Found(kind: .missedFork, skill: "forks", values: values)
                }
                for line in next.lineups(from: best.to) {
                    guard let front = next.piece(at: line.front), let back = next.piece(at: line.back) else { continue }
                    let frontValue = BoardGeometry.exchangeValue(front.kind)
                    let backValue = BoardGeometry.exchangeValue(back.kind)
                    values["piece"] = BoardGeometry.name(front.kind)
                    values["targets"] = BoardGeometry.name(back.kind)
                    if backValue > frontValue {
                        return Found(kind: .missedPin, skill: "pins", values: values)
                    }
                    if frontValue > backValue {
                        return Found(kind: .missedSkewer, skill: "skewers", values: values)
                    }
                }
            }
        }

        // The queen out too early.
        if TrainingChess.moveNumber(fenBefore) <= 6, mover.kind == .queen, before.piece(at: played.to) == nil {
            return Found(kind: .earlyQueen, skill: "opening", values: values)
        }
        return nil
    }

    // MARK: Praise

    private static func praise(
        played: (from: Square, to: Square),
        mover: Piece,
        before: BoardGeometry,
        after: BoardGeometry,
        values: [String: String]
    ) -> Found? {
        var values = values
        let me = mover.color

        if let target = before.piece(at: played.to), target.color != me,
           BoardGeometry.value(target.kind) >= 3, !before.isDefended(played.to, by: target.color) {
            values["piece"] = BoardGeometry.name(target.kind)
            values["square"] = played.to.notation
            return Found(kind: .foundFreePiece, skill: "free-pieces", values: values)
        }

        let targets = sortedByValue(after.forkTargets(from: played.to), on: after).filter { square in
            guard let piece = after.piece(at: square) else { return false }
            return piece.kind == .king || BoardGeometry.value(piece.kind) >= 3
        }
        if targets.count >= 2, let striker = after.piece(at: played.to) {
            values["piece"] = BoardGeometry.name(striker.kind)
            values["targets"] = names(targets, on: after)
            return Found(kind: .foundFork, skill: "forks", values: values)
        }

        if mover.kind == .king, abs(played.from.fileIndex - played.to.fileIndex) == 2 {
            return Found(kind: .castled, skill: "opening", values: values)
        }
        return nil
    }

    // MARK: Helpers

    /// A rook or queen landing on the defender's back rank, with the king still there.
    private static func isBackRank(_ reply: String?, on board: BoardGeometry, defender: Piece.Color) -> Bool {
        guard
            let reply, let squares = Notation.squares(of: reply),
            let piece = board.piece(at: squares.from), piece.kind == .rook || piece.kind == .queen,
            let king = board.king(of: defender)
        else { return false }
        let backRank = defender == .white ? 0 : 7
        return squares.to.rankIndex == backRank && king.rankIndex == backRank
    }

    private static func sortedByValue(_ squares: [Square], on board: BoardGeometry) -> [Square] {
        squares.sorted {
            BoardGeometry.exchangeValue(board.piece(at: $0)?.kind ?? .pawn)
                > BoardGeometry.exchangeValue(board.piece(at: $1)?.kind ?? .pawn)
        }
    }

    private static func names(_ squares: [Square], on board: BoardGeometry) -> String {
        BoardGeometry.list(squares.compactMap { board.piece(at: $0).map { BoardGeometry.name($0.kind) } })
    }

    // MARK: Words

    /// Built-in wording, used when the course file has none for a kind.
    static func defaultText(for kind: CoachMoment.Kind) -> (title: String, detail: String) {
        switch kind {
        case .missedMate:
            return ("You had checkmate!", "There was mate in {n} here, starting with {best}. Look at every check first.")
        case .allowedMate:
            return ("Checkmate threat", "After {played}, {reply} starts a checkmate. Red light: what are their pieces aiming at?")
        case .hungPiece:
            return ("Your {piece} wasn't safe", "{reply} wins your {piece} on {square}. Green light: before you let go, can they take it?")
        case .allowedFork:
            return ("Watch out for forks", "{reply} lets their {piece} attack your {targets} at once.")
        case .missedFreePiece:
            return ("Free {piece}!", "Their {piece} on {square} wasn't protected. {best} wins it.")
        case .missedFork:
            return ("There was a fork", "{best} attacks their {targets} at the same time.")
        case .missedPin:
            return ("There was a pin", "{best} pins their {piece} to the {targets}.")
        case .missedSkewer:
            return ("There was a skewer", "{best} hits their {piece}, and the {targets} behind it falls.")
        case .earlyQueen:
            return ("Queen out early", "Out this soon, she gets chased around while their pieces develop. Knights and bishops first.")
        case .foundMate:
            return ("Checkmate!", "{played} ends it. The best feeling in chess.")
        case .foundFork:
            return ("Beautiful fork!", "{played} hits their {targets} at once.")
        case .foundFreePiece:
            return ("Free piece, taken", "You spotted the unprotected {piece}. That's the yellow light working.")
        case .castled:
            return ("King tucked away", "Castling hides your king and wakes up a rook. Great habit.")
        case .fixedIt:
            return ("That's it!", "{played} is the move. You found it.")
        }
    }

    /// Fills {played}, {best} and the rest into a line of text.
    static func fill(_ template: String, with values: [String: String]) -> String {
        var text = template
        for (key, value) in values {
            text = text.replacingOccurrences(of: "{\(key)}", with: value)
        }
        return text
    }
}
