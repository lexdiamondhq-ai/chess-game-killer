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
    /// The person offered a draw and the rival said no.
    case drawDeclined

    /// Moments that are always worth a line; the rest wait their turn.
    var isBig: Bool {
        switch self {
        case .greeting, .rivalResigns, .playerResigned, .rivalWins, .playerWins, .draw, .drawDeclined: return true
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

/// What each crowd says, as one voice for thousands of players: "we". The 1000s are cheerful
/// and surprised, the Masters barely speak. Dry, never chirpy, and short enough to fit the line
/// under its name (48 characters at most). The Grudge has its own voice: `GrudgeVoice`.
enum RivalVoice {
    /// A line for `moment`, or nil if this crowd keeps quiet. `pick` in 0..<1 chooses among them.
    static func line(for moment: RivalMoment, level: MatchController.Level, pick: Double) -> String? {
        choose(lines(for: moment, level: level), pick: pick)
    }

    static func choose(_ options: [String], pick: Double) -> String? {
        guard !options.isEmpty else { return nil }
        let index = max(0, min(options.count - 1, Int(pick * Double(options.count))))
        return options[index]
    }

    static func lines(for moment: RivalMoment, level: MatchController.Level) -> [String] {
        switch (moment, level) {
        // MARK: Hello
        case (.greeting, .beginner): return ["Hi! There are a lot of us. Go easy.", "We're still learning too."]
        case (.greeting, .casual): return ["Hello from all of us.", "We play this on weekends. Let's go."]
        case (.greeting, .club): return ["Good luck. We've seen this before.", "Thousands of us. One move at a time."]
        case (.greeting, .expert): return ["We know the openings. Do you?", "Begin when ready."]
        case (.greeting, .grandmaster): return ["The masters are seated.", "Proceed."]

        // MARK: Taking a piece
        case (.tookPiece(let kind), .beginner): return ["Oh! We took your \(kind.word).", "Most of us took that. Sorry!"]
        case (.tookPiece(let kind), .casual): return ["Your \(kind.word)? We'll take it.", "A free \(kind.word). Thanks."]
        case (.tookPiece(let kind), .club): return ["Thanks for the \(kind.word).", "That \(kind.word) was loose."]
        case (.tookPiece(let kind), .expert): return ["\(kind.word.capitalized) taken.", "Nearly all of us saw that."]
        case (.tookPiece, .grandmaster): return ["Taken.", "As the masters play it."]

        // MARK: Losing a piece
        case (.lostPiece(let kind), .beginner): return ["Oh no, our \(kind.word).", "Some of us saw that coming."]
        case (.lostPiece(let kind), .casual): return ["Ah. There goes our \(kind.word).", "We didn't need that \(kind.word)."]
        case (.lostPiece(let kind), .club): return ["Hm. Our \(kind.word). Noted.", "We'll want that \(kind.word) back."]
        case (.lostPiece, .expert): return ["Acceptable.", "Some of us would have seen it."]
        case (.lostPiece, .grandmaster): return ["Interesting.", "Hm."]

        // MARK: Check
        case (.givesCheck, .beginner): return ["Check! Did we say that right?", "Check!"]
        case (.givesCheck, .casual): return ["Check. Just saying hello.", "Check, friend."]
        case (.givesCheck, .club): return ["Check. Your move.", "Check. Careful now."]
        case (.givesCheck, .expert): return ["Check.", "Check. Your options narrow."]
        case (.givesCheck, .grandmaster): return ["Check."]
        case (.inCheck, .beginner): return ["Oh! Our king.", "Careful, king."]
        case (.inCheck, .casual): return ["Whoa, easy.", "Okay, okay, we see you."]
        case (.inCheck, .club): return ["Annoying.", "That changes nothing."]
        case (.inCheck, .expert): return ["Expected.", "A check is not a plan."]
        case (.inCheck, .grandmaster): return []

        // MARK: The person's moves
        case (.playerBlunder, .beginner): return ["Was that on purpose?", "Are you sure about that?"]
        case (.playerBlunder, .casual): return ["Oops. Is that a gift?", "Not your best."]
        case (.playerBlunder, .club): return ["Most of us wouldn't play that.", "That helps us."]
        case (.playerBlunder, .expert): return ["That's a mistake.", "Almost none of us play that."]
        case (.playerBlunder, .grandmaster): return ["Careful.", "And there it is."]
        case (.playerGreatMove, .beginner): return ["How did you see that?", "Teach us that one!"]
        case (.playerGreatMove, .casual): return ["Okay, that was slick.", "Nice one. Seriously."]
        case (.playerGreatMove, .club): return ["Good move. Annoyingly good.", "Few of us find that."]
        case (.playerGreatMove, .expert): return ["Correct.", "The best move. Noted."]
        case (.playerGreatMove, .grandmaster): return ["Adequate."]

        // MARK: The end
        case (.rivalResigns, .beginner): return ["Okay, you win! Again?"]
        case (.rivalResigns, .casual): return ["We're done. Well played."]
        case (.rivalResigns, .club): return ["We resign. Well played."]
        case (.rivalResigns, .expert): return ["No way back. We resign."]
        case (.rivalResigns, .grandmaster): return ["We resign. Well played."]
        case (.playerResigned, .beginner): return ["Oh! Next time, then."]
        case (.playerResigned, .casual): return ["Fair enough. Next time."]
        case (.playerResigned, .club): return ["A wise call."]
        case (.playerResigned, .expert), (.playerResigned, .grandmaster): return ["Accepted."]
        case (.rivalWins, .beginner): return ["We won? We won! Another?"]
        case (.rivalWins, .casual): return ["Good game. Another?"]
        case (.rivalWins, .club): return ["Good game. Come back stronger."]
        case (.rivalWins, .expert): return ["Most of us would win that. Again?"]
        case (.rivalWins, .grandmaster): return ["As played before."]
        case (.playerWins, .beginner): return ["You got us. Well played!"]
        case (.playerWins, .casual): return ["You got us. Nicely done."]
        case (.playerWins, .club): return ["Well played. You beat the 1600s."]
        case (.playerWins, .expert): return ["You beat the 2000s. Seriously."]
        case (.playerWins, .grandmaster): return ["Well played. You earned that."]
        case (.draw, _): return ["A draw. Fair enough."]
        case (.drawDeclined, .beginner): return ["A draw? No way, we're doing fine!"]
        case (.drawDeclined, .casual): return ["Nah, let's keep playing."]
        case (.drawDeclined, .club): return ["No thanks. We'll play on."]
        case (.drawDeclined, .expert): return ["Declined."]
        case (.drawDeclined, .grandmaster): return ["A draw? Never."]
        }
    }
}

/// What your Grudge says. It only ever states true things from your games against it: the
/// score, its streaks, the piece it took last time. Dry, short, never an insult, and short
/// enough for the line under its name (48 characters at most).
enum GrudgeVoice {
    static func line(for moment: RivalMoment, record: GrudgeRecord?, now: Date = .now, pick: Double) -> String? {
        RivalVoice.choose(lines(for: moment, record: record, now: now), pick: pick)
    }

    static func lines(for moment: RivalMoment, record: GrudgeRecord?, now: Date = .now) -> [String] {
        let mood = record?.mood ?? .even
        let its = record?.itsWins ?? 0
        let quiet = mood == .rattled
        switch moment {
        case .greeting:
            if let memory = record?.lastLoss, mood != .respect, let line = recall(memory, now: now) {
                return [line]
            }
            switch mood {
            case .smug: return ["You again. \(its) to me so far.", "Sit down. I remember you."]
            case .rattled: return ["Two in a row. Not three."]
            case .furious: return ["You ended my streak. Sit down."]
            case .respect: return ["Fine. Let's see if it holds."]
            case .even: return ["We're level. Not for long.", "I remember you."]
            }
        case .tookPiece(let kind):
            return quiet ? ["Mine."] : ["Your \(kind.word). Like last time.", "I'll remember that \(kind.word)."]
        case .lostPiece:
            return quiet ? ["…"] : ["Keep it. For now.", "That changes nothing."]
        case .givesCheck:
            return quiet ? ["Check."] : ["Check. Remember this?", "Check."]
        case .inCheck:
            return quiet ? [] : ["Hm.", "You've been practising."]
        case .playerBlunder:
            return ["There it is.", "Same as last time."]
        case .playerGreatMove:
            return quiet ? ["…"] : ["Lucky.", "Who taught you that?"]
        case .rivalResigns:
            return ["This one. Not the next."]
        case .playerResigned:
            return ["Wise. That's \(its + 1)."]
        case .rivalWins:
            return ["Again.", "That's \(its + 1)."]
        case .playerWins:
            return quiet ? ["…"] : ["Lucky.", "Enjoy it. It's going on the list."]
        case .draw:
            return ["A draw. We'll finish this."]
        case .drawDeclined:
            return quiet ? ["No."] : ["No. Play it out.", "A draw? Not with you."]
        }
    }

    /// "Tuesday. Move 12. Remember?", or for an older game "Your knight. Move 12. Remember?"
    static func recall(_ memory: GrudgeRecord.Moment, now: Date) -> String? {
        let days = Calendar.current.dateComponents([.day], from: memory.date, to: now).day ?? 99
        if days >= 1 && days < 7 {
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.dateFormat = "EEEE"
            return "\(formatter.string(from: memory.date)). Move \(memory.move). Remember?"
        }
        if days < 1 { return "Move \(memory.move). Your \(memory.piece). Remember?" }
        return "Your \(memory.piece) on \(memory.square). Remember?"
    }
}
