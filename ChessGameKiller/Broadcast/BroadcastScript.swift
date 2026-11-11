import ChessKit
import Foundation

/// The King's hall: turn the phone sideways in a game against the Ashen King and the two of you
/// sit at his stone table in the rain, your challenger on the left, the King on his throne on the
/// right, the real board floating between you (Alex, 2026-11-10).
///
/// Every figure is a set of short films, five seconds each, that start and end on the same
/// still pose, so any one can follow any other. This file is the script: which film each
/// figure plays for each moment of the game, and when. It knows nothing of video.
///
/// The films live in Broadcast/Films as `broadcast-<figure>-<name>.mp4`.
struct BroadcastClip: Hashable {
    enum Figure: String {
        case king
        /// The player's challenger. Only the Wolf Knight has been filmed so far.
        case knight
    }

    let figure: Figure
    let name: String

    static func king(_ name: String) -> BroadcastClip { BroadcastClip(figure: .king, name: name) }
    static func knight(_ name: String) -> BroadcastClip { BroadcastClip(figure: .knight, name: name) }

    /// The film's name in the bundle, without ".mp4".
    var resource: String { "broadcast-\(figure.rawValue)-\(name)" }

    /// An ending: it plays once and holds.
    var holds: Bool { name == "win" || name == "lose" }

    /// A hand goes out to the board.
    var isReach: Bool { touch != nil }

    /// Seconds in when the hand sets the piece down, for the films that move one.
    var touch: Double? {
        switch (figure, base) {
        case (.king, "near"): return 2.4
        case (.king, "far"): return 2.7
        case (.king, "strike"): return 2.8
        case (.knight, "near"): return 2.6
        case (.knight, "far"): return 2.8
        case (.knight, "strike"): return 2.7
        default: return nil
        }
    }

    /// The film's motion without the storm's light: "strike" for "strike-pawn".
    private var base: String { name.split(separator: "-").first.map(String.init) ?? "" }

    /// The challenger's films are laid over the King's through a mask cut close around him.
    /// While his arm is out over the table, the mask also takes in the strip of table on his
    /// side, and for his fall at the end a wider one. The King's hand never comes that far
    /// (measured on every film), so the two never meet.
    var strip: Strip? {
        guard figure == .knight else { return nil }
        switch base {
        case "near": return Strip(wide: false, from: 0.7, to: 3.8)
        case "far": return Strip(wide: false, from: 0.7, to: 4.15)
        // Off before the storm's light arrives (see `BroadcastScript.stormDelay`).
        case "strike": return Strip(wide: false, from: 0.7, to: 3.6)
        case "lose": return Strip(wide: true, from: 0, to: nil)
        default: return nil
        }
    }

    /// The King's films where the sky is part of the show: the storms that answer a capture
    /// (the dragons breathe fire in them) and the two endings. The dragons' own film, which
    /// beats their wings over every other film of his, stands aside for these.
    var ownsSky: Bool {
        figure == .king && (base == "loss" || holds)
    }

    struct Strip: Equatable {
        /// The wider strip, past the middle of the table.
        let wide: Bool
        let from: Double
        /// Nil keeps it for good (an ending).
        let to: Double?
    }
}

/// What the King loses when the player captures, and so how the storm answers: lightning for
/// a pawn, the dragon's fire for a piece, both dragons for his queen.
enum BroadcastLoss: String, CaseIterable {
    case pawn, piece, queen

    init(_ kind: Piece.Kind) {
        switch kind {
        case .pawn: self = .pawn
        case .queen: self = .queen
        default: self = .piece
        }
    }

    /// The King's film: the storm fills the sky behind him.
    var storm: BroadcastClip { .king("loss-\(rawValue)") }
    /// The challenger's capture, with the storm's light falling on him as it comes.
    var strike: BroadcastClip { .knight("strike-\(rawValue)") }
    /// What he plays next, the light fading from him.
    var after: BroadcastClip { .knight("pleased-\(rawValue)") }
}

/// What a move asks of the scene.
struct BroadcastCue: Equatable {
    /// The film the mover plays now.
    var reach: BroadcastClip
    /// The film the mover plays after it, in place of an idle one.
    var then: BroadcastClip?
    /// The King's storm, and how long after the reach it starts.
    var storm: BroadcastClip?
    /// Seconds from now until the King is free to make his own move.
    var kingWaits: Double = 0
}

struct BroadcastScript {
    /// Seconds into the challenger's capture when the King's storm film starts: the piece is
    /// down. The light baked into the challenger's lit films is timed to this (67 frames at
    /// 24 a second; see scripts/broadcast/encode.py).
    static let stormDelay: Double = 67.0 / 24.0
    /// Seconds into a storm film when the sky has settled and the King may move again.
    static let stormSettles: Double = 3.6
    /// How long one film cross-fades into the next.
    static let fade: Double = 0.22
    /// Seconds into a loop when the next film is started: eight frames before its end, so the
    /// next is on screen and faded in just as this one finishes, and the rain never stands still
    /// while a film loads. A loop's last frames are back on the still pose, so nothing is lost.
    /// (The storm's light in "pleased-pawn" and the like is baked to this handover.)
    static let handover: Double = 112.0 / 24.0

    /// The dragons' wing beats: one looping film of the top of the sky, laid over the King's
    /// films and cut to the two dragons. In the King's own films they only move when they
    /// breathe fire (Alex, 2026-11-10: "the dragons are not moving").
    static let skyFilm = "broadcast-sky-dragons"
    /// The share of the picture's height that film covers, from the top (352 of 1080 lines).
    static let skyShare: Double = 352.0 / 1080.0
    /// The challenger's flinch when the King takes one of the player's pieces.
    static let wince = BroadcastClip.knight("wince")

    // The idle films, in a set order: never the same one twice running. The challenger has
    // the most to do (Alex, 2026-11-10: "the challenger needs to have more movements"): he
    // rubs his brow, folds his arms, looks up at the storm, clasps his fists, with the quiet
    // thinking film as a breath between.
    private static let kingIdles = ["lean", "nod", "lean", "lean", "nod"]
    private static let knightIdles = ["brow", "think", "arms", "nod", "upward", "lean", "fists", "think"]
    private var kingTurn = 0
    private var knightTurn = 0

    /// The next film for a figure with nothing else to do.
    mutating func idle(_ figure: BroadcastClip.Figure) -> BroadcastClip {
        switch figure {
        case .king:
            defer { kingTurn += 1 }
            return .king(Self.kingIdles[kingTurn % Self.kingIdles.count])
        case .knight:
            defer { knightTurn += 1 }
            return .knight(Self.knightIdles[knightTurn % Self.knightIdles.count])
        }
    }

    /// The film a figure opens on: the challenger thinking, the King leaning in.
    static func opening(_ figure: BroadcastClip.Figure) -> BroadcastClip {
        figure == .king ? .king("lean") : .knight("think")
    }

    /// A move that lands past the middle of the board, seen from the side that made it, is a
    /// far reach.
    static func isFar(uci: String, by color: Piece.Color) -> Bool {
        guard uci.count >= 4, let rank = Int(String(uci[uci.index(uci.startIndex, offsetBy: 3)])) else { return false }
        return color == .white ? rank >= 5 : rank <= 4
    }

    /// The player's move has landed on the board: the challenger makes it at the table. A
    /// capture is a hard move, and the storm answers once the piece is down, unless the move
    /// ended the game.
    static func playerMoved(uci: String, color: Piece.Color, captured: Piece.Kind?, endsGame: Bool) -> BroadcastCue {
        guard let captured else {
            let reach = BroadcastClip.knight(isFar(uci: uci, by: color) ? "far" : "near")
            return BroadcastCue(reach: reach, kingWaits: reach.touch ?? 0)
        }
        guard !endsGame else { return BroadcastCue(reach: .knight("strike")) }
        let loss = BroadcastLoss(captured)
        return BroadcastCue(reach: loss.strike, then: loss.after, storm: loss.storm,
                            kingWaits: stormDelay + stormSettles)
    }

    /// The King has chosen his move: the film his hand makes it with. After a capture he
    /// allows himself a moment's satisfaction.
    static func kingMoves(uci: String, color: Piece.Color, captures: Bool) -> BroadcastCue {
        if captures { return BroadcastCue(reach: .king("strike"), then: .king("pleased")) }
        return BroadcastCue(reach: .king(isFar(uci: uci, by: color) ? "far" : "near"))
    }

    /// The last films: the winner's and the loser's. Nil for a draw, where both sit on.
    static func ending(playerWon: Bool?) -> (king: BroadcastClip, knight: BroadcastClip)? {
        guard let playerWon else { return nil }
        return playerWon ? (.king("lose"), .knight("win")) : (.king("win"), .knight("lose"))
    }

    /// Whether a move the rival is about to make takes something: a piece on the square it
    /// lands on, or a pawn changing files (en passant).
    static func captures(uci: String, in game: GameModel) -> Bool {
        guard uci.count >= 4 else { return false }
        let from = Square(String(uci.prefix(2)))
        let to = Square(String(uci.dropFirst(2).prefix(2)))
        if game.piece(at: to) != nil { return true }
        guard let mover = game.piece(at: from), mover.kind == .pawn else { return false }
        return uci.first != uci.dropFirst(2).first
    }

    /// Every film the scene can ask for, so a test can check each is in the bundle.
    static var allClips: [BroadcastClip] {
        let king = ["lean", "nod", "near", "far", "strike", "pleased", "win", "lose"].map(BroadcastClip.king)
        let knight = ["think", "nod", "lean", "brow", "fists", "upward", "arms", "wince",
                      "near", "far", "strike", "pleased", "win", "lose"].map(BroadcastClip.knight)
        let storms = BroadcastLoss.allCases.flatMap { [$0.storm, $0.strike, $0.after] }
        return king + knight + storms
    }
}
