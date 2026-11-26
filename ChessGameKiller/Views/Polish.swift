import SwiftUI

// The app's finish, in one place: the gilded edge every card, bar and pane wears. Every screen
// takes its edge from here, so the whole app is polished alike (Alex, 2026-11-26: "polish up
// every single screen, make the colors pop out, highlight the borders"; picked the Rich look).

enum Polish {
    // MARK: Gold

    /// Gold where the light catches it, on a dark room and on a light one.
    static func goldCatch(dark: Bool) -> Color { dark ? Color(hex: 0xFBE6B0) : Color(hex: 0xD9A94E) }
    static func goldBase(dark: Bool) -> Color { dark ? Color(hex: 0xE8C27A) : Color(hex: 0xB7832E) }
    static func goldDeep(dark: Bool) -> Color { dark ? Color(hex: 0xA8793A) : Color(hex: 0x8A5F1E) }

    /// An edge's three tones: where the light catches it, its body, and its shade.
    struct Metal {
        let catchLight: Color
        let base: Color
        let deep: Color
    }

    /// The app's gold, or the same three tones cut from a look's own metal (Sculpted's silver,
    /// Neon's cyan), so an edge never argues with the board it frames.
    static func metal(_ own: Color?, dark: Bool) -> Metal {
        guard let own else {
            return Metal(catchLight: goldCatch(dark: dark), base: goldBase(dark: dark), deep: goldDeep(dark: dark))
        }
        return Metal(catchLight: own.mixed(with: .white, by: dark ? 0.45 : 0.2), base: own,
                     deep: own.mixed(with: .black, by: 0.3))
    }

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
        /// A well or a choice set into a card: quieter than the card around it.
        case well
    }

    /// The edge's strength where the light catches it, in its middle, and at the far corner.
    static func edgeStrength(_ edge: Edge, dark: Bool) -> (catchLight: Double, middle: Double, far: Double) {
        let scale: Double
        switch edge {
        case .card: scale = 1
        case .glass: scale = 0.8
        case .lit: scale = 1.25
        case .pill: scale = 0.9
        case .well: scale = 0.55
        }
        // Gold on a white card needs a firmer line than gold on espresso.
        let room: Double = dark ? 1 : 1.12
        return (min(1, 0.95 * scale * room), min(1, 0.32 * scale * room), min(1, 0.62 * scale * room))
    }

    static func edgeWidth(_ edge: Edge) -> CGFloat { edge == .lit ? 1.25 : 1 }

    /// The gilded edge itself: light falls from the top left, so the line is brightest there,
    /// thins through the middle, and catches again at the far corner.
    static func edgeGradient(_ edge: Edge, metal: Metal, dark: Bool) -> LinearGradient {
        let s = edgeStrength(edge, dark: dark)
        return LinearGradient(
            stops: [
                .init(color: metal.catchLight.opacity(s.catchLight), location: 0),
                .init(color: metal.base.opacity(s.middle), location: 0.38),
                .init(color: metal.deep.opacity(s.middle), location: 0.66),
                .init(color: metal.base.opacity(s.far), location: 1),
            ],
            startPoint: .topLeading, endPoint: .bottomTrailing)
    }

    /// The glow that spills past a lit edge. Only the thing that needs you glows.
    static func edgeGlow(_ edge: Edge, dark: Bool) -> Double {
        edge == .lit ? (dark ? 0.22 : 0.154) : 0
    }
}

private struct PolishMetalKey: EnvironmentKey {
    static let defaultValue: Color? = nil
}

extension EnvironmentValues {
    /// The metal this screen's edges are cut from; nil for the app's gold.
    var polishMetal: Color? {
        get { self[PolishMetalKey.self] }
        set { self[PolishMetalKey.self] = newValue }
    }
}

extension BoardTheme {
    /// The metal this look's edges are cut from: nil for the app's gold, which every warm look
    /// wears; its own on the looks whose metal is not gold.
    var polishMetal: Color? {
        switch id {
        case .sculpted, .neon, .spark, .drift, .pulse, .vector, .singularity: return trainingAccent
        default: return nil
        }
    }
}

/// A shape's gilded edge (see `Polish`).
struct PolishedEdge<S: InsettableShape>: View {
    let shape: S
    var edge: Polish.Edge = .card
    /// The room's light or dark; the environment's when nil.
    var dark: Bool? = nil

    @Environment(\.colorScheme) private var scheme
    @Environment(\.polishMetal) private var ownMetal

    var body: some View {
        let isDark: Bool = dark ?? (scheme == .dark)
        let metal: Polish.Metal = Polish.metal(ownMetal, dark: isDark)
        let glow: Double = Polish.edgeGlow(edge, dark: isDark)
        ZStack {
            if glow > 0 {
                shape.stroke(metal.base.opacity(glow), lineWidth: 3)
                    .blur(radius: 7)
            }
            if isDark {
                // A second, fainter line just inside: the bevel under the gilding.
                shape.inset(by: 1).strokeBorder(Color.white.opacity(0.05), lineWidth: 0.6)
            }
            shape.strokeBorder(Polish.edgeGradient(edge, metal: metal, dark: isDark), lineWidth: Polish.edgeWidth(edge))
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
