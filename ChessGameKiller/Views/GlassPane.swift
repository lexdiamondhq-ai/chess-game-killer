import SwiftUI

// The app's one glass. The board's frame, the top bar, the player lines, the dock and the cards
// all sit on it, so every screen reads as one piece of polished glass over the same lit backdrop.

/// How much the glass frosts what is behind it.
enum GlassWeight {
    /// Nearly clear, for glass over a picture: the board's frame, a card over the board.
    case clear
    /// Frosted, for chrome over the backdrop: bars, player lines, cards with text on them.
    case regular
}

/// Puts the view on the app's glass: Liquid Glass on iOS 26, the same glass the top bar's buttons
/// sit on, and before it a frosted pane with a soft sheen and a bright polished edge, so it reads
/// as glass and never as a grey box.
struct GlassPane<S: InsettableShape>: ViewModifier {
    let shape: S
    /// A faint color in the glass, such as the side to move or a selected card.
    var tint: Color?
    var weight: GlassWeight = .regular

    @ViewBuilder
    func body(content: Content) -> some View {
        #if compiler(>=6.2)
        if #available(iOS 26.0, *) {
            // Glass on the view itself, as the system does it, so what sits on it reads well.
            content.glassEffect(GlassSurface<S>.liquidGlass(weight: weight, tint: tint), in: shape)
        } else {
            content.background { GlassSurface(shape: shape, tint: tint, weight: weight) }
        }
        #else
        content.background { GlassSurface(shape: shape, tint: tint, weight: weight) }
        #endif
    }
}

/// The glass itself, for use as a background.
struct GlassSurface<S: InsettableShape>: View {
    let shape: S
    var tint: Color?
    var weight: GlassWeight = .regular

    var body: some View {
        pane
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }

    @ViewBuilder
    private var pane: some View {
        #if compiler(>=6.2)
        if #available(iOS 26.0, *) {
            // Liquid Glass brings its own light, edge and shadow; nothing is drawn over it.
            Color.clear.glassEffect(Self.liquidGlass(weight: weight, tint: tint), in: shape)
        } else {
            fallback
        }
        #else
        fallback
        #endif
    }

    #if compiler(>=6.2)
    @available(iOS 26.0, *)
    static func liquidGlass(weight: GlassWeight, tint: Color?) -> Glass {
        let glass: Glass = weight == .clear ? .clear : .regular
        guard let tint else { return glass }
        return glass.tint(tint.opacity(0.3))
    }
    #endif

    /// Before iOS 26: a frosted pane, a little darkened so light text stays crisp on it,
    /// with light falling across it from the top left and a polished edge.
    private var fallback: some View {
        ZStack {
            if weight == .regular {
                // A soft shadow under the pane lifts it off the backdrop. It is drawn beside the
                // frost, not around it, so the frost still sees the backdrop's light.
                shape.fill(Color.black.opacity(0.2))
                    .blur(radius: 9)
                    .offset(y: 4)
            }
            shape.fill(weight == .clear ? AnyShapeStyle(Material.ultraThinMaterial.opacity(0.6))
                                        : AnyShapeStyle(Material.ultraThinMaterial))
            shape.fill(Color.black.opacity(weight == .clear ? 0.05 : 0.2))
            if let tint {
                shape.fill(tint.opacity(0.14))
            }
            shape.fill(LinearGradient(
                stops: [
                    .init(color: .white.opacity(weight == .clear ? 0.16 : 0.1), location: 0),
                    .init(color: .white.opacity(0.02), location: 0.45),
                    .init(color: .white.opacity(0.05), location: 1),
                ],
                startPoint: .topLeading, endPoint: .bottomTrailing
            ))
            // Brightest where the light falls.
            shape.strokeBorder(
                LinearGradient(colors: [.white.opacity(0.4), .white.opacity(0.08), .white.opacity(0.2)],
                               startPoint: .topLeading, endPoint: .bottomTrailing),
                lineWidth: 0.9
            )
        }
    }
}

extension View {
    /// Sets the view on the app's glass, in `shape`. `tint` colors the glass faintly.
    func glassPane<S: InsettableShape>(_ shape: S, tint: Color? = nil, weight: GlassWeight = .regular) -> some View {
        modifier(GlassPane(shape: shape, tint: tint, weight: weight))
    }
}
