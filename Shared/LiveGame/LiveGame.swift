import ActivityKit
import Foundation

// Your game on the Lock Screen and in the Dynamic Island (a Live Activity), and in StandBy on
// the charger. The app starts it on a game's first move, updates it after every move and ends
// it with the game (LiveGameKeeper); the widget extension draws it (LiveGameViews). Compiled
// into both, so Foundation and ActivityKit only.

/// What stays the same for a whole game: who it is against and how it is played.
struct LiveGameAttributes: ActivityAttributes {
    /// The rival's name: "Pulse".
    var rival: String
    /// The color its portrait glows (Rival.lightHex), so the activity wears it.
    var lightHex: UInt32
    /// The rival's glow in the asset catalogs: "rival-pulse-glow".
    var glow: String
    /// The board is drawn from your side.
    var youAreWhite: Bool
    /// "10+0", or "No clock".
    var clock: String

    /// What changes with every move.
    struct ContentState: Codable, Hashable {
        /// The position now.
        var fen: String
        /// The last move in standard notation ("Nf6"), and whether the rival played it.
        var lastMove: String?
        var lastMoveByRival = false
        var yourMove: Bool
        /// The move number now (1 before Black's first reply).
        var moveNumber: Int
        /// Seconds left on your clock in a timed game. The clock waits while the app is away,
        /// so this is the time you come back to.
        var yourSeconds: Int?
        /// The opening, once the game has reached a named one: "Italian Game".
        var opening: String?
        /// Set once the game is over: "You won", "Pulse won", "Draw".
        var result: String?
    }
}

extension LiveGameAttributes.ContentState {
    /// The big line: "Pulse played Nf6", "You played e4", "You won".
    func headline(rival: String) -> String {
        if let result { return result }
        if yourMove {
            if let lastMove, lastMoveByRival { return "\(rival) played \(lastMove)" }
            return "Your move"
        }
        if let lastMove, !lastMoveByRival { return "You played \(lastMove)" }
        return "\(rival) to move"
    }

    /// The line under it: "4:11 on your clock", "Your move · Move 14", "Pulse to move".
    func detail(rival: String) -> String {
        if result != nil { return moveNumber > 1 ? "In \(moveNumber) moves" : "Game over" }
        let time = yourSeconds.map { "\(Self.clockText($0)) on your clock" }
        if yourMove { return time ?? "Your move · Move \(moveNumber)" }
        return time.map { "\(rival) to move · \($0)" } ?? "\(rival) to move · Move \(moveNumber)"
    }

    /// The Dynamic Island's few characters: your clock, or whose move it is.
    var shortStatus: String {
        if result != nil { return "Over" }
        if let yourSeconds { return Self.clockText(yourSeconds) }
        return yourMove ? "Your move" : "Their move"
    }

    /// "4:11", "12:05", "0:42".
    static func clockText(_ seconds: Int) -> String {
        let total = max(seconds, 0)
        return String(format: "%d:%02d", total / 60, total % 60)
    }
}

/// Opens the game from the Lock Screen or the Dynamic Island.
enum LiveGameLink {
    static let url = URL(string: "chessgamekiller://game")!

    static func matches(_ url: URL) -> Bool {
        guard url.scheme?.lowercased() == "chessgamekiller" else { return false }
        if url.host?.lowercased() == "game" { return true }
        return url.pathComponents.filter { $0 != "/" }.first?.lowercased() == "game"
    }
}
