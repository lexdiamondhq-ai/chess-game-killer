import SwiftUI
import UIKit

/// The home's colors, taken from the board it stands on: the dark of the room, the stone's
/// warmth, the pieces' metal and the ivory of the white set. Gilded gives espresso and
/// satin gold, Midnight ink blue and gold, Bordeaux wine; so the page belongs to the board.
struct HomeTone {
    /// The room: the deepest color, behind everything.
    let canvas: Color
    /// A clock face's solid fill, for a reader who asks for less transparency.
    let smoke: Color
    /// The pool of light the board stands in.
    let pool: Color
    /// The pieces' metal: the only accent, used sparingly (the side to move, the next rung).
    let metal: Color
    /// The white pieces' ivory: the one solid button.
    let ivory: Color
    let onIvory: Color

    /// Text: warm white, then two quieter steps. The quietest still reads at small sizes.
    var ink: Color { Color(red: 0.965, green: 0.945, blue: 0.91) }
    var ink2: Color { ink.opacity(0.72) }
    var ink3: Color { ink.opacity(0.6) }
    var hairline: Color { ink.opacity(0.12) }
    /// Something happening right now, like players waiting online: a soft green, the one
    /// color that isn't the board's, kept to a dot.
    var live: Color { Color(hex: 0x7FE0A3) }

    static func of(_ look: SculptedLook) -> HomeTone {
        switch look.name {
        case "Portoro":
            return HomeTone(canvas: Color(hex: 0x0C0C0C), smoke: Color(hex: 0x171614), pool: Color(hex: 0x565554),
                            metal: Color(hex: 0xE2B577), ivory: Color(hex: 0xF4EDDF), onIvory: Color(hex: 0x15110C))
        case "Noir":
            return HomeTone(canvas: Color(hex: 0x0C0C0C), smoke: Color(hex: 0x171615), pool: Color(hex: 0x565553),
                            metal: Color(hex: 0xCFBB92), ivory: Color(hex: 0xF4EDDF), onIvory: Color(hex: 0x15110C))
        case "Bordeaux":
            return HomeTone(canvas: Color(hex: 0x12090A), smoke: Color(hex: 0x211112), pool: Color(hex: 0x774548),
                            metal: Color(hex: 0xE0B676), ivory: Color(hex: 0xF4EDDF), onIvory: Color(hex: 0x15110C))
        case "Midnight":
            return HomeTone(canvas: Color(hex: 0x090C13), smoke: Color(hex: 0x111827), pool: Color(hex: 0x455478),
                            metal: Color(hex: 0xDEB775), ivory: Color(hex: 0xF4EDDF), onIvory: Color(hex: 0x15110C))
        case "Sculpted":
            return HomeTone(canvas: Color(hex: 0x0C0C0D), smoke: Color(hex: 0x16171A), pool: Color(hex: 0x545558),
                            metal: Color(hex: 0xC9CACF), ivory: Color(hex: 0xF1F1EE), onIvory: Color(hex: 0x0E1217))
        default:
            // Gilded: espresso, brown marble and satin gold.
            return HomeTone(canvas: Color(hex: 0x100B08), smoke: Color(hex: 0x1E150F), pool: Color(hex: 0x684F40),
                            metal: Color(hex: 0xE2B577), ivory: Color(hex: 0xF4EDDF), onIvory: Color(hex: 0x15110C))
        }
    }
}

extension HomeTone {
    /// The jewel's gold, top to foot: the pieces' metal lit toward white where the light
    /// catches it, then deepening into shadow.
    var jewelLight: Color { metal.mixed(with: .white, by: 0.55) }
    var jewelDeep: Color { metal.mixed(with: .black, by: 0.42) }
}

extension Color {
    /// This color taken `amount` of the way toward `other` (0 is this color, 1 is `other`).
    func mixed(with other: UIColor, by amount: CGFloat) -> Color {
        var r1: CGFloat = 0, g1: CGFloat = 0, b1: CGFloat = 0, a1: CGFloat = 0
        var r2: CGFloat = 0, g2: CGFloat = 0, b2: CGFloat = 0, a2: CGFloat = 0
        UIColor(self).getRed(&r1, green: &g1, blue: &b1, alpha: &a1)
        other.getRed(&r2, green: &g2, blue: &b2, alpha: &a2)
        let t: CGFloat = min(max(amount, 0), 1)
        let red: CGFloat = r1 + (r2 - r1) * t
        let green: CGFloat = g1 + (g2 - g1) * t
        let blue: CGFloat = b1 + (b2 - b1) * t
        return Color(red: Double(red), green: Double(green), blue: Double(blue), opacity: Double(a1))
    }
}

/// The home's type, all Geist. It follows the reader's text size.
enum HomeType {
    /// A panel's name, like the You panel's.
    static let section = Font.app(.title2, weight: .semibold)
}

/// One set of measures for every card, so all their edges and insides line up.
enum HomeMetrics {
    /// A card's corner.
    static let cardRadius: CGFloat = 30
    /// What a card keeps between its edge and what it holds.
    static let inset: CGFloat = 16
    /// A tile's corner: a touch tighter than the board window's, so the window leads.
    static let tileRadius: CGFloat = 26
}

// MARK: - Glass

/// How a pane sits on the page.
enum HomePaneWeight {
    /// Cards with text on them.
    case card
    /// The dock and the pull-down cue, a bar over the page.
    case bar
    /// A face inside a card: a darker well, or a lit one for the side to move.
    case well(lit: Bool)
}

/// The home's glass. Cards and bars are the app's one glass (`glassPane`): Liquid Glass on
/// iOS 26, as on the game screen's bars and dock, and a frosted pane before it. A well inside
/// a card has no glass of its own, since it sits on the card's: it is a darker or lighter
/// tone with a fine edge. Opaque when the reader asks for less transparency.
struct HomePane<S: InsettableShape>: ViewModifier {
    let shape: S
    let tone: HomeTone
    var weight: HomePaneWeight = .card

    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorSchemeContrast) private var contrast

    @ViewBuilder
    func body(content: Content) -> some View {
        switch weight {
        case .well(let lit):
            content.background { well(lit: lit) }
        case .card, .bar:
            content.glassPane(shape)
        }
    }

    private func well(lit: Bool) -> some View {
        ZStack {
            if reduceTransparency {
                shape.fill(tone.smoke)
                if lit { shape.fill(tone.ink.opacity(0.1)) }
            } else {
                shape.fill(lit ? tone.ink.opacity(0.13) : tone.canvas.opacity(0.42))
                shape.fill(LinearGradient(
                    stops: [
                        .init(color: tone.ink.opacity(0.09), location: 0),
                        .init(color: tone.ink.opacity(0.015), location: 0.45),
                        .init(color: tone.ink.opacity(0.03), location: 1),
                    ],
                    startPoint: .topLeading, endPoint: .bottomTrailing
                ))
            }
            shape.strokeBorder(rim, lineWidth: contrast == .increased ? 1 : 0.75)
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private var rim: LinearGradient {
        let strong = contrast == .increased ? 0.42 : 0.16
        return LinearGradient(colors: [tone.ink.opacity(strong), tone.ink.opacity(strong * 0.25), tone.ink.opacity(strong * 0.55)],
                              startPoint: .topLeading, endPoint: .bottomTrailing)
    }
}

extension View {
    /// Sets the view on the home's glass, in `shape`.
    func homePane<S: InsettableShape>(_ shape: S, tone: HomeTone, weight: HomePaneWeight = .card) -> some View {
        modifier(HomePane(shape: shape, tone: tone, weight: weight))
    }
}

// MARK: - Buttons

/// The ivory capsule behind the one solid button, lit from above and lifted off the glass.
struct HomeIvoryFill: View {
    let tone: HomeTone

    var body: some View {
        Capsule()
            .fill(tone.ivory)
            .overlay {
                Capsule().fill(LinearGradient(colors: [.white.opacity(0.35), .clear], startPoint: .top, endPoint: .center))
            }
            .shadow(color: .black.opacity(0.25), radius: 8, y: 4)
    }
}

/// The one solid button on a card: ivory, like the white pieces, with dark type.
struct HomeIvoryButtonStyle: ButtonStyle {
    let tone: HomeTone
    var compact = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(compact ? .app(.subheadline, weight: .semibold) : .app(.headline))
            .foregroundStyle(tone.onIvory)
            .lineLimit(1)
            .minimumScaleFactor(0.85)
            .padding(.horizontal, compact ? 18 : 22)
            .frame(minHeight: compact ? 40 : 52)
            .background { HomeIvoryFill(tone: tone) }
            // A compact button still answers a finger's height (44 points) around it.
            .padding(.vertical, compact ? 2 : 0)
            .contentShape(Rectangle())
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .opacity(configuration.isPressed ? 0.9 : 1)
            .animation(.spring(response: 0.25, dampingFraction: 0.8), value: configuration.isPressed)
    }
}

/// The quiet button beside it, or the second action in a card: clear glass with a fine edge.
struct HomeGlassButtonStyle: ButtonStyle {
    let tone: HomeTone
    var compact = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(compact ? .app(.subheadline, weight: .semibold) : .app(.headline, weight: .medium))
            .foregroundStyle(tone.ink)
            .lineLimit(1)
            .minimumScaleFactor(0.85)
            .padding(.horizontal, compact ? 18 : 20)
            .frame(minHeight: compact ? 40 : 52)
            .background {
                Capsule()
                    .fill(tone.ink.opacity(configuration.isPressed ? 0.14 : 0.08))
                    .overlay { Capsule().strokeBorder(tone.ink.opacity(0.18), lineWidth: 0.75) }
            }
            // A compact button still answers a finger's height (44 points) around it.
            .padding(.vertical, compact ? 2 : 0)
            .contentShape(Rectangle())
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.spring(response: 0.25, dampingFraction: 0.8), value: configuration.isPressed)
    }
}

/// Rows and icons darken a touch while pressed, and never move.
struct HomeRowPressStyle: ButtonStyle {
    let tone: HomeTone

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(tone.ink.opacity(configuration.isPressed ? 0.07 : 0))
                    .padding(.horizontal, -8)
            }
    }
}

/// The dock's icons sink a touch while pressed.
struct HomePressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.92 : 1)
            .opacity(configuration.isPressed ? 0.75 : 1)
            .animation(.spring(response: 0.25, dampingFraction: 0.8), value: configuration.isPressed)
    }
}

// MARK: - Shared pieces

/// A row that opens one thing: a name, a line about it, and a chevron, with a glyph in
/// front only where it says something the words don't.
struct HomeLinkRow: View {
    var glyph: String? = nil
    let title: String
    let detail: String
    let tone: HomeTone
    let action: () -> Void

    @ScaledMetric(relativeTo: .body) private var iconSize: CGFloat = 26

    var body: some View {
        Button(action: action) {
            HStack(spacing: 14) {
                if let glyph {
                    Glyph(name: glyph, size: iconSize)
                        .foregroundStyle(tone.ink2)
                        .frame(width: iconSize + 6)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.app(.body, weight: .semibold))
                        .foregroundStyle(tone.ink)
                    Text(detail)
                        .font(.app(.subheadline))
                        .foregroundStyle(tone.ink2)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                Image(systemName: "chevron.forward")
                    .font(.app(.footnote, weight: .semibold))
                    .foregroundStyle(tone.ink3)
            }
            .padding(.vertical, 13)
            .frame(minHeight: 56)
            .contentShape(Rectangle())
        }
        .buttonStyle(HomeRowPressStyle(tone: tone))
        .accessibilityElement(children: .combine)
        .accessibilityLabel(title)
        .accessibilityHint(detail)
    }
}

/// A fine line between rows.
struct HomeHairline: View {
    let tone: HomeTone
    var inset: CGFloat = 0

    var body: some View {
        Rectangle()
            .fill(tone.hairline)
            .frame(height: 0.5)
            .padding(.leading, inset)
            .accessibilityHidden(true)
    }
}
