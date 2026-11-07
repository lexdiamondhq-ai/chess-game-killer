import AVFoundation
import SwiftUI
import UIKit

/// The rivals' hall, opened from Rivals on Home (Alex, 2026-11-07): one card for each rival,
/// swiped through, its film's last frame above a short line on how it plays. Face plays the
/// rival's welcome film, then Begin starts the game. The Lionheart and the Dragonlord stay
/// locked until the rival before them is beaten; their cards still show, saying who to beat.
struct RivalsHall: View {
    /// The rival the hall opens on; nil opens on the first one not yet beaten.
    var start: MatchController.Level? = nil
    /// The game starts against this rival.
    let begin: (MatchController.Level) -> Void
    let close: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var ladder: RivalLadder
    @State private var selected: MatchController.Level?
    /// The rival whose film is playing.
    @State private var showing: RivalFilm?

    private static let gold = Color(hex: 0xE8C27A)

    init(start: MatchController.Level? = nil, begin: @escaping (MatchController.Level) -> Void,
         close: @escaping () -> Void) {
        self.start = start
        self.begin = begin
        self.close = close
        let ladder = RivalLadder()
        _ladder = State(initialValue: ladder)
        _selected = State(initialValue: start ?? ladder.current)
    }

    var body: some View {
        ZStack {
            backdrop
            VStack(spacing: 0) {
                header
                GeometryReader { geo in
                    cards(in: geo.size)
                }
                rungs
                    .padding(.bottom, 18)
            }
            if let film = showing {
                RivalWelcome(film: film, begin: { begin(film.level) }, back: {
                    withAnimation(.easeOut(duration: 0.35)) { showing = nil }
                })
                .transition(.opacity)
                .zIndex(1)
            }
        }
        .preferredColorScheme(.dark)
        .statusBarHidden(showing != nil)
        .onAppear {
            HomeMusic.shared.setCovered(true)
        }
        .onDisappear { HomeMusic.shared.setCovered(false) }
    }

    /// Deep ink, lit by the rival in front: its last frame, blurred far back.
    private var backdrop: some View {
        ZStack {
            Color(hex: 0x060608)
            if let image = RivalFilm.of(selected ?? .beginner).cardImage {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .blur(radius: 60)
                    .opacity(0.45)
                    .id(selected)
                    .transition(.opacity)
            }
            LinearGradient(colors: [.black.opacity(0.55), .clear, .black.opacity(0.8)],
                           startPoint: .top, endPoint: .bottom)
        }
        .ignoresSafeArea()
        .animation(.easeInOut(duration: 0.6), value: selected)
    }

    private var header: some View {
        ZStack {
            VStack(spacing: 4) {
                Text("RIVALS")
                    .font(.custom(HomeCarvingFont.plain, size: 22, relativeTo: .title3))
                    .tracking(5)
                    .foregroundStyle(Self.gold)
                Text("Beat each one to climb")
                    .font(.system(size: 12, weight: .medium, design: .serif))
                    .italic()
                    .foregroundStyle(.white.opacity(0.55))
            }
            HStack {
                Button(action: close) {
                    Image(systemName: "xmark")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.85))
                        .frame(width: 44, height: 44)
                        .background(.ultraThinMaterial, in: Circle())
                }
                .accessibilityLabel("Close")
                Spacer()
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 6)
        .padding(.bottom, 14)
    }

    private func cards(in size: CGSize) -> some View {
        // As tall as the room allows, never wider than most of the screen.
        let height = max(320, size.height - 8)
        let width = min(size.width * 0.82, height * 0.6)
        let side = (size.width - width) / 2
        return ScrollView(.horizontal, showsIndicators: false) {
            LazyHStack(spacing: 14) {
                ForEach(RivalFilm.all, id: \.level) { film in
                    RivalHallCard(film: film, open: ladder.isOpen(film.level), beaten: ladder.beaten(film.rival)) {
                        withAnimation(.easeIn(duration: 0.3)) { showing = film }
                    }
                    .frame(width: width, height: height)
                    .scrollTransition(axis: .horizontal) { content, phase in
                        content
                            .scaleEffect(phase.isIdentity || reduceMotion ? 1 : 0.9)
                            .opacity(phase.isIdentity ? 1 : 0.55)
                    }
                    .id(film.level)
                }
            }
            .scrollTargetLayout()
        }
        .contentMargins(.horizontal, side, for: .scrollContent)
        .scrollTargetBehavior(.viewAligned)
        .scrollPosition(id: $selected)
        .frame(height: size.height)
    }

    /// I to V under the cards: the one in front in gold, beaten ones marked, locked ones dim.
    private var rungs: some View {
        HStack(spacing: 18) {
            ForEach(RivalFilm.all, id: \.level) { film in
                let isSelected = film.level == selected
                Button {
                    withAnimation(.spring(response: 0.45, dampingFraction: 0.86)) { selected = film.level }
                } label: {
                    VStack(spacing: 5) {
                        Text(film.numeral)
                            .font(.custom(HomeCarvingFont.plain, size: 14, relativeTo: .footnote))
                            .foregroundStyle(isSelected ? Self.gold : .white.opacity(ladder.isOpen(film.level) ? 0.6 : 0.28))
                        Circle()
                            .fill(ladder.beaten(film.rival) ? Self.gold : .white.opacity(isSelected ? 0.7 : 0.18))
                            .frame(width: 5, height: 5)
                    }
                    .frame(minWidth: 30, minHeight: 36)
                }
                .accessibilityLabel(film.rival.name)
            }
        }
        .padding(.top, 14)
    }
}

/// The names of the carving's fonts, for the rivals' hall.
enum HomeCarvingFont {
    static let plain = "Cinzel-Bold"
}

/// One rival's card: its last frame, its rank and name, a line on how it plays, and Face, or
/// for a locked rival who to beat first.
struct RivalHallCard: View {
    let film: RivalFilm
    let open: Bool
    let beaten: Bool
    let face: () -> Void

    private static let gold = Color(hex: 0xE8C27A)

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 30, style: .continuous)
        ZStack(alignment: .bottom) {
            picture
            LinearGradient(stops: [.init(color: .clear, location: 0.38),
                                   .init(color: .black.opacity(0.72), location: 0.66),
                                   .init(color: .black.opacity(0.94), location: 1)],
                           startPoint: .top, endPoint: .bottom)
            words
                .padding(.horizontal, 22)
                .padding(.bottom, 22)
        }
        .clipShape(shape)
        .overlay {
            shape.strokeBorder(LinearGradient(colors: [Self.gold.opacity(open ? 0.55 : 0.18), Self.gold.opacity(0.05)],
                                              startPoint: .top, endPoint: .bottom), lineWidth: 1)
        }
        .overlay(alignment: .topTrailing) {
            if beaten {
                Label("Beaten", systemImage: "checkmark.seal.fill")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Self.gold)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(.ultraThinMaterial, in: Capsule())
                    .padding(14)
            }
        }
        .shadow(color: .black.opacity(0.6), radius: 24, y: 14)
    }

    @ViewBuilder
    private var picture: some View {
        GeometryReader { geo in
            if let image = film.cardImage {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .frame(width: geo.size.width, height: geo.size.height, alignment: .top)
                    .clipped()
                    .saturation(open ? 1 : 0.15)
                    .brightness(open ? 0 : -0.18)
            } else {
                Color(hex: 0x15171F)
            }
        }
    }

    private var words: some View {
        VStack(spacing: 10) {
            Text("RANK \(film.numeral)  ·  \(film.rival.elo)")
                .font(.system(size: 11, weight: .bold).monospacedDigit())
                .tracking(2.2)
                .foregroundStyle(Self.gold.opacity(open ? 1 : 0.6))
            Text(film.rival.name.uppercased())
                .font(.custom(HomeCarvingFont.plain, size: 28, relativeTo: .title))
                .tracking(1.5)
                .foregroundStyle(.white.opacity(open ? 1 : 0.7))
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            Text(film.lore)
                .font(.system(size: 15, weight: .regular, design: .serif))
                .italic()
                .multilineTextAlignment(.center)
                .foregroundStyle(.white.opacity(open ? 0.78 : 0.5))
                .fixedSize(horizontal: false, vertical: true)
            action
                .padding(.top, 6)
        }
    }

    @ViewBuilder
    private var action: some View {
        if open {
            Button(action: face) {
                Text("Face \(film.rival.name.lowercasedFirstWord)")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Color(hex: 0x1C1813))
                    .frame(maxWidth: .infinity, minHeight: 50)
                    .background(HomeAuroraPalette.goldButton, in: Capsule())
                    .shadow(color: Self.gold.opacity(0.35), radius: 14, y: 4)
            }
            .buttonStyle(HomeStagePress())
            .accessibilityHint("Plays \(film.rival.name)'s welcome, then starts the game")
        } else {
            HStack(spacing: 8) {
                Image(systemName: "lock.fill")
                    .font(.system(size: 13, weight: .semibold))
                Text("Beat \((film.previous?.name ?? "").lowercasedFirstWord) to face \(film.rival.name.lowercasedFirstWord)")
                    .font(.system(size: 14, weight: .semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
            }
            .foregroundStyle(.white.opacity(0.7))
            .frame(maxWidth: .infinity, minHeight: 50)
            .background(Capsule().fill(.white.opacity(0.06)))
            .overlay(Capsule().strokeBorder(.white.opacity(0.14), lineWidth: 1))
            .accessibilityLabel("Locked. Beat \(film.previous?.name ?? "the rival before") first.")
        }
    }
}

private extension String {
    /// "The Lionheart" as it reads mid-sentence: "the Lionheart".
    var lowercasedFirstWord: String {
        hasPrefix("The ") ? "the " + dropFirst(4) : self
    }
}

/// A rival's welcome: its film, full screen and with sound, opening from a point of torchlight;
/// then its name, and Begin. A tap skips to the name. The film's last frame holds behind it.
struct RivalWelcome: View {
    let film: RivalFilm
    let begin: () -> Void
    let back: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var player: AVPlayer?
    @State private var iris: CGFloat = 0
    @State private var titled = false

    private static let gold = Color(hex: 0xE8C27A)

    var body: some View {
        GeometryReader { geo in
            let reach = hypot(geo.size.width, geo.size.height)
            ZStack {
                Color.black
                if let player {
                    RivalFilmLayer(player: player)
                        .blur(radius: reduceMotion ? 0 : (1 - iris) * 14)
                } else if let image = film.cardImage {
                    Image(uiImage: image).resizable().scaledToFill()
                }
                // The torchlight: the dark draws back from the middle.
                RadialGradient(colors: [.clear, .black],
                               center: UnitPoint(x: 0.5, y: 0.42),
                               startRadius: iris * reach * 0.42,
                               endRadius: iris * reach * 0.42 + max(1, reach * 0.28))
                    .opacity(1 - Double(iris) * 0.15)
                    .allowsHitTesting(false)
                LinearGradient(stops: [.init(color: .clear, location: 0.5),
                                       .init(color: .black.opacity(titled ? 0.85 : 0), location: 1)],
                               startPoint: .top, endPoint: .bottom)
                    .allowsHitTesting(false)
                if titled { titleCard.transition(.opacity.combined(with: .offset(y: 18))) }
            }
            .frame(width: geo.size.width, height: geo.size.height)
        }
        .ignoresSafeArea()
        .contentShape(Rectangle())
        .onTapGesture { skip() }
        .overlay(alignment: .topTrailing) {
            Button(action: leave) {
                Image(systemName: "xmark")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.8))
                    .frame(width: 40, height: 40)
                    .background(.ultraThinMaterial, in: Circle())
            }
            .padding(.trailing, 16)
            .padding(.top, 8)
            .accessibilityLabel("Back to the rivals")
        }
        .task { await play() }
        .onDisappear { player?.pause() }
    }

    private var titleCard: some View {
        VStack(spacing: 10) {
            Spacer()
            Text("RANK \(film.numeral)")
                .font(.system(size: 11, weight: .bold))
                .tracking(3)
                .foregroundStyle(Self.gold)
            Text(film.rival.name.uppercased())
                .font(.custom(HomeCarvingFont.plain, size: 38, relativeTo: .largeTitle))
                .tracking(2)
                .foregroundStyle(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .shadow(color: .black.opacity(0.8), radius: 12)
            Text(film.title)
                .font(.system(size: 16, weight: .regular, design: .serif))
                .italic()
                .foregroundStyle(.white.opacity(0.75))
            LinearGradient(colors: [Self.gold.opacity(0), Self.gold.opacity(0.8), Self.gold.opacity(0)],
                           startPoint: .leading, endPoint: .trailing)
                .frame(width: 120, height: 1)
                .padding(.vertical, 6)
            Button {
                RivalTheme.shared.arm(film.level)
                player?.pause()
                begin()
            } label: {
                Text("Begin")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(Color(hex: 0x1C1813))
                    .frame(width: 220, height: 52)
                    .background(HomeAuroraPalette.goldButton, in: Capsule())
                    .shadow(color: Self.gold.opacity(0.4), radius: 16, y: 4)
            }
            .buttonStyle(HomeStagePress())
            .accessibilityHint("Starts the game against \(film.rival.name)")
            Button("Not now", action: leave)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(.white.opacity(0.6))
                .frame(minHeight: 44)
        }
        .padding(.horizontal, 28)
        .padding(.bottom, 44)
    }

    private func play() async {
        guard let url = film.filmURL else {
            iris = 1
            titled = true
            return
        }
        // Playback: the film is something you chose to watch, so it plays with the ring switch off.
        try? AVAudioSession.sharedInstance().setCategory(.playback, options: [.mixWithOthers])
        try? AVAudioSession.sharedInstance().setActive(true)
        let player = AVPlayer(url: url)
        player.actionAtItemEnd = .pause
        self.player = player
        if !Welcome.isUnderTest { player.play() }
        withAnimation(reduceMotion ? .easeOut(duration: 0.4) : .easeOut(duration: 1.8)) { iris = 1 }
        try? await Task.sleep(for: .seconds(film.beat + 0.8))
        guard !Task.isCancelled else { return }
        showTitle()
    }

    private func skip() {
        guard !titled else { return }
        player?.seek(to: CMTime(seconds: film.beat + 0.8, preferredTimescale: 600))
        withAnimation(.easeOut(duration: 0.3)) { iris = 1 }
        showTitle()
    }

    private func showTitle() {
        guard !titled else { return }
        withAnimation(reduceMotion ? .easeOut(duration: 0.3) : .easeOut(duration: 0.9)) { titled = true }
    }

    private func leave() {
        player?.pause()
        back()
    }
}

/// The film on an AVPlayerLayer, filling the screen with no controls.
struct RivalFilmLayer: UIViewRepresentable {
    let player: AVPlayer

    final class LayerView: UIView {
        override class var layerClass: AnyClass { AVPlayerLayer.self }
        var playerLayer: AVPlayerLayer { layer as! AVPlayerLayer }
    }

    func makeUIView(context: Context) -> LayerView {
        let view = LayerView()
        view.backgroundColor = .black
        view.playerLayer.videoGravity = .resizeAspectFill
        view.playerLayer.player = player
        return view
    }

    func updateUIView(_ view: LayerView, context: Context) {
        if view.playerLayer.player !== player { view.playerLayer.player = player }
    }
}

#Preview("Rivals") {
    RivalsHall(begin: { _ in }, close: {})
}
