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
    static let coach = "glyph-coach"
    static let challenge = "glyph-challenge"
    static let online = "glyph-online"
    /// A pawn in a camera's corners: read a real board.
    static let scan = "glyph-scan"
    /// A pawn on a calendar page: Today's Move.
    static let today = "glyph-today"
    /// Home's fine emblems, drawn in gold on a jewel tile (HomeAuroraJewel): an eye for Puzzles,
    /// a laurel round a pawn for Coach Leo, and one for each Chess DNA style.
    static let fineEye = "glyph-fine-eye"
    static let fineLaurel = "glyph-fine-laurel"
    static let fineAttacker = "glyph-fine-attacker"
    static let fineTactician = "glyph-fine-tactician"
    static let fineCounterpuncher = "glyph-fine-counterpuncher"
    static let fineGrinder = "glyph-fine-grinder"
    static let fineBuilder = "glyph-fine-builder"
    static let fineAllRounder = "glyph-fine-all-rounder"

    static let all = [home, train, play, puzzles, analyze, army, games, undo, hints, hintsOff, flip,
                      settings, normalView, bigBoard, king, pawn, coach, challenge, online, scan, today,
                      fineEye, fineLaurel, fineAttacker, fineTactician, fineCounterpuncher, fineGrinder,
                      fineBuilder, fineAllRounder]
}

/// The small plate a row's icon sits on (New Game's match card, Challenge a friend). On the
/// home's gold pages it is the same gold enamel plate as a Settings row or a Learn row wears,
/// so no cool grey sits among the gold; a look with its own color keeps the quiet dark well.
struct GlyphTile<Content: View>: View {
    let theme: BoardTheme
    @ViewBuilder let content: () -> Content

    var body: some View {
        let tile = RoundedRectangle(cornerRadius: 10, style: .continuous)
        if theme.screenTone != nil {
            let accent: Color = theme.trainingAccent
            content()
                .foregroundStyle(accent)
                .frame(width: 34, height: 34)
                .background(LinearGradient(colors: [accent.opacity(0.24), accent.opacity(0.1)],
                                           startPoint: .top, endPoint: .bottom), in: tile)
                .overlay {
                    tile.strokeBorder(LinearGradient(colors: [accent.opacity(0.5), accent.opacity(0.2)],
                                                     startPoint: .top, endPoint: .bottom), lineWidth: 0.75)
                }
        } else {
            content()
                .foregroundStyle(Color.primary.opacity(0.86))
                .frame(width: 34, height: 34)
                .background(theme.screenIsDark ? Color.black.opacity(0.3) : Color.primary.opacity(0.06), in: tile)
                .overlay { tile.strokeBorder(Color.primary.opacity(theme.screenIsDark ? 0.09 : 0.08), lineWidth: 0.75) }
        }
    }
}
