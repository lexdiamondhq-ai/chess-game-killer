import SwiftUI

/// One of the app's chess icons, drawn by scripts/make_glyphs.py into Assets.xcassets/Glyphs
/// (a rook for Home, a knight for Train, a chess clock for Play, a helmeted pawn for the Army),
/// or an SF Symbol for any other name. Takes the foreground color like a symbol.
struct Glyph: View {
    let name: String
    /// The icon's box, in points. Glyphs fill a little more of it than SF Symbols do of their font.
    var size: CGFloat = 24
    var weight: Font.Weight = .semibold

    static func isGlyph(_ name: String) -> Bool { name.hasPrefix("glyph-") }

    var body: some View {
        if Self.isGlyph(name) {
            // Decorative: the button or row it sits in says what it is, not the file's name.
            Image(decorative: name)
                .renderingMode(.template)
                .resizable()
                .interpolation(.high)
                .scaledToFit()
                .frame(width: size, height: size)
        } else {
            Image(systemName: name)
                .font(.system(size: size * 0.78, weight: weight))
                .frame(width: size, height: size)
        }
    }
}

/// The names, so a typo is caught by the compiler rather than drawing nothing.
enum Glyphs {
    static let home = "glyph-home"
    static let train = "glyph-train"
    static let play = "glyph-play"
    static let puzzles = "glyph-puzzles"
    static let analyze = "glyph-analyze"
    static let army = "glyph-army"
    static let games = "glyph-games"
    static let undo = "glyph-undo"
    static let hints = "glyph-hints"
    static let hintsOff = "glyph-hints-off"
    static let flip = "glyph-flip"
    static let settings = "glyph-settings"
    static let normalView = "glyph-normal-view"
    static let bigBoard = "glyph-big-board"
    static let king = "glyph-king"
    static let pawn = "glyph-pawn"

    static let all = [home, train, play, puzzles, analyze, army, games, undo, hints, hintsOff, flip,
                      settings, normalView, bigBoard, king, pawn]
}
