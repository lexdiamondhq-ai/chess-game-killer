import Foundation

/// A move's sound on a lesson's or a room's board: the right one for the move (a capture, a check,
/// castling, a plain move), heard as its piece touches down. On the 3D board the piece glides
/// there first, so the sound waits for it, as it does in a game.
@MainActor
enum MoveSound {
    /// Whether these boards are drawn in 3D now: the look has a 3D board and 3D pieces are on
    /// (what `TrainerBoard` asks).
    static var boardIs3D: Bool {
        let defaults = UserDefaults.standard
        let id = defaults.string(forKey: "boardTheme").flatMap(BoardTheme.ID.init(rawValue:)) ?? .gilded
        let setting = defaults.object(forKey: "sculpted3D") as? Bool ?? true
        return BoardView.playsIn3D(BoardTheme.named(id), setting: setting)
    }

    /// Seconds until `move`, just played on `game`, touches down.
    static func landing(of move: PlayedMove, in game: GameModel) -> TimeInterval {
        boardIs3D ? SculptedBoardScene.landingDelay(for: move, in: game) : 0
    }

    /// Plays the sound of the last move on `game`.
    static func play(in game: GameModel, on sounds: SoundPlaying? = SoundPlayer.shared) {
        guard let move = game.lastPlayed else { return }
        play(move, in: game, on: sounds)
    }

    static func play(_ move: PlayedMove, in game: GameModel, on sounds: SoundPlaying? = SoundPlayer.shared) {
        guard let sounds else { return }
        let landing = landing(of: move, in: game)
        if move.isCapture {
            sounds.play(.capture, after: landing)
        } else if move.givesCheck {
            sounds.play(.check, after: landing)
        } else if move.isCastle {
            sounds.play(.castle, after: landing)
        } else {
            sounds.play(.move, after: landing)
        }
    }
}
