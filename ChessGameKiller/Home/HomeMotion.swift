import SwiftUI

// The home's tap moments (Alex's picks, 2026-11-01: B1 and J1 on the Tap Moments page).
// B1: a tile sits on a thin gold edge, sinks onto it under the finger with a soft tick, then
// grows into the screen it opens (iOS 18's zoom; earlier systems keep the usual cover).
// J1: the gold knight leaps out of the jewel, twists and lands with a gold ring, then the game opens.

// MARK: - B1 press and lift

/// A home tile's press: it sinks onto its gold edge and a light tick answers the finger.
struct HomeLiftStyle: ButtonStyle {
    let tone: HomeTone
    var radius: CGFloat = HomeMetrics.tileRadius

    func makeBody(configuration: Configuration) -> some View {
        HomeLiftBody(label: configuration.label, pressed: configuration.isPressed, tone: tone, radius: radius)
    }
}

private struct HomeLiftBody<Content: View>: View {
    let label: Content
    let pressed: Bool
    let tone: HomeTone
    let radius: CGFloat

    /// Counts releases: each one plays the pop, so even a quick tap in a scroll view shows.
    @State private var releases = 0
    @AppStorage("haptics") private var hapticsOn = true
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// How far the tile stands above its edge, and sinks when pressed.
    static var lip: CGFloat { 4 }

    var body: some View {
        let drop: CGFloat = pressed ? Self.lip : 0
        let depth: CGFloat = Self.lip - drop
        let edge: Color = tone.metal.opacity(0.5)
        let scale: CGFloat = pressed && !reduceMotion ? 0.96 : 1
        let rim: Color = tone.metal.opacity(pressed ? 0.75 : 0)
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
        label
            .overlay {
                shape.strokeBorder(rim, lineWidth: 1.5)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            }
            .background {
                HomeLipShape(radius: radius, depth: depth)
                    .fill(edge, style: FillStyle(eoFill: true))
                    .accessibilityHidden(true)
            }
            .offset(y: drop)
            .scaleEffect(scale)
            .modifier(HomeLiftPop(trigger: releases, tone: tone, radius: radius, still: reduceMotion))
            .animation(.spring(response: 0.2, dampingFraction: 0.7), value: pressed)
            .sensoryFeedback(.impact(weight: .medium), trigger: pressed) { _, down in down && hapticsOn }
            .onChange(of: pressed) { old, new in
                if old && !new { releases += 1 }
            }
    }
}

/// Where a tile is in its pop on release: a small overshoot and a gold rim that fades.
struct LiftPop {
    var scale: CGFloat = 1
    var glow: Double = 0
}

/// On release the tile springs up past its size, back, with a gold rim flash.
private struct HomeLiftPop: ViewModifier {
    let trigger: Int
    let tone: HomeTone
    let radius: CGFloat
    let still: Bool

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
        return content.keyframeAnimator(initialValue: LiftPop(), trigger: trigger) { view, value in
            view
                .scaleEffect(still ? 1 : value.scale)
                .overlay {
                    shape.strokeBorder(tone.metal.opacity(value.glow), lineWidth: 1.5)
                        .shadow(color: tone.metal.opacity(value.glow * 0.6), radius: 8)
                        .allowsHitTesting(false)
                }
        } keyframes: { _ in
            KeyframeTrack(\.scale) {
                CubicKeyframe(0.95, duration: 0.06)
                SpringKeyframe(1.035, duration: 0.16, spring: .snappy)
                SpringKeyframe(1, duration: 0.25, spring: .bouncy)
            }
            KeyframeTrack(\.glow) {
                LinearKeyframe(0.9, duration: 0.08)
                CubicKeyframe(0, duration: 0.5)
            }
        }
    }
}

/// The gold edge under a tile: the sliver between the tile and the same shape moved down.
struct HomeLipShape: Shape {
    var radius: CGFloat
    var depth: CGFloat

    var animatableData: CGFloat {
        get { depth }
        set { depth = newValue }
    }

    func path(in rect: CGRect) -> Path {
        let lowered: CGRect = rect.offsetBy(dx: 0, dy: max(0, depth))
        var path = Path(roundedRect: lowered, cornerRadius: radius, style: .continuous)
        path.addPath(Path(roundedRect: rect, cornerRadius: radius, style: .continuous))
        return path
    }
}

// MARK: - B1 the screen grows out of the tile

/// The tiles and rows that grow into the screen they open. On the board home every row of
/// the sheet does: Puzzles, your games and your pieces as well as Today's Move and the coach.
enum HomeZoomID: String {
    case daily, coach, puzzles, games, army
}

private struct HomeZoomKey: EnvironmentKey {
    static let defaultValue: Namespace.ID? = nil
}

extension EnvironmentValues {
    /// Where the home's tiles and the screens they open meet, for the zoom between them.
    var homeZoom: Namespace.ID? {
        get { self[HomeZoomKey.self] }
        set { self[HomeZoomKey.self] = newValue }
    }
}

private struct HomeZoomSource: ViewModifier {
    let id: HomeZoomID
    @Environment(\.homeZoom) private var space

    @ViewBuilder
    func body(content: Content) -> some View {
        if #available(iOS 18.0, *), let space {
            content.matchedTransitionSource(id: id.rawValue, in: space)
        } else {
            content
        }
    }
}

private struct HomeZoomDestination: ViewModifier {
    let id: HomeZoomID
    let space: Namespace.ID
    let enabled: Bool

    @ViewBuilder
    func body(content: Content) -> some View {
        if #available(iOS 18.0, *), enabled {
            content.navigationTransition(.zoom(sourceID: id.rawValue, in: space))
        } else {
            content
        }
    }
}

extension View {
    /// This tile is where its screen grows from.
    func homeZoomSource(_ id: HomeZoomID) -> some View {
        modifier(HomeZoomSource(id: id))
    }

    /// This screen grows out of its home tile, when it was opened from the home.
    func homeZoom(_ id: HomeZoomID, in space: Namespace.ID, when enabled: Bool) -> some View {
        modifier(HomeZoomDestination(id: id, space: space, enabled: enabled))
    }
}

// MARK: - J1 knight vault

/// Where the jewel is in its catch of the light.
struct JewelGlint {
    /// The knight's nod, in degrees.
    var nod: Double = 0
    /// The gold face's press and release.
    var scale: CGFloat = 1
    /// The streak of light across the gold: from -1 (off the top left) to 1 (gone past).
    var sweep: CGFloat = -1
    /// The soft gold bloom behind the jewel: 0 none, 1 at its fullest.
    var bloom: CGFloat = 0
}

extension HomeJewel {
    /// How long the glint takes before the game opens: the light has crossed the gold by then.
    static let vaultLanding: Duration = .milliseconds(380)
}

/// A tap on the jewel: it presses in like a real button, a streak of light runs across the
/// gold, the knight gives a small nod, and a soft bloom of light rises behind it. Quiet and
/// quick, like a watch's crown, rather than a cartoon leap.
struct KnightVaultEffect: ViewModifier {
    let trigger: Int

    func body(content: Content) -> some View {
        content.keyframeAnimator(initialValue: JewelGlint(), trigger: trigger) { view, value in
            view
                .rotationEffect(.degrees(value.nod), anchor: .bottom)
                .scaleEffect(value.scale)
        } keyframes: { _ in
            KeyframeTrack(\.nod) {
                LinearKeyframe(0, duration: 0.06)
                CubicKeyframe(-7, duration: 0.14)
                SpringKeyframe(0, duration: 0.3, spring: .smooth)
            }
            KeyframeTrack(\.scale) {
                CubicKeyframe(0.94, duration: 0.08)
                SpringKeyframe(1, duration: 0.32, spring: .smooth)
            }
        }
    }
}

/// The soft bloom of gold light that rises behind the jewel as it's tapped, and fades.
struct JewelLandingRing: View {
    let color: Color
    let trigger: Int

    var body: some View {
        Circle()
            .fill(RadialGradient(colors: [color.opacity(0.6), color.opacity(0)],
                                 center: .center, startRadius: 0, endRadius: 48))
            .padding(-22)
            .blur(radius: 5)
            .keyframeAnimator(initialValue: JewelGlint(), trigger: trigger) { glow, value in
                glow
                    .scaleEffect(0.85 + value.bloom * 0.3)
                    .opacity(Double(value.bloom))
            } keyframes: { _ in
                KeyframeTrack(\.bloom) {
                    CubicKeyframe(1, duration: 0.16)
                    CubicKeyframe(0, duration: 0.55)
                }
            }
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }
}

/// The streak of light that runs across the jewel's gold as it's tapped, under the knight.
struct JewelSheen: View {
    let trigger: Int

    var body: some View {
        GeometryReader { geo in
            let reach: CGFloat = geo.size.width * 0.85
            Color.clear
                .keyframeAnimator(initialValue: JewelGlint(), trigger: trigger) { _, value in
                    LinearGradient(colors: [Color.white.opacity(0), Color.white.opacity(0.7), Color.white.opacity(0)],
                                   startPoint: .leading, endPoint: .trailing)
                        .frame(width: geo.size.width * 0.3, height: geo.size.height * 1.6)
                        .rotationEffect(.degrees(24))
                        .offset(x: value.sweep * reach)
                        .opacity(value.sweep > -1 && value.sweep < 1 ? 1 : 0)
                        .frame(width: geo.size.width, height: geo.size.height)
                } keyframes: { _ in
                    KeyframeTrack(\.sweep) {
                        LinearKeyframe(-1, duration: 0.04)
                        CubicKeyframe(1, duration: 0.44)
                    }
                }
        }
        .clipShape(Capsule())
        .blendMode(.plusLighter)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}
