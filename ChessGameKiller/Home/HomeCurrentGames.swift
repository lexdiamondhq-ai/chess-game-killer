import ChessKit
import SwiftUI

/// One game still going, as the home's strip of current games shows it: against the computer,
/// a friend by link, or a player found online.
struct HomeCurrentGame: Identifiable, Equatable {
    enum Kind: Equatable {
        case computer, friend, online
    }

    let id: String
    let kind: Kind
    /// "vs Sam", "vs Pulse", "Open challenge".
    let title: String
    /// "Friend · 10+0 · Move 12".
    let detail: String
    /// The detail without its last part, for a row too narrow for all of it: "Friend · 10+0".
    var shortDetail: String {
        detail.components(separatedBy: " · ").dropLast().joined(separator: " · ")
    }
    /// The position now, drawn small from your side.
    let fen: String?
    /// You play Black, so Black is at the bottom of the small board.
    let flipped: Bool
    let status: Status
    /// The friend game to open; nil for the game against the computer.
    let friendGame: FriendGame?

    enum Status: Equatable {
        case yourMove, theirMove, waiting

        var words: String {
            switch self {
            case .yourMove: return "Your move"
            case .theirMove: return "Their move"
            case .waiting: return "Waiting"
            }
        }
    }

    var isYourMove: Bool { status == .yourMove }

    /// Your move first, then their move, then open challenges; newest first within each
    /// (the order they come in), with the computer game first among equals.
    static func sorted(_ games: [HomeCurrentGame]) -> [HomeCurrentGame] {
        let rank: (HomeCurrentGame) -> Int = { game in
            switch game.status {
            case .yourMove: return 0
            case .theirMove: return 1
            case .waiting: return 2
            }
        }
        return games.enumerated().sorted { a, b in
            let ra = rank(a.element)
            let rb = rank(b.element)
            return ra != rb ? ra < rb : a.offset < b.offset
        }.map(\.element)
    }

    /// The game against the computer, when one is under way.
    static func computer(_ upNext: HomeUpNext, fen: String) -> HomeCurrentGame? {
        guard upNext.inProgress else { return nil }
        let clock = upNext.timeControl.isTimed ? upNext.timeControl.rawValue : "No clock"
        return HomeCurrentGame(
            id: "computer", kind: .computer, title: "vs \(upNext.rival.name)",
            detail: "Computer · \(clock) · Move \(upNext.moveNumber)", fen: fen,
            flipped: upNext.playerColor == .black, status: upNext.yourMove ? .yourMove : .theirMove,
            friendGame: nil)
    }

    /// A friend or online game that hasn't ended.
    static func friend(_ game: FriendGame) -> HomeCurrentGame {
        let status: Status
        switch game.status {
        case .active: status = game.isYourMove ? .yourMove : .theirMove
        case .waiting, .over: status = .waiting
        }
        var parts: [String] = []
        if game.rated {
            parts.append(game.opponentRating.map { "Online · \($0)" } ?? "Online")
        } else {
            parts.append("Friend")
        }
        parts.append(game.clock?.label ?? "No clock")
        if game.status == .waiting {
            parts.append("Link sent")
        } else {
            parts.append("Move \(game.moveCount / 2 + 1)")
        }
        return HomeCurrentGame(
            id: game.code, kind: game.rated ? .online : .friend, title: game.title,
            detail: parts.joined(separator: " · "), fen: game.fen, flipped: game.seat == .black,
            status: status, friendGame: game)
    }

    /// The header's note: how many games wait on you.
    static func note(_ games: [HomeCurrentGame]) -> String? {
        let yours = games.filter(\.isYourMove).count
        if yours == 0 { return games.isEmpty ? nil : "Waiting on them" }
        return yours == 1 ? "1 needs your move" : "\(yours) need your move"
    }
}

/// A game's position drawn small, from the player's side, in the home's own look. No
/// coordinates: it is there to recognise the game at a glance.
struct HomeMiniBoard: View {
    let fen: String?
    let flipped: Bool
    let theme: BoardTheme
    let tone: HomeTone
    /// Your move: a fine gold rim.
    var lit = false

    private var draft: PositionDraft {
        fen.flatMap(PositionDraft.init(fen:)) ?? PositionDraft(fen: Self.start) ?? PositionDraft()
    }

    private static let start = "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1"

    var body: some View {
        GeometryReader { geo in
            let side: CGFloat = min(geo.size.width, geo.size.height)
            let square: CGFloat = side / 8
            let draft = self.draft
            VStack(spacing: 0) {
                ForEach(0..<8, id: \.self) { row in
                    HStack(spacing: 0) {
                        ForEach(0..<8, id: \.self) { column in
                            let at = flipped ? Square(file: 7 - column, rank: row) : Square(file: column, rank: 7 - row)
                            ZStack {
                                Rectangle().fill((at.fileIndex + at.rankIndex) % 2 == 1 ? theme.light : theme.dark)
                                if let token = draft[at] {
                                    PieceImage(piece: token.piece(at: at), theme: theme, size: square, onBoard: true)
                                }
                            }
                            .frame(width: square, height: square)
                        }
                    }
                }
            }
            .frame(width: side, height: side)
        }
        .aspectRatio(1, contentMode: .fit)
        .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 5, style: .continuous)
                .strokeBorder(lit ? tone.metal.opacity(0.9) : tone.ink.opacity(0.3), lineWidth: lit ? 1 : 0.5)
        }
        .environment(\.layoutDirection, .leftToRight)
        .accessibilityHidden(true)
    }
}
