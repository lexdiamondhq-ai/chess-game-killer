import ChessKit
import SwiftUI

/// The stage home (Alex's pick, 2026-11-07): dark, the real 3D board lit on a stage, your
/// level with three rings, a deck of cards for what's next, and a floating glass tab bar.
/// Off by default: Alex keeps the current Home (2026-11-07), and Settings > Stage home turns
/// this on. The game's own board is untouched: only Home looks like this.
enum HomeStageLayout {
    static let key = "homeStage"
    static let defaultOn = false

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
                    .ignoresSafeArea(edges: .top)

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

                if fanned {
                    fan(safeTop: safeTop)
                        .transition(.opacity)
                        .zIndex(2)
                }
            }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                HomeStageTabBar(tone: tone, upNext: info.upNext, learn: actions.learn, play: actions.play,
                                rooms: actions.rooms, you: actions.you)
                    .padding(.horizontal, 18)
                    .padding(.bottom, 4)
                    .opacity(fanned ? 0 : 1)
            }
        }
        .environment(\.colorScheme, .dark)
        .sensoryFeedback(.selection, trigger: order) { _, _ in hapticsOn }
        .sensoryFeedback(.impact(weight: .light), trigger: fanned) { _, _ in hapticsOn }
        .onAppear { music.homeAppeared() }
        .onDisappear { music.homeDisappeared() }
    }

    // MARK: The stage

    private func stage(width: CGFloat, height: CGFloat) -> some View {
        let upNext: HomeUpNext = info.upNext
        let leaning: Bool = upNext.inProgress && upNext.yourMove
        return ZStack {
            HomeSheetScene(look: look, tone: tone, pieces: pieces, black: upNext.playerColor == .black,
                           rival: upNext.rival, leaning: leaning, lift: 0)
            HomeStageHalo(gold: gold)
                .allowsHitTesting(false)
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
        .onTapGesture(perform: actions.play)
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
            Spacer(minLength: 0)
            if music.available {
                HomeStageCircleButton(tone: tone, label: music.on ? "Music off" : "Music on", action: music.toggle) {
                    HomeMusicBars(on: music.on, gold: gold)
                }
            }
            Button(action: actions.dailyMove) {
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
                .background(Capsule().fill(Color.white.opacity(0.07)))
                .overlay(Capsule().strokeBorder(Color.white.opacity(0.1)))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("\(info.day.streak) day streak")
            HomeStageCircleButton(tone: tone, label: "You", action: actions.you) {
                Text(initial)
                    .font(.system(size: 16, weight: .semibold, design: .serif))
                    .foregroundStyle(tone.onIvory)
                    .frame(width: 40, height: 40)
                    .background(Circle().fill(LinearGradient(colors: [Color(hex: 0xF4DDA4), Color(hex: 0xC99B4E)],
                                                             startPoint: .top, endPoint: .bottom)))
            }
        }
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
                    .foregroundStyle(LinearGradient(colors: [Color(hex: 0xFFF3D2), gold], startPoint: .top, endPoint: .bottom))
                    .monospacedDigit()
                Text(info.rating == nil ? "Play a few games for your level" : "Your level")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(tone.ink2)
            }
            Spacer(minLength: 0)
            HomeStageRing(value: Double(min(info.day.streak, 7)) / 7, label: "Streak", text: "\(info.day.streak)", gold: gold, tone: tone)
            HomeStageRing(value: Double(min(info.day.puzzlesToday, DailyRules.puzzlesForTheDay)) / Double(DailyRules.puzzlesForTheDay),
                          label: "Puzzles", text: "\(info.day.puzzlesToday)", gold: gold, tone: tone)
            HomeStageRing(value: info.rankProgress, label: "Rank", text: "\(Int((info.rankProgress * 100).rounded()))%",
                          gold: gold, tone: tone)
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
                            .fill(card == order.first ? gold : Color.white.opacity(0.22))
                            .frame(width: card == order.first ? 16 : 6, height: 6)
                    }
                }
                Spacer()
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
                    .background(Capsule().fill(Color.white.opacity(0.08)))
                    .overlay(Capsule().strokeBorder(Color.white.opacity(0.1)))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Show all cards")
            }
            .padding(.horizontal, 4)
        }
    }

    private func deckCard(_ card: HomeStageCard, depth: Int) -> some View {
        let lift: CGFloat = CGFloat(depth) * -11
        let scale: CGFloat = 1 - CGFloat(depth) * 0.05
        let drag: CGFloat = depth == 0 ? max(deckDrag, -40) : 0
        return HomeStageCardView(card: card, info: info, tone: tone, compact: false, open: { open(card) },
                                 secondary: card == .game ? actions.change : nil)
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

    private var spring: Animation {
        reduceMotion ? .easeOut(duration: 0.2) : .spring(response: 0.42, dampingFraction: 0.82)
    }

    private func open(_ card: HomeStageCard) {
        switch card {
        case .game: actions.play()
        case .today: actions.dailyMove()
        case .coach: actions.coach()
        case .masterpiece:
            if let masterpiece = info.masterpiece, let fen = masterpiece.frames.first {
                actions.analyzePosition(fen)
            }
        case .analyze: actions.analyze()
        }
    }

    // MARK: All the cards at once

    private func fan(safeTop: CGFloat) -> some View {
        ZStack(alignment: .top) {
            Color.black.opacity(0.55)
                .ignoresSafeArea()
                .onTapGesture { withAnimation(spring) { fanned = false } }
            ScrollView {
                VStack(spacing: 12) {
                    ForEach(Array(order.enumerated()), id: \.element) { index, card in
                        HomeStageCardView(card: card, info: info, tone: tone, compact: false,
                                          open: {
                                              withAnimation(spring) { fanned = false }
                                              open(card)
                                          },
                                          secondary: card == .game ? actions.change : nil)
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
                    .background(Capsule().fill(LinearGradient(colors: [Color(hex: 0xF4DDA4), Color(hex: 0xC99B4E)],
                                                              startPoint: .top, endPoint: .bottom)))
                }
                .buttonStyle(.plain)
                .padding(.bottom, 24)
            }
        }
    }
}

// MARK: - A card

struct HomeStageCardView: View {
    let card: HomeStageCard
    let info: HomeStageInfo
    let tone: HomeTone
    let compact: Bool
    let open: () -> Void
    var secondary: (() -> Void)? = nil

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
            .background(HomeStageGlass(corner: 26))
            .contentShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
        }
        .buttonStyle(HomeStagePress())
        .accessibilityElement(children: .combine)
        .accessibilityAction(named: "Change") { secondary?() }
    }

    private var orb: some View {
        ZStack {
            Circle()
                .fill(RadialGradient(colors: [Color(hex: 0xF4DDA4).opacity(0.35), gold.opacity(0.06)],
                                     center: UnitPoint(x: 0.35, y: 0.3), startRadius: 2, endRadius: 34))
            Circle().strokeBorder(gold.opacity(0.35), lineWidth: 1)
            Glyph(name: glyph, size: 26)
                .foregroundStyle(Color(hex: 0xF4DDA4))
        }
        .frame(width: 58, height: 58)
        .shadow(color: gold.opacity(0.35), radius: 12)
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
                    .background(Capsule().fill(LinearGradient(colors: [Color(hex: 0xF4DDA4), Color(hex: 0xC99B4E)],
                                                              startPoint: .top, endPoint: .bottom)))
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

/// The dark room: warm smoke at the top falling to black.
struct HomeStageBackdrop: View {
    let tone: HomeTone

    var body: some View {
        ZStack {
            Color(hex: 0x0A0807)
            RadialGradient(colors: [Color(hex: 0x2A2018), Color(hex: 0x0A0807).opacity(0)],
                           center: UnitPoint(x: 0.5, y: 0.18), startRadius: 10, endRadius: 520)
        }
    }
}

/// The gold light the board stands in.
struct HomeStageHalo: View {
    let gold: Color

    var body: some View {
        GeometryReader { geo in
            let w: CGFloat = geo.size.width
            Ellipse()
                .fill(RadialGradient(colors: [gold.opacity(0.32), gold.opacity(0.08), .clear],
                                     center: .center, startRadius: 4, endRadius: w * 0.55))
                .frame(width: w * 1.1, height: w * 0.7)
                .position(x: w / 2, y: geo.size.height * 0.62)
                .blendMode(.plusLighter)
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

/// Dark glass with a warm hairline.
struct HomeStageGlass: View {
    let corner: CGFloat

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: corner, style: .continuous)
        shape
            .fill(.ultraThinMaterial)
            .overlay(shape.fill(Color(hex: 0x201B16).opacity(0.55)))
            .overlay(shape.strokeBorder(Color(hex: 0xFFF8EB).opacity(0.11), lineWidth: 1))
            .shadow(color: .black.opacity(0.5), radius: 18, y: 12)
    }
}

/// A card sinks a little under the finger.
struct HomeStagePress: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.spring(response: 0.25, dampingFraction: 0.8), value: configuration.isPressed)
    }
}

/// A round glass button in the top bar.
struct HomeStageCircleButton<Content: View>: View {
    let tone: HomeTone
    let label: String
    let action: () -> Void
    @ViewBuilder let content: () -> Content

    var body: some View {
        Button(action: action) {
            content()
                .frame(width: 40, height: 40)
                .background(Circle().fill(Color.white.opacity(0.07)))
                .overlay(Circle().strokeBorder(Color.white.opacity(0.1)))
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
    let gold: Color
    let tone: HomeTone

    var body: some View {
        VStack(spacing: 5) {
            ZStack {
                Circle().stroke(Color.white.opacity(0.1), lineWidth: 4)
                Circle()
                    .trim(from: 0, to: max(min(value, 1), 0.001))
                    .stroke(LinearGradient(colors: [Color(hex: 0xF4DDA4), gold], startPoint: .top, endPoint: .bottom),
                            style: StrokeStyle(lineWidth: 4, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .shadow(color: gold.opacity(0.6), radius: 4)
                Text(text)
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                    .foregroundStyle(tone.ink)
                    .minimumScaleFactor(0.7)
            }
            .frame(width: 46, height: 46)
            Text(label)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(tone.ink2)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(label): \(text)")
    }
}

/// The floating glass tab bar: Today, Learn, the gold Play jewel, You, and Rooms (everything).
struct HomeStageTabBar: View {
    let tone: HomeTone
    let upNext: HomeUpNext
    let learn: () -> Void
    let play: () -> Void
    let rooms: () -> Void
    let you: () -> Void

    var body: some View {
        HStack(spacing: 0) {
            tab("Today", glyph: Glyphs.today, on: true) {}
            tab("Learn", glyph: Glyphs.train, on: false, action: learn)
            jewel
            tab("You", glyph: "person.crop.circle", on: false, action: you)
            tab("Rooms", glyph: "square.stack.3d.up", on: false, action: rooms)
        }
        .padding(.horizontal, 6)
        .frame(height: 64)
        .background(HomeStageGlass(corner: 32))
    }

    private func tab(_ title: String, glyph: String, on: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 3) {
                Glyph(name: glyph, size: 22)
                Text(title)
                    .font(.system(size: 10.5, weight: .semibold))
            }
            .foregroundStyle(on ? tone.metal : tone.ink2)
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
        .accessibilityAddTraits(on ? .isSelected : [])
    }

    private var jewel: some View {
        Button(action: play) {
            ZStack {
                Circle()
                    .fill(RadialGradient(colors: [Color(hex: 0xFCEBC0), Color(hex: 0xD7A957), Color(hex: 0x8A6125)],
                                         center: UnitPoint(x: 0.35, y: 0.3), startRadius: 2, endRadius: 40))
                Glyph(name: Glyphs.play, size: 26)
                    .foregroundStyle(Color(hex: 0x2E200C))
            }
            .frame(width: 60, height: 60)
            .shadow(color: Color(hex: 0xD9B26A).opacity(0.7), radius: 16)
            .offset(y: -12)
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(HomeStagePress())
        .accessibilityLabel(upNext.inProgress ? "Resume your game" : "Play \(upNext.rival.name)")
    }
}

/// Three little bars that dance while the music plays.
struct HomeMusicBars: View {
    let on: Bool
    let gold: Color

    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 12, paused: !on)) { context in
            let t: Double = context.date.timeIntervalSinceReferenceDate
            HStack(alignment: .bottom, spacing: 2.5) {
                ForEach(0..<3, id: \.self) { i in
                    let h: Double = on ? 6 + 6 * abs(sin(t * 3 + Double(i) * 1.7)) : 4
                    Capsule()
                        .fill(on ? gold : Color.white.opacity(0.5))
                        .frame(width: 3, height: CGFloat(h))
                }
            }
            .frame(height: 14, alignment: .bottom)
        }
    }
}
