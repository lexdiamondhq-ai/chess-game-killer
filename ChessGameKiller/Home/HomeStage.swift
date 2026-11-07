import ChessKit
import SwiftUI

/// The stage home (Alex's pick, 2026-11-07): the real 3D board lit on a stage, your level with
/// three rings, a deck of cards for what's next, and a floating glass tab bar. It follows
/// Settings > Home colors (Light, Middle or Dark). The board turns slowly on a stone stage, and
/// every way out swoops the camera down into the board as the page fades, then opens.
/// On by default (Alex, 2026-11-07); Settings > Stage home turns it off, back to the board
/// and sheet. The game's own board is untouched: only Home looks like this.
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
    /// Toward the next coach rank, 0...1.
    var rankProgress: Double
    var plan: SessionPlan?
    var trainedToday: Bool
    var masterpiece: HomeMasterpiece?
    var name: String
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

/// The stage's colors in the room's light: dark glass at night, milk glass by day.
struct HomeStagePalette {
    let tone: HomeTone

    var dark: Bool { tone.scheme == .dark }
    var gold: Color { tone.metal }
    /// The bright end of the gold gradients.
    var goldHi: Color { dark ? Color(hex: 0xF4DDA4) : Color(hex: 0xE2B56A) }
    var goldLo: Color { dark ? Color(hex: 0xC99B4E) : Color(hex: 0xA8732A) }
    var glassFill: Color { dark ? Color(hex: 0x201B16).opacity(0.55) : Color.white.opacity(0.66) }
    var glassLine: Color { dark ? Color(hex: 0xFFF8EB).opacity(0.11) : tone.ink.opacity(0.08) }
    var chipFill: Color { dark ? Color.white.opacity(0.07) : Color.white.opacity(0.78) }
    var chipLine: Color { dark ? Color.white.opacity(0.1) : tone.ink.opacity(0.08) }
    var track: Color { dark ? Color.white.opacity(0.1) : tone.ink.opacity(0.08) }
    var dot: Color { dark ? Color.white.opacity(0.22) : tone.ink.opacity(0.18) }
    var shadow: Double { dark ? 0.5 : 0.14 }
    /// The stone stage under the board.
    var plinth: UIColor { dark ? UIColor(red: 0.2, green: 0.17, blue: 0.145, alpha: 1) : UIColor(red: 0.9, green: 0.855, blue: 0.795, alpha: 1) }

    var goldFill: LinearGradient {
        LinearGradient(colors: [goldHi, goldLo], startPoint: .top, endPoint: .bottom)
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
    /// The deck's order: the first is in front.
    @State private var order: [HomeStageCard] = HomeStageCard.allCases
    @State private var fanned = false
    @GestureState private var deckDrag: CGFloat = 0
    @State private var music = HomeMusic.shared
    /// Settings > Home colors, also switched by the sun and moon in the top bar.
    @AppStorage(HomeToneMode.key) private var toneMode = HomeToneMode.defaultMode
    /// 0 at rest, 1 with the camera swooped down into the board and the page faded away.
    @State private var dive: CGFloat = 0
    @State private var swirling = false
    @State private var boardStage = SculptedStage()

    private var palette: HomeStagePalette { HomeStagePalette(tone: tone) }
    private var gold: Color { tone.metal }

    var body: some View {
        GeometryReader { geo in
            let width: CGFloat = geo.size.width
            let safeTop: CGFloat = geo.safeAreaInsets.top
            let stageHeight: CGFloat = min(width * 1.02, geo.size.height * 0.5)
            ZStack(alignment: .top) {
                HomeStageBackdrop(tone: tone)
                    .ignoresSafeArea()

                stage(width: width, height: stageHeight + safeTop)
                    .scaleEffect(1 + 0.5 * dive, anchor: UnitPoint(x: 0.5, y: 0.35))
                    .ignoresSafeArea(edges: .top)
                page(stageHeight: stageHeight)
                    .opacity(Double(1 - dive))
                    .scaleEffect(1 + 0.06 * dive)

                if fanned {
                    fan(safeTop: safeTop)
                        .transition(.opacity)
                        .zIndex(2)
                }
            }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                HomeStageTabBar(tone: tone, upNext: info.upNext,
                                learn: actions.learn, play: { toBoard(actions.play) },
                                rooms: actions.rooms, you: actions.you)
                    .padding(.horizontal, 14)
                    .padding(.bottom, 4)
                    .opacity(fanned ? 0 : Double(1 - dive))
                    .offset(y: 50 * dive)
            }
        }
        .environment(\.colorScheme, tone.scheme)
        .allowsHitTesting(!swirling)
        .sensoryFeedback(.selection, trigger: order) { _, _ in hapticsOn }
        .sensoryFeedback(.impact(weight: .light), trigger: fanned) { _, _ in hapticsOn }
        .sensoryFeedback(.impact(weight: .medium), trigger: swirling) { _, now in now && hapticsOn }
        .onAppear {
            music.homeAppeared()
            if dive > 0 { settle() }
        }
        .onDisappear { music.homeDisappeared() }
    }

    private func page(stageHeight: CGFloat) -> some View {
        VStack(spacing: 0) {
            topBar
                .padding(.horizontal, 18)
                .padding(.top, 6)
            Spacer(minLength: 0)
                .frame(height: max(stageHeight - 70, 120))
            levelRow
                .padding(.horizontal, 20)
            deck
                .padding(.horizontal, 16)
                .padding(.top, 18)
            Spacer(minLength: 0)
        }
        .blur(radius: fanned ? 14 : 0)
        .allowsHitTesting(!fanned)
    }

    // MARK: The way out

    /// Only on the way to a board (a game, Today's Move, a masterpiece; Alex, 2026-11-07): the
    /// camera swirls down into the board as the page fades and the tab bar drops away, the board
    /// opens, and the home settles back behind it. Every other place opens straight away.
    private func toBoard(_ action: @escaping () -> Void) {
        guard !swirling else { return }
        guard !reduceMotion else {
            action()
            return
        }
        swirling = true
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
        swirling = false
    }

    // MARK: The stage

    private func stage(width: CGFloat, height: CGFloat) -> some View {
        let upNext: HomeUpNext = info.upNext
        let leaning: Bool = upNext.inProgress && upNext.yourMove
        return ZStack {
            HomeStageHalo(gold: gold, dark: palette.dark)
                .allowsHitTesting(false)
            if SculptedAssets.shared.isLoaded {
                HomeStageBoard(stage: boardStage, look: look, pieces: pieces, black: upNext.playerColor == .black,
                               light: upNext.rival.lightUI, leaning: leaning, plinth: palette.plinth,
                               still: reduceMotion, dive: dive)
                    .id(look.name)
            }
            HomeStageMotes(gold: gold, still: reduceMotion)
                .allowsHitTesting(false)
        }
        .frame(width: width, height: height)
        .mask {
            LinearGradient(stops: [.init(color: .black.opacity(0.0), location: 0),
                                   .init(color: .black, location: 0.16),
                                   .init(color: .black, location: 0.72),
                                   .init(color: .black.opacity(0), location: 1)],
                           startPoint: .top, endPoint: .bottom)
        }
        .contentShape(Rectangle())
        .onTapGesture { toBoard(actions.play) }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(upNext.inProgress ? "Your game against \(upNext.rival.name)" : "Next game: \(upNext.rival.name)")
        .accessibilityAddTraits(.isButton)
    }

    // MARK: Top

    private var topBar: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 1) {
                Text(greeting)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(tone.ink2)
                Text("Beauty of Chess")
                    .font(.system(size: 19, weight: .medium, design: .serif))
                    .foregroundStyle(tone.ink)
            }
            .lineLimit(1)
            .minimumScaleFactor(0.7)
            Spacer(minLength: 0)
            if music.available {
                HomeStageCircleButton(palette: palette, label: music.on ? "Music off" : "Music on", action: music.toggle) {
                    HomeMusicBars(on: music.on, gold: gold, off: tone.ink3)
                }
            }
            HomeStageCircleButton(palette: palette, label: palette.dark ? "Light mode" : "Dark mode", action: flipLight) {
                Image(systemName: palette.dark ? "sun.max.fill" : "moon.fill")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(gold)
                    .contentTransition(.symbolEffect(.replace))
            }
            streakChip
            HomeStageCircleButton(palette: palette, label: "You", action: actions.you) {
                Text(initial)
                    .font(.system(size: 16, weight: .semibold, design: .serif))
                    .foregroundStyle(tone.onIvory)
                    .frame(width: 40, height: 40)
                    .background(Circle().fill(palette.goldFill))
            }
        }
    }

    private func flipLight() {
        withAnimation(.easeInOut(duration: 0.45)) {
            toneMode = palette.dark ? .light : .dark
        }
    }

    private var streakChip: some View {
        Button { toBoard(actions.dailyMove) } label: {
            HStack(spacing: 5) {
                Image(systemName: "flame.fill")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(gold)
                Text("\(info.day.streak)")
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                    .foregroundStyle(tone.ink)
            }
            .padding(.horizontal, 12)
            .frame(height: 40)
            .background(Capsule().fill(palette.chipFill))
            .overlay(Capsule().strokeBorder(palette.chipLine))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(info.day.streak) day streak")
    }

    private var greeting: String {
        let hour: Int = Calendar.current.component(.hour, from: .now)
        let part: String = hour < 5 ? "Good evening" : hour < 12 ? "Good morning" : hour < 18 ? "Good afternoon" : "Good evening"
        let name: String = info.name.trimmingCharacters(in: .whitespaces)
        return name.isEmpty ? part : "\(part), \(name)"
    }

    private var initial: String {
        let name: String = info.name.trimmingCharacters(in: .whitespaces)
        return name.first.map { String($0).uppercased() } ?? "♞"
    }

    // MARK: Level and rings

    private var levelRow: some View {
        HStack(alignment: .center, spacing: 14) {
            VStack(alignment: .leading, spacing: 2) {
                Text(info.rating.map { $0.formatted(.number) } ?? "New")
                    .font(.system(size: 44, weight: .regular, design: .serif))
                    .foregroundStyle(palette.goldFill)
                    .monospacedDigit()
                Text(info.rating == nil ? "Play a few games for your level" : "Your level")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(tone.ink2)
            }
            Spacer(minLength: 0)
            rings
        }
    }

    private var rings: some View {
        let day: HomeDailyState = info.day
        let need: Int = DailyRules.puzzlesForTheDay
        let rank: Double = info.rankProgress
        return HStack(spacing: 14) {
            HomeStageRing(value: Double(min(day.streak, 7)) / 7, label: "Streak", text: "\(day.streak)", palette: palette)
            HomeStageRing(value: Double(min(day.puzzlesToday, need)) / Double(need), label: "Puzzles",
                          text: "\(day.puzzlesToday)", palette: palette)
            HomeStageRing(value: rank, label: "Rank", text: "\(Int((rank * 100).rounded()))%", palette: palette)
        }
    }

    // MARK: The deck

    private static let deckHeight: CGFloat = 128

    private var deck: some View {
        VStack(spacing: 10) {
            ZStack(alignment: .bottom) {
                ForEach(Array(order.prefix(3).enumerated().reversed()), id: \.element) { depth, card in
                    deckCard(card, depth: depth)
                }
            }
            .frame(height: Self.deckHeight + 22, alignment: .bottom)
            .gesture(deckSwipe)

            HStack {
                HStack(spacing: 5) {
                    ForEach(HomeStageCard.allCases) { card in
                        Capsule()
                            .fill(card == order.first ? gold : palette.dot)
                            .frame(width: card == order.first ? 16 : 6, height: 6)
                    }
                }
                Spacer()
                allButton
            }
            .padding(.horizontal, 4)
        }
    }

    private var allButton: some View {
        Button {
            withAnimation(spring) { fanned = true }
        } label: {
            HStack(spacing: 5) {
                Image(systemName: "square.stack.3d.down.right")
                Text("All")
            }
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(tone.ink)
            .padding(.horizontal, 12)
            .frame(height: 30)
            .background(Capsule().fill(palette.chipFill))
            .overlay(Capsule().strokeBorder(palette.chipLine))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Show all cards")
    }

    private func deckCard(_ card: HomeStageCard, depth: Int) -> some View {
        let lift: CGFloat = CGFloat(depth) * -11
        let scale: CGFloat = 1 - CGFloat(depth) * 0.05
        let drag: CGFloat = depth == 0 ? max(deckDrag, -40) : 0
        return HomeStageCardView(card: card, info: info, tone: tone, open: { open(card) },
                                 secondary: secondary(for: card))
            .frame(height: Self.deckHeight)
            .scaleEffect(scale, anchor: .top)
            .offset(y: lift + drag)
            .opacity(depth == 0 ? 1 : 0.9 - Double(depth) * 0.2)
            .allowsHitTesting(depth == 0)
            .accessibilityHidden(depth != 0)
            .zIndex(Double(3 - depth))
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
                    withAnimation(spring) { fanned = true }
                }
            }
    }

    /// The game card's Change (or New during a game).
    private func secondary(for card: HomeStageCard) -> (() -> Void)? {
        guard card == .game else { return nil }
        let change: () -> Void = actions.change
        return change
    }

    private var spring: Animation {
        reduceMotion ? .easeOut(duration: 0.2) : .spring(response: 0.42, dampingFraction: 0.82)
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

    // MARK: All the cards at once

    private func fan(safeTop: CGFloat) -> some View {
        ZStack(alignment: .top) {
            Color.black.opacity(palette.dark ? 0.55 : 0.25)
                .ignoresSafeArea()
                .onTapGesture { withAnimation(spring) { fanned = false } }
            ScrollView {
                VStack(spacing: 12) {
                    ForEach(Array(order.enumerated()), id: \.element) { index, card in
                        HomeStageCardView(card: card, info: info, tone: tone,
                                          open: {
                                              withAnimation(spring) { fanned = false }
                                              open(card)
                                          },
                                          secondary: secondary(for: card))
                            .frame(height: Self.deckHeight)
                            .transition(.offset(y: CGFloat(-index) * 40).combined(with: .opacity))
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 70)
                .padding(.bottom, 110)
            }
            .scrollIndicators(.hidden)
            VStack {
                Spacer()
                Button {
                    withAnimation(spring) { fanned = false }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "square.stack.3d.up")
                        Text("Stack")
                    }
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(tone.onIvory)
                    .padding(.horizontal, 22)
                    .frame(height: 46)
                    .background(Capsule().fill(palette.goldFill))
                }
                .buttonStyle(.plain)
                .padding(.bottom, 24)
            }
        }
    }
}

// MARK: - The board on its stage

/// The real 3D board on a round stone stage, the camera circling it slowly. `dive` swoops the
/// camera down and around into the board, for the way out of the home.
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

    /// About two minutes a turn, a little above the board, the whole stage in view.
    static func camera(size: CGSize, time: Double, dive: CGFloat, black: Bool) -> SculptedCamera {
        let d: Float = Float(min(max(dive, 0), 1))
        let ease: Float = d * d * (3 - 2 * d)
        let orbit: Float = Float((time * 0.05).truncatingRemainder(dividingBy: 2 * Double.pi))
        var camera = SculptedCamera()
        camera.fieldOfView = 22 * .pi / 180
        camera.aspect = Float(size.width / max(size.height, 1))
        camera.azimuth = -0.45 + orbit + 1.8 * ease + (black ? Float.pi : 0)
        camera.elevation = (30 + 52 * ease) * .pi / 180
        camera.distance = 36 - 24 * ease
        camera.focus = SIMD3<Float>(0, -0.5 * (1 - ease), 0)
        return camera
    }
}

// MARK: - A card

struct HomeStageCardView: View {
    let card: HomeStageCard
    let info: HomeStageInfo
    let tone: HomeTone
    let open: () -> Void
    var secondary: (() -> Void)? = nil

    private var palette: HomeStagePalette { HomeStagePalette(tone: tone) }
    private var gold: Color { tone.metal }

    var body: some View {
        Button(action: open) {
            HStack(spacing: 14) {
                orb
                VStack(alignment: .leading, spacing: 3) {
                    Text(eyebrow.uppercased())
                        .font(.system(size: 11, weight: .semibold))
                        .tracking(1.6)
                        .foregroundStyle(gold)
                    Text(title)
                        .font(.system(size: 22, weight: .medium, design: .serif))
                        .foregroundStyle(tone.ink)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                    Text(detail)
                        .font(.system(size: 13))
                        .foregroundStyle(tone.ink2)
                        .lineLimit(2)
                }
                Spacer(minLength: 0)
                action
            }
            .padding(.horizontal, 16)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(HomeStageGlass(corner: 26, palette: palette))
            .contentShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
        }
        .buttonStyle(HomeStagePress())
        .accessibilityElement(children: .combine)
        .accessibilityAction(named: "Change") { secondary?() }
    }

    private var orb: some View {
        ZStack {
            Circle()
                .fill(RadialGradient(colors: [palette.goldHi.opacity(palette.dark ? 0.35 : 0.45), gold.opacity(0.06)],
                                     center: UnitPoint(x: 0.35, y: 0.3), startRadius: 2, endRadius: 34))
            Circle().strokeBorder(gold.opacity(0.35), lineWidth: 1)
            Glyph(name: glyph, size: 26)
                .foregroundStyle(palette.dark ? palette.goldHi : palette.goldLo)
        }
        .frame(width: 58, height: 58)
        .shadow(color: gold.opacity(palette.dark ? 0.35 : 0.2), radius: 12)
    }

    @ViewBuilder
    private var action: some View {
        if card == .game {
            VStack(spacing: 8) {
                Text(info.upNext.inProgress ? "Resume" : "Play")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(tone.onIvory)
                    .padding(.horizontal, 16)
                    .frame(height: 34)
                    .background(Capsule().fill(palette.goldFill))
                if let secondary {
                    Button(action: secondary) {
                        Text(info.upNext.inProgress ? "New" : "Change")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(tone.ink2)
                    }
                    .buttonStyle(.plain)
                }
            }
        } else {
            Image(systemName: "chevron.right")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(tone.ink3)
        }
    }

    private var glyph: String {
        switch card {
        case .game: return Glyphs.play
        case .today: return Glyphs.today
        case .coach: return Glyphs.coach
        case .masterpiece: return "crown"
        case .analyze: return Glyphs.analyze
        }
    }

    private var eyebrow: String {
        switch card {
        case .game: return info.upNext.inProgress ? "Your game" : "Next game"
        case .today: return "Today's Move"
        case .coach: return "Coach Leo"
        case .masterpiece: return "Masterpiece"
        case .analyze: return "Analyze"
        }
    }

    private var title: String {
        switch card {
        case .game: return info.upNext.rival.name
        case .today:
            if info.day.found { return "Found it" }
            return info.day.number > 0 ? "No. \(info.day.number)" : "Today's puzzle"
        case .coach: return info.plan?.title ?? "Today's session"
        case .masterpiece: return info.masterpiece?.title ?? "A great game"
        case .analyze: return "Any position"
        }
    }

    private var detail: String {
        switch card {
        case .game:
            let upNext: HomeUpNext = info.upNext
            if upNext.inProgress {
                return upNext.yourMove ? "Move \(upNext.moveNumber) · your move" : "Move \(upNext.moveNumber) · their move"
            }
            return upNext.timeControl.isTimed ? "\(upNext.rival.elo) · \(upNext.timeControl.name)" : upNext.rival.elo
        case .today:
            if info.day.played { return "Back tomorrow for the next one" }
            return info.day.difficulty.isEmpty ? "One puzzle, the same for everyone" : "\(info.day.difficulty) · the same for everyone"
        case .coach:
            if info.trainedToday { return "Done today. Another round?" }
            if let plan = info.plan { return "\(plan.minutes) min with Leo" }
            return "A few minutes with Leo"
        case .masterpiece: return info.masterpiece?.players ?? "Play through the finish"
        case .analyze: return "A photo, a screenshot or set it up"
        }
    }
}

// MARK: - Pieces of the stage

/// The room: warm smoke falling to black at night, a soft white glow on cream by day.
struct HomeStageBackdrop: View {
    let tone: HomeTone

    var body: some View {
        if tone.scheme == .dark {
            ZStack {
                Color(hex: 0x0A0807)
                RadialGradient(colors: [Color(hex: 0x2A2018), Color(hex: 0x0A0807).opacity(0)],
                               center: UnitPoint(x: 0.5, y: 0.18), startRadius: 10, endRadius: 520)
            }
        } else {
            ZStack {
                tone.canvas
                RadialGradient(colors: [Color.white.opacity(0.85), tone.canvas.opacity(0)],
                               center: UnitPoint(x: 0.5, y: 0.2), startRadius: 10, endRadius: 520)
            }
        }
    }
}

/// The gold light the board stands in.
struct HomeStageHalo: View {
    let gold: Color
    let dark: Bool

    var body: some View {
        GeometryReader { geo in
            let w: CGFloat = geo.size.width
            Ellipse()
                .fill(RadialGradient(colors: [gold.opacity(dark ? 0.32 : 0.16), gold.opacity(dark ? 0.08 : 0.04), .clear],
                                     center: .center, startRadius: 4, endRadius: w * 0.55))
                .frame(width: w * 1.1, height: w * 0.7)
                .position(x: w / 2, y: geo.size.height * 0.62)
                .blendMode(dark ? .plusLighter : .multiply)
        }
    }
}

/// Slow gold dust in the light.
struct HomeStageMotes: View {
    let gold: Color
    let still: Bool

    private static let seeds: [(CGFloat, CGFloat, CGFloat, Double)] = (0..<26).map { i in
        let x: CGFloat = CGFloat((i * 37) % 100) / 100
        let y: CGFloat = CGFloat((i * 53) % 100) / 100
        let r: CGFloat = 0.8 + CGFloat(i % 3) * 0.6
        let speed: Double = 0.02 + Double(i % 5) * 0.006
        return (x, y, r, speed)
    }

    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 30, paused: still)) { context in
            Canvas { gc, size in
                let t: Double = context.date.timeIntervalSinceReferenceDate
                for seed in Self.seeds {
                    let rise: Double = (Double(seed.1) - t * seed.3).truncatingRemainder(dividingBy: 1)
                    let y: CGFloat = CGFloat(rise < 0 ? rise + 1 : rise) * size.height
                    let sway: CGFloat = CGFloat(sin(t * 0.6 + Double(seed.0) * 9)) * 6
                    let x: CGFloat = seed.0 * size.width + sway
                    let fade: Double = sin(Double(y / max(size.height, 1)) * .pi)
                    let rect = CGRect(x: x, y: y, width: seed.2 * 2, height: seed.2 * 2)
                    gc.fill(Path(ellipseIn: rect), with: .color(gold.opacity(0.55 * fade)))
                }
            }
        }
    }
}

/// Glass with a hairline: dark and warm at night, milky by day.
struct HomeStageGlass: View {
    let corner: CGFloat
    let palette: HomeStagePalette

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: corner, style: .continuous)
        shape
            .fill(.ultraThinMaterial)
            .overlay(shape.fill(palette.glassFill))
            .overlay(shape.strokeBorder(palette.glassLine, lineWidth: 1))
            .shadow(color: .black.opacity(palette.shadow), radius: 18, y: 12)
    }
}

/// A card sinks a little under the finger.
struct HomeStagePress: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.95 : 1)
            .animation(.spring(response: 0.25, dampingFraction: 0.7), value: configuration.isPressed)
    }
}

/// A round glass button in the top bar.
struct HomeStageCircleButton<Content: View>: View {
    let palette: HomeStagePalette
    let label: String
    let action: () -> Void
    @ViewBuilder let content: () -> Content

    var body: some View {
        Button(action: action) {
            content()
                .frame(width: 40, height: 40)
                .background(Circle().fill(palette.chipFill))
                .overlay(Circle().strokeBorder(palette.chipLine))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }
}

/// One of the three rings beside your level.
struct HomeStageRing: View {
    let value: Double
    let label: String
    let text: String
    let palette: HomeStagePalette

    var body: some View {
        VStack(spacing: 5) {
            ZStack {
                Circle().stroke(palette.track, lineWidth: 4)
                Circle()
                    .trim(from: 0, to: max(min(value, 1), 0.001))
                    .stroke(palette.goldFill, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .shadow(color: palette.gold.opacity(palette.dark ? 0.6 : 0.25), radius: 4)
                Text(text)
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                    .foregroundStyle(palette.tone.ink)
                    .minimumScaleFactor(0.7)
            }
            .frame(width: 46, height: 46)
            Text(label)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(palette.tone.ink2)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(label): \(text)")
    }
}

/// The floating glass tab bar: Today, Learn, the gold knight to play, You, and Rooms (everything).
/// Each icon is the app's own chess glyph on a raised tile, like the game's tool buttons.
struct HomeStageTabBar: View {
    let tone: HomeTone
    let upNext: HomeUpNext
    let learn: () -> Void
    let play: () -> Void
    let rooms: () -> Void
    let you: () -> Void

    private var palette: HomeStagePalette { HomeStagePalette(tone: tone) }

    var body: some View {
        HStack(spacing: 0) {
            HomeStageTab(title: "Today", glyph: Glyphs.today, on: true, palette: palette) {}
            HomeStageTab(title: "Learn", glyph: Glyphs.coach, on: false, palette: palette, action: learn)
            jewel
            HomeStageTab(title: "You", glyph: Glyphs.king, on: false, palette: palette, action: you)
            HomeStageTab(title: "Rooms", glyph: Glyphs.home, on: false, palette: palette, action: rooms)
        }
        .padding(.horizontal, 6)
        .frame(height: 74)
        .background(HomeStageGlass(corner: 30, palette: palette))
    }

    private var jewel: some View {
        Button(action: play) {
            ZStack {
                Circle()
                    .fill(RadialGradient(colors: [Color(hex: 0xFCEBC0), Color(hex: 0xD7A957), Color(hex: 0x8A6125)],
                                         center: UnitPoint(x: 0.35, y: 0.3), startRadius: 2, endRadius: 40))
                Circle()
                    .strokeBorder(LinearGradient(colors: [Color.white.opacity(0.8), Color(hex: 0x8A6125).opacity(0.4)],
                                                 startPoint: .top, endPoint: .bottom), lineWidth: 1.5)
                Glyph(name: Glyphs.train, size: 32)
                    .foregroundStyle(Color(hex: 0x2E200C))
            }
            .frame(width: 64, height: 64)
            .shadow(color: Color(hex: 0xD9B26A).opacity(palette.dark ? 0.7 : 0.5), radius: 16)
            .offset(y: -14)
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(HomeStagePress())
        .accessibilityLabel(upNext.inProgress ? "Resume your game" : "Play \(upNext.rival.name)")
    }
}

/// One tab: a bold glyph on a raised, rounded tile, gold when it's the page showing.
struct HomeStageTab: View {
    let title: String
    let glyph: String
    let on: Bool
    let palette: HomeStagePalette
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Glyph(name: glyph, size: 24, weight: .bold)
                    .foregroundStyle(on ? palette.tone.onIvory : palette.tone.ink)
                    .frame(width: 44, height: 38)
                    .background(tile)
                Text(title)
                    .font(.system(size: 10.5, weight: .semibold))
                    .foregroundStyle(on ? palette.gold : palette.tone.ink2)
            }
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(HomeStagePress())
        .accessibilityLabel(title)
        .accessibilityAddTraits(on ? .isSelected : [])
    }

    @ViewBuilder
    private var tile: some View {
        let shape = RoundedRectangle(cornerRadius: 13, style: .continuous)
        if on {
            shape
                .fill(palette.goldFill)
                .overlay(shape.strokeBorder(Color.white.opacity(0.45), lineWidth: 1))
                .shadow(color: palette.gold.opacity(0.45), radius: 8, y: 3)
        } else {
            shape
                .fill(palette.chipFill)
                .overlay(shape.strokeBorder(palette.chipLine, lineWidth: 1))
                .shadow(color: .black.opacity(palette.dark ? 0.35 : 0.08), radius: 4, y: 2)
        }
    }
}

/// Three little bars that dance while the music plays.
struct HomeMusicBars: View {
    let on: Bool
    let gold: Color
    let off: Color

    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 12, paused: !on)) { context in
            let t: Double = context.date.timeIntervalSinceReferenceDate
            HStack(alignment: .bottom, spacing: 2.5) {
                ForEach(0..<3, id: \.self) { i in
                    let h: Double = on ? 6 + 6 * abs(sin(t * 3 + Double(i) * 1.7)) : 4
                    Capsule()
                        .fill(on ? gold : off)
                        .frame(width: 3, height: CGFloat(h))
                }
            }
            .frame(height: 14, alignment: .bottom)
        }
    }
}
