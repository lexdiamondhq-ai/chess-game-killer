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

    @AppStorage("haptics") private var hapticsOn = true
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// How far the tile stands above its edge, and sinks when pressed.
    static var lip: CGFloat { 3 }

    var body: some View {
        let drop: CGFloat = pressed ? Self.lip : 0
        let depth: CGFloat = Self.lip - drop
        let edge: Color = tone.metal.opacity(0.32)
        let scale: CGFloat = pressed && !reduceMotion ? 0.985 : 1
        label
            .background {
                HomeLipShape(radius: radius, depth: depth)
                    .fill(edge, style: FillStyle(eoFill: true))
                    .accessibilityHidden(true)
            }
            .offset(y: drop)
            .scaleEffect(scale)
            .animation(.spring(response: 0.22, dampingFraction: 0.72), value: pressed)
            .sensoryFeedback(.impact(weight: .light), trigger: pressed) { _, down in down && hapticsOn }
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

/// The tiles that grow into the screen they open.
enum HomeZoomID: String {
    case daily, coach
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

/// Where the knight is in its leap out of the jewel.
struct KnightVault {
    var lift: CGFloat = 0
    var tilt: Double = 0
    var scale: CGFloat = 1
    var squash: CGFloat = 1
}

/// How far a gold ring has spread from the jewel, from 0 (none) to 1 (gone).
struct JewelRing {
    var spread: CGFloat = 0
}

extension HomeJewel {
    /// How long the leap takes before the game opens: the knight has landed by then.
    static let vaultLanding: Duration = .milliseconds(430)
}

/// The knight's leap: crouch, up with a twist, land with a squash and settle.
struct KnightVaultEffect: ViewModifier {
    let trigger: Int

    func body(content: Content) -> some View {
        content.keyframeAnimator(initialValue: KnightVault(), trigger: trigger) { view, value in
            view
                .scaleEffect(x: value.scale, y: value.scale * value.squash, anchor: .bottom)
                .rotationEffect(.degrees(value.tilt))
                .offset(y: value.lift)
        } keyframes: { _ in
            KeyframeTrack(\.lift) {
                CubicKeyframe(2, duration: 0.07)
                CubicKeyframe(-30, duration: 0.18)
                CubicKeyframe(0, duration: 0.17)
                SpringKeyframe(0, duration: 0.2, spring: .bouncy)
            }
            KeyframeTrack(\.tilt) {
                LinearKeyframe(0, duration: 0.07)
                CubicKeyframe(-14, duration: 0.14)
                CubicKeyframe(10, duration: 0.12)
                CubicKeyframe(0, duration: 0.15)
            }
            KeyframeTrack(\.scale) {
                CubicKeyframe(0.88, duration: 0.07)
                CubicKeyframe(1.12, duration: 0.18)
                CubicKeyframe(1, duration: 0.2)
            }
            KeyframeTrack(\.squash) {
                LinearKeyframe(1, duration: 0.42)
                CubicKeyframe(0.86, duration: 0.06)
                SpringKeyframe(1, duration: 0.25, spring: .bouncy)
            }
        }
    }
}

/// The gold ring the knight's landing sends out across the dock.
struct JewelLandingRing: View {
    let color: Color
    let trigger: Int

    var body: some View {
        Circle()
            .strokeBorder(color, lineWidth: 1.5)
            .keyframeAnimator(initialValue: JewelRing(), trigger: trigger) { ring, value in
                let shown: Double = value.spread > 0 ? Double(1 - value.spread) : 0
                ring
                    .scaleEffect(1 + value.spread * 1.4)
                    .opacity(shown)
            } keyframes: { _ in
                KeyframeTrack(\.spread) {
                    LinearKeyframe(0, duration: 0.42)
                    LinearKeyframe(0.01, duration: 0.01)
                    CubicKeyframe(1, duration: 0.45)
                }
            }
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }
}
