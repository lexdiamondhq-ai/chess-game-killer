import ChessKit
import Foundation

// Talk It Through: the player tells Leo their plan, Leo checks each claim with the rules and
// Stockfish, and answers. These are the messages between the app and Leo's server; the
// contract is coach/PROTOCOL.md. Decoding is forgiving: a field the app doesn't know, or one
// that is missing, never sinks the whole answer.

// MARK: What the app sends

/// The position, what the player said, and Stockfish's numbers, in one request.
struct TalkRequest: Encodable, Equatable, Sendable {
    var v = 1
    var fen: String
    var said: String
    /// Typed rather than spoken, so Leo needn't allow for misheard words.
    var typed: Bool
    /// Leo may name the best move. False in training, where he nudges instead.
    var reveal: Bool
    var context: TalkContext
    /// The opponent's last move in engine notation, like "f8c5".
    var lastMove: String?
    /// Whether to send Leo's voice.
    var voice: Bool
    var facts: TalkFacts?
    /// Who answers: left out for Leo, "vera" for Vera (her persona and her voice).
    var coach: String?
}

/// Where the player asked.
enum TalkContext: String, Codable, Sendable {
    case game, session, analysis
}

/// Stockfish's numbers for the position, worked out while the player talks.
struct TalkFacts: Codable, Equatable, Sendable {
    var depth: Int
    /// The player's legal moves, scored in the position from the player's view, best first.
    var moves: [TalkFactLine]
    /// The opponent's best moves if it were their turn, from the opponent's view, best first.
    /// Empty when the player is in check.
    var threats: [TalkFactLine]
}

/// One move and the line the engine expects after it.
struct TalkFactLine: Codable, Equatable, Sendable {
    var uci: String
    var eval: TalkEval
    var pv: [String]

    init(uci: String, eval: TalkEval, pv: [String]) {
        self.uci = uci
        self.eval = eval
        self.pv = pv
    }

    /// An engine line as the facts carry it: its first move, its score, at most 10 moves of line.
    init?(_ line: EngineLine) {
        guard let first = line.moves.first else { return nil }
        self.init(uci: first, eval: TalkEval(line.evaluation), pv: Array(line.moves.prefix(10)))
    }
}

/// An engine score as the server writes it: `{"cp": 35}` or `{"mate": 3}`.
struct TalkEval: Codable, Equatable, Sendable {
    var cp: Int?
    var mate: Int?

    init(cp: Int? = nil, mate: Int? = nil) {
        self.cp = cp
        self.mate = mate
    }

    init(_ evaluation: Evaluation) {
        switch evaluation {
        case .centipawns(let value): self.init(cp: value)
        case .mate(let moves): self.init(mate: moves)
        }
    }

    var evaluation: Evaluation? {
        if let mate { return .mate(mate) }
        if let cp { return .centipawns(cp) }
        return nil
    }
}

// MARK: What Leo's server sends back

/// One line of the server's answer stream, in order: checked, answer, voice, done.
enum TalkEvent: Equatable, Sendable {
    /// Leo's verdicts on the move and each claim.
    case checked(TalkCheck)
    /// What Leo says.
    case answer(TalkAnswer)
    /// Leo's voice, or why there is none.
    case voice(TalkVoice)
    case done
    /// The server's error code, like "upstream". The stream ends with it.
    case failed(String)

    /// Reads one line of the stream. Nil for a blank line or a kind of line this app doesn't know.
    static func decode(line: some StringProtocol) throws -> TalkEvent? {
        let text = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return nil }
        let data = Data(text.utf8)
        let decoder = JSONDecoder()
        let head = try decoder.decode(Head.self, from: data)
        switch head.type {
        case "checked":
            return .checked(try decoder.decode(TalkCheck.self, from: data))
        case "answer":
            return .answer(try decoder.decode(TalkAnswer.self, from: data))
        case "voice":
            return .voice(try decoder.decode(TalkVoice.self, from: data))
        case "done":
            return .done
        case "error":
            return .failed(head.error ?? "internal")
        default:
            return nil
        }
    }

    private struct Head: Decodable {
        var type: String
        var error: String?
    }
}

/// A move in both notations.
struct TalkMove: Codable, Equatable, Sendable {
    var san: String
    var uci: String
}

/// An arrow to draw on the board for a verdict.
struct TalkArrow: Codable, Equatable, Hashable, Sendable {
    enum Tone: String, Codable, Sendable {
        /// Green: the good move, a right idea.
        case good
        /// Red: the danger, a wrong idea.
        case bad
        /// The coach's accent: a fact, like a pin.
        case info
    }

    var from: String
    var to: String
    var tone: Tone

    init(from: String, to: String, tone: Tone = .info) {
        self.from = from
        self.to = to
        self.tone = tone
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        from = try c.decode(String.self, forKey: .from)
        to = try c.decode(String.self, forKey: .to)
        tone = (try? c.decodeIfPresent(Tone.self, forKey: .tone)) ?? .info
    }

    private enum CodingKeys: String, CodingKey { case from, to, tone }
}

/// Leo's verdict on the move the player said they would play.
struct TalkMoveCheck: Codable, Equatable, Sendable {
    enum Grade: String, Codable, Sendable {
        case checkmate, best, excellent, good, inaccuracy, mistake, blunder
        /// Not a legal move here.
        case illegal
        /// Legal, but Stockfish's numbers don't cover it.
        case unknown
    }

    /// Their words for the move.
    var said: String
    /// The legal move it was read as; nil when it isn't legal.
    var san: String?
    var uci: String?
    var grade: Grade
    /// One line for the screen, like "After h6, Bxh6 wins a pawn."
    var note: String
    /// The opponent's best answer.
    var reply: TalkMove?
    var squares: [String]
    var arrows: [TalkArrow]

    init(said: String, san: String?, uci: String?, grade: Grade, note: String, reply: TalkMove? = nil,
         squares: [String] = [], arrows: [TalkArrow] = []) {
        self.said = said
        self.san = san
        self.uci = uci
        self.grade = grade
        self.note = note
        self.reply = reply
        self.squares = squares
        self.arrows = arrows
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        said = (try? c.decodeIfPresent(String.self, forKey: .said)) ?? ""
        san = try? c.decodeIfPresent(String.self, forKey: .san)
        uci = try? c.decodeIfPresent(String.self, forKey: .uci)
        grade = (try? c.decodeIfPresent(Grade.self, forKey: .grade)) ?? .unknown
        note = (try? c.decodeIfPresent(String.self, forKey: .note)) ?? ""
        reply = try? c.decodeIfPresent(TalkMove.self, forKey: .reply)
        squares = (try? c.decodeIfPresent(LenientList<String>.self, forKey: .squares))?.elements ?? []
        arrows = (try? c.decodeIfPresent(LenientList<TalkArrow>.self, forKey: .arrows))?.elements ?? []
    }

    private enum CodingKeys: String, CodingKey { case said, san, uci, grade, note, reply, squares, arrows }
}

/// One thing the player claimed, and whether it holds.
struct TalkClaim: Codable, Equatable, Identifiable, Sendable {
    enum Kind: String, Codable, Sendable {
        case threat, attacks, defends, safe, hanging, pinned, check, mate, wins, line, eval, material, plan
        /// A kind this version of the app doesn't know.
        case other
    }

    enum Verdict: String, Codable, Sendable {
        case right, wrong, partly, unclear
    }

    var id: String
    /// The player's words for the claim, like "his bishop eyes h7".
    var said: String
    var kind: Kind
    var verdict: Verdict
    /// One line for the screen, like "The d4 pawn is pinned, so it can't take back."
    var note: String
    var squares: [String]
    var arrows: [TalkArrow]

    init(id: String, said: String, kind: Kind, verdict: Verdict, note: String,
         squares: [String] = [], arrows: [TalkArrow] = []) {
        self.id = id
        self.said = said
        self.kind = kind
        self.verdict = verdict
        self.note = note
        self.squares = squares
        self.arrows = arrows
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        said = (try? c.decodeIfPresent(String.self, forKey: .said)) ?? ""
        kind = (try? c.decodeIfPresent(Kind.self, forKey: .kind)) ?? .other
        verdict = (try? c.decodeIfPresent(Verdict.self, forKey: .verdict)) ?? .unclear
        note = (try? c.decodeIfPresent(String.self, forKey: .note)) ?? ""
        squares = (try? c.decodeIfPresent(LenientList<String>.self, forKey: .squares))?.elements ?? []
        arrows = (try? c.decodeIfPresent(LenientList<TalkArrow>.self, forKey: .arrows))?.elements ?? []
    }

    private enum CodingKeys: String, CodingKey { case id, said, kind, verdict, note, squares, arrows }
}

/// Something that mattered and wasn't said, like the opponent's threat.
struct TalkMissed: Codable, Equatable, Sendable {
    /// "threat", "hanging", "mate" or "free".
    var kind: String
    var note: String
    var squares: [String]
    var arrows: [TalkArrow]

    init(kind: String, note: String, squares: [String] = [], arrows: [TalkArrow] = []) {
        self.kind = kind
        self.note = note
        self.squares = squares
        self.arrows = arrows
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        kind = (try? c.decodeIfPresent(String.self, forKey: .kind)) ?? "threat"
        note = (try? c.decodeIfPresent(String.self, forKey: .note)) ?? ""
        squares = (try? c.decodeIfPresent(LenientList<String>.self, forKey: .squares))?.elements ?? []
        arrows = (try? c.decodeIfPresent(LenientList<TalkArrow>.self, forKey: .arrows))?.elements ?? []
    }

    private enum CodingKeys: String, CodingKey { case kind, note, squares, arrows }
}

/// Leo's Traffic Light: their threats (red), my checks, captures and attacks (yellow), and
/// whether my move is safe (green).
struct TalkHabits: Codable, Equatable, Sendable {
    enum Mark: String, Codable, Sendable {
        /// They covered it.
        case good
        /// It mattered and they didn't.
        case missed
        /// Nothing to judge this time.
        case none
    }

    var threats: Mark
    var forcing: Mark
    var safety: Mark

    init(threats: Mark = .none, forcing: Mark = .none, safety: Mark = .none) {
        self.threats = threats
        self.forcing = forcing
        self.safety = safety
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        threats = (try? c.decodeIfPresent(Mark.self, forKey: .threats)) ?? .none
        forcing = (try? c.decodeIfPresent(Mark.self, forKey: .forcing)) ?? .none
        safety = (try? c.decodeIfPresent(Mark.self, forKey: .safety)) ?? .none
    }

    private enum CodingKeys: String, CodingKey { case threats, forcing, safety }
}

/// Everything Leo checked, before he says a word.
struct TalkCheck: Codable, Equatable, Sendable {
    /// False when nothing they said was about the position.
    var understood: Bool
    /// "white" or "black".
    var player: String
    var move: TalkMoveCheck?
    var claims: [TalkClaim]
    var missed: [TalkMissed]
    var habits: TalkHabits
    /// The position with best play, from the player's view.
    var eval: TalkEval?
    /// The engine's move, only when Leo may reveal it.
    var best: TalkMove?
    /// A hint naming the piece, not the square, when Leo may not reveal the move.
    var nudge: String?

    init(understood: Bool = true, player: String = "white", move: TalkMoveCheck? = nil, claims: [TalkClaim] = [],
         missed: [TalkMissed] = [], habits: TalkHabits = TalkHabits(), eval: TalkEval? = nil,
         best: TalkMove? = nil, nudge: String? = nil) {
        self.understood = understood
        self.player = player
        self.move = move
        self.claims = claims
        self.missed = missed
        self.habits = habits
        self.eval = eval
        self.best = best
        self.nudge = nudge
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        understood = (try? c.decodeIfPresent(Bool.self, forKey: .understood)) ?? true
        player = (try? c.decodeIfPresent(String.self, forKey: .player)) ?? "white"
        move = try? c.decodeIfPresent(TalkMoveCheck.self, forKey: .move)
        claims = (try? c.decodeIfPresent(LenientList<TalkClaim>.self, forKey: .claims))?.elements ?? []
        missed = (try? c.decodeIfPresent(LenientList<TalkMissed>.self, forKey: .missed))?.elements ?? []
        habits = (try? c.decodeIfPresent(TalkHabits.self, forKey: .habits)) ?? TalkHabits()
        eval = try? c.decodeIfPresent(TalkEval.self, forKey: .eval)
        best = try? c.decodeIfPresent(TalkMove.self, forKey: .best)
        nudge = try? c.decodeIfPresent(String.self, forKey: .nudge)
    }

    private enum CodingKeys: String, CodingKey {
        case understood, player, move, claims, missed, habits, eval, best, nudge
    }

    /// How many claims held up, for "3 of 4 right". Unclear claims don't count either way.
    var rightCount: Int { claims.filter { $0.verdict == .right }.count }
    var judgedCount: Int { claims.filter { $0.verdict != .unclear }.count }
}

/// What Leo says, in plain spoken words.
struct TalkAnswer: Codable, Equatable, Sendable {
    var text: String
    /// "leo" when Claude worded it, "template" for the server's own wording.
    var source: String

    init(text: String, source: String = "leo") {
        self.text = text
        self.source = source
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        text = (try? c.decodeIfPresent(String.self, forKey: .text)) ?? ""
        source = (try? c.decodeIfPresent(String.self, forKey: .source)) ?? "leo"
    }

    private enum CodingKeys: String, CodingKey { case text, source }
}

/// Leo's voice as an MP3, or why the device's own voice should speak instead.
struct TalkVoice: Decodable, Equatable, Sendable {
    var audio: Data?
    /// "budget", "upstream" or "not_configured" when there's no audio.
    var unavailable: String?

    init(audio: Data?, unavailable: String? = nil) {
        self.audio = audio
        self.unavailable = unavailable
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let base64 = try? c.decodeIfPresent(String.self, forKey: .audio)
        audio = base64.flatMap { Data(base64Encoded: $0) }
        unavailable = try? c.decodeIfPresent(String.self, forKey: .unavailable)
        if audio == nil, unavailable == nil { unavailable = "upstream" }
    }

    private enum CodingKeys: String, CodingKey { case audio, unavailable }
}

// MARK: What the board lights up

/// Which verdict's squares the board shows.
enum TalkFocus: Hashable, Sendable {
    /// The move the player chose (the default).
    case move
    case claim(String)
    case missed(Int)
}

extension TalkCheck {
    /// The squares and arrows to light for a verdict. Nil focus lights the move, or the first claim
    /// when no move was named.
    func highlights(for focus: TalkFocus?) -> (squares: [String], arrows: [TalkArrow]) {
        switch focus ?? .move {
        case .move:
            if let move { return (move.squares, move.arrows) }
            if let first = claims.first { return (first.squares, first.arrows) }
            return ([], [])
        case .claim(let id):
            guard let claim = claims.first(where: { $0.id == id }) else { return ([], []) }
            return (claim.squares, claim.arrows)
        case .missed(let index):
            guard missed.indices.contains(index) else { return ([], []) }
            return (missed[index].squares, missed[index].arrows)
        }
    }
}

/// A list decoded one element at a time, so an element the app can't read is dropped instead of
/// emptying the whole list (a plain array fails as a whole).
private struct LenientList<Element: Decodable>: Decodable {
    var elements: [Element]

    init(from decoder: Decoder) throws {
        var container = try decoder.unkeyedContainer()
        var elements: [Element] = []
        while !container.isAtEnd {
            if let element = try? container.decode(Element.self) {
                elements.append(element)
            } else if (try? container.decode(Skipped.self)) == nil {
                // A failed decode doesn't move past the element; this does. If even that fails, stop.
                break
            }
        }
        self.elements = elements
    }

    /// Reads nothing, so it decodes from any value and steps over it.
    private struct Skipped: Decodable {
        init(from decoder: Decoder) throws {}
    }
}
