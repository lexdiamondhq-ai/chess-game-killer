import ChessKit
import SwiftUI

/// Everything that changes when the player picks a different board look.
struct BoardTheme: Identifiable {
    enum ID: String, CaseIterable {
        case gilded, portoro, classic, noir, sculpted, bordeaux, midnight, neon, faberge, blueprint
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
    /// Shadows or glows drawn under the board. None for the boards in a glass frame:
    /// a shadow under clear glass turns it grey, and the backdrop's light should show through.
    let boardShadows: [Color]
    let isDark: Bool
    let accent: Color?

    /// The real 3D board's stone, finishes and light. Looks without one are drawn flat.
    var sculptedLook: SculptedLook? = nil

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

    /// With coordinates the frame is half a square wide, room for the letters and numbers;
    /// without them it is a fine glass rim, so the squares grow.
    func frameInset(side: CGFloat, coordinates: Bool = true) -> CGFloat {
        guard boardArt != nil else { return 0 }
        return side * (coordinates ? 1 / 18 : Self.thinRim)
    }

    /// The glass rim's width, as a share of the board, when coordinates are hidden.
    static let thinRim: CGFloat = 1 / 64

    /// How many squares wide the whole board is, frame included.
    func squaresAcross(coordinates: Bool = true) -> CGFloat {
        8 / (1 - 2 * frameInset(side: 1, coordinates: coordinates))
    }

    /// The Settings switch for the letters and numbers around every board.
    static let coordinatesKey = "showCoordinates"

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

    /// A side's color for words and small symbols. Black's own color is near-black on
    /// every dark look but Neon, so there it reads in a light graphite instead.
    func ink(for color: Piece.Color) -> Color {
        if color == .white || glows { return sideColor(color) }
        return isDark ? Color(white: 0.7) : blackSide
    }

    /// The last move's wash, strong enough to read on light and dark squares alike: gold, or a
    /// yellow-green on looks whose own marks are gold already, so the two never look alike.
    static let goldWash = Color(hex: 0xD9A92B).opacity(0.38)
    static let greenWash = Color(hex: 0xB9C24A).opacity(0.45)

    func sparks(for color: Piece.Color) -> [Color] {
        color == .white ? whiteSparks : blackSparks
    }

    /// The first is the default look.
    static let all: [BoardTheme] = [
        .gilded, .portoro, .classic, .noir, .sculpted, .bordeaux, .midnight, .neon, .faberge, .blueprint, .spark, .drift, .pulse, .vector, .singularity,
    ]

    /// The boards that belong to a rival, in rival order.
    static let rivals: [BoardTheme] = [.spark, .drift, .pulse, .vector, .singularity]

    static func named(_ id: ID) -> BoardTheme {
        all.first { $0.id == id } ?? .gilded
    }

    /// The default: polished onyx and bright ivory pieces with gold, on cream marble and rich
    /// brown marble with black veins, ruled in gold. In a game it is a real 3D board; small
    /// boards draw a picture of it.
    static let gilded = BoardTheme(
        id: .gilded,
        name: "Gilded",
        symbol: "crown.fill",
        light: Color(hex: 0xCDBC9C),
        dark: Color(hex: 0x553420),
        surface: nil,
        gridLine: nil,
        labelOnLight: Color(hex: 0x2A2722).opacity(0.8),
        labelOnDark: Color(hex: 0xE8DFCC).opacity(0.8),
        selected: Color(hex: 0x5E8FFF).opacity(0.28),
        selectedRing: nil,
        lastMove: BoardTheme.goldWash,
        lastMoveRing: nil,
        hint: Color(hex: 0x5E8FFF).opacity(0.92),
        hintGlow: nil,
        check: Color(hex: 0xD92D3F),
        pieceSet: "gilded-",
        whiteGlow: nil,
        blackGlow: nil,
        whiteSide: Color(hex: 0xE6D9BF),
        blackSide: Color(hex: 0x141416),
        whiteName: "Ivory",
        blackName: "Onyx",
        bestArrow: Color(hex: 0x5E8FFF).opacity(0.95),
        secondArrow: Color(hex: 0x5E8FFF).opacity(0.72),
        arrowGlow: nil,
        whiteSparks: [Color.white, Color(hex: 0xF1E4C8), Color(hex: 0xF2C27A), Color(hex: 0xE39A45)],
        blackSparks: [Color.white, Color(hex: 0xF2C27A), Color(hex: 0xE39A45), Color(hex: 0xFF8A2A)],
        boardEdge: nil,
        boardShadows: [],
        isDark: true,
        accent: Color(hex: 0x7EA6FF),
        sculptedLook: .gilded,
        boardArt: "board-gilded",
        spritePieces: true,
        backdrop: [Color(hex: 0x2B2A2C), Color(hex: 0x070708)]
    )

    /// Clean and flat, as the browser shows a friend game: the classic printed pieces on plain
    /// cream and brown squares. No 3D, no picture, nothing but the game.
    static let classic = BoardTheme(
        id: .classic,
        name: "Classic",
        symbol: "square.grid.3x3.fill",
        light: Color(hex: 0xCDBC9C),
        dark: Color(hex: 0x553420),
        surface: nil,
        gridLine: nil,
        labelOnLight: Color(hex: 0x2A2722).opacity(0.82),
        labelOnDark: Color(hex: 0xE8DFCC).opacity(0.85),
        selected: Color(hex: 0x5E8FFF).opacity(0.3),
        selectedRing: nil,
        lastMove: BoardTheme.goldWash,
        lastMoveRing: nil,
        hint: Color(hex: 0x5E8FFF).opacity(0.86),
        hintGlow: nil,
        check: Color(hex: 0xD92D3F),
        pieceSet: "",
        whiteGlow: nil,
        blackGlow: nil,
        whiteSide: Color(hex: 0xF4F1EA),
        blackSide: Color(hex: 0x141416),
        whiteName: "White",
        blackName: "Black",
        bestArrow: Color(hex: 0x5E8FFF).opacity(0.95),
        secondArrow: Color(hex: 0x5E8FFF).opacity(0.72),
        arrowGlow: nil,
        whiteSparks: [Color.white, Color(hex: 0xF1E4C8), Color(hex: 0xF2C27A), Color(hex: 0xE39A45)],
        blackSparks: [Color.white, Color(hex: 0xF2C27A), Color(hex: 0xE39A45), Color(hex: 0xFF8A2A)],
        boardEdge: nil,
        boardShadows: [],
        isDark: true,
        accent: Color(hex: 0x7EA6FF),
        backdrop: [Color(hex: 0x2B2A2C), Color(hex: 0x070708)]
    )

    /// The gilded set on cream marble and black Portoro marble with fine gold veins.
    static let portoro = BoardTheme(
        id: .portoro,
        name: "Portoro",
        symbol: "seal.fill",
        light: Color(hex: 0xCDBC9C),
        dark: Color(hex: 0x1E1E21),
        surface: nil,
        gridLine: nil,
        labelOnLight: Color(hex: 0x2A2722).opacity(0.8),
        labelOnDark: Color(hex: 0xE8DFCC).opacity(0.8),
        selected: Color(hex: 0x5E8FFF).opacity(0.28),
        selectedRing: nil,
        lastMove: BoardTheme.goldWash,
        lastMoveRing: nil,
        hint: Color(hex: 0x5E8FFF).opacity(0.92),
        hintGlow: nil,
        check: Color(hex: 0xD92D3F),
        pieceSet: "gilded-",
        whiteGlow: nil,
        blackGlow: nil,
        whiteSide: Color(hex: 0xE6D9BF),
        blackSide: Color(hex: 0x141416),
        whiteName: "Ivory",
        blackName: "Onyx",
        bestArrow: Color(hex: 0x5E8FFF).opacity(0.95),
        secondArrow: Color(hex: 0x5E8FFF).opacity(0.72),
        arrowGlow: nil,
        whiteSparks: [Color.white, Color(hex: 0xF1E4C8), Color(hex: 0xF2C27A), Color(hex: 0xE39A45)],
        blackSparks: [Color.white, Color(hex: 0xF2C27A), Color(hex: 0xE39A45), Color(hex: 0xFF8A2A)],
        boardEdge: nil,
        boardShadows: [],
        isDark: true,
        accent: Color(hex: 0x7EA6FF),
        sculptedLook: .portoro,
        boardArt: "board-portoro",
        spritePieces: true,
        backdrop: [Color(hex: 0x2B2A2C), Color(hex: 0x070708)]
    )

    /// The carved set on deep cream and black marble, ruled in champagne, under a warm studio light.
    static let noir = BoardTheme(
        id: .noir,
        name: "Noir",
        symbol: "circle.lefthalf.filled",
        light: Color(hex: 0xCDBC9C),
        dark: Color(hex: 0x1E1E21),
        surface: nil,
        gridLine: nil,
        labelOnLight: Color(hex: 0x2A2722).opacity(0.8),
        labelOnDark: Color(hex: 0xE8DFCC).opacity(0.8),
        selected: Color(hex: 0x5E8FFF).opacity(0.28),
        selectedRing: nil,
        lastMove: BoardTheme.goldWash,
        lastMoveRing: nil,
        hint: Color(hex: 0x5E8FFF).opacity(0.92),
        hintGlow: nil,
        check: Color(hex: 0xD92D3F),
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
        whiteSparks: [Color.white, Color(hex: 0xF4ECDD), Color(hex: 0xE0CFA8), Color(hex: 0x8FB0FF)],
        blackSparks: [Color.white, Color(hex: 0xE0CFA8), Color(hex: 0x8FB0FF), Color(hex: 0x5E8FFF)],
        boardEdge: nil,
        boardShadows: [],
        isDark: true,
        accent: Color(hex: 0x7EA6FF),
        sculptedLook: .noir,
        boardArt: "board-noir",
        spritePieces: true,
        backdrop: [Color(hex: 0x2B2A2C), Color(hex: 0x070708)]
    )

    /// The carved set on deep cream and wine-red marble, with gold marks.
    static let bordeaux = BoardTheme(
        id: .bordeaux,
        name: "Bordeaux",
        symbol: "wineglass.fill",
        light: Color(hex: 0xCDBC9C),
        dark: Color(hex: 0x7A2530),
        surface: nil,
        gridLine: nil,
        labelOnLight: Color(hex: 0x4A1A22).opacity(0.8),
        labelOnDark: Color(hex: 0xF2E6CF).opacity(0.8),
        selected: Color(hex: 0xEBB357).opacity(0.3),
        selectedRing: nil,
        lastMove: BoardTheme.greenWash,
        lastMoveRing: nil,
        hint: Color(hex: 0xEBB357).opacity(0.92),
        hintGlow: nil,
        check: Color(hex: 0xD92D3F),
        pieceSet: "sculpted-",
        whiteGlow: nil,
        blackGlow: nil,
        whiteSide: Color(hex: 0xEDE6D8),
        blackSide: Color(hex: 0x26242A),
        whiteName: "Ivory",
        blackName: "Ebony",
        bestArrow: Color(hex: 0xEBB357).opacity(0.95),
        secondArrow: Color(hex: 0xEBB357).opacity(0.72),
        arrowGlow: nil,
        whiteSparks: [Color.white, Color(hex: 0xF4ECDD), Color(hex: 0xF2D49A), Color(hex: 0xEBB357)],
        blackSparks: [Color.white, Color(hex: 0xF2D49A), Color(hex: 0xC0505E), Color(hex: 0xEBB357)],
        boardEdge: nil,
        boardShadows: [],
        isDark: true,
        accent: Color(hex: 0xEBB357),
        sculptedLook: .bordeaux,
        boardArt: "board-bordeaux",
        spritePieces: true,
        backdrop: [Color(hex: 0x2E2426), Color(hex: 0x0A0607)]
    )

    /// The carved set on deep cream and ink-blue stone, with gold marks.
    static let midnight = BoardTheme(
        id: .midnight,
        name: "Midnight",
        symbol: "moon.stars.fill",
        light: Color(hex: 0xCDBC9C),
        dark: Color(hex: 0x2C3D6C),
        surface: nil,
        gridLine: nil,
        labelOnLight: Color(hex: 0x1E2A4A).opacity(0.8),
        labelOnDark: Color(hex: 0xE8E4D8).opacity(0.8),
        selected: Color(hex: 0xF2BD5C).opacity(0.3),
        selectedRing: nil,
        lastMove: BoardTheme.greenWash,
        lastMoveRing: nil,
        hint: Color(hex: 0xF2BD5C).opacity(0.92),
        hintGlow: nil,
        check: Color(hex: 0xD92D3F),
        pieceSet: "sculpted-",
        whiteGlow: nil,
        blackGlow: nil,
        whiteSide: Color(hex: 0xEDE6D8),
        blackSide: Color(hex: 0x26242A),
        whiteName: "Ivory",
        blackName: "Ebony",
        bestArrow: Color(hex: 0xF2BD5C).opacity(0.95),
        secondArrow: Color(hex: 0xF2BD5C).opacity(0.72),
        arrowGlow: nil,
        whiteSparks: [Color.white, Color(hex: 0xF4ECDD), Color(hex: 0xF6D592), Color(hex: 0xF2BD5C)],
        blackSparks: [Color.white, Color(hex: 0xF6D592), Color(hex: 0x6F8BD0), Color(hex: 0xF2BD5C)],
        boardEdge: nil,
        boardShadows: [],
        isDark: true,
        accent: Color(hex: 0xF2BD5C),
        sculptedLook: .midnight,
        boardArt: "board-midnight",
        spritePieces: true,
        backdrop: [Color(hex: 0x232836), Color(hex: 0x06070B)]
    )

    /// Carved ivory and ebony on grey and black marble, with platinum rings and sapphires,
    /// under an even light. In a game it is a real 3D board; small boards draw renders of the same set.
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
        lastMove: BoardTheme.goldWash,
        lastMoveRing: nil,
        hint: Color(hex: 0x5E8FFF).opacity(0.92),
        hintGlow: nil,
        check: Color(hex: 0xD92D3F),
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
        boardShadows: [],
        isDark: true,
        accent: Color(hex: 0x7EA6FF),
        sculptedLook: .classic,
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
        labelOnLight: Color(hex: 0x7D5710),
        labelOnDark: Color(hex: 0xFFF0C2),
        selected: Color(hex: 0xF6D27A).opacity(0.22),
        selectedRing: Color(hex: 0xF6D27A).opacity(0.95),
        lastMove: BoardTheme.greenWash,
        lastMoveRing: nil,
        hint: Color(hex: 0xE8BE64).opacity(0.9),
        hintGlow: nil,
        check: Color(hex: 0xD92D3F),
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
        boardShadows: [],
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
        lastMove: BoardTheme.greenWash,
        lastMoveRing: nil,
        hint: Color(hex: 0xFFC24D).opacity(0.9),
        hintGlow: nil,
        check: Color(hex: 0xD92D3F),
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
        boardShadows: [],
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
        check: Color(hex: 0xD62A5C),
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
        backdrop: [Color(hex: 0x3A2210), Color(hex: 0x0A0604)],
        lastMove: BoardTheme.greenWash
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
        whiteSparks: [Color], blackSparks: [Color], backdrop: [Color],
        lastMove: Color = BoardTheme.goldWash
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
            lastMove: lastMove,
            lastMoveRing: nil,
            hint: accent.opacity(0.9),
            hintGlow: nil,
            check: Color(hex: 0xD92D3F),
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
            boardShadows: [],
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

/// The soft lights of a look's backdrop, so the glass over it has light to bend: a dark base in
/// the look's own color, a key light from above that the top bar catches, the board's color
/// glowing behind the board, and a pool of light under the dock. Nothing in it has an edge.
struct BackdropLight {
    /// The base, top and bottom.
    let top: UInt32
    let bottom: UInt32
    let key: UInt32
    /// The board's own color, softly behind it.
    let fill: UInt32
    /// Pools under the dock.
    let floor: UInt32
    /// How bright the lights are; the saturated rival colors are a little quieter.
    var strength: Double = 1

    /// Between the base's two colors, a little nearer the bottom one.
    var middle: Color {
        func channel(_ shift: UInt32) -> UInt32 {
            let a = Double((top >> shift) & 0xFF), b = Double((bottom >> shift) & 0xFF)
            return UInt32((a + (b - a) * 0.6).rounded()) << shift
        }
        return Color(hex: channel(16) | channel(8) | channel(0))
    }
}

extension BoardTheme {
    /// Nil for Neon, which has its own glows.
    var backdropLight: BackdropLight? {
        switch id {
        case .gilded: return BackdropLight(top: 0x16120F, bottom: 0x060505, key: 0xD9A65E, fill: 0x7A4A26, floor: 0xD29A52)
        case .portoro: return BackdropLight(top: 0x232220, bottom: 0x09090A, key: 0xD2B06A, fill: 0x4A4640, floor: 0xBC9A55)
        case .classic: return BackdropLight(top: 0x1A1612, bottom: 0x070606, key: 0xD9B98A, fill: 0x553420, floor: 0xC9A06A)
        case .noir: return BackdropLight(top: 0x232224, bottom: 0x08080A, key: 0xDCCBA6, fill: 0x3E3E46, floor: 0xB9A784)
        case .sculpted: return BackdropLight(top: 0x24262A, bottom: 0x08080A, key: 0xD8CCB4, fill: 0x4A4C55, floor: 0xA9A08C)
        case .bordeaux: return BackdropLight(top: 0x2A1E21, bottom: 0x0A0607, key: 0xEBB357, fill: 0x7A2530, floor: 0xA8404E)
        case .midnight: return BackdropLight(top: 0x0F1424, bottom: 0x040509, key: 0xE8C27A, fill: 0x2E4AA0, floor: 0x5C7BE0)
        case .faberge: return BackdropLight(top: 0x0A1440, bottom: 0x030515, key: 0xE8BE64, fill: 0x2348F0, floor: 0x3A64FF)
        case .blueprint: return BackdropLight(top: 0x0F2240, bottom: 0x040A14, key: 0xCFE0F5, fill: 0x24589A, floor: 0x3D78C8)
        case .spark: return BackdropLight(top: 0x1C0F07, bottom: 0x070403, key: 0xFFB24A, fill: 0xC05A1E, floor: 0xFF8A2A)
        case .drift: return BackdropLight(top: 0x0E2329, bottom: 0x040A0B, key: 0x9FE6DC, fill: 0x1E5F66, floor: 0x7A6CC8)
        case .pulse: return BackdropLight(top: 0x08203A, bottom: 0x02060C, key: 0x7FE6FF, fill: 0x1C4FA0, floor: 0x2FA8D8, strength: 0.85)
        case .vector: return BackdropLight(top: 0x1D1036, bottom: 0x07040F, key: 0xE2D4FF, fill: 0x5A2FA0, floor: 0x9A62E8, strength: 0.9)
        case .singularity: return BackdropLight(top: 0x1B1726, bottom: 0x060509, key: 0xE8E4FF, fill: 0x54506B, floor: 0xC04A9A, strength: 0.85)
        case .neon: return nil
        }
    }
}

/// The screen behind the board: the look's softly lit backdrop, the Neon glow, or the grouped gray.
struct ThemeBackdrop: View {
    let theme: BoardTheme

    var body: some View {
        if let light = theme.backdropLight {
            LitBackdrop(light: light)
        } else if let colors = theme.backdrop {
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

/// A look's backdrop with its lights; see `BackdropLight`.
private struct LitBackdrop: View {
    let light: BackdropLight

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height
            let gain = 1.6 * light.strength
            ZStack {
                LinearGradient(stops: [
                    .init(color: Color(hex: light.top), location: 0),
                    .init(color: light.middle, location: 0.5),
                    .init(color: Color(hex: light.bottom), location: 1),
                ], startPoint: .top, endPoint: .bottom)
                // From above, a little past the top edge.
                pool(light.key, peak: 0.3 * gain, middle: 0.1 * gain, at: 0.45,
                     width: w * 1.5, height: h * 0.44, x: w / 2, y: -0.04 * h)
                // Behind the board, wider than it, so its glass frame bends the light.
                pool(light.fill, peak: 0.36 * gain, middle: 0.12 * gain, at: 0.55,
                     width: w * 1.6, height: h * 0.68, x: w / 2, y: 0.47 * h)
                // Under the dock.
                pool(light.floor, peak: 0.46 * gain, middle: 0.12 * gain, at: 0.55,
                     width: w * 1.44, height: h * 0.26, x: w / 2, y: 1.01 * h)
                // A quiet vignette.
                EllipticalGradient(stops: [
                    .init(color: .clear, location: 0.5),
                    .init(color: .black.opacity(0.42), location: 1),
                ], center: .center, startRadiusFraction: 0, endRadiusFraction: 0.5)
                .frame(width: w * 2.2, height: h * 1.6)
                .position(x: w / 2, y: h / 2)
            }
            .frame(width: w, height: h)
            .clipped()
        }
        .ignoresSafeArea()
        .accessibilityHidden(true)
    }

    /// A soft oval of light, brightest at its center and gone at its edge.
    private func pool(_ hex: UInt32, peak: Double, middle: Double, at location: CGFloat,
                      width: CGFloat, height: CGFloat, x: CGFloat, y: CGFloat) -> some View {
        let color = Color(hex: hex)
        return EllipticalGradient(stops: [
            .init(color: color.opacity(peak), location: 0),
            .init(color: color.opacity(middle), location: location),
            .init(color: color.opacity(0), location: 1),
        ], center: .center, startRadiusFraction: 0, endRadiusFraction: 0.5)
        .frame(width: width, height: height)
        .position(x: x, y: y)
    }
}

/// Dark backdrop with soft colored glows and out-of-focus lights, behind the Neon board,
/// and violet light pooling under the dock.
struct NeonBackdrop: View {
    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height
            ZStack {
                Color(hex: 0x04050D)
                RadialGradient(colors: [Color(hex: 0x14BEC8).opacity(0.24), .clear],
                               center: UnitPoint(x: 0, y: 0.18), startRadius: 0, endRadius: w * 1.0)
                RadialGradient(colors: [Color(hex: 0xC83CD2).opacity(0.24), .clear],
                               center: UnitPoint(x: 1, y: 0.78), startRadius: 0, endRadius: w * 1.1)
                EllipticalGradient(colors: [Color(hex: 0x7C4DFF).opacity(0.3), Color(hex: 0x7C4DFF).opacity(0)],
                                   center: .center, startRadiusFraction: 0, endRadiusFraction: 0.5)
                    .frame(width: w * 1.4, height: h * 0.28)
                    .position(x: w / 2, y: h)
                bokeh(Color(hex: 0x50F0E6), size: 26, x: w * 0.13, y: h * 0.15)
                bokeh(Color(hex: 0xFF5AC8), size: 18, x: w * 0.84, y: h * 0.12)
                bokeh(Color(hex: 0xA06EFF), size: 30, x: w * 0.75, y: h * 0.78)
                bokeh(Color(hex: 0xFFBE5A), size: 16, x: w * 0.18, y: h * 0.83)
            }
            .frame(width: w, height: h)
            .clipped()
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

/// The system design a look would use. Text is drawn in Geist now (Shared/AppFont.swift),
/// so this only matters to the few places that still ask for `.themed`.
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
