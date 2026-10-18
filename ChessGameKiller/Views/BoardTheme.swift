import ChessKit
import SwiftUI

/// Everything that changes when the player picks a different board look.
struct BoardTheme: Identifiable {
    enum ID: String, CaseIterable {
        case malachite, faberge, blueprint, walnut, neon
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
    /// Prefix of the piece images in Assets.xcassets/Pieces ("" or "neon-").
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

    static let all: [BoardTheme] = [.malachite, .faberge, .blueprint, .walnut, .neon]

    static func named(_ id: ID) -> BoardTheme {
        all.first { $0.id == id } ?? .malachite
    }

    /// Mother-of-pearl and banded malachite inlaid with rose gold, on black onyx.
    static let malachite = BoardTheme(
        id: .malachite,
        name: "Malachite",
        symbol: "diamond.fill",
        light: Color(hex: 0xF2F0EB),
        dark: Color(hex: 0x0D7340),
        surface: nil,
        gridLine: nil,
        labelOnLight: Color(hex: 0xB86A50),
        labelOnDark: Color(hex: 0xFFE3D6),
        selected: Color(hex: 0xFFC2AC).opacity(0.22),
        selectedRing: Color(hex: 0xFFC2AC).opacity(0.95),
        lastMove: Color(hex: 0xFFFDF8).opacity(0.30),
        lastMoveRing: Color(hex: 0xF2A98F).opacity(0.55),
        hint: Color(hex: 0xF2A98F).opacity(0.85),
        hintGlow: Color(hex: 0xFFC2AC),
        check: Color(hex: 0xFF3B4E),
        pieceSet: "malachite-",
        whiteGlow: nil,
        blackGlow: nil,
        whiteSide: Color(hex: 0xF4EFEA),
        blackSide: Color(hex: 0x0A0C0B),
        whiteName: "Pearl",
        blackName: "Onyx",
        bestArrow: Color(hex: 0xF2A98F).opacity(0.95),
        secondArrow: Color(hex: 0xF2A98F).opacity(0.7),
        arrowGlow: Color(hex: 0xFFC2AC),
        whiteSparks: [Color(hex: 0xFFFDF8), Color(hex: 0xFFE3D6), Color(hex: 0xF2A98F), Color(hex: 0x9FE6D0)],
        blackSparks: [Color(hex: 0xFFE3D6), Color(hex: 0x44B377), Color(hex: 0x0D7340), Color(hex: 0xF2A98F)],
        boardEdge: nil,
        boardShadows: [Color.black.opacity(0.6)],
        isDark: true,
        accent: Color(hex: 0xF2A98F),
        boardArt: "board-malachite",
        spritePieces: true,
        backdrop: [Color(hex: 0x0F3B29), Color(hex: 0x030C08)]
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
        hintGlow: Color(hex: 0xF6D27A),
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
        arrowGlow: Color(hex: 0xF6D27A),
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
        hintGlow: Color(hex: 0xFFC24D),
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
        arrowGlow: Color(hex: 0xFFC24D),
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

    /// Warm walnut and cream, tuned for contrast with the black and white pieces.
    static let walnut = BoardTheme(
        id: .walnut,
        name: "Walnut",
        symbol: "square.grid.3x3.fill",
        light: Color(hex: 0xF0D9B5),
        dark: Color(hex: 0xB58863),
        surface: nil,
        gridLine: nil,
        labelOnLight: Color(hex: 0xB58863),
        labelOnDark: Color(hex: 0xF0D9B5),
        selected: Color(red: 0.42, green: 0.62, blue: 0.20).opacity(0.55),
        selectedRing: nil,
        lastMove: Color(red: 0.80, green: 0.82, blue: 0.24).opacity(0.45),
        lastMoveRing: nil,
        hint: Color.black.opacity(0.20),
        hintGlow: nil,
        check: Color(red: 0.90, green: 0.10, blue: 0.10),
        pieceSet: "",
        whiteGlow: nil,
        blackGlow: nil,
        whiteSide: .white,
        blackSide: .black,
        whiteName: "White",
        blackName: "Black",
        bestArrow: Color(hex: 0x15781B).opacity(0.85),
        secondArrow: Color(hex: 0x15781B).opacity(0.55),
        arrowGlow: nil,
        whiteSparks: [Color(hex: 0xFFF4D6), Color(hex: 0xFFC24A), Color(hex: 0xFF7A1A)],
        blackSparks: [Color(hex: 0xFFC24A), Color(hex: 0xFF7A1A), Color(hex: 0x6B3A1E)],
        boardEdge: nil,
        boardShadows: [Color.black.opacity(0.25)],
        isDark: false,
        accent: nil
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
                RadialGradient(colors: colors, center: UnitPoint(x: 0.5, y: 0.4),
                               startRadius: 0, endRadius: max(geo.size.width, geo.size.height) * 0.75)
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
