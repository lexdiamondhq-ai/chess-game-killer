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
    case rivalWins
    case playerWins
    case draw

    /// Moments that are always worth a line; the rest wait their turn.
    var isBig: Bool {
        switch self {
        case .greeting, .rivalResigns, .rivalWins, .playerWins, .draw: return true
        case .tookPiece(let kind), .lostPiece(let kind): return kind == .queen
        default: return false
        }
    }
}

/// One thing a rival says, shown in a bubble by its portrait for a few seconds.
struct RivalLine: Equatable, Identifiable {
    let id: Int
    let text: String
}

/// What each rival says, in its own voice: Spark is excitable, Drift laid back,
/// Pulse competitive, Vector cold and exact, Singularity barely human.
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
        case (.greeting, .beginner): return ["Hi! I'm still learning too. Be nice!", "Ooh, a new game! Let's go!"]
        case (.greeting, .casual): return ["Hey. No pressure, just vibes.", "Let's keep it chill. Mostly."]
        case (.greeting, .club): return ["Good luck. You'll need it.", "Loose pawns are mine. Fair warning."]
        case (.greeting, .expert): return ["Calculating. Begin when ready.", "Every slip is noted."]
        case (.greeting, .grandmaster): return ["I have seen this game end.", "Proceed."]

        // MARK: Taking a piece
        case (.tookPiece(let kind), .beginner): return ["Yay, I got your \(kind.word)!", "Wait, I can take that? Yes!"]
        case (.tookPiece(let kind), .casual): return ["Your \(kind.word)? Don't mind if I do.", "Free \(kind.word). Nice."]
        case (.tookPiece(let kind), .club): return ["Thanks for the \(kind.word).", "That \(kind.word) was loose."]
        case (.tookPiece(let kind), .expert): return ["\(kind.word.capitalized) removed.", "As calculated."]
        case (.tookPiece, .grandmaster): return ["Inevitable.", "Another one."]

        // MARK: Losing a piece
        case (.lostPiece(let kind), .beginner): return ["Noooo, my \(kind.word)!", "Hey! I liked that \(kind.word)!"]
        case (.lostPiece(let kind), .casual): return ["Oof. Bye, \(kind.word).", "Eh, I didn't need that \(kind.word)."]
        case (.lostPiece(let kind), .club): return ["Hm. My \(kind.word). Noted.", "Lucky. That \(kind.word) will be avenged."]
        case (.lostPiece, .expert): return ["An acceptable loss.", "Interesting. Recalculating."]
        case (.lostPiece, .grandmaster): return ["Irrelevant.", "A sacrifice you did not understand."]

        // MARK: Check
        case (.givesCheck, .beginner): return ["Check! Did I say it right?", "Check! Ha!"]
        case (.givesCheck, .casual): return ["Check. Just saying hi to your king.", "Check, buddy."]
        case (.givesCheck, .club): return ["Check. Your move.", "Check. Careful now."]
        case (.givesCheck, .expert): return ["Check.", "Check. Two moves from over."]
        case (.givesCheck, .grandmaster): return ["Check.", "Your king feels it."]
        case (.inCheck, .beginner): return ["Eek! My king!", "Run, king, run!"]
        case (.inCheck, .casual): return ["Whoa, easy.", "Okay, okay, I see you."]
        case (.inCheck, .club): return ["Annoying.", "That changes nothing."]
        case (.inCheck, .expert): return ["Expected.", "A check is not a plan."]
        case (.inCheck, .grandmaster): return []

        // MARK: The person's moves
        case (.playerBlunder, .beginner): return ["Ooh, was that on purpose?", "Even I saw that one!"]
        case (.playerBlunder, .casual): return ["Oops. That's a gift, right?", "Not your best, friend."]
        case (.playerBlunder, .club): return ["That's a mistake. I'll take it.", "You'll regret that."]
        case (.playerBlunder, .expert): return ["Error detected.", "That move loses. Precisely."]
        case (.playerBlunder, .grandmaster): return ["Thank you.", "And there it is."]
        case (.playerGreatMove, .beginner): return ["Wow, how did you see that?", "Teach me that one!"]
        case (.playerGreatMove, .casual): return ["Okay, that was slick.", "Nice one. Seriously."]
        case (.playerGreatMove, .club): return ["Good move. Annoyingly good.", "Strong. Hm."]
        case (.playerGreatMove, .expert): return ["Correct.", "The best move. Unexpected."]
        case (.playerGreatMove, .grandmaster): return ["Adequate."]

        // MARK: The end
        case (.rivalResigns, .beginner): return ["Okay, okay, you win! Again?"]
        case (.rivalResigns, .casual): return ["Yeah, I'm done. Well played."]
        case (.rivalResigns, .club): return ["I resign. Well played."]
        case (.rivalResigns, .expert): return ["No path remains. I resign."]
        case (.rivalResigns, .grandmaster): return ["...Impossible. I resign."]
        case (.rivalWins, .beginner): return ["I won? I WON! Rematch?"]
        case (.rivalWins, .casual): return ["GG. Run it back?"]
        case (.rivalWins, .club): return ["Good game. Come back stronger."]
        case (.rivalWins, .expert): return ["As calculated. Again?"]
        case (.rivalWins, .grandmaster): return ["As foreseen."]
        case (.playerWins, .beginner): return ["You got me! That was awesome!"]
        case (.playerWins, .casual): return ["Ha, you got me. Nice."]
        case (.playerWins, .club): return ["Well played. I want a rematch."]
        case (.playerWins, .expert): return ["Checkmate. I underestimated you."]
        case (.playerWins, .grandmaster): return ["This should not be possible."]
        case (.draw, _): return ["A draw. Fair enough."]
        }
    }
}
