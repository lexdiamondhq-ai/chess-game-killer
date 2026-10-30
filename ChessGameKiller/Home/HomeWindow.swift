import ChessKit
import SwiftUI
import UIKit

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
                                black: upNext.playerColor == .black, rival: upNext.rival, leaning: leaning)
                    .contentShape(shape)
                    .onTapGesture(perform: primary)
                    .accessibilityHidden(true)
            }
            .overlay { HomeWindowShade(tone: tone, light: upNext.rival.light) }
            .overlay { HomeRivalPresence(rival: upNext.rival, leaning: leaning, scroll: scroll) }
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

    /// A game waits on your move: the rival across the board leans in.
    private var leaning: Bool { upNext.inProgress && upNext.yourMove }

    /// A fine rim, brightest where the light comes from, with a breath of the pieces' gold.
    private var rim: LinearGradient {
        LinearGradient(colors: [tone.metal.opacity(0.42), tone.ink.opacity(0.08), tone.metal.opacity(0.22)],
                       startPoint: .topLeading, endPoint: .bottomTrailing)
    }

    private var words: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top, spacing: 8) {
                // Half the window at most: the rival's light floats beside it.
                HomeWindowTag(upNext: upNext, tone: tone)
                    .frame(maxWidth: width * 0.5, alignment: .leading)
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
/// come. Before a game its dot glows in the next rival's light; during one it is gold and
/// breathes while it is your move.
struct HomeWindowTag: View {
    let upNext: HomeUpNext
    let tone: HomeTone

    var body: some View {
        HStack(spacing: 7) {
            if upNext.inProgress {
                HomeLiveDot(color: upNext.yourMove ? tone.metal : tone.ink3, live: upNext.yourMove)
            } else {
                Circle()
                    .fill(upNext.rival.light)
                    .frame(width: 7, height: 7)
                    .shadow(color: upNext.rival.light.opacity(0.9), radius: 4)
            }
            // The longest line that fits beside the rival's light.
            ViewThatFits(in: .horizontal) {
                Text(text)
                Text(shortText)
            }
            .font(.app(.footnote, weight: .semibold))
            .foregroundStyle(tone.ink)
            .lineLimit(1)
        }
        .padding(.horizontal, 11)
        .frame(minHeight: 30)
        .background { HomeChipFill(tone: tone) }
        .padding(.vertical, 7)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(spoken)
    }

    /// "vs Pulse · Move 14", or before a game "Next · Pulse".
    private var text: String {
        if upNext.inProgress { return "vs \(upNext.rival.name) · Move \(upNext.moveNumber)" }
        if upNext.kind == .firstGame { return "Your first game · \(upNext.rival.name)" }
        return "Next · \(upNext.rival.name)"
    }

    /// "vs Singularity", "First game · Spark", "Pulse".
    private var shortText: String {
        if upNext.inProgress { return "vs \(upNext.rival.name)" }
        if upNext.kind == .firstGame { return "First game · \(upNext.rival.name)" }
        return upNext.rival.name
    }

    /// The tag in words, with the rival's strength the picture leaves out.
    private var spoken: String {
        let who = "\(upNext.rival.name), \(upNext.rival.spokenElo)"
        if upNext.inProgress { return "Against \(who), move \(upNext.moveNumber)" }
        if upNext.kind == .firstGame { return "Your first game: \(who)" }
        return "Next: \(who)"
    }
}

/// The foot of the window darkens into the page so the words read over the board. The top
/// falls away into the room's dark beyond the far side, where the next rival's light glows.
struct HomeWindowShade: View {
    let tone: HomeTone
    /// The rival's light, warming the dark at the far side of the board.
    var light: Color? = nil

    var body: some View {
        GeometryReader { geo in
            ZStack {
                LinearGradient(stops: [
                    .init(color: tone.canvas.opacity(0.7), location: 0),
                    .init(color: tone.canvas.opacity(0.3), location: 0.17),
                    .init(color: tone.canvas.opacity(0), location: 0.4),
                    .init(color: tone.canvas.opacity(0), location: 0.46),
                    .init(color: tone.canvas.opacity(0.62), location: 0.72),
                    .init(color: tone.canvas.opacity(0.9), location: 1),
                ], startPoint: .top, endPoint: .bottom)
                if let light {
                    RadialGradient(colors: [light.opacity(0.3), light.opacity(0.1), light.opacity(0)],
                                   center: UnitPoint(x: HomeRivalPresence.across, y: 0.06),
                                   startRadius: 0, endRadius: geo.size.width * 0.62)
                        .blendMode(.plusLighter)
                }
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// Someone at the table: the next rival waits across the board as its own glowing light, high
/// over the far squares, drifting while it waits. It fades in as the home opens and leans in
/// (a little bigger and brighter) when a game waits on your move. The light it throws on the
/// pieces is the 3D board's own (`SculptedPresence`); this is the orb and the glow around it.
struct HomeRivalPresence: View {
    let rival: Rival
    let leaning: Bool
    let scroll: HomeScroll

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var drifting = false
    @State private var shown = false

    /// Across the window, a little right of the middle: clear of the tag on the left and the
    /// button on the right.
    static let across: CGFloat = 0.615

    /// The orb's width in a window this size.
    static func orb(in size: CGSize) -> CGFloat {
        min(max(size.width * 0.16, 48), 62)
    }

    /// Where the orb floats: in the window's top, a little right of the middle. As the page
    /// scrolls (`turned` 0 to 1) the board turns under it and the orb slides the other way a little.
    static func center(in size: CGSize, turned: CGFloat = 0) -> CGPoint {
        let x: CGFloat = size.width * across - turned * 14
        let y: CGFloat = max(size.height * 0.2, orb(in: size) / 2 + 10)
        return CGPoint(x: x, y: y)
    }

    var body: some View {
        GeometryReader { geo in
            let size = geo.size
            let orb: CGFloat = Self.orb(in: size)
            let turned: CGFloat = min(max(scroll.y / max(size.height, 1), 0), 1)
            let spot: CGPoint = Self.center(in: size, turned: turned)
            let x: CGFloat = spot.x
            let y: CGFloat = spot.y
            let grown: CGFloat = shown ? 1 : 0.86
            let lean: CGFloat = leaning ? 1.1 : 1
            let glow: Double = shown ? (drifting ? 1 : 0.78) : 0
            ZStack {
                halo(orb)
                    .opacity(glow)
                    .position(x: x, y: y)
                Image(rival.glowName)
                    .resizable()
                    .interpolation(.high)
                    .frame(width: orb, height: orb)
                    .scaleEffect(grown * lean)
                    .offset(y: drifting ? -3 : 2)
                    .opacity(shown ? 1 : 0)
                    .position(x: x, y: y)
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
        .onAppear(perform: appear)
        .onChange(of: rival.level) { _, _ in
            // A new rival across the board: it fades in again.
            shown = false
            appear()
        }
        .animation(.spring(response: 0.7, dampingFraction: 0.75), value: leaning)
    }

    private func appear() {
        withAnimation(.easeOut(duration: 1.1).delay(0.35)) { shown = true }
        guard !reduceMotion, !drifting else { return }
        withAnimation(.easeInOut(duration: 2.8).repeatForever(autoreverses: true)) { drifting = true }
    }

    /// The light around the orb, brightest at its heart.
    private func halo(_ orb: CGFloat) -> some View {
        Ellipse()
            .fill(RadialGradient(colors: [rival.light.opacity(0.5), rival.light.opacity(0.16), rival.light.opacity(0)],
                                 center: .center, startRadius: 0, endRadius: orb * 1.55))
            .frame(width: orb * 3.4, height: orb * 2.5)
            .blendMode(.plusLighter)
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
    /// Someone at the table: the next rival, whose light falls across the board.
    let rival: Rival
    /// A game waits on your move, and the rival's light leans in.
    var leaning = false

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
                                    size: geo.size, travel: geo.size.height, light: rival.lightUI, leaning: leaning,
                                    arrival: reduceMotion ? 0 : arrival)
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
    /// The next rival's light, from across the board.
    let light: UIColor
    let leaning: Bool
    var arrival: CGFloat

    var animatableData: CGFloat {
        get { arrival }
        set { arrival = newValue }
    }

    var body: some View {
        let scrolled: CGFloat = min(max(scroll.y / max(travel, 1), 0), 1)
        HomeHeroBoard(stage: stage, look: look, pieces: pieces,
                      camera: Self.camera(size: size, scrolled: scrolled, arrival: arrival, black: black),
                      presence: Self.presence(light, arrival: arrival, leaning: leaning))
            .frame(width: size.width, height: size.height)
    }

    /// The rival's light comes up as the camera settles in, as if it had been waiting for you,
    /// and is a touch brighter while a game waits on your move. Rounded, so a frame of the
    /// glide in only relights the board when the light has visibly changed.
    static func presence(_ light: UIColor, arrival: CGFloat, leaning: Bool) -> SculptedPresence {
        let settled = Float(1 - min(max(arrival, 0), 1))
        let strength = (0.2 + 0.8 * settled) * (leaning ? 1.15 : 1)
        return .window(light, strength: (strength * 50).rounded() / 50)
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
