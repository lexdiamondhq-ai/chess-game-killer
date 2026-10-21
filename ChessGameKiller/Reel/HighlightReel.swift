import ChessKit
import Foundation

/// One of the person's moves as the coach graded it, kept for the highlight reel.
struct ReelMoment: Equatable {
    let ply: Int
    let grade: MoveReview.Grade
    let san: String
    let uci: String
    let color: Piece.Color
    let fenBefore: String
    let fenAfter: String
    /// The engine's better move, in standard notation, when there was one.
    let best: String?
    /// Winning chances for the mover, -1 to 1, before and after the move.
    let before: Double
    let after: Double
    /// Where the moving piece started the game, so the army can name it.
    var origin: Square? = nil
    /// For Rewind: the engine's move in engine notation, its whole line, and the
    /// opponent's best answer to the move played.
    var bestUCI: String? = nil
    var bestLine: [String] = []
    var reply: String? = nil
    /// The engine's scores for the mover, before and after the move.
    var beforeEval: Evaluation? = nil
    var afterEval: Evaluation? = nil
}

/// A finished game cut down to its story: up to three moments and how it ended.
struct GameReel: Equatable, Identifiable {
    /// Each reel is its own, so it can be shown with `fullScreenCover(item:)`.
    let id = UUID()

    enum Kind: String, Equatable {
        case brilliant, turningPoint, blunder, finish

        var title: String {
            switch self {
            case .brilliant: return "Best move"
            case .turningPoint: return "Turning point"
            case .blunder: return "The one that hurt"
            case .finish: return "The finish"
            }
        }
    }

    enum Result: Equatable { case win, loss, draw }

    struct Highlight: Equatable, Identifiable {
        let kind: Kind
        let moment: ReelMoment
        /// What Leo says over it. Every line is recorded once, so it never names a move.
        let line: String
        /// The name of the army piece that made the move, when it has one.
        var piece: String? = nil
        var id: Int { moment.ply }
    }

    let player: String
    let opponent: String
    let playerColor: Piece.Color
    let result: Result
    let accuracy: Int?
    let moveCount: Int
    let highlights: [Highlight]
    let finalFEN: String
    /// The Piece of the Match line, shown at the end.
    var hero: String? = nil

    // MARK: Leo's lines (kept short so they can be recorded ahead of time)

    static let introLine = "Here's how it went."
    static let lines: [Kind: String] = [
        .brilliant: "What a move. This is the one I'd frame.",
        .turningPoint: "And right here, the whole game turned.",
        .blunder: "Ouch. This is the one to learn from.",
        .finish: "And that's how you finish a game.",
    ]
    static let endLines: [Result: String] = [
        .win: "A win. Well played.",
        .loss: "Not this time. We'll get them next game.",
        .draw: "Honours even. A fair result.",
    ]

    /// Every line Leo can say in a reel, for recording.
    static var allLines: [String] {
        [introLine] + Kind.allCases.compactMap { lines[$0] } + [Result.win, .loss, .draw].compactMap { endLines[$0] }
    }

    var endLine: String { Self.endLines[result] ?? "" }

    /// Picks the moments. Best: the strong move that gained the most. Turning point:
    /// the move that took the game from one side to the other. Blunder: the move that
    /// gave the most away. A mate replaces the best move. In the order they were played.
    static func make(log: [Int: ReelMoment], player: String, opponent: String, playerColor: Piece.Color,
                     winner: Piece.Color?, isOver: Bool, accuracy: Int?, moveCount: Int, finalFEN: String,
                     pieceName: (Square) -> String? = { _ in nil }, hero: String? = nil) -> GameReel {
        let moments = log.values.sorted { $0.ply < $1.ply }
        var chosen: [Kind: ReelMoment] = [:]

        // How much each move changed things since the person's previous move.
        var previous = 0.0
        var swings: [(ReelMoment, Double)] = []
        for moment in moments {
            swings.append((moment, moment.after - previous))
            previous = moment.after
        }

        if let mate = moments.last(where: { $0.grade == .checkmate }) {
            chosen[.finish] = mate
        } else if let best = swings
            .filter({ [.best, .excellent].contains($0.0.grade) && $0.1 > 0.1 })
            .max(by: { $0.1 < $1.1 })?.0 {
            chosen[.brilliant] = best
        }
        if let worst = moments
            .filter({ [.blunder, .mistake].contains($0.grade) })
            .max(by: { ($0.before - $0.after) < ($1.before - $1.after) }) {
            chosen[.blunder] = worst
        }
        let used = Set(chosen.values.map(\.ply))
        // The game crossed from one side to the other: the biggest such swing.
        if let turn = swings
            .filter({ !used.contains($0.0.ply) && abs($0.1) > 0.35 && ($0.0.after - $0.1).sign != $0.0.after.sign })
            .max(by: { abs($0.1) < abs($1.1) })?.0 {
            chosen[.turningPoint] = turn
        }

        let highlights = chosen
            .map { Highlight(kind: $0.key, moment: $0.value, line: lines[$0.key] ?? "",
                             piece: $0.value.origin.flatMap(pieceName)) }
            .sorted { $0.moment.ply < $1.moment.ply }
        let result: Result = winner.map { $0 == playerColor ? .win : .loss } ?? .draw
        return GameReel(player: player, opponent: opponent, playerColor: playerColor,
                        result: isOver ? result : .draw, accuracy: accuracy, moveCount: moveCount,
                        highlights: highlights, finalFEN: finalFEN, hero: hero)
    }

    // MARK: Timing (seconds), shared by playback and the exported video

    static let introLength = 3.2
    static let highlightLength = 6.5
    static let outroLength = 4.0
    /// Within a highlight: the move's arrow shows, then the move lands.
    static let moveLandsAt = 2.4

    var length: Double { Self.introLength + Double(highlights.count) * Self.highlightLength + Self.outroLength }

    enum Scene: Equatable {
        case intro(progress: Double)
        case highlight(index: Int, time: Double)
        case outro(progress: Double)
    }

    func scene(at time: Double) -> Scene {
        if time < Self.introLength { return .intro(progress: time / Self.introLength) }
        let t = time - Self.introLength
        let index = Int(t / Self.highlightLength)
        if index < highlights.count {
            return .highlight(index: index, time: t - Double(index) * Self.highlightLength)
        }
        let outro = t - Double(highlights.count) * Self.highlightLength
        return .outro(progress: min(1, outro / Self.outroLength))
    }

    /// When each of Leo's lines starts, for playback and for the video's sound.
    var narration: [(time: Double, text: String)] {
        var cues: [(time: Double, text: String)] = [(0.3, Self.introLine)]
        for (index, highlight) in highlights.enumerated() {
            cues.append((Self.introLength + Double(index) * Self.highlightLength + 0.3, highlight.line))
        }
        cues.append((Self.introLength + Double(highlights.count) * Self.highlightLength + 0.3, endLine))
        return cues
    }
}

extension GameReel.Kind: CaseIterable {}
