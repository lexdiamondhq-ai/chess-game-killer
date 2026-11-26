import SwiftUI

// The app's finish, in one place: how brightly an edge catches the light, how rich the gold
// and the jewel colors run, and how firmly the quiet text reads. Every screen takes its edges
// and accents from here, so the whole app is polished alike (Alex, 2026-11-26: "polish up
// every single screen, make the colors pop out, highlight the borders").

enum Polish {
    /// How far the finish goes. `off` is the app as it was.
    enum Level: Int, Comparable {
        case off = 0, gentle, rich, bold

        static func < (a: Level, b: Level) -> Bool { a.rawValue < b.rawValue }

        init?(name: String) {
            switch name.lowercased() {
            case "off", "0", "none": self = .off
            case "gentle", "a", "1": self = .gentle
            case "rich", "b", "2": self = .rich
            case "bold", "c", "3": self = .bold
            default: return nil
            }
        }
    }

    /// PREVIEW ONLY: the three looks side by side, picked with `-polish rich` at launch or
    /// SNAPSHOT_POLISH in the tests. Once Alex picks one, this becomes a constant.
    static let level: Level = {
        if let asked = ProcessInfo.processInfo.environment["SNAPSHOT_POLISH"].flatMap(Level.init(name:)) { return asked }
        if let asked = UserDefaults.standard.string(forKey: "polish").flatMap(Level.init(name:)) { return asked }
        return .off
    }()

    /// One value per level: off, gentle, rich, bold.
    static func choose<T>(_ off: T, _ gentle: T, _ rich: T, _ bold: T) -> T {
        switch level {
        case .off: return off
        case .gentle: return gentle
        case .rich: return rich
        case .bold: return bold
        }
    }

    // Plain types for each use, so a long SwiftUI expression never has to guess one.
    /// A strength, 0 to 1.
    static func pick(_ off: Double, _ gentle: Double, _ rich: Double, _ bold: Double) -> Double {
        choose(off, gentle, rich, bold)
    }

    /// A measure in points.
    static func size(_ off: CGFloat, _ gentle: CGFloat, _ rich: CGFloat, _ bold: CGFloat) -> CGFloat {
        choose(off, gentle, rich, bold)
    }

    /// A color as 0xRRGGBB.
    static func hex(_ off: UInt32, _ gentle: UInt32, _ rich: UInt32, _ bold: UInt32) -> UInt32 {
        choose(off, gentle, rich, bold)
    }

    // MARK: Gold

    /// Gold where the light catches it, on a dark room and on a light one.
    static func goldCatch(dark: Bool) -> Color { dark ? Color(hex: 0xFBE6B0) : Color(hex: 0xD9A94E) }
    static func goldBase(dark: Bool) -> Color { dark ? Color(hex: 0xE8C27A) : Color(hex: 0xB7832E) }
    static func goldDeep(dark: Bool) -> Color { dark ? Color(hex: 0xA8793A) : Color(hex: 0x8A5F1E) }

    /// What an edge is for.
    enum Edge {
        /// A card or a row at rest.
        case card
        /// A pane of the app's glass: a bar, the dock, a glass card.
        case glass
        /// The one thing to look at: your move, the card in front, a selected choice.
        case lit
        /// A small pill or chip.
        case pill
    }

    /// The edge's strength where the light catches it, in its middle, and at the far corner.
    static func edgeStrength(_ edge: Edge, dark: Bool) -> (catchLight: Double, middle: Double, far: Double) {
        let base: (Double, Double, Double) = choose((0, 0, 0), (0.6, 0.2, 0.36), (0.95, 0.32, 0.62), (1, 0.55, 0.85))
        let scale: Double
        switch edge {
        case .card: scale = 1
        case .glass: scale = 0.8
        case .lit: scale = 1.25
        case .pill: scale = 0.9
        }
        // Gold on a white card needs a firmer line than gold on espresso.
        let room: Double = dark ? 1 : 1.12
        return (min(1, base.0 * scale * room), min(1, base.1 * scale * room), min(1, base.2 * scale * room))
    }

    static func edgeWidth(_ edge: Edge) -> CGFloat {
        let width: CGFloat = size(1, 1, 1, 1.4)
        return edge == .lit ? width + size(0, 0, 0.25, 0.4) : width
    }

    /// The gilded edge itself: light falls from the top left, so the line is brightest there,
    /// thins through the middle, and catches again at the far corner.
    static func edgeGradient(_ edge: Edge, dark: Bool) -> LinearGradient {
        let s = edgeStrength(edge, dark: dark)
        return LinearGradient(
            stops: [
                .init(color: goldCatch(dark: dark).opacity(s.catchLight), location: 0),
                .init(color: goldBase(dark: dark).opacity(s.middle), location: 0.38),
                .init(color: goldDeep(dark: dark).opacity(s.middle), location: 0.66),
                .init(color: goldBase(dark: dark).opacity(s.far), location: 1),
            ],
            startPoint: .topLeading, endPoint: .bottomTrailing)
    }

    /// The glow that spills past a lit edge, and past every card's on Bold.
    static func edgeGlow(_ edge: Edge, dark: Bool) -> Double {
        switch edge {
        case .lit: return pick(0, 0, 0.22, 0.38) * (dark ? 1 : 0.7)
        case .card, .glass: return pick(0, 0, 0, 0.16) * (dark ? 1 : 0.6)
        case .pill: return 0
        }
    }
}

/// A shape's gilded edge (see `Polish`). Draws nothing while the polish is off, so a screen
/// that keeps its own old line can show it instead.
struct PolishedEdge<S: InsettableShape>: View {
    let shape: S
    var edge: Polish.Edge = .card
    /// The room's light or dark; the environment's when nil.
    var dark: Bool? = nil

    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let isDark: Bool = dark ?? (scheme == .dark)
        let glow: Double = Polish.edgeGlow(edge, dark: isDark)
        ZStack {
            if glow > 0 {
                shape.stroke(Polish.goldBase(dark: isDark).opacity(glow), lineWidth: 3)
                    .blur(radius: 7)
            }
            if Polish.level >= .rich, isDark {
                // A second, fainter line just inside: the bevel under the gilding.
                shape.inset(by: 1).strokeBorder(Color.white.opacity(Polish.pick(0, 0, 0.05, 0.08)), lineWidth: 0.6)
            }
            shape.strokeBorder(Polish.edgeGradient(edge, dark: isDark), lineWidth: Polish.edgeWidth(edge))
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

extension View {
    /// Lays the gilded edge over the view, in `shape`.
    func polishedEdge<S: InsettableShape>(_ shape: S, _ edge: Polish.Edge = .card, dark: Bool? = nil) -> some View {
        overlay { PolishedEdge(shape: shape, edge: edge, dark: dark) }
    }
}
