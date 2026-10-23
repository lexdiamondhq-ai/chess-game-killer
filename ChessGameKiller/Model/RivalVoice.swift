import ChessKit
import Foundation

/// Something in the game a rival has an opinion about.
enum RivalMoment: Equatable {
    case greeting
    /// The rival took one of the person's pieces.
    case tookPiece(Piece.Kind)
    /// The person took one of the rival's pieces.
    case lostPiece(Piece.Kind)
    /// The rival gave check.
    case givesCheck
    /// The person gave check.
    case inCheck
    case playerBlunder
    case playerGreatMove
    case rivalResigns
    /// The person resigned.
    case playerResigned
    case rivalWins
    case playerWins
    case draw
    /// The rival has steered the player back to a position they got wrong before, `when`.
    case trapSet(when: String)
    /// The player made the same mistake again.
    case trapFell
    /// The player found something better this time.
    case trapDodged

    /// Moments that are always worth a line; the rest wait their turn.
    var isBig: Bool {
        switch self {
        case .greeting, .rivalResigns, .playerResigned, .rivalWins, .playerWins, .draw,
             .trapSet, .trapFell, .trapDodged: return true
        case .tookPiece(let kind), .lostPiece(let kind): return kind == .queen
        default: return false
        }
    }
}

/// One thing a rival says, written into its line by the board for a few seconds.
struct RivalLine: Equatable, Identifiable {
    let id: Int
    let text: String
}

/// What each rival says, in its own voice: Spark is eager, Drift laid back,
/// Pulse competitive, Vector cold and exact, Singularity barely human. Dry, never
/// chirpy, and short enough to fit the line under its name (48 characters at most).
enum RivalVoice {
    /// A line for `moment`, or nil if this rival keeps quiet. `pick` in 0..<1 chooses among them.
    static func line(for moment: RivalMoment, level: MatchController.Level, pick: Double) -> String? {
        let options = lines(for: moment, level: level)
        guard !options.isEmpty else { return nil }
        let index = max(0, min(options.count - 1, Int(pick * Double(options.count))))
        return options[index]
    }

    static func lines(for moment: RivalMoment, level: MatchController.Level) -> [String] {
        switch (moment, level) {
        // MARK: Hello
        case (.greeting, .beginner): return ["Hello! I'm still learning. Go easy on me.", "A new game! Let's play."]
        case (.greeting, .casual): return ["Hello. No pressure.", "Let's keep it friendly. Mostly."]
        case (.greeting, .club): return ["Good luck.", "Loose pawns are mine. Fair warning."]
        case (.greeting, .expert): return ["Calculating. Begin when ready.", "Every slip is noted."]
        case (.greeting, .grandmaster): return ["I have seen this game end.", "Proceed."]

        // MARK: Taking a piece
        case (.tookPiece(let kind), .beginner): return ["Oh! I took your \(kind.word).", "I can take that? Then I will."]
        case (.tookPiece(let kind), .casual): return ["Your \(kind.word)? Don't mind if I do.", "A free \(kind.word). Thanks."]
        case (.tookPiece(let kind), .club): return ["Thanks for the \(kind.word).", "That \(kind.word) was loose."]
        case (.tookPiece(let kind), .expert): return ["\(kind.word.capitalized) removed.", "As calculated."]
        case (.tookPiece, .grandmaster): return ["Inevitable.", "Another one."]

        // MARK: Losing a piece
        case (.lostPiece(let kind), .beginner): return ["Oh no, my \(kind.word).", "I was fond of that \(kind.word)."]
        case (.lostPiece(let kind), .casual): return ["Ah. Goodbye, \(kind.word).", "I didn't need that \(kind.word) anyway."]
        case (.lostPiece(let kind), .club): return ["Hm. My \(kind.word). Noted.", "Lucky. I'll want that \(kind.word) back."]
        case (.lostPiece, .expert): return ["An acceptable loss.", "Interesting. Recalculating."]
        case (.lostPiece, .grandmaster): return ["Irrelevant.", "Interesting."]

        // MARK: Check
        case (.givesCheck, .beginner): return ["Check. Did I say that right?", "Check!"]
        case (.givesCheck, .casual): return ["Check. Just saying hello to your king.", "Check, my friend."]
        case (.givesCheck, .club): return ["Check. Your move.", "Check. Careful now."]
        case (.givesCheck, .expert): return ["Check.", "Check. Your options narrow."]
        case (.givesCheck, .grandmaster): return ["Check.", "Your king feels it."]
        case (.inCheck, .beginner): return ["Oh! My king.", "Careful, king."]
        case (.inCheck, .casual): return ["Whoa, easy.", "Okay, okay, I see you."]
        case (.inCheck, .club): return ["Annoying.", "That changes nothing."]
        case (.inCheck, .expert): return ["Expected.", "A check is not a plan."]
        case (.inCheck, .grandmaster): return []

        // MARK: The person's moves
        case (.playerBlunder, .beginner): return ["Was that on purpose?", "Are you sure about that?"]
        case (.playerBlunder, .casual): return ["Oops. Is that a gift?", "Not your best, friend."]
        case (.playerBlunder, .club): return ["That's a mistake. I'll take it.", "That helps me."]
        case (.playerBlunder, .expert): return ["That's a mistake.", "That move loses. Precisely."]
        case (.playerBlunder, .grandmaster): return ["Careful.", "And there it is."]
        case (.playerGreatMove, .beginner): return ["How did you see that?", "Teach me that one!"]
        case (.playerGreatMove, .casual): return ["Okay, that was slick.", "Nice one. Seriously."]
        case (.playerGreatMove, .club): return ["Good move. Annoyingly good.", "Strong. Hm."]
        case (.playerGreatMove, .expert): return ["Correct.", "The best move. Unexpected."]
        case (.playerGreatMove, .grandmaster): return ["Adequate."]

        // MARK: The end
        case (.rivalResigns, .beginner): return ["Okay, you win! Again?"]
        case (.rivalResigns, .casual): return ["I'm done. Well played."]
        case (.rivalResigns, .club): return ["I resign. Well played."]
        case (.rivalResigns, .expert): return ["No path remains. I resign."]
        case (.rivalResigns, .grandmaster): return ["Impossible. I resign."]
        case (.playerResigned, .beginner): return ["Oh! Next time, then."]
        case (.playerResigned, .casual): return ["Fair enough. Next time."]
        case (.playerResigned, .club): return ["A wise call."]
        case (.playerResigned, .expert), (.playerResigned, .grandmaster): return ["Accepted."]
        case (.rivalWins, .beginner): return ["I won? I won! Another?"]
        case (.rivalWins, .casual): return ["Good game. Another?"]
        case (.rivalWins, .club): return ["Good game. Come back stronger."]
        case (.rivalWins, .expert): return ["As calculated. Again?"]
        case (.rivalWins, .grandmaster): return ["As foreseen."]
        case (.playerWins, .beginner): return ["You got me. Well played!"]
        case (.playerWins, .casual): return ["You got me. Nicely done."]
        case (.playerWins, .club): return ["Well played. I want a rematch."]
        case (.playerWins, .expert): return ["I underestimated you."]
        case (.playerWins, .grandmaster): return ["Well played. You earned that."]
        case (.draw, _): return ["A draw. Fair enough."]

        // MARK: The Scouting Report
        case (.trapSet(let when), .beginner): return ["Wait, we were here \(when)!", "Ooh, I remember this spot."]
        case (.trapSet(let when), .casual): return ["Familiar? We were here \(when).", "Same spot as \(when). Funny."]
        case (.trapSet(let when), .club): return ["There it is. Just like \(when).", "You've been here \(when). I studied it."]
        case (.trapSet(let when), .expert): return ["This position. \(when.capitalized). Again?", "As prepared. You were here \(when)."]
        case (.trapSet, .grandmaster): return ["You have stood here before.", "I have seen you here."]
        case (.trapFell, .beginner): return ["Same move again! Oh!", "Ha, just like last time!"]
        case (.trapFell, .casual): return ["Same move as last time. Thanks.", "Some habits stick, huh?"]
        case (.trapFell, .club): return ["Same move. My notes were right.", "Again? I knew it."]
        case (.trapFell, .expert): return ["Predicted.", "The same error. Noted twice."]
        case (.trapFell, .grandmaster): return ["As expected."]
        case (.trapDodged, .beginner): return ["Oh, you learned that one!", "Hey, different move!"]
        case (.trapDodged, .casual): return ["You remembered. Nice.", "Okay, you did your homework."]
        case (.trapDodged, .club): return ["Hm. You learned. New notes, then.", "Not this time. Well seen."]
        case (.trapDodged, .expert): return ["Corrected. Impressive.", "You studied too."]
        case (.trapDodged, .grandmaster): return ["You learned."]
        }
    }
}
