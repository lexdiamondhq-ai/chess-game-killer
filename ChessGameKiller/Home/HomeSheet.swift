import ChessKit
import SwiftUI
import UIKit

/// The board home (Alex picked "1A Sheet With Tabs", 2026-11-03): the real 3D board fills the
/// top of the screen and never leaves it, and one glass sheet slides over it. The sheet's tabs
/// (Today, Learn, Army, You) sit at its foot beside the gold knight. Pull the sheet up for
/// more, push it down to play: it folds into one slim strip with the game on it.
/// Settings can switch back to the tiles home.
enum HomeLayout {
    static let key = "homeBoardSheet"
    static let defaultOn = true

    static func usesSheet(_ defaults: UserDefaults = .standard) -> Bool {
        defaults.object(forKey: key) as? Bool ?? defaultOn
    }
}

/// Where the sheet rests.
enum HomeSheetDetent: Int, CaseIterable {
    /// Folded to one strip: the board fills the screen, ready to play.
    case board
    /// Halfway: the board on top, today's things below.
    case half
    /// Up: the board peeks above the sheet.
    case full
}

/// The sheet's tabs.
enum HomeSheetTab: Int, CaseIterable, Identifiable {
    case today, learn, army, you

    var id: Int { rawValue }

    var title: String {
        switch self {
        case .today: return "Today"
        case .learn: return "Learn"
        case .army: return "Army"
        case .you: return "You"
        }
    }

    var glyph: String {
        switch self {
        case .today: return Glyphs.today
        case .learn: return Glyphs.train
        case .army: return Glyphs.army
        case .you: return Glyphs.king
        }
    }
}

/// The sheet's measures on a screen this tall, all from the screen's foot.
struct HomeSheetMetrics {
    /// The whole screen, safe areas included.
    let total: CGFloat
    let safeTop: CGFloat
    let safeBottom: CGFloat

    /// The folded strip's height above the home indicator.
    static let stripHeight: CGFloat = 96
    /// How much of the board still shows above the sheet when it is all the way up.
    static let peek: CGFloat = 120

    func height(of detent: HomeSheetDetent) -> CGFloat {
        switch detent {
        case .board:
            return Self.stripHeight + safeBottom
        case .half:
            let half: CGFloat = total * 0.5
            return max(half, 380)
        case .full:
            return total - safeTop - Self.peek
        }
    }

    var lowest: CGFloat { height(of: .board) }
    var highest: CGFloat { height(of: .full) }

    /// The sheet's height with the finger `drag` points down from the detent. Past either end
    /// it gives less and less, like a rubber band.
    func height(_ detent: HomeSheetDetent, drag: CGFloat) -> CGFloat {
        let raw: CGFloat = height(of: detent) - drag
        if raw > highest {
            let over: CGFloat = raw - highest
            return highest + Self.band(over)
        }
        if raw < lowest {
            let under: CGFloat = lowest - raw
            return lowest - Self.band(under)
        }
        return raw
    }

    /// 0 folded to the strip, 1 all the way up.
    func progress(_ height: CGFloat) -> CGFloat {
        let span: CGFloat = max(highest - lowest, 1)
        let value: CGFloat = (height - lowest) / span
        return min(max(value, 0), 1)
    }

    /// The detent nearest a height.
    func nearest(to height: CGFloat) -> HomeSheetDetent {
        var best: HomeSheetDetent = .half
        var distance: CGFloat = .greatestFiniteMagnitude
        for detent in HomeSheetDetent.allCases {
            let gap: CGFloat = abs(self.height(of: detent) - height)
            if gap < distance {
                distance = gap
                best = detent
            }
        }
        return best
    }

    /// A rubber band: the further past the end, the less it gives.
    static func band(_ distance: CGFloat) -> CGFloat {
        let limit: CGFloat = 70
        return limit * (1 - 1 / (distance / limit + 1))
    }
}

// MARK: - The board behind the sheet

/// The real 3D board behind the sheet. It settles in once as the home opens, and as the
/// sheet rises the camera turns around the board, the same walk the tiles home takes while
/// its page scrolls.
struct HomeSheetScene: View {
    let look: SculptedLook
    let tone: HomeTone
    let pieces: [Piece]
    let black: Bool
    let rival: Rival
    let leaning: Bool
    /// 0 with the sheet folded, 1 all the way up.
    let lift: CGFloat

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var stage = SculptedStage()
    /// 1 before the home shows, 0 once the camera has settled.
    @State private var arrival: CGFloat = 1
    @State private var shown = false

    var body: some View {
        GeometryReader { geo in
            ZStack {
                room(geo.size)
                if SculptedAssets.shared.isLoaded {
                    HomeSheetBoard(stage: stage, look: look, pieces: pieces, black: black, size: geo.size,
                                   light: rival.lightUI, leaning: leaning,
                                   arrival: reduceMotion ? 0 : arrival, lift: lift)
                        .id(look.name)
                        .opacity(shown ? 1 : 0)
                }
            }
        }
        .onAppear {
            withAnimation(.easeOut(duration: 0.6)) { shown = true }
            guard !reduceMotion, arrival > 0 else { return }
            withAnimation(.timingCurve(0.2, 0.7, 0.2, 1, duration: 1.8)) { arrival = 0 }
        }
    }

    private func room(_ size: CGSize) -> some View {
        ZStack {
            tone.canvas
            RadialGradient(colors: [tone.pool.opacity(0.95), tone.pool.opacity(0.3), tone.canvas.opacity(0)],
                           center: UnitPoint(x: 0.56, y: 0.4),
                           startRadius: 8, endRadius: max(size.width, 300) * 0.85)
        }
    }
}

/// The board with its camera worked out every frame, so the glide in and the sheet's rise
/// both move the real pieces' view smoothly.
struct HomeSheetBoard: View, Animatable {
    let stage: SculptedStage
    let look: SculptedLook
    let pieces: [Piece]
    let black: Bool
    let size: CGSize
    let light: UIColor
    let leaning: Bool
    var arrival: CGFloat
    var lift: CGFloat

    var animatableData: AnimatablePair<CGFloat, CGFloat> {
        get { AnimatablePair(arrival, lift) }
        set {
            arrival = newValue.first
            lift = newValue.second
        }
    }

    var body: some View {
        let turned: CGFloat = min(max(lift, 0), 1)
        let camera: SculptedCamera = HomeWindowBoard.camera(size: size, scrolled: turned, arrival: arrival, black: black)
        let presence: SculptedPresence = HomeWindowBoard.presence(light, arrival: arrival, leaning: leaning)
        HomeHeroBoard(stage: stage, look: look, pieces: pieces, camera: camera, presence: presence)
            .frame(width: size.width, height: size.height)
    }
}

/// The board's top and foot fade into the room, so the greeting reads over it and the
/// sheet seems to rise out of the dark.
struct HomeSheetShade: View {
    let tone: HomeTone

    var body: some View {
        LinearGradient(stops: [
            .init(color: tone.canvas.opacity(0.75), location: 0),
            .init(color: tone.canvas.opacity(0.2), location: 0.16),
            .init(color: tone.canvas.opacity(0), location: 0.3),
            .init(color: tone.canvas.opacity(0), location: 0.62),
            .init(color: tone.canvas.opacity(0.85), location: 1),
        ], startPoint: .top, endPoint: .bottom)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

// MARK: - The sheet's parts

/// The handle at the sheet's top. It stretches while the sheet is dragged.
struct HomeSheetGrabber: View {
    let tone: HomeTone
    let dragging: Bool

    var body: some View {
        Capsule()
            .fill(tone.ink.opacity(dragging ? 0.55 : 0.3))
            .frame(width: dragging ? 52 : 38, height: 5)
            .animation(.spring(response: 0.3, dampingFraction: 0.6), value: dragging)
            .frame(maxWidth: .infinity)
            .frame(height: 22)
            .contentShape(Rectangle())
            .accessibilityHidden(true)
    }
}

/// The tabs at the sheet's foot: a lit pill slides to the one picked, its glyph springs up,
/// and the gold knight stands beside them.
struct HomeSheetTabBar<Jewel: View>: View {
    let tone: HomeTone
    let selection: HomeSheetTab
    let pick: (HomeSheetTab) -> Void
    @ViewBuilder let jewel: () -> Jewel

    @Namespace private var pill
    @ScaledMetric(relativeTo: .caption) private var glyphSize: CGFloat = 22

    var body: some View {
        HStack(spacing: 10) {
            HStack(spacing: 2) {
                ForEach(HomeSheetTab.allCases) { tab in
                    button(tab)
                }
            }
            .padding(4)
            .background {
                Capsule()
                    .fill(tone.canvas.opacity(0.35))
                    .overlay { Capsule().strokeBorder(tone.ink.opacity(0.12), lineWidth: 0.75) }
            }
            jewel()
        }
    }

    private func button(_ tab: HomeSheetTab) -> some View {
        let on: Bool = tab == selection
        return Button {
            pick(tab)
        } label: {
            VStack(spacing: 2) {
                Glyph(name: tab.glyph, size: glyphSize)
                    .scaleEffect(on ? 1.12 : 1)
                    .offset(y: on ? -1 : 0)
                Text(tab.title)
                    .font(.app(.caption2, weight: .semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .foregroundStyle(on ? tone.ink : tone.ink3)
            .frame(maxWidth: .infinity)
            .frame(minHeight: 50)
            .background {
                if on {
                    Capsule()
                        .fill(tone.ink.opacity(0.13))
                        .overlay { Capsule().strokeBorder(tone.metal.opacity(0.35), lineWidth: 0.75) }
                        .matchedGeometryEffect(id: "pill", in: pill)
                }
            }
            .contentShape(Capsule())
        }
        .buttonStyle(HomePressStyle())
        .accessibilityLabel(tab.title)
        .accessibilityAddTraits(on ? .isSelected : [])
    }
}

/// The sheet folded down: one strip with the game on it, and the way to play.
struct HomeSheetStrip: View {
    let upNext: HomeUpNext
    let tone: HomeTone
    let play: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 7) {
                    HomeLiveDot(color: dotColor, live: upNext.inProgress && upNext.yourMove)
                    Text(kicker)
                        .font(.app(.footnote, weight: .semibold))
                        .foregroundStyle(tone.ink2)
                        .lineLimit(1)
                }
                Text(title)
                    .font(.app(.title3, weight: .semibold))
                    .foregroundStyle(tone.ink)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityElement(children: .combine)
            Button(action: play) {
                Text(upNext.inProgress ? "Resume" : "Play")
                    .frame(minWidth: 64)
            }
            .buttonStyle(HomeIvoryButtonStyle(tone: tone, compact: true))
        }
    }

    private var dotColor: Color {
        let lit: Bool = upNext.yourMove || !upNext.inProgress
        return lit ? tone.metal : tone.ink3
    }

    private var kicker: String {
        if upNext.inProgress { return "vs \(upNext.rival.name) · Move \(upNext.moveNumber)" }
        return "Next · \(upNext.rival.name)"
    }

    private var title: String {
        guard upNext.inProgress else { return "Play \(upNext.rival.name)" }
        if let time = upNext.yourTime, upNext.yourMove { return "Your move · \(time.clockLabel)" }
        return upNext.yourMove ? "Your move" : "Their move"
    }
}

// MARK: - Motion

/// Each block of a tab rises into place a beat after the one above it, out of a soft blur.
private struct HomeRise: ViewModifier {
    let index: Int

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var shown = false

    func body(content: Content) -> some View {
        let up: Bool = shown || reduceMotion
        content
            .opacity(up ? 1 : 0)
            .offset(y: up ? 0 : 18)
            .blur(radius: up ? 0 : 6)
            .scaleEffect(up ? 1 : 0.98, anchor: .top)
            .onAppear {
                guard !reduceMotion else { return }
                let delay: Double = 0.06 + Double(index) * 0.06
                withAnimation(.spring(response: 0.55, dampingFraction: 0.82).delay(delay)) { shown = true }
            }
    }
}

extension View {
    /// Rises into place in turn: `index` 0 first.
    func homeRise(_ index: Int) -> some View {
        modifier(HomeRise(index: index))
    }
}

/// A tab's page slides in from the side of the tab picked, out of a blur.
struct HomePageShift: ViewModifier {
    let x: CGFloat
    let blur: CGFloat
    let opacity: Double

    func body(content: Content) -> some View {
        content
            .offset(x: x)
            .blur(radius: blur)
            .opacity(opacity)
    }
}

extension AnyTransition {
    /// The page for a tab to the right comes in from the right; to the left, from the left.
    static func homePage(forward: Bool, reduceMotion: Bool) -> AnyTransition {
        if reduceMotion { return .opacity }
        let step: CGFloat = forward ? 44 : -44
        let insertion = AnyTransition.modifier(active: HomePageShift(x: step, blur: 8, opacity: 0),
                                               identity: HomePageShift(x: 0, blur: 0, opacity: 1))
        let removal = AnyTransition.modifier(active: HomePageShift(x: -step, blur: 8, opacity: 0),
                                             identity: HomePageShift(x: 0, blur: 0, opacity: 1))
        return .asymmetric(insertion: insertion, removal: removal)
    }
}
