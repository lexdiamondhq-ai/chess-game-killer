import ChessKit
import SwiftUI

/// The stage home (Alex's pick, 2026-11-07), laid out as the mockup: "Beauty of Chess" with the
/// music, streak and You up top; the real 3D board turning slowly on a faceted stone stage in a
/// dark room; the rating with three pills under it; a deck of cards (swipe down for the next,
/// All for every one); and a floating glass tab bar with the gold knight. It follows
/// Settings > Home colors, with a sun and moon to switch. Going to a board swoops the camera in.
/// On by default; Settings > Stage home turns it off. The game's own board is untouched.
enum HomeStageLayout {
    static let key = "homeStage"
    static let defaultOn = true

    static func isOn(_ defaults: UserDefaults = .standard) -> Bool {
        defaults.object(forKey: key) as? Bool ?? defaultOn
    }
}

/// What the stage home shows, worked out by the home.
struct HomeStageInfo {
    var upNext: HomeUpNext
    var day: HomeDailyState
    var rating: Int?
    var rankNumber: Int
    var plan: SessionPlan?
    var trainedToday: Bool
    var masterpiece: HomeMasterpiece?
    var name: String
    /// The game on the board.
    var gameFEN: String
    var todayFEN: String?
    var todaySolver: Piece.Color?
    var pieceTheme: BoardTheme
}

/// Where the stage home's taps go.
struct HomeStageActions {
    var play: () -> Void
    var change: () -> Void
    var dailyMove: () -> Void
    var coach: () -> Void
    var learn: () -> Void
    var analyze: () -> Void
    var analyzePosition: (String) -> Void
    var you: () -> Void
    var rooms: () -> Void
}

/// One card in the deck.
enum HomeStageCard: Int, CaseIterable, Identifiable {
    case game, today, coach, masterpiece, analyze
    var id: Int { rawValue }
}

/// The stage's colors in the room's light: the mockup's dark room at night, cream by day.
struct HomeStagePalette {
    let tone: HomeTone

    var dark: Bool { tone.scheme == .dark }
    var gold: Color { dark ? Color(hex: 0xD9B26A) : tone.metal }
    var goldHi: Color { dark ? Color(hex: 0xF4DDA4) : Color(hex: 0xB9822F) }
    var ink: Color { dark ? Color(hex: 0xF3ECE0) : tone.ink }
    var ink2: Color { ink.opacity(dark ? 0.62 : 0.66) }
    var ink3: Color { ink.opacity(dark ? 0.38 : 0.42) }
    var goldFill: LinearGradient {
        LinearGradient(colors: [Color(hex: 0xF1D79C), Color(hex: 0xC99B4E)], startPoint: .top, endPoint: .bottom)
    }
    var card: LinearGradient {
        dark ? LinearGradient(colors: [Color(red: 54 / 255, green: 46 / 255, blue: 37 / 255).opacity(0.92),
                                       Color(red: 24 / 255, green: 20 / 255, blue: 17 / 255).opacity(0.95)],
                              startPoint: .topLeading, endPoint: .bottomTrailing)
            : LinearGradient(colors: [Color.white.opacity(0.96), Color(hex: 0xF3ECE1).opacity(0.96)],
                             startPoint: .topLeading, endPoint: .bottomTrailing)
    }
    var line: Color { dark ? Color(hex: 0xFFF8EB).opacity(0.1) : tone.ink.opacity(0.08) }
    var glass: Color { dark ? Color(red: 30 / 255, green: 26 / 255, blue: 22 / 255).opacity(0.62) : Color.white.opacity(0.72) }
    var tabOn: Color { dark ? Color(hex: 0xFFF8EB).opacity(0.12) : tone.ink.opacity(0.07) }
    var pill: Color { dark ? Color(red: 10 / 255, green: 8 / 255, blue: 7 / 255).opacity(0.4) : Color.white.opacity(0.6) }
    var soft: Color { dark ? Color(hex: 0xFFF8EB).opacity(0.05) : Color.white.opacity(0.7) }
    var shadow: Color { .black.opacity(dark ? 0.6 : 0.14) }
    /// The stone stage under the board.
    var plinth: UIColor {
        dark ? UIColor(red: 0.18, green: 0.157, blue: 0.133, alpha: 1) : UIColor(red: 0.88, green: 0.835, blue: 0.77, alpha: 1)
    }
    var ctaFill: LinearGradient {
        dark ? LinearGradient(colors: [Color(hex: 0xFFF8EB).opacity(0.16), Color(hex: 0xFFF8EB).opacity(0.06)],
                              startPoint: .top, endPoint: .bottom)
            : LinearGradient(colors: [Color.white, Color(hex: 0xF5EFE5)], startPoint: .top, endPoint: .bottom)
    }
}

struct HomeStageView: View {
    let tone: HomeTone
    let look: SculptedLook
    let pieces: [Piece]
    let info: HomeStageInfo
    let actions: HomeStageActions

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @AppStorage("haptics") private var hapticsOn = true
    /// Settings > Home colors, also switched by the sun and moon in the top bar.
    @AppStorage(HomeToneMode.key) private var toneMode = HomeToneMode.defaultMode
    /// The deck's order: the first is in front.
    @State private var order: [HomeStageCard] = HomeStageCard.allCases
    @State private var fanned = false
    @GestureState private var deckDrag: CGFloat = 0
    @State private var music = HomeMusic.shared
    /// 0 at rest, 1 with the camera swooped down into the board and the page faded away.
    @State private var dive: CGFloat = 0
    @State private var swooping = false
    @State private var boardStage = SculptedStage()

    private var palette: HomeStagePalette { HomeStagePalette(tone: tone) }

    var body: some View {
        GeometryReader { geo in
            let safeTop: CGFloat = geo.safeAreaInsets.top
            let safeBottom: CGFloat = geo.safeAreaInsets.bottom
            let full = CGSize(width: geo.size.width, height: geo.size.height + safeTop + safeBottom)
            let layout = HomeStageLayoutMetrics(size: full, safeTop: safeTop, safeBottom: safeBottom)
            ZStack(alignment: .topLeading) {
                HomeStageBackdrop(palette: palette)

                stage(layout)
                    .scaleEffect(1 + 0.45 * dive, anchor: UnitPoint(x: 0.5, y: 0.3))

                page(layout)
                    .opacity(Double(1 - dive))

                if fanned {
                    fan(layout)
                        .transition(.opacity)
                }

                tabBar(layout)
            }
            .frame(width: full.width, height: full.height, alignment: .topLeading)
            .ignoresSafeArea()
        }
        .environment(\.colorScheme, tone.scheme)
        .allowsHitTesting(!swooping)
        .sensoryFeedback(.selection, trigger: order) { _, _ in hapticsOn }
        .sensoryFeedback(.impact(weight: .light), trigger: fanned) { _, _ in hapticsOn }
        .sensoryFeedback(.impact(weight: .medium), trigger: swooping) { _, now in now && hapticsOn }
        .onAppear {
            music.homeAppeared()
            if dive > 0 { settle() }
        }
        .onDisappear { music.homeDisappeared() }
    }

    // MARK: The way to a board

    /// Only on the way to a board (a game, Today's Move, a masterpiece; Alex, 2026-11-07): the
    /// camera swoops down into the board as the page fades and the tab bar drops away, the board
    /// opens, and the home settles back behind it. Every other place opens straight away.
    private func toBoard(_ action: @escaping () -> Void) {
        guard !swooping else { return }
        guard !reduceMotion else {
            action()
            return
        }
        swooping = true
        withAnimation(.timingCurve(0.55, 0, 0.3, 1, duration: 0.5)) { dive = 1 }
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(440))
            action()
            try? await Task.sleep(for: .milliseconds(450))
            settle()
        }
    }

    private func settle() {
        withAnimation(.spring(response: 0.7, dampingFraction: 0.9)) { dive = 0 }
        swooping = false
    }

    // MARK: The stage

    private func stage(_ layout: HomeStageLayoutMetrics) -> some View {
        let upNext: HomeUpNext = info.upNext
        let leaning: Bool = upNext.inProgress && upNext.yourMove
        return ZStack {
            if SculptedAssets.shared.isLoaded {
                HomeStageBoard(stage: boardStage, look: look, pieces: pieces, black: upNext.playerColor == .black,
                               light: upNext.rival.lightUI, leaning: leaning, plinth: palette.plinth,
                               still: reduceMotion, dive: dive)
                    .id(look.name)
            }
            HomeStageMotes(gold: palette.gold, still: reduceMotion)
                .allowsHitTesting(false)
        }
        .frame(width: layout.size.width, height: layout.boardHeight)
        .mask {
            LinearGradient(stops: [.init(color: .black, location: 0),
                                   .init(color: .black, location: 0.72),
                                   .init(color: .black.opacity(0), location: 1)],
                           startPoint: .top, endPoint: .bottom)
        }
        .contentShape(Rectangle())
        .onTapGesture { toBoard(actions.play) }
        .offset(y: layout.boardTop)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(upNext.inProgress ? "Your game against \(upNext.rival.name)" : "Next game: \(upNext.rival.name)")
        .accessibilityAddTraits(.isButton)
    }

    // MARK: The page

    private func page(_ layout: HomeStageLayoutMetrics) -> some View {
        ZStack(alignment: .topLeading) {
            topBar
                .padding(.horizontal, 22)
                .frame(width: layout.size.width)
                .offset(y: layout.topBarTop)
            score
                .frame(width: layout.size.width)
                .offset(y: layout.scoreTop)
            trio
                .frame(width: layout.size.width)
                .offset(y: layout.trioTop)
            deck
                .padding(.horizontal, 16)
                .frame(width: layout.size.width, height: layout.deckHeight)
                .offset(y: layout.deckTop)
        }
        .frame(width: layout.size.width, height: layout.size.height, alignment: .topLeading)
        .blur(radius: fanned ? 14 : 0)
        .allowsHitTesting(!fanned)
    }

    // MARK: Top

    private var topBar: some View {
        HStack(spacing: 10) {
            (Text("Beauty ") + Text("of").italic().foregroundColor(palette.gold) + Text(" Chess"))
                .font(.system(size: 26, weight: .medium, design: .serif))
                .foregroundStyle(palette.ink)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Spacer(minLength: 0)
            if music.available {
                roundButton(label: music.on ? "Music off" : "Music on", action: music.toggle) {
                    HomeMusicBars(on: music.on, gold: palette.goldHi, off: palette.ink3)
                }
            }
            roundButton(label: palette.dark ? "Light mode" : "Dark mode", action: flipLight) {
                Image(systemName: palette.dark ? "sun.max.fill" : "moon.fill")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(palette.goldHi)
            }
            Button { toBoard(actions.dailyMove) } label: {
                HStack(spacing: 5) {
                    Image(systemName: "flame.fill")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(palette.gold)
                    Text("\(info.day.streak)")
                        .font(.system(size: 16, weight: .bold, design: .rounded))
                        .foregroundStyle(palette.goldHi)
                }
                .frame(height: 38)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("\(info.day.streak) day streak")
            Button(action: actions.you) {
                Image(systemName: "crown")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(palette.goldHi)
                    .frame(width: 38, height: 38)
                    .background(Circle().fill(palette.soft))
                    .overlay(Circle().strokeBorder(palette.gold.opacity(0.6), lineWidth: 1.5))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("You")
        }
    }

    private func roundButton<Label: View>(label: String, action: @escaping () -> Void,
                                          @ViewBuilder content: () -> Label) -> some View {
        Button(action: action) {
            content()
                .frame(width: 38, height: 38)
                .background(Circle().fill(palette.soft))
                .overlay(Circle().strokeBorder(palette.line, lineWidth: 1))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }

    private func flipLight() {
        withAnimation(.easeInOut(duration: 0.45)) {
            toneMode = palette.dark ? .light : .dark
        }
    }

    // MARK: Rating and pills

    private var score: some View {
        VStack(spacing: 2) {
            Text("Rating")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(palette.ink2)
            Text(info.rating.map { $0.formatted(.number) } ?? "New")
                .font(.system(size: 46, weight: .bold, design: .rounded))
                .tracking(-0.9)
                .foregroundStyle(palette.ink)
                .monospacedDigit()
        }
        .accessibilityElement(children: .combine)
    }

    private var trio: some View {
        let day: HomeDailyState = info.day
        return VStack(spacing: 0) {
            HomeStageBracket(color: palette.gold.opacity(0.35))
                .frame(width: 200, height: 22)
            HStack(spacing: 16) {
                HomeStagePill(symbol: "flame", value: "\(day.streak)", label: "Streak", palette: palette)
                HomeStagePill(symbol: "puzzlepiece", value: "\(day.puzzlesToday)", label: "Puzzles", palette: palette)
                HomeStagePill(symbol: "crown", value: "\(info.rankNumber)", label: "Level", palette: palette)
            }
        }
    }

    // MARK: The deck

    private var deck: some View {
        ZStack(alignment: .bottom) {
            ForEach(Array(order.enumerated()), id: \.element) { depth, card in
                deckCard(card, depth: depth)
            }
            HStack(spacing: 5) {
                ForEach(HomeStageCard.allCases) { card in
                    Capsule()
                        .fill(card == order.first ? palette.gold : palette.ink.opacity(0.25))
                        .frame(width: card == order.first ? 16 : 5, height: 5)
                }
            }
            .offset(y: 16)
        }
        .gesture(deckSwipe)
    }

    private func deckCard(_ card: HomeStageCard, depth: Int) -> some View {
        let shown: Int = min(depth, 3)
        let lift: CGFloat = [0, -14, -26, -34][shown]
        let scale: CGFloat = [1, 0.94, 0.88, 0.82][shown]
        let dim: Double = [0, 0.3, 0.5, 0.6][shown]
        let drag: CGFloat = depth == 0 ? max(deckDrag, 0) : 0
        return HomeStageCardView(card: card, info: info, palette: palette, front: depth == 0,
                                 open: { open(card) }, all: showAll)
            .overlay {
                RoundedRectangle(cornerRadius: 28, style: .continuous)
                    .fill(Color.black.opacity(palette.dark ? dim : dim * 0.15))
                    .allowsHitTesting(false)
            }
            .scaleEffect(scale, anchor: .top)
            .offset(y: lift + drag)
            .opacity(depth > 2 ? 0 : 1)
            .allowsHitTesting(depth == 0)
            .accessibilityHidden(depth != 0)
            .zIndex(Double(10 - depth))
    }

    /// Down sends the front card to the back; up opens them all.
    private var deckSwipe: some Gesture {
        DragGesture(minimumDistance: 12)
            .updating($deckDrag) { value, state, _ in state = value.translation.height }
            .onEnded { value in
                let dy: CGFloat = value.translation.height
                if dy > 40 {
                    withAnimation(spring) { order.append(order.removeFirst()) }
                } else if dy < -40 {
                    showAll()
                }
            }
    }

    private func showAll() {
        withAnimation(spring) { fanned = true }
    }

    private var spring: Animation {
        reduceMotion ? .easeOut(duration: 0.2) : .spring(response: 0.5, dampingFraction: 0.84)
    }

    private func open(_ card: HomeStageCard) {
        switch card {
        case .game: toBoard(actions.play)
        case .today: toBoard(actions.dailyMove)
        case .coach: actions.coach()
        case .masterpiece:
            if let masterpiece = info.masterpiece, let fen = masterpiece.frames.first {
                toBoard { actions.analyzePosition(fen) }
            }
        case .analyze: actions.analyze()
        }
    }

    // MARK: Every card at once

    private func fan(_ layout: HomeStageLayoutMetrics) -> some View {
        ZStack(alignment: .top) {
            Rectangle()
                .fill(.ultraThinMaterial)
                .overlay(Color.black.opacity(palette.dark ? 0.55 : 0.1))
                .onTapGesture { withAnimation(spring) { fanned = false } }
            VStack(spacing: 0) {
                HStack(alignment: .center) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Today")
                            .font(.system(size: 34, weight: .medium, design: .serif))
                            .foregroundStyle(palette.ink)
                        Text("\(HomeStageCard.allCases.count) things waiting")
                            .font(.system(size: 13))
                            .foregroundStyle(palette.ink2)
                    }
                    Spacer()
                    Button {
                        withAnimation(spring) { fanned = false }
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "square.stack.3d.up")
                                .foregroundStyle(palette.goldHi)
                            Text("Stack")
                        }
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(palette.ink)
                        .padding(.horizontal, 14)
                        .frame(height: 38)
                        .background(Capsule().fill(palette.soft))
                        .overlay(Capsule().strokeBorder(palette.line))
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 20)
                .padding(.top, layout.topBarTop)
                ScrollView {
                    VStack(spacing: 12) {
                        ForEach(order) { card in
                            HomeStageCardView(card: card, info: info, palette: palette, front: true,
                                              open: {
                                                  withAnimation(spring) { fanned = false }
                                                  open(card)
                                              }, all: nil)
                                .frame(height: 178)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 16)
                    .padding(.bottom, 120)
                }
                .scrollIndicators(.hidden)
            }
        }
        .frame(width: layout.size.width, height: layout.size.height)
    }

    // MARK: The tab bar

    private func tabBar(_ layout: HomeStageLayoutMetrics) -> some View {
        HomeStageTabBar(palette: palette, upNext: info.upNext,
                        learn: actions.learn, play: { toBoard(actions.play) },
                        rooms: actions.rooms, you: actions.you)
            .frame(width: layout.size.width)
            .offset(y: layout.tabBarTop + 50 * dive)
            .opacity(fanned ? 0 : Double(1 - dive))
            .allowsHitTesting(!fanned)
    }
}

/// Where everything sits, as fractions of the screen like the mockup, kept apart on short phones.
struct HomeStageLayoutMetrics {
    let size: CGSize
    let safeTop: CGFloat
    let safeBottom: CGFloat

    var topBarTop: CGFloat { safeTop + 6 }
    var boardTop: CGFloat { safeTop + 2 }
    var boardHeight: CGFloat { size.height * 0.46 }
    var scoreTop: CGFloat { size.height * 0.468 }
    var trioTop: CGFloat { scoreTop + 66 }
    /// The pills and their names end here.
    private var trioBottom: CGFloat { trioTop + 22 + 42 + 22 }
    var tabBarTop: CGFloat { size.height - max(safeBottom, 20) - 8 - 66 }
    var deckHeight: CGFloat { min(178, max(150, tabBarTop - 26 - (trioBottom + 34))) }
    var deckTop: CGFloat { tabBarTop - 26 - deckHeight }
}

// MARK: - The board on its stage

/// The real 3D board on a faceted stone stage, the camera circling it slowly. `dive` swoops the
/// camera down and around into the board, on the way to a board.
struct HomeStageBoard: View, Animatable {
    let stage: SculptedStage
    let look: SculptedLook
    let pieces: [Piece]
    let black: Bool
    let light: UIColor
    let leaning: Bool
    let plinth: UIColor
    let still: Bool
    var dive: CGFloat

    var animatableData: CGFloat {
        get { dive }
        set { dive = newValue }
    }

    var body: some View {
        GeometryReader { geo in
            TimelineView(.animation(minimumInterval: 1 / 30, paused: still)) { context in
                let time: Double = still ? 0 : context.date.timeIntervalSinceReferenceDate
                HomeHeroBoard(stage: stage, look: look, pieces: pieces,
                              camera: Self.camera(size: geo.size, time: time, dive: dive, black: black),
                              presence: HomeWindowBoard.presence(light, arrival: 0, leaning: leaning),
                              plinth: plinth)
            }
        }
    }

    /// About two minutes a turn, high enough to see the whole board, the stage cut by the edges.
    static func camera(size: CGSize, time: Double, dive: CGFloat, black: Bool) -> SculptedCamera {
        let d = Float(min(max(dive, 0), 1))
        let ease: Float = d * d * (3 - 2 * d)
        let orbit = Float((time * 0.05).truncatingRemainder(dividingBy: 2 * Double.pi))
        var camera = SculptedCamera()
        camera.fieldOfView = 26 * .pi / 180
        camera.aspect = Float(size.width / max(size.height, 1))
        camera.azimuth = -0.35 + orbit + 1.8 * ease + (black ? Float.pi : 0)
        camera.elevation = (40 + 42 * ease) * .pi / 180
        camera.distance = 25 - 13 * ease
        camera.focus = SIMD3<Float>(0, -1.2 * (1 - ease), 0)
        return camera
    }
}

// MARK: - A card

struct HomeStageCardView: View {
    let card: HomeStageCard
    let info: HomeStageInfo
    let palette: HomeStagePalette
    /// Only the front card shows what's on it; the ones behind are just their edges.
    let front: Bool
    let open: () -> Void
    /// Shows every card. Nil in the list of every card.
    let all: (() -> Void)?

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 28, style: .continuous)
        VStack(alignment: .leading, spacing: 8) {
            head
            HStack(alignment: .center, spacing: 14) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.system(size: 19, weight: .bold))
                        .foregroundStyle(palette.ink)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                    Text(detail)
                        .font(.system(size: 14))
                        .foregroundStyle(palette.ink2)
                        .lineLimit(2)
                }
                Spacer(minLength: 0)
                if let fen {
                    HomeMiniBoard(fen: fen, flipped: flipped, theme: info.pieceTheme, tone: palette.tone)
                        .frame(width: 62, height: 62)
                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                        .shadow(color: .black.opacity(0.5), radius: 8, y: 6)
                }
            }
            Spacer(minLength: 0)
            Button(action: open) {
                HStack(spacing: 8) {
                    Image(systemName: ctaSymbol)
                        .font(.system(size: 14, weight: .semibold))
                    Text(cta)
                        .font(.system(size: 15, weight: .semibold))
                }
                .foregroundStyle(card == .game ? Color(hex: 0x2A1E0F) : palette.ink)
                .frame(maxWidth: .infinity)
                .frame(height: 44)
                .background(ctaBackground)
            }
            .buttonStyle(HomeStagePress())
        }
        .opacity(front ? 1 : 0)
        .padding(.horizontal, 18)
        .padding(.vertical, 16)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(shape.fill(palette.card))
        .background(shape.fill(.ultraThinMaterial))
        .overlay(shape.strokeBorder(palette.line, lineWidth: 1))
        .clipShape(shape)
        .shadow(color: palette.shadow, radius: 20, y: 18)
        .contentShape(shape)
        .onTapGesture(perform: open)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
    }

    private var head: some View {
        HStack(spacing: 8) {
            Image(systemName: headSymbol)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(palette.gold)
            Text(eyebrow)
                .foregroundStyle(palette.ink2)
            if let sub = eyebrowDetail {
                Text("/").foregroundStyle(palette.ink3)
                Text(sub).foregroundStyle(palette.ink2)
            }
            Spacer(minLength: 0)
            if let all {
                Button(action: all) {
                    HStack(spacing: 4) {
                        Image(systemName: "square.stack.3d.up")
                        Text("All")
                    }
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(palette.goldHi)
                    .padding(.horizontal, 9)
                    .frame(height: 26)
                    .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(palette.gold.opacity(0.12)))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Show all cards")
            }
        }
        .font(.system(size: 13))
        .lineLimit(1)
    }

    @ViewBuilder
    private var ctaBackground: some View {
        if card == .game {
            Capsule().fill(palette.goldFill)
                .shadow(color: Color(hex: 0xD9B26A).opacity(0.5), radius: 10, y: 6)
        } else {
            Capsule().fill(palette.ctaFill)
                .overlay(Capsule().strokeBorder(palette.line, lineWidth: 1))
        }
    }

    // MARK: Words

    private var headSymbol: String {
        switch card {
        case .game: return "play"
        case .today: return "sun.max"
        case .coach: return "book"
        case .masterpiece: return "sparkle"
        case .analyze: return "magnifyingglass"
        }
    }

    private var eyebrow: String {
        switch card {
        case .game: return info.upNext.inProgress ? "Your game" : "Next game"
        case .today: return "Today's Move"
        case .coach: return "Coach Leo"
        case .masterpiece: return "Masterpiece of the day"
        case .analyze: return "Analyze"
        }
    }

    private var eyebrowDetail: String? {
        switch card {
        case .game: return info.upNext.rival.name
        case .today: return Date.now.formatted(.dateTime.weekday(.abbreviated).day())
        case .coach: return info.plan.map { "\($0.minutes) min" }
        case .masterpiece, .analyze: return nil
        }
    }

    private var title: String {
        switch card {
        case .game:
            let upNext: HomeUpNext = info.upNext
            guard upNext.inProgress else { return "Play \(upNext.rival.name)" }
            return upNext.yourMove ? "Your move, move \(upNext.moveNumber)" : "Their move, move \(upNext.moveNumber)"
        case .today:
            if info.day.found { return "Found it" }
            let side: String = info.todaySolver == .black ? "Black" : "White"
            return "\(side) to play and win"
        case .coach: return info.plan?.title ?? "Today's session"
        case .masterpiece: return info.masterpiece?.title ?? "A great game"
        case .analyze: return "Any position"
        }
    }

    private var detail: String {
        switch card {
        case .game:
            let upNext: HomeUpNext = info.upNext
            let side: String = upNext.playerColor == .black ? "Black" : "White"
            let clock: String = upNext.timeControl.isTimed ? ", \(upNext.timeControl.name)" : ""
            return upNext.inProgress ? "You're \(side)\(clock). Pick up where you left off."
                : "You're \(side)\(clock). \(upNext.rival.elo)."
        case .today:
            if info.day.played { return "Back tomorrow for the next one." }
            return info.day.difficulty.isEmpty ? "One puzzle, the same for everyone." : "\(info.day.difficulty). Can you see it?"
        case .coach:
            if info.trainedToday { return "Done today. Another round?" }
            return info.plan?.headline ?? "Pick up where you stopped."
        case .masterpiece: return info.masterpiece?.players ?? "Play through the finish."
        case .analyze: return "A photo, a screenshot or a board you set up."
        }
    }

    private var cta: String {
        switch card {
        case .game: return info.upNext.inProgress ? "Resume" : "Play"
        case .today: return info.day.played ? "See it again" : "Solve"
        case .coach: return "Continue with Leo"
        case .masterpiece: return "Watch it"
        case .analyze: return "Analyze"
        }
    }

    private var ctaSymbol: String {
        switch card {
        case .game: return "play.fill"
        case .today: return "scope"
        case .coach: return "book"
        case .masterpiece: return "sparkle"
        case .analyze: return "magnifyingglass"
        }
    }

    private var fen: String? {
        switch card {
        case .game: return info.gameFEN
        case .today: return info.todayFEN
        case .masterpiece: return info.masterpiece?.frames.first
        case .coach, .analyze: return nil
        }
    }

    private var flipped: Bool {
        switch card {
        case .game: return info.upNext.playerColor == .black
        case .today: return info.todaySolver == .black
        case .masterpiece: return info.masterpiece?.flipped ?? false
        case .coach, .analyze: return false
        }
    }
}

// MARK: - Pieces of the stage

/// The room: the mockup's cave at night (warm smoke, dark walls at the sides, a pool of gold
/// light), cream with a soft glow by day.
struct HomeStageBackdrop: View {
    let palette: HomeStagePalette

    var body: some View {
        GeometryReader { geo in
            let w: CGFloat = geo.size.width
            let h: CGFloat = geo.size.height
            if palette.dark {
                ZStack {
                    LinearGradient(stops: [.init(color: Color(hex: 0x211B15), location: 0),
                                           .init(color: Color(hex: 0x0E0C0B), location: 0.55),
                                           .init(color: Color(hex: 0x070606), location: 1)],
                                   startPoint: .top, endPoint: .bottom)
                    Ellipse()
                        .fill(RadialGradient(colors: [Color(hex: 0xD9B26A).opacity(0.22), .clear],
                                             center: .center, startRadius: 0, endRadius: w * 0.6))
                        .frame(width: w * 1.2, height: h * 0.68)
                        .position(x: w / 2, y: h * 0.3)
                    HStack {
                        HomeStageWall()
                        Spacer()
                        HomeStageWall().scaleEffect(x: -1)
                    }
                    .frame(height: h * 0.56)
                    .frame(maxHeight: .infinity, alignment: .top)
                }
            } else {
                ZStack {
                    palette.tone.canvas
                    Ellipse()
                        .fill(RadialGradient(colors: [Color.white.opacity(0.95), Color.white.opacity(0)],
                                             center: .center, startRadius: 0, endRadius: w * 0.7))
                        .frame(width: w * 1.3, height: h * 0.7)
                        .position(x: w / 2, y: h * 0.28)
                    Ellipse()
                        .fill(RadialGradient(colors: [Color(hex: 0xD9B26A).opacity(0.14), .clear],
                                             center: .center, startRadius: 0, endRadius: w * 0.5))
                        .frame(width: w, height: h * 0.5)
                        .position(x: w / 2, y: h * 0.3)
                }
            }
        }
        .ignoresSafeArea()
        .accessibilityHidden(true)
    }
}

/// A dark rock wall at the room's side.
struct HomeStageWall: View {
    var body: some View {
        UnevenRoundedRectangle(cornerRadii: .init(topLeading: 0, bottomLeading: 0,
                                                  bottomTrailing: 90, topTrailing: 50),
                               style: .continuous)
            .fill(LinearGradient(colors: [Color(hex: 0x060505), Color(hex: 0x14100D).opacity(0)],
                                 startPoint: .leading, endPoint: .trailing))
            .blur(radius: 2)
            .frame(width: 120)
    }
}

/// The bracket from the rating down to its three pills.
struct HomeStageBracket: View {
    let color: Color

    var body: some View {
        Canvas { gc, size in
            var path = Path()
            let top: CGFloat = 10
            let r: CGFloat = 10
            path.move(to: CGPoint(x: size.width / 2, y: 0))
            path.addLine(to: CGPoint(x: size.width / 2, y: top))
            path.move(to: CGPoint(x: 0, y: size.height))
            path.addLine(to: CGPoint(x: 0, y: top + r))
            path.addQuadCurve(to: CGPoint(x: r, y: top), control: CGPoint(x: 0, y: top))
            path.addLine(to: CGPoint(x: size.width - r, y: top))
            path.addQuadCurve(to: CGPoint(x: size.width, y: top + r), control: CGPoint(x: size.width, y: top))
            path.addLine(to: CGPoint(x: size.width, y: size.height))
            gc.stroke(path, with: .color(color), lineWidth: 1)
        }
        .accessibilityHidden(true)
    }
}

/// One of the three pills under the rating: an icon and a number in a gold ring, its name below.
struct HomeStagePill: View {
    let symbol: String
    let value: String
    let label: String
    let palette: HomeStagePalette

    var body: some View {
        VStack(spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: symbol)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(palette.gold)
                Text(value)
                    .font(.system(size: 17, weight: .bold, design: .rounded))
                    .foregroundStyle(palette.ink)
                    .monospacedDigit()
            }
            .padding(.horizontal, 14)
            .frame(height: 42)
            .background(Capsule().fill(palette.pill))
            .overlay(Capsule().strokeBorder(palette.gold.opacity(0.55), lineWidth: 1.5))
            Text(label)
                .font(.system(size: 12))
                .foregroundStyle(palette.ink2)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(label): \(value)")
    }
}

/// Slow gold dust in the light.
struct HomeStageMotes: View {
    let gold: Color
    let still: Bool

    private static let seeds: [(x: CGFloat, y: CGFloat, r: CGFloat, speed: Double)] = (0..<26).map { i in
        (x: CGFloat((i * 37) % 100) / 100, y: CGFloat((i * 53) % 100) / 100,
         r: 0.8 + CGFloat(i % 3) * 0.6, speed: 0.02 + Double(i % 5) * 0.006)
    }

    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 30, paused: still)) { context in
            Canvas { gc, size in
                let t: Double = context.date.timeIntervalSinceReferenceDate
                for seed in Self.seeds {
                    var rise: Double = (Double(seed.y) - t * seed.speed).truncatingRemainder(dividingBy: 1)
                    if rise < 0 { rise += 1 }
                    let y = CGFloat(rise) * size.height
                    let sway = CGFloat(sin(t * 0.6 + Double(seed.x) * 9)) * 6
                    let x: CGFloat = seed.x * size.width + sway
                    let fade: Double = sin(rise * .pi)
                    let rect = CGRect(x: x, y: y, width: seed.r * 2, height: seed.r * 2)
                    gc.fill(Path(ellipseIn: rect), with: .color(gold.opacity(0.55 * fade)))
                }
            }
        }
    }
}

/// A button sinks a little under the finger.
struct HomeStagePress: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.95 : 1)
            .animation(.spring(response: 0.25, dampingFraction: 0.7), value: configuration.isPressed)
    }
}

/// The floating glass tab bar, as in the mockup: Today, Learn, the gold knight to play, You and
/// Rooms. The icons are the app's own chess glyphs, bold.
struct HomeStageTabBar: View {
    let palette: HomeStagePalette
    let upNext: HomeUpNext
    let learn: () -> Void
    let play: () -> Void
    let rooms: () -> Void
    let you: () -> Void

    var body: some View {
        HStack(spacing: 2) {
            HomeStageTab(title: "Today", glyph: Glyphs.today, on: true, palette: palette) {}
            HomeStageTab(title: "Learn", glyph: Glyphs.coach, on: false, palette: palette, action: learn)
            jewel
                .padding(.horizontal, 4)
            HomeStageTab(title: "You", glyph: Glyphs.king, on: false, palette: palette, action: you)
            HomeStageTab(title: "Rooms", glyph: Glyphs.home, on: false, palette: palette, action: rooms)
        }
        .padding(6)
        .background {
            Capsule()
                .fill(.ultraThinMaterial)
                .overlay(Capsule().fill(palette.glass))
                .overlay(Capsule().strokeBorder(palette.line, lineWidth: 1))
                .shadow(color: palette.shadow, radius: 20, y: 14)
        }
    }

    private var jewel: some View {
        Button(action: play) {
            ZStack {
                Circle()
                    .fill(RadialGradient(stops: [.init(color: Color(hex: 0xFCEBC0), location: 0),
                                                 .init(color: Color(hex: 0xD7A957), location: 0.5),
                                                 .init(color: Color(hex: 0x8A6125), location: 1)],
                                         center: UnitPoint(x: 0.34, y: 0.28), startRadius: 0, endRadius: 34))
                Circle()
                    .strokeBorder(Color.white.opacity(0.45), lineWidth: 1)
                Glyph(name: Glyphs.train, size: 30, weight: .bold)
                    .foregroundStyle(Color(hex: 0x2E200C))
            }
            .frame(width: 54, height: 54)
            .shadow(color: Color(hex: 0xD9B26A).opacity(0.6), radius: 11)
        }
        .buttonStyle(HomeStagePress())
        .accessibilityLabel(upNext.inProgress ? "Resume your game" : "Play \(upNext.rival.name)")
    }
}

/// One tab: a bold glyph over its name, the page showing lit in a soft capsule.
struct HomeStageTab: View {
    let title: String
    let glyph: String
    let on: Bool
    let palette: HomeStagePalette
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 3) {
                Glyph(name: glyph, size: 23, weight: .bold)
                    .foregroundStyle(on ? palette.goldHi : palette.ink.opacity(palette.dark ? 0.78 : 0.7))
                Text(title)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(on ? palette.ink : palette.ink2)
            }
            .frame(width: 62, height: 54)
            .background(Capsule().fill(on ? palette.tabOn : .clear))
            .contentShape(Capsule())
        }
        .buttonStyle(HomeStagePress())
        .accessibilityLabel(title)
        .accessibilityAddTraits(on ? .isSelected : [])
    }
}

/// Four little bars that dance while the music plays.
struct HomeMusicBars: View {
    let on: Bool
    let gold: Color
    let off: Color

    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 12, paused: !on)) { context in
            let t: Double = context.date.timeIntervalSinceReferenceDate
            HStack(alignment: .bottom, spacing: 2) {
                ForEach(0..<4, id: \.self) { i in
                    Capsule()
                        .fill(on ? gold : off)
                        .frame(width: 2.5, height: on ? CGFloat(4 + 10 * abs(sin(t * 2.8 + Double(i) * 1.3))) : 4)
                }
            }
            .frame(height: 14, alignment: .bottom)
        }
    }
}
