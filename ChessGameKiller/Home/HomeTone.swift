import SwiftUI

/// The home's colors, taken from the board it stands on: the dark of the room, the stone's
/// warmth, the pieces' metal and the ivory of the white set. Gilded gives espresso and
/// satin gold, Midnight ink blue and gold, Bordeaux wine; so the page belongs to the board.
struct HomeTone {
    /// The room: the deepest color, behind everything.
    let canvas: Color
    /// Smoked glass: the fill of panes and the clock's faces.
    let smoke: Color
    /// The pool of light the board stands in.
    let pool: Color
    /// The pieces' metal: the only accent, used sparingly (the side to move, the next rung).
    let metal: Color
    /// The white pieces' ivory: the one solid button.
    let ivory: Color
    let onIvory: Color

    /// Text: warm white, then two quieter steps.
    var ink: Color { Color(red: 0.965, green: 0.945, blue: 0.91) }
    var ink2: Color { ink.opacity(0.7) }
    var ink3: Color { ink.opacity(0.5) }
    var hairline: Color { ink.opacity(0.12) }

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

/// The home's type: New York for what you read as a title or a number on a scoresheet,
/// SF Pro for everything you tap. All of it follows the reader's text size.
enum HomeType {
    static let section = Font.system(.title2, design: .serif, weight: .medium)
    static let title = Font.system(.title3, design: .serif, weight: .medium)
    static let score = Font.system(.body, design: .serif, weight: .medium)
    static let number = Font.system(.title2, design: .serif, weight: .regular)
}

// MARK: - Glass

/// How much a pane holds back what is behind it.
enum HomePaneWeight {
    /// Cards with text: smoked enough that light text reads over anything.
    case card
    /// The dock and the clock capsule: lighter, a bar over the page.
    case bar
    /// A face inside a card: a darker well, or a lit one for the side to move.
    case well(lit: Bool)
}

/// The home's glass: Liquid Glass on iOS 26 (a frosted pane before it), smoked with the
/// room's color so text stays crisp over the bright pieces, a soft light falling from the top
/// left and a fine polished edge. Opaque when the reader asks for less transparency.
struct HomePane<S: InsettableShape>: ViewModifier {
    let shape: S
    let tone: HomeTone
    var weight: HomePaneWeight = .card

    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorSchemeContrast) private var contrast

    func body(content: Content) -> some View {
        content.background { surface }
    }

    private var smoke: Double {
        switch weight {
        case .card: return 0.5
        case .bar: return 0.34
        case .well(let lit): return lit ? 0.1 : 0.42
        }
    }

    @ViewBuilder
    private var surface: some View {
        ZStack {
            if reduceTransparency {
                shape.fill(tone.smoke)
                if isLitWell { shape.fill(tone.ink.opacity(0.1)) }
            } else {
                switch weight {
                case .well(let lit):
                    // A well needs no glass of its own: it sits on the card's.
                    shape.fill(lit ? tone.ink.opacity(0.13) : tone.canvas.opacity(smoke))
                default:
                    glass
                    shape.fill(tone.canvas.opacity(smoke))
                }
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
        .compositingGroup()
        .shadow(color: .black.opacity(isWell ? 0 : 0.32), radius: 18, y: 10)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private var isWell: Bool {
        if case .well = weight { return true }
        return false
    }

    private var isLitWell: Bool {
        if case .well(let lit) = weight { return lit }
        return false
    }

    private var rim: LinearGradient {
        let strong = contrast == .increased ? 0.42 : (isWell ? 0.16 : 0.26)
        return LinearGradient(colors: [tone.ink.opacity(strong), tone.ink.opacity(strong * 0.25), tone.ink.opacity(strong * 0.55)],
                              startPoint: .topLeading, endPoint: .bottomTrailing)
    }

    @ViewBuilder
    private var glass: some View {
        #if compiler(>=6.2)
        if #available(iOS 26.0, *) {
            Color.clear.glassEffect(.regular, in: shape)
        } else {
            shape.fill(.ultraThinMaterial)
        }
        #else
        shape.fill(.ultraThinMaterial)
        #endif
    }
}

extension View {
    /// Sets the view on the home's glass, in `shape`.
    func homePane<S: InsettableShape>(_ shape: S, tone: HomeTone, weight: HomePaneWeight = .card) -> some View {
        modifier(HomePane(shape: shape, tone: tone, weight: weight))
    }
}

// MARK: - Buttons

/// The one solid button on a card: ivory, like the white pieces, with dark type.
struct HomeIvoryButtonStyle: ButtonStyle {
    let tone: HomeTone
    var compact = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(compact ? .subheadline.weight(.semibold) : .headline)
            .foregroundStyle(tone.onIvory)
            .lineLimit(1)
            .minimumScaleFactor(0.85)
            .padding(.horizontal, compact ? 18 : 22)
            .frame(minHeight: compact ? 40 : 52)
            .background {
                Capsule()
                    .fill(tone.ivory)
                    .overlay {
                        Capsule().fill(LinearGradient(colors: [.white.opacity(0.35), .clear], startPoint: .top, endPoint: .center))
                    }
                    .shadow(color: .black.opacity(0.25), radius: 8, y: 4)
            }
            .contentShape(Capsule())
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .opacity(configuration.isPressed ? 0.9 : 1)
            .animation(.spring(response: 0.25, dampingFraction: 0.8), value: configuration.isPressed)
            // A compact button still answers a finger's width around it.
            .padding(.vertical, compact ? 2 : 0)
    }
}

/// The quiet button beside it: clear glass with a fine edge.
struct HomeGlassButtonStyle: ButtonStyle {
    let tone: HomeTone

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline.weight(.medium))
            .foregroundStyle(tone.ink)
            .lineLimit(1)
            .minimumScaleFactor(0.85)
            .padding(.horizontal, 20)
            .frame(minHeight: 52)
            .background {
                Capsule()
                    .fill(tone.ink.opacity(configuration.isPressed ? 0.14 : 0.08))
                    .overlay { Capsule().strokeBorder(tone.ink.opacity(0.18), lineWidth: 0.75) }
            }
            .contentShape(Capsule())
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

/// A section's name in New York, with a quiet note or a link on the right.
struct HomeSectionHeader: View {
    let title: String
    let tone: HomeTone
    var note: String? = nil
    var link: String? = nil
    var action: (() -> Void)? = nil

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(title)
                .font(HomeType.section)
                .foregroundStyle(tone.ink)
                .accessibilityAddTraits(.isHeader)
            Spacer(minLength: 0)
            if let link, let action {
                Button(action: action) {
                    HStack(spacing: 3) {
                        Text(link)
                        Image(systemName: "chevron.forward")
                            .font(.caption.weight(.semibold))
                    }
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(tone.metal)
                    .frame(minHeight: 44)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            } else if let note {
                Text(note)
                    .font(.subheadline)
                    .foregroundStyle(tone.ink2)
                    .multilineTextAlignment(.trailing)
            }
        }
        .padding(.horizontal, 6)
        .padding(.top, 30)
        .padding(.bottom, 8)
    }
}

/// A row that opens one thing: a chess glyph, a name, a line about it, and a chevron.
struct HomeLinkRow: View {
    let glyph: String
    let title: String
    let detail: String
    let tone: HomeTone
    let action: () -> Void

    @ScaledMetric(relativeTo: .body) private var iconSize: CGFloat = 26

    var body: some View {
        Button(action: action) {
            HStack(spacing: 14) {
                Glyph(name: glyph, size: iconSize)
                    .foregroundStyle(tone.metal)
                    .frame(width: iconSize + 6)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.body.weight(.semibold))
                        .foregroundStyle(tone.ink)
                    Text(detail)
                        .font(.subheadline)
                        .foregroundStyle(tone.ink2)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                Image(systemName: "chevron.forward")
                    .font(.footnote.weight(.semibold))
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
