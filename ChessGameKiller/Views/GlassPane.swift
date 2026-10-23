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

/// Puts the view on the app's glass: Liquid Glass on iOS 26, and before it a frosted pane with a
/// soft sheen and a bright polished edge, so it reads as glass and never as a grey box.
struct GlassPane<S: InsettableShape>: ViewModifier {
    let shape: S
    /// A faint color in the glass, such as the side to move or a selected card.
    var tint: Color?
    var weight: GlassWeight = .regular

    func body(content: Content) -> some View {
        content
            .background { GlassSurface(shape: shape, tint: tint, weight: weight) }
    }
}

/// The glass itself, for use as a background.
struct GlassSurface<S: InsettableShape>: View {
    let shape: S
    var tint: Color?
    var weight: GlassWeight = .regular

    var body: some View {
        ZStack {
            pane
            // Light falls across from the top left, as on the board's frame.
            shape.fill(LinearGradient(
                stops: [
                    .init(color: .white.opacity(weight == .clear ? 0.16 : 0.12), location: 0),
                    .init(color: .white.opacity(0.03), location: 0.45),
                    .init(color: .white.opacity(0.06), location: 1),
                ],
                startPoint: .topLeading, endPoint: .bottomTrailing
            ))
            if let tint {
                shape.fill(tint.opacity(0.14))
            }
            // A bright polished edge, brightest where the light falls.
            shape.strokeBorder(
                LinearGradient(colors: [.white.opacity(0.42), .white.opacity(0.08), .white.opacity(0.22)],
                               startPoint: .topLeading, endPoint: .bottomTrailing),
                lineWidth: 0.9
            )
        }
        .compositingGroup()
        .shadow(color: .black.opacity(0.28), radius: 14, y: 6)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    @ViewBuilder
    private var pane: some View {
        #if compiler(>=6.2)
        if #available(iOS 26.0, *) {
            Color.clear.glassEffect(weight == .clear ? .clear : .regular, in: shape)
        } else {
            fallback
        }
        #else
        fallback
        #endif
    }

    /// Before iOS 26: a frosted pane, a little darkened so light text stays crisp on it.
    private var fallback: some View {
        ZStack {
            shape.fill(weight == .clear ? AnyShapeStyle(.ultraThinMaterial.opacity(0.6)) : AnyShapeStyle(.ultraThinMaterial))
            shape.fill(Color.black.opacity(weight == .clear ? 0.05 : 0.18))
        }
    }
}

extension View {
    /// Sets the view on the app's glass, in `shape`. `tint` colors the glass faintly.
    func glassPane<S: InsettableShape>(_ shape: S, tint: Color? = nil, weight: GlassWeight = .regular) -> some View {
        modifier(GlassPane(shape: shape, tint: tint, weight: weight))
    }
}
