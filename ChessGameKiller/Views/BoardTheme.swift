import ChessKit
import SwiftUI

/// Everything that changes when the player picks a different board look.
struct BoardTheme: Identifiable {
    enum ID: String, CaseIterable {
        case sculpted, neon, faberge, blueprint
        // One board per rival, matching its portrait.
        case spark, drift, pulse, vector, singularity
    }

    let id: ID
    let name: String
    /// SF Symbol shown next to the name in the theme menu.
    let symbol: String

    // Squares
    let light: Color
    let dark: Color
    /// Drawn under the squares; when set, `light` and `dark` are translucent tints over it.
    let surface: [Color]?
    /// Thin line around every square.
    let gridLine: Color?
    let labelOnLight: Color
    let labelOnDark: Color

    // Highlights
    let selected: Color
    let selectedRing: Color?
    let lastMove: Color
    let lastMoveRing: Color?
    let hint: Color
    let hintGlow: Color?
    let check: Color

    // Pieces
    /// Prefix of the piece images in Assets.xcassets/Pieces (such as "neon-" or "faberge-").
    let pieceSet: String
    let whiteGlow: Color?
    let blackGlow: Color?
    /// The dot next to "White to move" / "Black to move".
    let whiteSide: Color
    let blackSide: Color
    /// What the sides are called on screen ("White", or "Gold" on Neon).
    let whiteName: String
    let blackName: String

    // Coach
    /// The best-move arrow (solid) and the second-best arrow (dashed).
    let bestArrow: Color
    let secondArrow: Color
    let arrowGlow: Color?
    /// Spark colors when a piece of that color is captured.
    let whiteSparks: [Color]
    let blackSparks: [Color]

    // Screen
    let boardEdge: Color?
    let boardShadows: [Color]
    let isDark: Bool
    let accent: Color?

    // Pre-rendered 3D themes
    /// A full board picture in Assets.xcassets/Boards: 9 squares wide, so the
    /// frame around the playing area is half a square on each side. Squares are not drawn when set.
    var boardArt: String? = nil
    /// Pieces are 3D sprites that stand on their square and rise above it.
    var spritePieces = false
    /// Inner and outer colors of the screen's radial backdrop.
    var backdrop: [Color]? = nil

    /// The width of the frame around the 8x8 squares, for a board `side` points wide.
    /// Neon is the only theme with colored halos. Every other theme is the
    /// quiet "executive" look: no glows, plain type, fine lines, one accent.
    var glows: Bool { id == .neon }

    func frameInset(side: CGFloat) -> CGFloat {
        boardArt == nil ? 0 : side / 18
    }

    /// The fill for a square: clear when the board picture already shows it.
    func squareFill(isLight: Bool) -> Color {
        boardArt == nil ? (isLight ? light : dark) : .clear
    }

    func imageName(for piece: Piece) -> String {
        pieceSet + piece.assetName
    }

    func name(of color: Piece.Color) -> String {
        color == .white ? whiteName : blackName
    }

    func sideColor(_ color: Piece.Color) -> Color {
        color == .white ? whiteSide : blackSide
    }

    func sparks(for color: Piece.Color) -> [Color] {
        color == .white ? whiteSparks : blackSparks
    }

    /// The first is the default look.
    static let all: [BoardTheme] = [.sculpted, .neon, .faberge, .blueprint, .spark, .drift, .pulse, .vector, .singularity]

    /// The boards that belong to a rival, in rival order.
    static let rivals: [BoardTheme] = [.spark, .drift, .pulse, .vector, .singularity]

    static func named(_ id: ID) -> BoardTheme {
        all.first { $0.id == id } ?? .sculpted
    }

    /// Carved ivory and ebony on grey and black marble, with platinum rings and sapphires.
    /// In a game it is a real 3D board; small boards draw renders of the same set.
    static let sculpted = BoardTheme(
        id: .sculpted,
        name: "Sculpted",
        symbol: "cube.fill",
        light: Color(hex: 0x92908D),
        dark: Color(hex: 0x35373B),
        surface: nil,
        gridLine: nil,
        labelOnLight: Color(hex: 0x2A2B2F).opacity(0.8),
        labelOnDark: Color(hex: 0xD6D9E0).opacity(0.8),
        selected: Color(hex: 0x5E8FFF).opacity(0.28),
        selectedRing: nil,
        lastMove: Color.white.opacity(0.14),
        lastMoveRing: nil,
        hint: Color(hex: 0x5E8FFF).opacity(0.92),
        hintGlow: nil,
        check: Color(hex: 0xFF3B4D),
        pieceSet: "sculpted-",
        whiteGlow: nil,
        blackGlow: nil,
        whiteSide: Color(hex: 0xEDE6D8),
        blackSide: Color(hex: 0x26242A),
        whiteName: "Ivory",
        blackName: "Ebony",
        bestArrow: Color(hex: 0x5E8FFF).opacity(0.95),
        secondArrow: Color(hex: 0x5E8FFF).opacity(0.72),
        arrowGlow: nil,
        whiteSparks: [Color.white, Color(hex: 0xF4ECDD), Color(hex: 0xD9DCE3), Color(hex: 0x8FB0FF)],
        blackSparks: [Color.white, Color(hex: 0xD9DCE3), Color(hex: 0x8FB0FF), Color(hex: 0x5E8FFF)],
        boardEdge: nil,
        boardShadows: [Color.black.opacity(0.55)],
        isDark: true,
        accent: Color(hex: 0x7EA6FF),
        boardArt: "board-sculpted",
        spritePieces: true,
        backdrop: [Color(hex: 0x2E3034), Color(hex: 0x08080A)]
    )

    /// Sapphire guilloché enamel and pearl, ruled in gold, after the imperial eggs.
    static let faberge = BoardTheme(
        id: .faberge,
        name: "Fabergé",
        symbol: "crown.fill",
        light: Color(hex: 0xF2EEE6),
        dark: Color(hex: 0x1236E0),
        surface: nil,
        gridLine: nil,
        labelOnLight: Color(hex: 0xB8862E),
        labelOnDark: Color(hex: 0xFFF0C2),
        selected: Color(hex: 0xF6D27A).opacity(0.22),
        selectedRing: Color(hex: 0xF6D27A).opacity(0.95),
        lastMove: Color(hex: 0xFFF6E4).opacity(0.28),
        lastMoveRing: Color(hex: 0xE8BE64).opacity(0.55),
        hint: Color(hex: 0xE8BE64).opacity(0.9),
        hintGlow: nil,
        check: Color(hex: 0xFF3B4E),
        pieceSet: "faberge-",
        whiteGlow: nil,
        blackGlow: nil,
        whiteSide: Color(hex: 0xE8BE64),
        blackSide: Color(hex: 0x030619),
        whiteName: "Gold",
        blackName: "Midnight",
        bestArrow: Color(hex: 0xE8BE64).opacity(0.95),
        secondArrow: Color(hex: 0xE8BE64).opacity(0.7),
        arrowGlow: nil,
        whiteSparks: [Color(hex: 0xFFF6E4), Color(hex: 0xFFF0C2), Color(hex: 0xE8BE64), Color(hex: 0xB8862E)],
        blackSparks: [Color(hex: 0xFFFFFF), Color(hex: 0x8FB0FF), Color(hex: 0x1236E0), Color(hex: 0xE8BE64)],
        boardEdge: nil,
        boardShadows: [Color.black.opacity(0.6)],
        isDark: true,
        accent: Color(hex: 0xE8BE64),
        boardArt: "board-faberge",
        spritePieces: true,
        backdrop: [Color(hex: 0x13235E), Color(hex: 0x050822)]
    )

    /// A drafting sheet: navy squares ruled in white, plaster and ink-glass pieces, amber marks.
    static let blueprint = BoardTheme(
        id: .blueprint,
        name: "Blueprint",
        symbol: "pencil.and.ruler.fill",
        light: Color(hex: 0x1E4275),
        dark: Color(hex: 0x102544),
        surface: nil,
        gridLine: nil,
        labelOnLight: Color.white.opacity(0.75),
        labelOnDark: Color.white.opacity(0.75),
        selected: Color(hex: 0xFFC24D).opacity(0.18),
        selectedRing: Color(hex: 0xFFC24D).opacity(0.95),
        lastMove: Color.white.opacity(0.14),
        lastMoveRing: Color.white.opacity(0.5),
        hint: Color(hex: 0xFFC24D).opacity(0.9),
        hintGlow: nil,
        check: Color(hex: 0xFF4D5E),
        pieceSet: "blueprint-",
        whiteGlow: nil,
        blackGlow: nil,
        whiteSide: Color(hex: 0xF4F7FB),
        blackSide: Color(hex: 0x0B1730),
        whiteName: "Plaster",
        blackName: "Ink",
        bestArrow: Color(hex: 0xFFC24D).opacity(0.95),
        secondArrow: Color(hex: 0xFFC24D).opacity(0.7),
        arrowGlow: nil,
        whiteSparks: [Color.white, Color(hex: 0xDCE8F7), Color(hex: 0xFFC24D), Color(hex: 0x7FB2FF)],
        blackSparks: [Color.white, Color(hex: 0x7FB2FF), Color(hex: 0x1E4275), Color(hex: 0xFFC24D)],
        boardEdge: nil,
        boardShadows: [Color.black.opacity(0.55)],
        isDark: true,
        accent: Color(hex: 0xFFC24D),
        boardArt: "board-blueprint",
        spritePieces: true,
        backdrop: [Color(hex: 0x1D3C66), Color(hex: 0x050C18)]
    )

    /// Glowing glass board with gold and violet pieces, from the Neon Glass concept.
    static let neon = BoardTheme(
        id: .neon,
        name: "Neon",
        symbol: "sparkles",
        light: Color(hex: 0x060716).opacity(0.30),
        dark: Color(hex: 0x060716).opacity(0.74),
        surface: [Color(hex: 0x19C6CF), Color(hex: 0x4C7BE8), Color(hex: 0x9B4BEA), Color(hex: 0xE04BC4)],
        gridLine: Color(hex: 0xD2FAFF).opacity(0.55),
        labelOnLight: Color.white.opacity(0.6),
        labelOnDark: Color.white.opacity(0.6),
        selected: Color(hex: 0x5AFAEB).opacity(0.22),
        selectedRing: Color(hex: 0x96FFF5).opacity(0.9),
        lastMove: Color(hex: 0xFFC86E).opacity(0.22),
        lastMoveRing: Color(hex: 0xFFD282).opacity(0.55),
        hint: Color(hex: 0x96FFFA).opacity(0.85),
        hintGlow: Color(hex: 0x6EFFF0),
        check: Color(hex: 0xFF3B6B),
        pieceSet: "neon-",
        whiteGlow: Color(hex: 0xFFAA46),
        blackGlow: Color(hex: 0xAA6EFF),
        whiteSide: Color(hex: 0xFFD08A),
        blackSide: Color(hex: 0xA66BFF),
        whiteName: "Gold",
        blackName: "Violet",
        bestArrow: Color(hex: 0x3DFF9A),
        secondArrow: Color(hex: 0x3DFF9A).opacity(0.7),
        arrowGlow: Color(hex: 0x3DFF9A),
        whiteSparks: [Color(hex: 0xFFF6DC), Color(hex: 0xFFD08A), Color(hex: 0xFF9E3D), Color(hex: 0xFF5AC8)],
        blackSparks: [Color(hex: 0xF0E2FF), Color(hex: 0xB98CFF), Color(hex: 0x7C4DFF), Color(hex: 0x50F0E6)],
        boardEdge: Color.white.opacity(0.35),
        boardShadows: [Color(hex: 0x3CDCE6).opacity(0.35), Color(hex: 0xC846DC).opacity(0.35)],
        isDark: true,
        accent: Color(hex: 0x7CF7FF)
    )

    // MARK: Rival boards

    /// A glowing ember: golden sparkles in warm amber glass, for Spark.
    static let spark = rivalTheme(
        id: .spark, name: "Spark", symbol: "flame.fill",
        light: Color(hex: 0xB86B26), dark: Color(hex: 0x170D08),
        labelOnLight: Color(hex: 0xFFE2B0), labelOnDark: Color(hex: 0xFFB24A),
        accent: Color(hex: 0xFFB24A), selected: Color(hex: 0xFFD27A),
        whiteSide: Color(hex: 0xFFC46A), blackSide: Color(hex: 0x1A120C), whiteName: "Ember", blackName: "Obsidian",
        whiteSparks: [Color(hex: 0xFFF4D6), Color(hex: 0xFFC24A), Color(hex: 0xFF7A1A), Color(hex: 0xFF4D1A)],
        blackSparks: [Color(hex: 0xFFC24A), Color(hex: 0xFF7A1A), Color(hex: 0x6B3A1E), Color(hex: 0xFFE2B0)],
        backdrop: [Color(hex: 0x3A2210), Color(hex: 0x0A0604)]
    )

    /// A tilted orbit of light around aqua glass, for Drift.
    static let drift = rivalTheme(
        id: .drift, name: "Drift", symbol: "circle.dotted.and.circle",
        light: Color(hex: 0x54A8A8), dark: Color(hex: 0x08161F),
        labelOnLight: Color(hex: 0x08161F), labelOnDark: Color(hex: 0x9FE6DC),
        accent: Color(hex: 0xC89CFF), selected: Color(hex: 0xE0C8FF),
        whiteSide: Color(hex: 0x9FFAEE), blackSide: Color(hex: 0x0A0C2E), whiteName: "Aqua", blackName: "Indigo",
        whiteSparks: [Color(hex: 0xEAFFFB), Color(hex: 0x9FFAEE), Color(hex: 0x5BE0B0), Color(hex: 0xFF8CF0)],
        blackSparks: [Color(hex: 0xE0C8FF), Color(hex: 0xC89CFF), Color(hex: 0x4C4CFF), Color(hex: 0x5BE0B0)],
        backdrop: [Color(hex: 0x17303A), Color(hex: 0x06100F)]
    )

    /// Shockwave rings of cyan light, for Pulse.
    static let pulse = rivalTheme(
        id: .pulse, name: "Pulse", symbol: "dot.radiowaves.left.and.right",
        light: Color(hex: 0x2B6EA3), dark: Color(hex: 0x050D1C),
        labelOnLight: Color(hex: 0xD6F4FF), labelOnDark: Color(hex: 0x7FE6FF),
        accent: Color(hex: 0x4DE0FF), selected: Color(hex: 0x96F0FF),
        whiteSide: Color(hex: 0xDBF7FF), blackSide: Color(hex: 0x030813), whiteName: "Ice", blackName: "Night",
        whiteSparks: [Color(hex: 0xFFFFFF), Color(hex: 0xDBF7FF), Color(hex: 0x7FE6FF), Color(hex: 0x4C7BE8)],
        blackSparks: [Color(hex: 0x7FE6FF), Color(hex: 0x4DE0FF), Color(hex: 0x1C4FA0), Color(hex: 0xFFFFFF)],
        backdrop: [Color(hex: 0x0B2A45), Color(hex: 0x03080F)]
    )

    /// Every square cut into violet crystal facets, for Vector.
    static let vector = rivalTheme(
        id: .vector, name: "Vector", symbol: "diamond.fill",
        light: Color(hex: 0x7349BF), dark: Color(hex: 0x160A2B),
        labelOnLight: Color(hex: 0xEBDCFF), labelOnDark: Color(hex: 0xB98CFF),
        accent: Color(hex: 0xCF8CFF), selected: Color(hex: 0xE6C2FF),
        whiteSide: Color(hex: 0xE2D4FF), blackSide: Color(hex: 0x12062A), whiteName: "Crystal", blackName: "Deep",
        whiteSparks: [Color(hex: 0xF7F0FF), Color(hex: 0xE2D4FF), Color(hex: 0xCF8CFF), Color(hex: 0xFF5AC8)],
        blackSparks: [Color(hex: 0xCF8CFF), Color(hex: 0xA66BFF), Color(hex: 0x7C4DFF), Color(hex: 0xFFFFFF)],
        backdrop: [Color(hex: 0x2C1850), Color(hex: 0x0A0515)]
    )

    /// A black hole with a bright photon ring and a magenta halo, for Singularity.
    static let singularity = rivalTheme(
        id: .singularity, name: "Singularity", symbol: "circle.circle",
        light: Color(hex: 0x54506B), dark: Color(hex: 0x080712),
        labelOnLight: Color(hex: 0xE8E4FF), labelOnDark: Color(hex: 0xB9B3D6),
        accent: Color(hex: 0xFF5AC8), selected: Color(hex: 0xFF9ADF),
        whiteSide: Color(hex: 0xF2EEFF), blackSide: Color(hex: 0x030205), whiteName: "Pearl", blackName: "Void",
        whiteSparks: [Color(hex: 0xFFFFFF), Color(hex: 0xF2EEFF), Color(hex: 0xFF9ADF), Color(hex: 0x8FB0FF)],
        blackSparks: [Color(hex: 0xFF5AC8), Color(hex: 0xFF3B6B), Color(hex: 0x8FB0FF), Color(hex: 0xFFFFFF)],
        backdrop: [Color(hex: 0x2A2438), Color(hex: 0x07060B)]
    )

    /// The shared shape of a rival's board: a pre-rendered picture, 3D sprites, marks in the accent.
    private static func rivalTheme(
        id: ID, name: String, symbol: String, light: Color, dark: Color,
        labelOnLight: Color, labelOnDark: Color, accent: Color, selected: Color,
        whiteSide: Color, blackSide: Color, whiteName: String, blackName: String,
        whiteSparks: [Color], blackSparks: [Color], backdrop: [Color]
    ) -> BoardTheme {
        BoardTheme(
            id: id,
            name: name,
            symbol: symbol,
            light: light,
            dark: dark,
            surface: nil,
            gridLine: nil,
            labelOnLight: labelOnLight,
            labelOnDark: labelOnDark,
            selected: selected.opacity(0.22),
            selectedRing: selected.opacity(0.95),
            lastMove: Color.white.opacity(0.16),
            lastMoveRing: accent.opacity(0.55),
            hint: accent.opacity(0.9),
            hintGlow: nil,
            check: Color(hex: 0xFF3B4E),
            pieceSet: id.rawValue + "-",
            whiteGlow: nil,
            blackGlow: nil,
            whiteSide: whiteSide,
            blackSide: blackSide,
            whiteName: whiteName,
            blackName: blackName,
            bestArrow: accent.opacity(0.95),
            secondArrow: accent.opacity(0.7),
            arrowGlow: nil,
            whiteSparks: whiteSparks,
            blackSparks: blackSparks,
            boardEdge: nil,
            boardShadows: [Color.black.opacity(0.6)],
            isDark: true,
            accent: accent,
            boardArt: "board-" + id.rawValue,
            spritePieces: true,
            backdrop: backdrop
        )
    }
}

extension Color {
    /// Color from a hex number like 0xF0D9B5.
    init(hex: UInt32) {
        self.init(
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255
        )
    }
}

/// The screen behind the board: the theme's radial backdrop, the Neon glow, or the grouped gray.
struct ThemeBackdrop: View {
    let theme: BoardTheme

    var body: some View {
        if let colors = theme.backdrop {
            GeometryReader { geo in
                ZStack {
                    RadialGradient(colors: colors, center: UnitPoint(x: 0.5, y: 0.4),
                                   startRadius: 0, endRadius: max(geo.size.width, geo.size.height) * 0.75)
                    // The executive look keeps the theme's color but deepens it toward black.
                    if !theme.glows {
                        LinearGradient(colors: [.black.opacity(0.2), .black.opacity(0.5)],
                                       startPoint: .top, endPoint: .bottom)
                    }
                }
            }
            .ignoresSafeArea()
            .accessibilityHidden(true)
        } else if theme.isDark {
            NeonBackdrop()
        } else {
            Color(.systemGroupedBackground).ignoresSafeArea()
        }
    }
}

/// Dark backdrop with soft colored glows and out-of-focus lights, behind the Neon board.
struct NeonBackdrop: View {
    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height
            ZStack {
                Color(hex: 0x04050D)
                RadialGradient(colors: [Color(hex: 0x14BEC8).opacity(0.22), .clear],
                               center: UnitPoint(x: 0, y: 0.18), startRadius: 0, endRadius: w * 1.0)
                RadialGradient(colors: [Color(hex: 0xC83CD2).opacity(0.22), .clear],
                               center: UnitPoint(x: 1, y: 0.78), startRadius: 0, endRadius: w * 1.1)
                bokeh(Color(hex: 0x50F0E6), size: 26, x: w * 0.13, y: h * 0.15)
                bokeh(Color(hex: 0xFF5AC8), size: 18, x: w * 0.84, y: h * 0.12)
                bokeh(Color(hex: 0xA06EFF), size: 30, x: w * 0.75, y: h * 0.78)
                bokeh(Color(hex: 0xFFBE5A), size: 16, x: w * 0.18, y: h * 0.83)
            }
        }
        .ignoresSafeArea()
        .accessibilityHidden(true)
    }

    private func bokeh(_ color: Color, size: CGFloat, x: CGFloat, y: CGFloat) -> some View {
        Circle()
            .fill(color.opacity(0.45))
            .frame(width: size, height: size)
            .blur(radius: 5)
            .position(x: x, y: y)
    }
}

/// The type design for the current look: rounded on Neon, plain SF Pro everywhere else.
/// `ContentView` sets it for the theme on screen before anything draws.
enum ThemeFont {
    static var design: Font.Design = .rounded

    static func use(_ theme: BoardTheme) {
        design = theme.glows ? .rounded : .default
    }
}

extension Font.Design {
    /// Rounded on Neon, the default SF Pro on the executive themes.
    static var themed: Font.Design { ThemeFont.design }
}
