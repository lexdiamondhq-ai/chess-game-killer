import ChessKit
import SwiftUI

/// Everything that changes when the player picks a different board look.
struct BoardTheme: Identifiable {
    enum ID: String, CaseIterable {
        case walnut, neon
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

    // Screen
    let boardEdge: Color?
    let boardShadows: [Color]
    let isDark: Bool
    let accent: Color?

    func imageName(for piece: Piece) -> String {
        pieceSet + piece.assetName
    }

    static let all: [BoardTheme] = [.walnut, .neon]

    static func named(_ id: ID) -> BoardTheme {
        all.first { $0.id == id } ?? .walnut
    }

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
