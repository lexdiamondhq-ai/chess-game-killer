import SwiftUI

/// The home screen's colors: near-black, warm charcoal cards and one amber accent.
/// Kept apart from the board themes, so the home looks the same whichever board is picked.
enum HomePalette {
    static let background = Color(red: 0.055, green: 0.055, blue: 0.055)
    static let card = Color(red: 0.118, green: 0.110, blue: 0.114)
    static let cardRaised = Color(red: 0.149, green: 0.141, blue: 0.141)
    static let stroke = Color.white.opacity(0.07)
    static let amber = Color(red: 0.996, green: 0.678, blue: 0.078)
    static let amberDeep = Color(red: 0.384, green: 0.267, blue: 0.090)
    static let amberGlow = Color(red: 0.996, green: 0.678, blue: 0.078).opacity(0.16)
    static let text = Color(red: 0.96, green: 0.95, blue: 0.93)
    static let secondary = Color(red: 0.62, green: 0.60, blue: 0.58)
    static let tertiary = Color(red: 0.42, green: 0.41, blue: 0.40)
    static let live = Color(red: 0.93, green: 0.22, blue: 0.20)

    static let cardRadius: CGFloat = 26
    static let gutter: CGFloat = 16
}

/// A home card: warm charcoal, a hairline edge and big round corners.
struct HomeCard<Content: View>: View {
    var padding: CGFloat = 18
    @ViewBuilder let content: () -> Content

    var body: some View {
        content()
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(HomePalette.card, in: RoundedRectangle(cornerRadius: HomePalette.cardRadius, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: HomePalette.cardRadius, style: .continuous)
                    .strokeBorder(HomePalette.stroke, lineWidth: 1)
            }
    }
}

/// The amber outline button inside a card: "Start today's session ›".
struct HomeOutlineButton: View {
    let title: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Text(title)
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .heavy))
            }
            .font(.system(size: 16, weight: .bold))
            .foregroundStyle(HomePalette.amber)
            .frame(maxWidth: .infinity)
            .frame(height: 48)
            .background(HomePalette.amberGlow.opacity(0.35), in: Capsule())
            .overlay { Capsule().strokeBorder(HomePalette.amber.opacity(0.55), lineWidth: 1.2) }
        }
        .buttonStyle(HomePressStyle())
    }
}

/// Cards and buttons sink a touch while pressed.
struct HomePressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.975 : 1)
            .opacity(configuration.isPressed ? 0.9 : 1)
            .animation(.spring(response: 0.25, dampingFraction: 0.8), value: configuration.isPressed)
    }
}

/// A round amber badge holding an SF Symbol, the icon at the head of a card.
struct HomeIconBadge: View {
    let symbol: String
    var size: CGFloat = 40

    var body: some View {
        Glyph(name: symbol, size: Glyph.isGlyph(symbol) ? size * 0.56 : size * 0.54, weight: .bold)
            .foregroundStyle(HomePalette.amber)
            .frame(width: size, height: size)
            .background(HomePalette.amberDeep.opacity(0.55), in: Circle())
            .overlay { Circle().strokeBorder(HomePalette.amber.opacity(0.25), lineWidth: 1) }
    }
}

/// Frosted glass: the real Liquid Glass on iOS 26, a dark material before it.
struct HomeGlass<S: Shape>: ViewModifier {
    let shape: S

    func body(content: Content) -> some View {
        #if compiler(>=6.2)
        if #available(iOS 26.0, *) {
            content.glassEffect(.regular, in: shape)
        } else {
            fallback(content)
        }
        #else
        fallback(content)
        #endif
    }

    private func fallback(_ content: Content) -> some View {
        content
            .background(.ultraThinMaterial, in: shape)
            .background(Color.black.opacity(0.25), in: shape)
            .overlay { shape.stroke(Color.white.opacity(0.14), lineWidth: 0.8) }
    }
}

extension View {
    func homeGlass<S: Shape>(_ shape: S) -> some View {
        modifier(HomeGlass(shape: shape))
    }
}
