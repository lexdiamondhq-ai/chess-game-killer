import SwiftUI
import UIKit

// The app's design language beyond Home, in one place (Alex, 2026-11-27: "go through all of the
// designs in the app to make them stick out a little bit better"). Home already spoke it: a
// serif for every name and heading, gold for the one thing to do, a jewel tile for a door, and
// a carved gold label over each group. These are the same four things for every other screen,
// so the whole app reads as Home does. `Polish` is the finish on the edges; this is the voice.

// MARK: - Type

extension Font {
    /// The display face: the serif of Home's headings ("Next game", "The Cub"). For a screen's
    /// title, a card's headline and the name of a thing (a door, a lesson, a rival). Buttons,
    /// labels, numbers and running text stay in Geist (`Font.app`).
    static func display(_ style: Font.TextStyle, weight: Font.Weight = .medium) -> Font {
        .system(style, design: .serif, weight: weight)
    }

    /// The display face at a fixed size, for a title drawn to fit a shape.
    static func display(size: CGFloat, weight: Font.Weight = .medium) -> Font {
        .system(size: size, weight: weight, design: .serif)
    }

    /// The carved face (Cinzel), for a few letters in capitals: a group's label, a room's name.
    static func carved(_ size: CGFloat, relativeTo style: Font.TextStyle = .caption) -> Font {
        .custom("Cinzel-Bold", size: size, relativeTo: style)
    }
}

/// The system's own bars, dressed in the display face, so "Learn", "Settings" and every page
/// title are set like Home's headings and not in the system's sans.
enum DesignChrome {
    /// Called once as the app starts, before any bar is made.
    static func dressBars() {
        let bar = UINavigationBar.appearance()
        bar.largeTitleTextAttributes = [.font: serif(34, weight: .medium, style: .largeTitle)]
        bar.titleTextAttributes = [.font: serif(18, weight: .semibold, style: .headline)]
    }

    /// The system's serif, following the reader's text size.
    static func serif(_ size: CGFloat, weight: UIFont.Weight, style: UIFont.TextStyle) -> UIFont {
        let base = UIFont.systemFont(ofSize: size, weight: weight)
        guard let descriptor = base.fontDescriptor.withDesign(.serif) else { return base }
        let font = UIFont(descriptor: descriptor, size: size)
        return UIFontMetrics(forTextStyle: style).scaledFont(for: font, maximumPointSize: size * 1.5)
    }
}

// MARK: - The main button

extension Polish {
    /// Ink on the solid metal of a main button: deep espresso, as on Home's gold Play.
    static let onMetal = Color(hex: 0x2A1E0F)

    /// A main button's metal, top to foot, and its rim: Home's gold, or the same cut from a
    /// look's own metal (Sculpted's silver).
    static func buttonMetal(_ own: Color?) -> (top: Color, foot: Color, rim: Color) {
        guard let own else {
            return (Color(hex: 0xF6DEA3), Color(hex: 0xC99B4E), Color(hex: 0x9C6B2C))
        }
        return (own.mixed(with: .white, by: 0.6), own.mixed(with: .white, by: 0.08), own.mixed(with: .black, by: 0.3))
    }
}

/// The solid metal behind a screen's one main button: gold lit from above, a bright upper lip,
/// a deeper rim at the foot and a warm glow under it. The same gold as Home's Play, the
/// rivals' "Face the Cub" and the Dungeon's "Enter the cell", so the thing to do next is gold
/// on every screen.
struct PolishedFill<S: InsettableShape>: View {
    let shape: S
    /// Dimmed, for a button that can't be pressed yet.
    var quiet = false

    @Environment(\.colorScheme) private var scheme
    @Environment(\.polishMetal) private var ownMetal

    var body: some View {
        let metal = Polish.buttonMetal(ownMetal)
        let lightRoom: Bool = scheme != .dark
        // In a dark room the upper lip is a line of light. On cream, light on light is no line
        // at all, so the lip is the edge's own gold there: one clean edge, lit by the sheen.
        let lip: Color = lightRoom ? Polish.metal(ownMetal, dark: false).catchLight.opacity(0.9)
                                   : Color.white.opacity(0.6)
        let glow: Double = quiet ? 0 : (lightRoom ? 0.26 : 0.3)
        shape
            .fill(LinearGradient(colors: [metal.top, metal.foot], startPoint: .top, endPoint: .bottom))
            .overlay {
                shape.fill(LinearGradient(colors: [Color.white.opacity(0.3), Color.white.opacity(0)],
                                          startPoint: .top, endPoint: .center))
            }
            .overlay {
                shape.strokeBorder(LinearGradient(colors: [lip, metal.rim.opacity(0.85)],
                                                  startPoint: .top, endPoint: .bottom),
                                   lineWidth: 1)
            }
            // On cream the glow falls under the button, not around it.
            .shadow(color: metal.foot.opacity(glow), radius: lightRoom ? 8 : 10, y: lightRoom ? 5 : 4)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }
}

/// The fill of a small capsule that is a card's own main action ("Take it back", "Done", "Play"):
/// the main button's gold on a gold look, and the look's own fill on any other.
struct MainPillFill<Plain: ShapeStyle>: View {
    let gilded: Bool
    let plain: Plain

    var body: some View {
        if gilded {
            PolishedFill(shape: Capsule(), quiet: true)
        } else {
            Capsule().fill(plain)
        }
    }
}

extension Polish {
    /// Ink on a small main capsule: espresso on the gold, the page's own color on a plain fill.
    static func pillInk(gilded: Bool) -> AnyShapeStyle {
        gilded ? AnyShapeStyle(onMetal) : AnyShapeStyle(.background)
    }
}

// MARK: - A choice of two or three

/// Two or three choices side by side ("Rated / Puzzle Rush"): a glass capsule with the chosen
/// one cut from the small gold capsule, the same family as the Tilted / Flat switch. It stands
/// in for the system's grey segmented control on the gold pages.
struct GildedSegments<Value: Hashable>: View {
    /// What the choice is, for VoiceOver ("Mode").
    let title: String
    @Binding var selection: Value
    let options: [(value: Value, label: String)]
    let theme: BoardTheme

    @Namespace private var marker

    var body: some View {
        let gilded: Bool = theme.screenTone != nil
        let accent: Color = theme.trainingAccent
        HStack(spacing: 0) {
            ForEach(options.indices, id: \.self) { index in
                let option = options[index]
                let isOn: Bool = option.value == selection
                Button {
                    withAnimation(.snappy(duration: 0.2)) { selection = option.value }
                } label: {
                    Text(option.label)
                        .font(.app(.subheadline, weight: .semibold))
                        .foregroundStyle(isOn ? (gilded ? AnyShapeStyle(Polish.onMetal) : AnyShapeStyle(Color.primary))
                                              : AnyShapeStyle(Color.quietInk))
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                        .padding(.horizontal, 10)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background {
                            if isOn {
                                Group {
                                    if gilded {
                                        PolishedFill(shape: Capsule(), quiet: true)
                                    } else {
                                        Capsule()
                                            .fill(accent.opacity(0.22))
                                            .overlay { Capsule().strokeBorder(accent.opacity(0.5), lineWidth: 0.75) }
                                    }
                                }
                                .matchedGeometryEffect(id: "on", in: marker)
                            }
                        }
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(isOn ? .isSelected : [])
            }
        }
        // As tall as the system's own two-way switch, so swapping one for the other moves nothing.
        .padding(2)
        .frame(height: 32)
        .glassPane(Capsule())
        .accessibilityElement(children: .contain)
        .accessibilityLabel(title)
    }
}

// MARK: - Labels

/// A group's label: a few carved gold capitals and a fine gold rule running off to the right,
/// as the castle's rooms head theirs. It gives a page its structure at a glance.
struct SectionLabel: View {
    let text: String
    /// A quiet note at the far end of the rule ("1 of 3 right").
    var note: String? = nil

    @Environment(\.colorScheme) private var scheme
    @Environment(\.polishMetal) private var ownMetal

    var body: some View {
        let dark: Bool = scheme == .dark
        let metal: Polish.Metal = Polish.metal(ownMetal, dark: dark)
        HStack(spacing: 10) {
            Text(text.uppercased())
                .font(.carved(12))
                .tracking(1.6)
                .foregroundStyle(dark ? metal.base : metal.deep)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
                .layoutPriority(1)
                .accessibilityAddTraits(.isHeader)
            Rectangle()
                .fill(LinearGradient(colors: [metal.base.opacity(dark ? 0.5 : 0.6), metal.base.opacity(0)],
                                     startPoint: .leading, endPoint: .trailing))
                .frame(minWidth: 8, maxWidth: .infinity)
                .frame(height: 1)
                .accessibilityHidden(true)
            if let note {
                Text(note)
                    .font(.app(.caption, weight: .medium))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
    }
}

extension Color {
    /// Quiet running text that sits on the page itself, not on a card: the page's ink at 62%.
    /// The system's secondary is a cool grey there, and too pale on cream.
    static let quietInk = Color.primary.opacity(0.62)
    /// A footnote: one step quieter, and still easy to read (the system's tertiary is not).
    static let faintInk = Color.primary.opacity(0.55)

    /// A color with a value for a light room and one for a dark room, for a palette that has
    /// no theme in hand. It follows the screen it is drawn on.
    static func ink(light: UInt32, dark: UInt32) -> Color {
        Color(UIColor { traits in
            let hex: UInt32 = traits.userInterfaceStyle == .dark ? dark : light
            return UIColor(red: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
                           blue: CGFloat(hex & 0xFF) / 255, alpha: 1)
        })
    }
}

/// The colors that mean something (right, wrong, careful, a hint), cut from the same stones as
/// the jewel tiles: deep on cream so they read as words, lit but never neon on espresso, so
/// gold stays the brightest thing on a page.
enum StoneInk {
    case emerald, ruby, carnelian, citrine, sapphire, amethyst, jade, rose, stone

    /// On a light page, and on a dark one.
    var hex: (light: UInt32, dark: UInt32) {
        switch self {
        case .emerald: return (0x1F7A4D, 0x6FCF97)
        case .ruby: return (0xB3283B, 0xEC6A78)
        case .carnelian: return (0xB4531F, 0xF09460)
        case .citrine: return (0xD49B00, 0xE6D04A)
        case .sapphire: return (0x2B5FB8, 0x8AAEF0)
        case .amethyst: return (0x5B3FB8, 0xB5A2F5)
        case .jade: return (0x17786A, 0x6CCFC0)
        case .rose: return (0xB03468, 0xF08CB8)
        case .stone: return (0x7A7164, 0xA69E92)
        }
    }

    func color(dark: Bool) -> Color { Color(hex: dark ? hex.dark : hex.light) }

    /// The same, following the screen it is drawn on.
    var color: Color { Color.ink(light: hex.light, dark: hex.dark) }
}

extension Text {
    /// A card's eyebrow: a few carved capitals over its headline ("NEXT UP", "RATED"), in the
    /// same hand as a group's label, so a card and the group above it read as one family.
    func eyebrow() -> Text {
        font(.carved(11)).tracking(1.4)
    }
}

// MARK: - Jewels

/// A door's own stone: a fine gold drawing on a deep jewel tile, the look of Home's Today tiles
/// (`HomeAuroraJewel`, Alex's pick), cut to any size. An SF Symbol or one of the app's glyphs.
struct JewelIcon: View {
    let symbol: String
    let stone: HomeAuroraJewel.Stone
    var size: CGFloat = 44

    var body: some View {
        let tile = RoundedRectangle(cornerRadius: size * 0.3, style: .continuous)
        tile
            .fill(LinearGradient(colors: stone.colors, startPoint: .topLeading, endPoint: .bottomTrailing))
            .overlay {
                // A soft sheen from the top left, like light on a cut stone.
                tile.fill(RadialGradient(colors: [Color.white.opacity(0.24), Color.white.opacity(0)],
                                         center: UnitPoint(x: 0.3, y: 0.2), startRadius: 0, endRadius: size * 0.7))
            }
            .overlay {
                // The fine inner thread, in the drawing's own gold: one metal on every stone.
                RoundedRectangle(cornerRadius: size * 0.24, style: .continuous)
                    .strokeBorder(AnyShapeStyle(HomeAuroraJewel.gold).opacity(0.9), lineWidth: 0.75)
                    .padding(size * 0.06)
            }
            .overlay {
                Glyph(name: symbol, size: size * (Glyph.isGlyph(symbol) ? 0.58 : 0.54), weight: .semibold)
                    .foregroundStyle(HomeAuroraJewel.gold)
            }
            .frame(width: size, height: size)
            .shadow(color: stone.colors[1].opacity(0.3), radius: size * 0.14, y: size * 0.08)
            .accessibilityHidden(true)
    }
}

// MARK: - The room's light

/// Home's own light at the top of a page: a breath of amethyst from the left and of rose from
/// the right, far softer than on Home, so the screens around it stand in the same room and a
/// cream page is never flat.
struct AuroraWash: View {
    let dark: Bool

    var body: some View {
        GeometryReader { geo in
            let w: CGFloat = geo.size.width
            ZStack(alignment: .top) {
                glow(Color(hex: 0x8B6CFF), opacity: dark ? 0.2 : 0.13, at: CGPoint(x: w * 0.1, y: 30), size: w * 1.05)
                glow(Color(hex: 0xF0708A), opacity: dark ? 0.15 : 0.1, at: CGPoint(x: w * 0.94, y: 10), size: w * 0.95)
            }
        }
        // The light stays inside the page it lights, however small that page is.
        .clipped()
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    /// One pool of light. The gradient is elliptical, so it reaches nothing at the very edge of
    /// its own frame all the way round, and it falls away on a soft curve: no rim to be seen.
    private func glow(_ color: Color, opacity: Double, at point: CGPoint, size: CGFloat) -> some View {
        let stops: [Gradient.Stop] = [
            .init(color: color.opacity(opacity), location: 0),
            .init(color: color.opacity(opacity * 0.72), location: 0.3),
            .init(color: color.opacity(opacity * 0.3), location: 0.6),
            .init(color: color.opacity(opacity * 0.07), location: 0.85),
            .init(color: color.opacity(0), location: 1)
        ]
        return EllipticalGradient(stops: stops, center: .center, startRadiusFraction: 0, endRadiusFraction: 0.5)
            .frame(width: size, height: size * 0.8)
            .position(point)
    }
}
