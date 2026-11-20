import SwiftUI

/// The rivals whose game turns into a filmed scene when the phone goes sideways, and what
/// differs between their scenes. The script, the stage and the view are shared; this says whose
/// films to play and where the board may float.
///
/// - The Ashen King's hall: his stone table in the rain, dragons over the ruins (2026-11-10).
/// - The Cub's forest: a tree stump in an autumn birch wood, owls and a fox in the trees, his
///   horse at its hay (Alex, 2026-11-14 to 2026-11-19).
///
/// In both, your challenger is the Wolf Knight on the left and the rival sits on the right.
enum BroadcastHall: String, CaseIterable {
    case ashenKing
    case cub

    /// The scene for a rival, if it has one.
    init?(_ level: MatchController.Level) {
        switch level {
        case .grandmaster: self = .ashenKing
        case .beginner: self = .cub
        default: return nil
        }
    }

    /// The figure's part of a film's name: `broadcast-<stem>-<name>.mp4`.
    func stem(_ figure: BroadcastClip.Figure) -> String {
        switch (self, figure) {
        case (.ashenKing, .king): return "king"
        case (.ashenKing, .knight): return "knight"
        case (.cub, .king): return "cub"
        case (.cub, .knight): return "cub-knight"
        }
    }

    /// The still both figures start from, shown until the films play.
    var plate: String {
        switch self {
        case .ashenKing: return "broadcast-plate"
        case .cub: return "broadcast-cub-plate"
        }
    }

    /// The challenger's shape, then the strips of table that can be added to it. In the forest
    /// his shape is simply the left of the board's middle: every film there was made with the
    /// other player holding still, so the two halves never meet.
    var masks: [String] {
        switch self {
        case .ashenKing: return ["broadcast-knight-mask", "broadcast-knight-strip", "broadcast-knight-strip-wide"]
        case .cub: return ["broadcast-cub-knight-mask"]
        }
    }

    /// The dragons' wing beats over the sky: only the King's hall has them.
    var hasSky: Bool { self == .ashenKing }

    /// In the forest the Cub's endings show the whole table, the knight's answer to them
    /// included, so the knight's own film stands aside for them.
    var rivalEndingsShowBoth: Bool { self == .cub }

    /// The idle films, in a set order: never the same one twice running.
    var idles: (king: [String], knight: [String]) {
        switch self {
        case .ashenKing:
            // The challenger has the most to do (Alex, 2026-11-10: "the challenger needs to
            // have more movements"): he rubs his brow, folds his arms, looks up at the storm,
            // clasps his fists, with the quiet thinking film as a breath between.
            return (["lean", "nod", "lean", "lean", "nod"],
                    ["brow", "think", "arms", "nod", "upward", "lean", "fists", "think"])
        case .cub:
            // "think" is the whole wood breathing for ten seconds: fog, leaves, the owls, the
            // horse at its hay (Alex, 2026-11-14: the animals should move).
            return (["think", "lean", "think", "nod"], ["think", "nod", "think", "lean"])
        }
    }

    /// The highest the board's foot may come, as a height in the film, and the widest it may be,
    /// in the film's pixels: clear of both heads and of the pieces on the table.
    func boardLimits(flat: Bool) -> (floor: CGFloat, widest: CGFloat) {
        switch self {
        case .ashenKing: return flat ? (575, 560) : (545, 640)
        // Between the knight's beard and the Cub's fox hood, which sit higher and closer than
        // the King's head; the lantern and the birds stay outside it. Below the heads there is
        // only mist down to the stump, so a flat board may reach lower: on the smallest phones
        // that keeps its squares big enough for a finger.
        case .cub: return flat ? (520, 470) : (440, 490)
        }
    }

    /// The words under the board when the game is over.
    func result(playerWon: Bool?) -> String {
        guard let playerWon else { return "Drawn" }
        switch self {
        case .ashenKing: return playerWon ? "The King has fallen" : "The King stands"
        case .cub: return playerWon ? "The Cub is beaten" : "The Cub wins"
        }
    }
}
