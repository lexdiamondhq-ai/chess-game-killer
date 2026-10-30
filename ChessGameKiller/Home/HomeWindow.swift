import ChessKit
import SwiftUI

/// The first thing on the home: the real 3D board seen through a rounded window, with the
/// game under way (or the next one) written over its foot and the way to play right on it.
/// Before a game it reads "Play Pulse"; during one, "Your move" and Resume. The board itself
/// is a way in too: a tap on it does what the ivory button does.
struct HomeBoardWindow: View {
    let upNext: HomeUpNext
    let tone: HomeTone
    let look: SculptedLook
    let pieces: [Piece]
    let scroll: HomeScroll
    let primary: () -> Void
    let secondary: () -> Void

    @Environment(\.dynamicTypeSize) private var typeSize
    @State private var width: CGFloat = 358

    /// Three by two on a phone, a little taller for the largest text.
    private var height: CGFloat {
        let natural: CGFloat = min(width / 1.5, 300)
        return typeSize.isAccessibilitySize ? max(natural, 330) : natural
    }

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: HomeMetrics.cardRadius, style: .continuous)
        Color.clear
            .frame(maxWidth: .infinity)
            .frame(height: height)
            .onGeometryChange(for: CGFloat.self) { proxy in
                proxy.size.width
            } action: { measured in
                width = measured
            }
            .overlay {
                HomeWindowScene(scroll: scroll, look: look, tone: tone, pieces: pieces,
                                black: upNext.playerColor == .black)
                    .contentShape(shape)
                    .onTapGesture(perform: primary)
                    .accessibilityHidden(true)
            }
            .overlay { HomeWindowShade(tone: tone) }
            .overlay { words }
            .clipShape(shape)
            .overlay { shape.strokeBorder(rim, lineWidth: 0.75) }
            // The shadow is cast by the window's shape, not by the live board inside it, so
            // the board isn't drawn a second time every frame while it turns.
            .background {
                shape.fill(tone.canvas)
                    .shadow(color: .black.opacity(0.45), radius: 22, y: 14)
            }
            .accessibilityElement(children: .contain)
            .accessibilityLabel(upNext.inProgress ? "Your game" : "Next game")
            .accessibilityAction(.magicTap, primary)
    }

    /// A fine rim, brightest where the light comes from, with a breath of the pieces' gold.
    private var rim: LinearGradient {
        LinearGradient(colors: [tone.metal.opacity(0.42), tone.ink.opacity(0.08), tone.metal.opacity(0.22)],
                       startPoint: .topLeading, endPoint: .bottomTrailing)
    }

    private var words: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top, spacing: 8) {
                HomeWindowTag(upNext: upNext, tone: tone)
                Spacer(minLength: 0)
                Button(action: secondary) {
                    Text(upNext.inProgress ? "New game" : "Change")
                        .font(.app(.footnote, weight: .semibold))
                        .foregroundStyle(tone.ink)
                        .padding(.horizontal, 12)
                        .frame(minHeight: 30)
                        .background { HomeChipFill(tone: tone) }
                        .padding(.vertical, 7)
                        .contentShape(Rectangle())
                }
                .buttonStyle(HomePressStyle())
                .accessibilityHint(upNext.inProgress ? "Set up another game" : "Pick another rival, side or clock")
            }
            Spacer(minLength: 8)
            footer
        }
        .padding(.horizontal, 14)
        .padding(.top, 7)
        .padding(.bottom, 14)
    }

    private var footer: some View {
        let layout = typeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 10))
            : AnyLayout(HStackLayout(alignment: .bottom, spacing: 12))
        return layout {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.app(.title, weight: .semibold))
                    .foregroundStyle(tone.ink)
                    .tracking(-0.6)
                Text(subtitle)
                    .font(.app(.subheadline).monospacedDigit())
                    .foregroundStyle(tone.ink2)
            }
            .lineLimit(1)
            .minimumScaleFactor(0.75)
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityElement(children: .combine)
            Button(action: primary) {
                Text(upNext.inProgress ? "Resume" : "Play")
                    .frame(minWidth: 64)
            }
            .buttonStyle(HomeIvoryButtonStyle(tone: tone))
            .accessibilityLabel(upNext.inProgress ? "Resume your game against \(upNext.rival.name)" : "Play \(upNext.rival.name)")
            .accessibilityInputLabels(upNext.inProgress ? ["Resume"] : ["Play", "Play \(upNext.rival.name)"])
        }
    }

    /// "Your move", "Their move", or before a game "Play Pulse".
    private var title: String {
        guard upNext.inProgress else { return "Play \(upNext.rival.name)" }
        return upNext.yourMove ? "Your move" : "Their move"
    }

    /// "10:00 on your clock", "Move 14 · No clock", or before a game "White · No clock".
    private var subtitle: String {
        if upNext.inProgress {
            if let time = upNext.yourTime { return "\(time.clockLabel) on your clock" }
            return "Move \(upNext.moveNumber) · No clock"
        }
        let side = upNext.randomSide ? "Either side" : (upNext.playerColor == .white ? "White" : "Black")
        return "\(side) · \(upNext.timeControl.name)"
    }
}

/// The small glass tag in the window's corner: who the game is against, and how far it has
/// come, with a gold dot that breathes while it is your move.
struct HomeWindowTag: View {
    let upNext: HomeUpNext
    let tone: HomeTone

    var body: some View {
        HStack(spacing: 7) {
            if upNext.inProgress {
                HomeLiveDot(color: upNext.yourMove ? tone.metal : tone.ink3, live: upNext.yourMove)
            }
            Text(text)
                .font(.app(.footnote, weight: .semibold))
                .foregroundStyle(tone.ink)
                .lineLimit(1)
        }
        .padding(.horizontal, 11)
        .frame(minHeight: 30)
        .background { HomeChipFill(tone: tone) }
        .padding(.vertical, 7)
        .accessibilityElement(children: .combine)
    }

    /// "vs Pulse · Move 14", or before a game "Next · Pulse ~1500".
    private var text: String {
        if upNext.inProgress { return "vs \(upNext.rival.name) · Move \(upNext.moveNumber)" }
        if upNext.kind == .firstGame { return "Your first game · \(upNext.rival.name) \(upNext.rival.elo)" }
        return "Next · \(upNext.rival.name) \(upNext.rival.elo)"
    }
}

/// The foot of the window darkens into the page so the words read over the board, and the
/// top keeps a whisper of shade under the corner tag.
struct HomeWindowShade: View {
    let tone: HomeTone

    var body: some View {
        LinearGradient(stops: [
            .init(color: tone.canvas.opacity(0.28), location: 0),
            .init(color: tone.canvas.opacity(0), location: 0.26),
            .init(color: tone.canvas.opacity(0), location: 0.46),
            .init(color: tone.canvas.opacity(0.62), location: 0.72),
            .init(color: tone.canvas.opacity(0.9), location: 1),
        ], startPoint: .top, endPoint: .bottom)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }
}

/// The room and the live board inside the window. The camera is the home's own at rest,
/// seen through a pane as wide as the screen; it settles in once when the home first shows,
/// and turns a little as the page scrolls, so the board feels deep behind the glass.
struct HomeWindowScene: View {
    let scroll: HomeScroll
    let look: SculptedLook
    let tone: HomeTone
    let pieces: [Piece]
    let black: Bool

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
                    HomeWindowBoard(stage: stage, look: look, pieces: pieces, black: black, scroll: scroll,
                                    size: geo.size, travel: geo.size.height, arrival: reduceMotion ? 0 : arrival)
                        .id(look.name)
                        .opacity(shown ? 1 : 0)
                }
            }
        }
        .onAppear {
            withAnimation(.easeOut(duration: 0.5)) { shown = true }
            guard !reduceMotion, arrival > 0 else { return }
            withAnimation(.timingCurve(0.2, 0.7, 0.2, 1, duration: 1.6)) { arrival = 0 }
        }
    }

    /// The room: its own dark, and the pool of light the board stands in.
    private func room(_ size: CGSize) -> some View {
        ZStack {
            tone.canvas
            RadialGradient(colors: [tone.pool.opacity(0.95), tone.pool.opacity(0.3), tone.canvas.opacity(0)],
                           center: UnitPoint(x: 0.56, y: 0.36),
                           startRadius: 8, endRadius: max(size.width, 300) * 0.8)
        }
    }
}

/// The board itself, with a camera worked out every frame: SwiftUI animates `arrival`, and
/// the page's scroll turns it, so the glide in and the turn both move the real pieces' view.
struct HomeWindowBoard: View, Animatable {
    let stage: SculptedStage
    let look: SculptedLook
    let pieces: [Piece]
    let black: Bool
    let scroll: HomeScroll
    let size: CGSize
    /// How far the page scrolls while the camera turns.
    let travel: CGFloat
    var arrival: CGFloat

    var animatableData: CGFloat {
        get { arrival }
        set { arrival = newValue }
    }

    var body: some View {
        let scrolled: CGFloat = min(max(scroll.y / max(travel, 1), 0), 1)
        HomeHeroBoard(stage: stage, look: look, pieces: pieces,
                      camera: Self.camera(size: size, scrolled: scrolled, arrival: arrival, black: black))
            .frame(width: size.width, height: size.height)
    }

    /// Where the look point sits in the window at rest: a little above the middle, so the
    /// pieces stand in the window's top and its foot is left for the words.
    static let restAnchor: Float = 0.12
    /// The share of the home's full walk the camera takes as the window scrolls away.
    static let turn: Float = 0.45
    /// How high and far back the camera starts before it settles.
    static let rise: Float = 0.7

    /// The home's hero camera, seen through the window. The lens spans the window's width,
    /// as it spans the screen's on the game, so the pieces keep the size players know.
    static func camera(size: CGSize, scrolled: CGFloat, arrival: CGFloat, black: Bool) -> SculptedCamera {
        let aspect = Float(size.width / max(size.height, 1))
        let progress = Float(min(max(scrolled, 0), 1)) * turn
        let anchor = restAnchor * (1 - Float(min(max(scrolled, 0), 1)))
        return HomeHeroCamera.camera(aspect: aspect, anchor: anchor, progress: progress,
                                     pull: Float(min(max(arrival, 0), 1)) * rise, black: black)
    }
}

/// A dot for something live: still when it isn't, breathing out a soft ring when it is.
struct HomeLiveDot: View {
    let color: Color
    var live = true
    var size: CGFloat = 7

    @State private var breathe = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Circle()
            .fill(color)
            .frame(width: size, height: size)
            .shadow(color: live ? color.opacity(0.8) : .clear, radius: 4)
            .background {
                if live, !reduceMotion {
                    Circle()
                        .fill(color.opacity(0.45))
                        .scaleEffect(breathe ? 2.8 : 1)
                        .opacity(breathe ? 0 : 1)
                }
            }
            .accessibilityHidden(true)
            .onAppear {
                guard live, !reduceMotion else { return }
                withAnimation(.easeOut(duration: 1.8).repeatForever(autoreverses: false)) { breathe = true }
            }
    }
}

/// The dark glass behind a small chip laid over the board or a card.
struct HomeChipFill: View {
    let tone: HomeTone

    var body: some View {
        Capsule()
            .fill(tone.canvas.opacity(0.5))
            .background(.ultraThinMaterial, in: Capsule())
            .overlay { Capsule().strokeBorder(tone.ink.opacity(0.14), lineWidth: 0.75) }
    }
}
