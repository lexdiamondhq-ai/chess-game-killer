import AVFoundation
import Combine
import SwiftUI
import UIKit

/// The rivals' hall, opened from Rivals on Home (Alex, 2026-11-07): one card for each rival,
/// swiped through, its film's last frame above a short line on how it plays. Landing on a rival
/// plays its film full screen; when it ends the film holds its last frame and the rival's words
/// and Face rise at the bottom, over I to V for swiping on to the others. Face plays the
/// rival's welcome film, then Begin starts the game. Every rival after the Cub stays locked
/// until the rival before it is beaten; their cards still show, saying who to beat.
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
    /// Just watched in full: back from its welcome, its card doesn't play the film again until
    /// you swipe away and back.
    @State private var watched: MatchController.Level?
    /// The rival whose film is playing large, over the whole hall, as you land on it.
    @State private var playing: MatchController.Level?
    /// The playing film has ended: it holds its last frame, with the rival's words and Face.
    @State private var ended: MatchController.Level?

    private static let gold = Color(hex: 0xE8C27A)

    /// `intro` opens straight into the start rival's welcome film: every time you face a rival
    /// from Home's Play, its film plays before the game (Alex, 2026-11-09).
    /// `ended` (for pictures) opens on that rival's film already ended, its words showing.
    init(start: MatchController.Level? = nil, intro: Bool = false, ended: MatchController.Level? = nil,
         begin: @escaping (MatchController.Level) -> Void, close: @escaping () -> Void) {
        self.start = start
        self.begin = begin
        self.close = close
        let ladder = RivalLadder()
        _ladder = State(initialValue: ladder)
        _selected = State(initialValue: start ?? ladder.current)
        _showing = State(initialValue: intro ? start.map(RivalFilm.of) : nil)
        _playing = State(initialValue: ended)
        _ended = State(initialValue: ended)
        if let ended { _selected = State(initialValue: ended) }
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
            if let level = playing {
                // The rival in front plays its film large, the whole screen, as you swipe to it
                // (Alex, 2026-11-10: "The videos of the rivals should be the larger videos, then
                // once its done the bottom buttons appear"). When it ends it stays large, holding
                // its last frame, with the rival's words and Face at the bottom and I to V under
                // them to swipe on, instead of going back to the cards (Alex, 2026-11-10).
                let film = RivalFilm.of(level)
                RivalHallFilm(film: film, ended: ended == level, done: { finishFilm(level) },
                              step: { stepFilm(by: $0) }, close: close) {
                    VStack(spacing: 0) {
                        RivalFilmEnding(film: film, open: ladder.isOpen(level),
                                        face: { withAnimation(.easeIn(duration: 0.3)) { showing = film } },
                                        notToday: close)
                        .padding(.horizontal, 24)
                        .opacity(ended == level ? 1 : 0)
                        .offset(y: ended == level ? 0 : 18)
                        .allowsHitTesting(ended == level)
                        rungs
                    }
                    .padding(.bottom, 18)
                }
                    .id(level)
                    .transition(reduceMotion ? .opacity : .scale(scale: 0.82).combined(with: .opacity))
                    .zIndex(1)
            }
            if let film = showing {
                RivalWelcome(film: film, begin: { begin(film.level) }, back: {
                    watched = film.level
                    withAnimation(.easeOut(duration: 0.35)) { showing = nil }
                })
                .transition(.opacity)
                .zIndex(2)
            }
        }
        .preferredColorScheme(.dark)
        .statusBarHidden(showing != nil || playing != nil)
        .onAppear {
            HomeMusic.shared.setCovered(true)
            if showing == nil { playFilm(selected) }
        }
        .onDisappear { HomeMusic.shared.setCovered(false) }
        .onChange(of: selected) { _, level in
            watched = nil
            playFilm(level)
        }
    }

    /// Opens the rival's film large over the hall, unless it was just watched in full.
    private func playFilm(_ level: MatchController.Level?) {
        guard let level, level != watched, showing == nil, !Welcome.isUnderTest else { return }
        withAnimation(.spring(response: 0.5, dampingFraction: 0.88)) { playing = level }
    }

    /// The film ended, or was tapped: it holds its last frame, and the words and Face rise.
    private func finishFilm(_ level: MatchController.Level) {
        guard playing == level else { return }
        withAnimation(.easeOut(duration: 0.6)) { ended = level }
    }

    /// A sideways swipe on a playing film goes on to the next rival (or back), and plays its film.
    private func stepFilm(by offset: Int) {
        let all = RivalFilm.all.map(\.level)
        guard let current = selected, let index = all.firstIndex(of: current) else { return }
        let next = index + offset
        guard all.indices.contains(next) else { return }
        withAnimation(.spring(response: 0.45, dampingFraction: 0.86)) { selected = all[next] }
    }

    /// Deep ink, lit by the rival in front: its last frame, blurred far back.
    private var backdrop: some View {
        // The frame laid over the ink, not beside it: a filled image would widen the hall past
        // the screen, and the film's ending with it.
        Color(hex: 0x060608)
            .overlay {
                if let image = RivalFilm.of(selected ?? .beginner).cardImage {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                        .blur(radius: 60)
                        .opacity(0.45)
                        .id(selected)
                        .transition(.opacity)
                }
            }
            .overlay {
                LinearGradient(colors: [.black.opacity(0.55), .clear, .black.opacity(0.8)],
                               startPoint: .top, endPoint: .bottom)
            }
            .clipped()
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
        return ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: 14) {
                    ForEach(RivalFilm.all, id: \.level) { film in
                        // Each rival's film plays as you swipe to it (Alex, 2026-11-09: "when you
                        // select all rivals you should get the video introduction of each").
                        RivalHallCard(film: film, open: ladder.isOpen(film.level), beaten: ladder.beaten(film.rival),
                                      waiting: film.level == playing) {
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
            // As on Home's Next game: the hall is put on its rival by hand as it opens, since a
            // position handed over before the cards are laid out is not always kept.
            .task { if let selected { proxy.scrollTo(selected, anchor: .center) } }
        }
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
    /// Its film is playing large over the hall: the words and Face wait until it ends.
    var waiting = false
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
                .opacity(waiting ? 0 : 1)
                .offset(y: waiting ? 16 : 0)
                .animation(.easeOut(duration: 0.5).delay(waiting ? 0 : 0.25), value: waiting)
                .allowsHitTesting(!waiting)
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
        RivalHallWords(film: film, open: open, face: face)
    }
}

/// A rival's rank and name, a line on how it plays, and Face, or for a locked rival who to beat
/// first: on its card, and over its film once the film ends.
struct RivalHallWords: View {
    let film: RivalFilm
    let open: Bool
    let face: () -> Void

    private static let gold = Color(hex: 0xE8C27A)

    var body: some View {
        words
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

/// How a rival's film ends in the hall (Alex, 2026-11-10, from a picture): its rank between gold
/// rules, its name, a line on how it plays, and Face in a dark glass capsule with its coin; "Not
/// today" leaves the hall. No rating or record (Alex, 2026-11-10: "give more room to see the video"). For a locked rival the capsule
/// says who to beat first.
struct RivalFilmEnding: View {
    let film: RivalFilm
    let open: Bool
    let face: () -> Void
    let notToday: () -> Void

    private static let gold = Color(hex: 0xE8C27A)
    private static let paleGold = Color(hex: 0xF3DDA8)

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 14) {
                rule
                Text("RANK \(film.numeral)")
                    .font(.custom(HomeCarvingFont.plain, size: 15, relativeTo: .footnote))
                    .tracking(3)
                    .foregroundStyle(Self.gold)
                rule
            }
            Text(film.rival.name.uppercased())
                .font(.custom(HomeCarvingFont.plain, size: 34, relativeTo: .largeTitle))
                .tracking(2.5)
                .foregroundStyle(LinearGradient(colors: [Self.paleGold, Self.gold],
                                                startPoint: .top, endPoint: .bottom))
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .shadow(color: .black.opacity(0.7), radius: 10)
                .padding(.top, 8)
            Text(film.lore)
                .font(.system(size: 18, weight: .regular, design: .serif))
                .italic()
                .multilineTextAlignment(.center)
                .foregroundStyle(.white.opacity(0.72))
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 12)
            capsule
                .padding(.top, 22)
            Button("Not today", action: notToday)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.white.opacity(0.42))
                .frame(minHeight: 44)
                .padding(.top, 4)
        }
    }

    private var rule: some View {
        Rectangle()
            .fill(Self.gold.opacity(0.55))
            .frame(width: 26, height: 1)
    }

    private var capsule: some View {
        Button(action: face) {
            HStack(spacing: 14) {
                RivalCoin(rival: film.rival, size: 32)
                    .saturation(open ? 1 : 0.2)
                if open {
                    Text("FACE \(film.rival.name.uppercased())")
                        .font(.custom(HomeCarvingFont.plain, size: 16, relativeTo: .body))
                        .tracking(2)
                        .foregroundStyle(LinearGradient(colors: [Self.paleGold, Self.gold],
                                                        startPoint: .top, endPoint: .bottom))
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                } else {
                    Text("Beat \((film.previous?.name ?? "").lowercasedFirstWord) first")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.6))
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                }
            }
            .padding(.horizontal, 24)
            .frame(maxWidth: .infinity, minHeight: 60)
            .background(Capsule().fill(Color(hex: 0x14110D).opacity(0.92)))
            .overlay(Capsule().strokeBorder(LinearGradient(colors: [Self.gold.opacity(open ? 0.7 : 0.25),
                                                                     Self.gold.opacity(open ? 0.3 : 0.1)],
                                                            startPoint: .top, endPoint: .bottom),
                                            lineWidth: 1))
            .shadow(color: Self.gold.opacity(open ? 0.18 : 0), radius: 14, y: 4)
        }
        .buttonStyle(HomeStagePress())
        .disabled(!open)
        .accessibilityLabel(open ? "Face \(film.rival.name)"
                                 : "Locked. Beat \(film.previous?.name ?? "the rival before") first.")
        .accessibilityHint(open ? "Plays \(film.rival.name)'s welcome, then starts the game" : "")
    }
}

extension String {
    /// "The Lionheart" as it reads mid-sentence: "the Lionheart".
    var lowercasedFirstWord: String {
        hasPrefix("The ") ? "the " + dropFirst(4) : self
    }
}

/// A rival's film large over the hall as you land on it: full screen, with sound, nothing over
/// the art but I to V at the bottom. A tap ends it sooner; then it holds its last frame and its
/// ending (the rival's words and Face) rises at the bottom. A sideways swipe goes on to the next
/// rival's film, and a swipe down leaves the hall: no button sits over the art (Alex, 2026-11-08).
struct RivalHallFilm<Ending: View>: View {
    let film: RivalFilm
    /// The film has ended: its ending shows, and a tap no longer does anything.
    let ended: Bool
    let done: () -> Void
    /// -1 for the rival before, +1 for the next.
    let step: (Int) -> Void
    let close: () -> Void
    @ViewBuilder let ending: () -> Ending

    @State private var player: AVPlayer?

    var body: some View {
        Color.clear
            .overlay(alignment: .bottom) { ending() }
            .background {
                // Laid over the black, so the screen sets their frame and the film sits centred: a
                // filled image beside them would widen the frame and push the film off centre.
                Color.black
                    .overlay {
                        if let image = film.cardImage {
                            Image(uiImage: image).resizable().scaledToFill()
                        }
                    }
                    .overlay {
                        if let player {
                            RivalFilmLayer(player: player)
                        }
                    }
                    .overlay {
                        LinearGradient(stops: [.init(color: .clear, location: 0.48),
                                               .init(color: .black.opacity(0.6), location: 0.64),
                                               .init(color: .black.opacity(0.88), location: 0.78),
                                               .init(color: .black.opacity(0.96), location: 1)],
                                       startPoint: .top, endPoint: .bottom)
                            .opacity(ended ? 1 : 0)
                    }
                    .clipped()
                    .ignoresSafeArea()
                    .allowsHitTesting(false)
            }
        .contentShape(Rectangle())
        .onTapGesture { if !ended { leave() } }
        .gesture(DragGesture(minimumDistance: 24).onEnded { drag in
            let t = drag.translation
            if abs(t.width) > 70, abs(t.width) > abs(t.height) {
                player?.pause()
                step(t.width < 0 ? 1 : -1)
            } else if t.height > 90 {
                player?.pause()
                close()
            }
        })
        .accessibilityElement(children: ended ? .contain : .ignore)
        .accessibilityLabel("\(film.rival.name)'s film")
        .accessibilityAddTraits(ended ? [] : .isButton)
        .accessibilityHint(ended ? "" : "Ends the film")
        .accessibilityAction(.escape) { player?.pause(); close() }
        .task { await play() }
        .onDisappear { player?.pause() }
        // The end can be posted off the main thread: brought back to it before the words rise.
        .onReceive(NotificationCenter.default.publisher(for: AVPlayerItem.didPlayToEndTimeNotification)
            .receive(on: DispatchQueue.main)) { note in
            if let item = note.object as? AVPlayerItem, item === player?.currentItem, !ended { done() }
        }
    }

    private func play() async {
        guard !ended else { return }
        guard let url = film.filmURL, !Welcome.isUnderTest else {
            done()
            return
        }
        // A film you came to watch: it plays with the ring switch off, like the welcome.
        try? AVAudioSession.sharedInstance().setCategory(.playback, options: [.mixWithOthers])
        try? AVAudioSession.sharedInstance().setActive(true)
        let player = AVPlayer(url: url)
        player.actionAtItemEnd = .pause
        self.player = player
        player.play()
        // In case the end is never heard: the words rise once the film's length has passed.
        guard let length = try? await player.currentItem?.asset.load(.duration), length.isNumeric else { return }
        try? await Task.sleep(for: .seconds(length.seconds + 0.4))
        guard !Task.isCancelled, !ended else { return }
        done()
    }

    private func leave() {
        player?.pause()
        done()
    }
}

/// A rival's welcome: its film, full screen and with sound, opening from a point of torchlight;
/// then, at the rival's moment, its name and Begin while the film plays on. A tap skips to the name; a swipe down goes back. Nothing sits over
/// the art. The film's last frame holds behind it.
struct RivalWelcome: View {
    let film: RivalFilm
    let begin: () -> Void
    let back: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var player: AVPlayer?
    @State private var iris: CGFloat = 0
    @State private var titled = false

    var body: some View {
        GeometryReader { geo in
            let reach = hypot(geo.size.width, geo.size.height)
            ZStack {
                // In an overlay, clipped, so a filled picture can't widen the screen.
                Color.black
                    .overlay {
                        if let player {
                            RivalFilmLayer(player: player)
                                .blur(radius: reduceMotion ? 0 : (1 - iris) * 14)
                        } else if let image = film.cardImage {
                            Image(uiImage: image).resizable().scaledToFill()
                        }
                    }
                    .clipped()
                // The torchlight: the dark draws back from the middle.
                RadialGradient(colors: [.clear, .black],
                               center: UnitPoint(x: 0.5, y: 0.42),
                               startRadius: iris * reach * 0.42,
                               endRadius: iris * reach * 0.42 + max(1, reach * 0.28))
                    .opacity(1 - Double(iris) * 0.15)
                    .allowsHitTesting(false)
                // The hall ending's shade, so the words read the same here.
                LinearGradient(stops: [.init(color: .clear, location: 0.48),
                                       .init(color: .black.opacity(0.6), location: 0.64),
                                       .init(color: .black.opacity(0.88), location: 0.78),
                                       .init(color: .black.opacity(0.96), location: 1)],
                               startPoint: .top, endPoint: .bottom)
                    .opacity(titled ? 1 : 0)
                    .allowsHitTesting(false)
                if titled { titleCard.transition(.opacity.combined(with: .offset(y: 18))) }
            }
            .frame(width: geo.size.width, height: geo.size.height)
        }
        .ignoresSafeArea()
        .contentShape(Rectangle())
        .onTapGesture { skip() }
        // No button over the art: a swipe down goes back to the rivals, as does "Not today".
        .gesture(DragGesture(minimumDistance: 24).onEnded { drag in
            let t = drag.translation
            if t.height > 90, t.height > abs(t.width) * 1.5 { leave() }
        })
        .accessibilityAction(.escape) { leave() }
        .task {
            RivalIntros.mark(film.level)
            await play()
        }
        .onDisappear { player?.pause() }
    }

    /// The same words as the hall's film ending (Alex, 2026-11-11: "I like this style better"):
    /// rank between rules, the gold name, the rival's line, Face, and Not today.
    private var titleCard: some View {
        VStack(spacing: 0) {
            Spacer()
            RivalFilmEnding(film: film, open: true,
                            face: {
                                player?.pause()
                                begin()
                            },
                            notToday: leave)
        }
        .padding(.horizontal, 24)
        .padding(.bottom, 44)
    }

    private func play() async {
        // Pictured under test on the film's last frame, with the words up.
        guard let url = film.filmURL, !Welcome.isUnderTest else {
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
        player.play()
        withAnimation(reduceMotion ? .easeOut(duration: 0.4) : .easeOut(duration: 1.8)) { iris = 1 }
        // The name and Begin rise at the rival's moment, a few seconds in, and the film plays on
        // beneath them to its end (Alex, 2026-11-11: waiting the whole film "takes too long").
        // A tap still brings them sooner.
        try? await Task.sleep(for: .seconds(film.beat + 0.8))
        guard !Task.isCancelled else { return }
        showTitle()
    }

    private func skip() {
        guard !titled else { return }
        // To the film's last frame, which holds behind the name.
        if let item = player?.currentItem, item.duration.isNumeric {
            player?.seek(to: item.duration)
        } else {
            player?.seek(to: CMTime(seconds: film.beat + 0.8, preferredTimescale: 600))
        }
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
