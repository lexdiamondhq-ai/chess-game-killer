import ChessKit
import SwiftUI

/// The Aurora home (Alex's pick, 2026-11-07: "Spotlight" with "Bento" tiles). Your game is the
/// hero: a clean flat board (the Gilded board with the app's cut-out pieces) under one serif
/// line and a gold button; swipe sideways to your other games, the next one peeking at the
/// right. Under it, tiles for your rating, streak, Today's Move, Coach Leo, Analyze and the
/// masterpiece. The room is deep ink with a soft violet, rose and gold glow and fine gold
/// engraved rings, or ivory by day. A glass tab bar with the gold knight beside it.
struct HomeAuroraInfo {
    var stage: HomeStageInfo
    /// Every game still going, your move first. Empty when none is.
    var games: [HomeCurrentGame]
}

struct HomeAuroraActions {
    var stage: HomeStageActions
    /// Opens one of your games.
    var open: (HomeCurrentGame) -> Void
}

/// Aurora's colors, night and day.
struct HomeAuroraPalette {
    let dark: Bool

    var bg: Color { dark ? Color(hex: 0x08080C) : Color(hex: 0xF6F3EE) }
    var bgLow: Color { dark ? Color(hex: 0x0C0B10) : Color(hex: 0xEFEAE2) }
    var ink: Color { dark ? Color(hex: 0xF2EEE6) : Color(hex: 0x1C1813) }
    var ink2: Color { ink.opacity(dark ? 0.62 : 0.6) }
    var ink3: Color { ink.opacity(dark ? 0.36 : 0.38) }
    var line: Color { dark ? Color.white.opacity(0.08) : Color(hex: 0x1C1813).opacity(0.08) }
    var glass: Color { dark ? Color.white.opacity(0.06) : Color.white.opacity(0.72) }
    var glassHi: Color { dark ? Color.white.opacity(0.12) : Color.white }
    var card: Color { dark ? Color(hex: 0x11131A) : Color.white }
    var gold: Color { dark ? Color(hex: 0xE8C27A) : Color(hex: 0xB7832E) }
    var rose: Color { dark ? Color(hex: 0xF0708A) : Color(hex: 0xD9466A) }
    var violet: Color { dark ? Color(hex: 0x8B6CFF) : Color(hex: 0x6A4BE0) }
    var teal: Color { dark ? Color(hex: 0x3FD1B8) : Color(hex: 0x169C86) }
    var shadow: Color { .black.opacity(dark ? 0.45 : 0.12) }
    var glow: Double { dark ? 1 : 0.5 }

    static let goldButton = LinearGradient(colors: [Color(hex: 0xF6DEA3), Color(hex: 0xC99B4E)],
                                           startPoint: .top, endPoint: .bottom)
    static let roseTile = LinearGradient(colors: [Color(hex: 0xFFB86B), Color(hex: 0xF0708A)],
                                         startPoint: .topLeading, endPoint: .bottomTrailing)
    static let violetTile = LinearGradient(colors: [Color(hex: 0x8B6CFF), Color(hex: 0x4C8DFF)],
                                           startPoint: .topLeading, endPoint: .bottomTrailing)
    static let tealTile = LinearGradient(colors: [Color(hex: 0x3FD1B8), Color(hex: 0x2E8C9E)],
                                         startPoint: .topLeading, endPoint: .bottomTrailing)
    static let goldTile = LinearGradient(colors: [Color(hex: 0xE8C27A), Color(hex: 0xB0763A)],
                                         startPoint: .topLeading, endPoint: .bottomTrailing)
}

struct HomeAuroraView: View {
    let tone: HomeTone
    let info: HomeAuroraInfo
    let actions: HomeAuroraActions

    @AppStorage("haptics") private var hapticsOn = true
    @AppStorage(HomeToneMode.key) private var toneMode = HomeToneMode.defaultMode
    @State private var music = HomeMusic.shared
    /// The game in front of the swipe row.
    @State private var shown: String?

    private var palette: HomeAuroraPalette { HomeAuroraPalette(dark: tone.scheme == .dark) }
    private var stage: HomeStageInfo { info.stage }

    /// The boards in the swipe row: your games, or the next game's start when none is going.
    private var cards: [HomeAuroraGameCard] {
        if info.games.isEmpty {
            return [HomeAuroraGameCard.next(stage.upNext, fen: stage.gameFEN)]
        }
        return info.games.map(HomeAuroraGameCard.init)
    }

    private var current: HomeAuroraGameCard {
        let all: [HomeAuroraGameCard] = cards
        return all.first { $0.id == shown } ?? all[0]
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            HomeAuroraBackdrop(palette: palette)
            ScrollView(.vertical) {
                VStack(spacing: 0) {
                    header
                    hero
                    HomeAuroraSection(title: "For today", palette: palette)
                    bento
                        .padding(.horizontal, 16)
                }
                .padding(.bottom, 130)
            }
            .scrollIndicators(.hidden)
            HomeAuroraTabBar(palette: palette, play: { actions.stage.play() }, learn: actions.stage.learn,
                             you: actions.stage.you, rooms: actions.stage.rooms)
                .padding(.horizontal, 16)
                .padding(.bottom, 8)
        }
        .environment(\.colorScheme, tone.scheme)
        .sensoryFeedback(.selection, trigger: shown) { _, _ in hapticsOn }
        .onAppear { music.homeAppeared() }
        .onDisappear { music.homeDisappeared() }
    }

    // MARK: Header

    private var header: some View {
        VStack(spacing: 14) {
            HStack(spacing: 8) {
                (Text("Beauty ") + Text("of").italic().foregroundColor(palette.gold) + Text(" Chess"))
                    .font(.system(size: 22, weight: .medium, design: .serif))
                    .foregroundStyle(palette.ink)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                Spacer(minLength: 0)
                if music.available {
                    circle(label: music.on ? "Music off" : "Music on", action: music.toggle) {
                        HomeMusicBars(on: music.on, gold: palette.gold, off: palette.ink3)
                    }
                }
                circle(label: palette.dark ? "Light mode" : "Dark mode", action: flipLight) {
                    Image(systemName: palette.dark ? "sun.max" : "moon")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(palette.gold)
                }
                streak
                circle(label: "You", action: actions.stage.you) {
                    Image(systemName: "crown")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(palette.gold)
                }
            }
            // A fine gold hairline, fading at both ends.
            LinearGradient(colors: [palette.gold.opacity(0), palette.gold.opacity(0.45), palette.gold.opacity(0)],
                           startPoint: .leading, endPoint: .trailing)
                .frame(height: 0.75)
        }
        .padding(.horizontal, 20)
        .padding(.top, 8)
    }

    private var streak: some View {
        Button(action: actions.stage.dailyMove) {
            HStack(spacing: 5) {
                Circle().fill(palette.rose).frame(width: 7, height: 7)
                    .shadow(color: palette.rose, radius: 4)
                Text("\(stage.day.streak)")
                    .font(.system(size: 14, weight: .bold, design: .rounded))
                    .foregroundStyle(palette.ink)
                    .monospacedDigit()
            }
            .padding(.horizontal, 12)
            .frame(height: 34)
            .background(Capsule().fill(palette.glass))
            .overlay(Capsule().strokeBorder(palette.line, lineWidth: 1))
        }
        .buttonStyle(HomeStagePress())
        .accessibilityLabel("\(stage.day.streak) day streak")
    }

    private func circle<Label: View>(label: String, action: @escaping () -> Void,
                                     @ViewBuilder content: () -> Label) -> some View {
        Button(action: action) {
            content()
                .frame(width: 34, height: 34)
                .background(Circle().fill(palette.glass))
                .overlay(Circle().strokeBorder(palette.line, lineWidth: 1))
        }
        .buttonStyle(HomeStagePress())
        .accessibilityLabel(label)
    }

    private func flipLight() {
        withAnimation(.easeInOut(duration: 0.4)) {
            toneMode = palette.dark ? .light : .dark
        }
    }

    // MARK: Hero

    private var hero: some View {
        let card: HomeAuroraGameCard = current
        let all: [HomeAuroraGameCard] = cards
        return VStack(spacing: 0) {
            Text(card.eyebrow.uppercased())
                .font(.system(size: 11, weight: .bold))
                .tracking(1.8)
                .foregroundStyle(palette.ink2)
                .padding(.top, 22)
            headline(card)
                .padding(.top, 8)
                .padding(.horizontal, 24)
            gameRow(all)
                .padding(.top, 22)
            if all.count > 1 {
                dots(all, current: card.id)
                    .padding(.top, 14)
            }
            tags(card)
                .padding(.top, 16)
            Button { open(card) } label: {
                Text(card.button)
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(Color(hex: 0x2A1E0F))
                    .frame(maxWidth: .infinity)
                    .frame(height: 54)
                    .background(Capsule().fill(HomeAuroraPalette.goldButton))
                    .shadow(color: Color(hex: 0xD9B26A).opacity(0.35), radius: 13, y: 10)
            }
            .buttonStyle(HomeStagePress())
            .padding(.horizontal, 24)
            .padding(.top, 16)
            Button(action: actions.stage.change) {
                Text(info.games.isEmpty ? "Change rival" : "New game")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(palette.ink2)
                    .frame(height: 36)
            }
            .buttonStyle(.plain)
            .padding(.top, 4)
        }
    }

    private func headline(_ card: HomeAuroraGameCard) -> some View {
        (Text(card.headline) + Text(card.headlineEnd).italic().foregroundColor(palette.gold))
            .font(.system(size: 32, weight: .regular, design: .serif))
            .foregroundStyle(palette.ink)
            .multilineTextAlignment(.center)
            .lineLimit(2)
            .minimumScaleFactor(0.7)
            .contentTransition(.opacity)
            .animation(.easeInOut(duration: 0.25), value: card.id)
    }

    /// Your games side by side: the one in front fills most of the width, the next peeks in at
    /// the right, and a swipe brings it in.
    private func gameRow(_ all: [HomeAuroraGameCard]) -> some View {
        ScrollView(.horizontal) {
            LazyHStack(spacing: 14) {
                ForEach(all) { card in
                    HomeAuroraBoard(fen: card.fen, flipped: card.flipped, lit: card.yourMove)
                        .shadow(color: .black.opacity(palette.dark ? 0.55 : 0.18), radius: 22, y: 18)
                        .shadow(color: palette.gold.opacity(0.14 * palette.glow), radius: 30)
                        .containerRelativeFrame(.horizontal) { width, _ in
                            all.count > 1 ? width - 84 : width - 48
                        }
                        .onTapGesture { open(card) }
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel("\(card.title), \(card.eyebrow)")
                        .accessibilityAddTraits(.isButton)
                }
            }
            .scrollTargetLayout()
        }
        .scrollTargetBehavior(.viewAligned)
        .scrollPosition(id: $shown)
        .scrollIndicators(.hidden)
        .scrollClipDisabled()
        .contentMargins(.leading, 24, for: .scrollContent)
        .contentMargins(.trailing, all.count > 1 ? 60 : 24, for: .scrollContent)
    }

    private func dots(_ all: [HomeAuroraGameCard], current: String) -> some View {
        HStack(spacing: 5) {
            ForEach(all) { card in
                Capsule()
                    .fill(card.id == current ? palette.gold : palette.ink3)
                    .frame(width: card.id == current ? 16 : 5, height: 5)
            }
        }
        .animation(.easeInOut(duration: 0.2), value: current)
        .accessibilityHidden(true)
    }

    private func tags(_ card: HomeAuroraGameCard) -> some View {
        HStack(spacing: 8) {
            if let rating = stage.rating {
                tag("Rating", bold: rating.formatted(.number))
            }
            ForEach(card.tags, id: \.self) { text in
                tag(text, bold: nil)
            }
        }
        .padding(.horizontal, 16)
    }

    private func tag(_ text: String, bold: String?) -> some View {
        HStack(spacing: 5) {
            Text(text).foregroundStyle(palette.ink2)
            if let bold {
                Text(bold).foregroundStyle(palette.ink).monospacedDigit()
            }
        }
        .font(.system(size: 12.5, weight: .semibold))
        .lineLimit(1)
        .padding(.horizontal, 12)
        .frame(height: 30)
        .background(Capsule().fill(palette.glass))
        .overlay(Capsule().strokeBorder(palette.line, lineWidth: 1))
    }

    private func open(_ card: HomeAuroraGameCard) {
        if let game = card.game {
            actions.open(game)
        } else {
            actions.stage.play()
        }
    }

    // MARK: Tiles

    private var bento: some View {
        let day: HomeDailyState = stage.day
        return VStack(spacing: 12) {
            HStack(spacing: 12) {
                HomeAuroraTile(eyebrow: "Rating", palette: palette, fill: nil, action: actions.stage.you) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(stage.rating.map { $0.formatted(.number) } ?? "New")
                            .font(.system(size: 38, weight: .regular, design: .serif))
                            .foregroundStyle(palette.ink)
                        Text("Level \(stage.rankNumber)")
                            .font(.system(size: 12.5))
                            .foregroundStyle(palette.ink2)
                    }
                }
                HomeAuroraTile(eyebrow: "Streak", palette: palette, fill: HomeAuroraPalette.roseTile,
                               mark: Glyphs.king, action: actions.stage.dailyMove) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("\(day.streak)")
                            .font(.system(size: 38, weight: .regular, design: .serif))
                        Text(day.streak == 1 ? "day" : "days in a row")
                            .font(.system(size: 12.5))
                            .opacity(0.85)
                    }
                }
            }
            HStack(spacing: 12) {
                HomeAuroraTile(eyebrow: "Today's Move", palette: palette, fill: HomeAuroraPalette.violetTile,
                               action: actions.stage.dailyMove) {
                    VStack(alignment: .leading, spacing: 8) {
                        HomeAuroraBoard(fen: stage.todayFEN, flipped: stage.todaySolver == .black, lit: false)
                            .frame(width: 78, height: 78)
                            .shadow(color: .black.opacity(0.3), radius: 8, y: 6)
                        Text(todayLine)
                            .font(.system(size: 12.5))
                            .opacity(0.85)
                            .lineLimit(2)
                    }
                }
                HomeAuroraTile(eyebrow: "Coach Leo", palette: palette, fill: HomeAuroraPalette.tealTile,
                               mark: Glyphs.train, action: actions.stage.coach) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(stage.plan?.title ?? "Today's lesson")
                            .font(.system(size: 22, weight: .regular, design: .serif))
                            .lineLimit(2)
                            .minimumScaleFactor(0.8)
                        Text(coachLine)
                            .font(.system(size: 12.5))
                            .opacity(0.85)
                    }
                }
            }
            HStack(spacing: 12) {
                HomeAuroraTile(eyebrow: "Analyze", palette: palette, fill: HomeAuroraPalette.goldTile,
                               mark: Glyphs.analyze, action: actions.stage.analyze) {
                    Text("A photo, a screenshot or any board")
                        .font(.system(size: 12.5))
                        .opacity(0.9)
                        .lineLimit(3)
                }
                if let masterpiece = stage.masterpiece {
                    HomeAuroraTile(eyebrow: "Masterpiece", palette: palette, fill: nil, action: {
                        if let fen = masterpiece.frames.first { actions.stage.analyzePosition(fen) }
                    }) {
                        VStack(alignment: .leading, spacing: 8) {
                            HomeAuroraBoard(fen: masterpiece.frames.first, flipped: masterpiece.flipped, lit: false)
                                .frame(width: 78, height: 78)
                            Text(masterpiece.title)
                                .font(.system(size: 12.5))
                                .foregroundStyle(palette.ink2)
                                .lineLimit(2)
                        }
                    }
                }
            }
        }
    }

    private var coachLine: String {
        if stage.trainedToday { return "Done today" }
        guard let plan = stage.plan else { return "Pick up where you stopped" }
        return "\(plan.minutes) min"
    }

    private var todayLine: String {
        let day: HomeDailyState = stage.day
        if day.found { return "Found it. Back tomorrow." }
        if day.played { return "See it again" }
        return stage.todaySolver == .black ? "Black to play and win" : "White to play and win"
    }
}

/// One board in the swipe row, and the words around it while it's in front.
struct HomeAuroraGameCard: Identifiable, Equatable {
    let id: String
    let game: HomeCurrentGame?
    let title: String
    let fen: String?
    let flipped: Bool
    let yourMove: Bool
    let eyebrow: String
    let headline: String
    let headlineEnd: String
    let button: String
    let tags: [String]

    init(_ game: HomeCurrentGame) {
        let name: String = game.title.hasPrefix("vs ") ? String(game.title.dropFirst(3)) : game.title
        let parts: [String] = game.detail.components(separatedBy: " · ")
        id = game.id
        self.game = game
        title = game.title
        fen = game.fen
        flipped = game.flipped
        yourMove = game.isYourMove
        eyebrow = parts.last.map { "\(game.status.words) · \($0)" } ?? game.status.words
        switch game.status {
        case .yourMove:
            headline = "\(name) is waiting\nfor "
            headlineEnd = "you"
            button = "Make your move"
        case .theirMove:
            headline = "\(name) is "
            headlineEnd = "thinking"
            button = "See the game"
        case .waiting:
            headline = "Waiting for "
            headlineEnd = "\(name)"
            button = "See the game"
        }
        var shown: [String] = Array(parts.dropLast())
        shown.append(game.flipped ? "You're Black" : "You're White")
        tags = shown
    }

    private init(next upNext: HomeUpNext, fen: String) {
        id = "next"
        game = nil
        title = "Play \(upNext.rival.name)"
        self.fen = fen
        flipped = upNext.playerColor == .black
        yourMove = false
        eyebrow = "Your next game"
        headline = "\(upNext.rival.name) is ready\nwhen "
        headlineEnd = "you are"
        button = "Play \(upNext.rival.name)"
        tags = [upNext.timeControl.isTimed ? upNext.timeControl.name : "No clock"]
    }

    static func next(_ upNext: HomeUpNext, fen: String) -> HomeAuroraGameCard {
        HomeAuroraGameCard(next: upNext, fen: fen)
    }
}

// MARK: - The board

/// A position on the Gilded board with the app's flat cut-out pieces, each with its soft
/// shadow: the same pieces as the game's Flat view, clean and sharp at any size.
struct HomeAuroraBoard: View {
    let fen: String?
    let flipped: Bool
    /// Your move: a fine gold rim.
    let lit: Bool

    /// The board picture's frame, as a share of its side.
    private static let inset: CGFloat = 0.046
    private static let start = "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR"

    private struct Placed: Identifiable {
        let id: Int
        let letter: Character
        let column: Int
        let row: Int
    }

    private var placed: [Placed] {
        let placement: String = (fen ?? Self.start).split(separator: " ").first.map(String.init) ?? Self.start
        var out: [Placed] = []
        var row: Int = 0
        var column: Int = 0
        for ch in placement {
            if ch == "/" {
                row += 1
                column = 0
            } else if let skip = ch.wholeNumberValue {
                column += skip
            } else {
                let c: Int = flipped ? 7 - column : column
                let r: Int = flipped ? 7 - row : row
                out.append(Placed(id: out.count, letter: ch, column: c, row: r))
                column += 1
            }
        }
        return out
    }

    var body: some View {
        GeometryReader { geo in
            let side: CGFloat = min(geo.size.width, geo.size.height)
            let margin: CGFloat = side * Self.inset
            let square: CGFloat = (side - 2 * margin) / 8
            let pieces: [Placed] = placed
            ZStack(alignment: .topLeading) {
                Image("board-gilded")
                    .resizable()
                    .interpolation(.high)
                    .frame(width: side, height: side)
                ForEach(pieces) { piece in
                    Image(Self.shadowName(piece.letter))
                        .resizable()
                        .interpolation(.high)
                        .frame(width: square, height: square)
                        .opacity(0.32)
                        .offset(x: margin + CGFloat(piece.column) * square + square * 0.075,
                                y: margin + CGFloat(piece.row) * square + square * 0.1)
                }
                ForEach(pieces) { piece in
                    Image(Self.pictureName(piece.letter))
                        .resizable()
                        .interpolation(.high)
                        .frame(width: square * 0.92, height: square * 0.92)
                        .offset(x: margin + CGFloat(piece.column) * square + square * 0.04,
                                y: margin + CGFloat(piece.row) * square + square * 0.04)
                }
            }
            .frame(width: side, height: side)
        }
        .aspectRatio(1, contentMode: .fit)
        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .strokeBorder(Color(hex: 0xE8C27A).opacity(lit ? 0.55 : 0), lineWidth: 1)
        }
        .environment(\.layoutDirection, .leftToRight)
        .accessibilityHidden(true)
    }

    private static func pictureName(_ letter: Character) -> String {
        let side: String = letter.isUppercase ? "w" : "b"
        return "cutout-\(side)\(String(letter).uppercased())"
    }

    private static func shadowName(_ letter: Character) -> String {
        "cutout-shadow-\(String(letter).uppercased())"
    }
}

// MARK: - Pieces of the page

struct HomeAuroraSection: View {
    let title: String
    let palette: HomeAuroraPalette

    var body: some View {
        HStack {
            Text(title)
                .font(.system(size: 22, weight: .medium, design: .serif))
                .foregroundStyle(palette.ink)
            Spacer()
        }
        .padding(.horizontal, 20)
        .padding(.top, 26)
        .padding(.bottom, 12)
        .accessibilityAddTraits(.isHeader)
    }
}

/// One Bento tile: plain card or a color gradient, a small caps label, and what's in it.
struct HomeAuroraTile<Content: View>: View {
    let eyebrow: String
    let palette: HomeAuroraPalette
    let fill: LinearGradient?
    var mark: String? = nil
    let action: () -> Void
    @ViewBuilder let content: () -> Content

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 26, style: .continuous)
        Button(action: action) {
            VStack(alignment: .leading, spacing: 10) {
                Text(eyebrow.uppercased())
                    .font(.system(size: 11, weight: .bold))
                    .tracking(1.3)
                    .opacity(fill == nil ? 1 : 0.85)
                    .foregroundStyle(fill == nil ? palette.ink2 : Color.white)
                content()
                Spacer(minLength: 0)
            }
            .foregroundStyle(fill == nil ? palette.ink : Color.white)
            .padding(14)
            .frame(maxWidth: .infinity, minHeight: 150, alignment: .topLeading)
            .background(alignment: .bottomTrailing) {
                if let mark {
                    Glyph(name: mark, size: 86, weight: .bold)
                        .foregroundStyle(Color.white.opacity(0.22))
                        .offset(x: 14, y: 14)
                }
            }
            .background {
                if let fill {
                    shape.fill(fill)
                } else {
                    shape.fill(palette.card)
                        .overlay(shape.strokeBorder(palette.line, lineWidth: 1))
                }
            }
            .clipShape(shape)
        }
        .buttonStyle(HomeStagePress())
    }
}

/// The room: deep ink (ivory by day) with a soft violet, rose and gold glow at the top and fine
/// gold rings engraved around where the board sits, like a watch dial.
struct HomeAuroraBackdrop: View {
    let palette: HomeAuroraPalette

    var body: some View {
        GeometryReader { geo in
            let w: CGFloat = geo.size.width
            ZStack(alignment: .top) {
                LinearGradient(colors: [palette.bg, palette.bgLow], startPoint: .top, endPoint: .bottom)
                glow(Color(hex: 0x8B6CFF), opacity: 0.42, at: CGPoint(x: w * 0.12, y: 40), size: w * 1.0)
                glow(Color(hex: 0xF0708A), opacity: 0.34, at: CGPoint(x: w * 0.92, y: 20), size: w * 0.9)
                glow(Color(hex: 0xE8C27A), opacity: 0.26, at: CGPoint(x: w * 0.5, y: 330), size: w * 1.2)
                HomeAuroraRings(color: palette.gold, opacity: palette.dark ? 0.07 : 0.1)
                    .frame(width: w * 1.6, height: w * 1.6)
                    .position(x: w / 2, y: 330)
                    .mask(LinearGradient(colors: [.black, .black, .clear], startPoint: .top, endPoint: .bottom))
            }
        }
        .ignoresSafeArea()
        .accessibilityHidden(true)
    }

    private func glow(_ color: Color, opacity: Double, at point: CGPoint, size: CGFloat) -> some View {
        Ellipse()
            .fill(RadialGradient(colors: [color.opacity(opacity * palette.glow), color.opacity(0)],
                                 center: .center, startRadius: 0, endRadius: size / 2))
            .frame(width: size, height: size * 0.8)
            .position(point)
    }
}

/// Fine engraved rings: circles in step, crossed by a slow rosette of offset circles.
struct HomeAuroraRings: View {
    let color: Color
    let opacity: Double

    var body: some View {
        Canvas { gc, size in
            let center = CGPoint(x: size.width / 2, y: size.height / 2)
            let outer: CGFloat = min(size.width, size.height) / 2
            let style = GraphicsContext.Shading.color(color.opacity(opacity))
            for i in 1...22 {
                let r: CGFloat = outer * CGFloat(i) / 22
                gc.stroke(Path(ellipseIn: CGRect(x: center.x - r, y: center.y - r, width: 2 * r, height: 2 * r)),
                          with: style, lineWidth: 0.5)
            }
            let petals: Int = 36
            let r: CGFloat = outer * 0.42
            for i in 0..<petals {
                let angle: Double = Double(i) / Double(petals) * 2 * Double.pi
                let cx: CGFloat = center.x + CGFloat(cos(angle)) * outer * 0.2
                let cy: CGFloat = center.y + CGFloat(sin(angle)) * outer * 0.2
                gc.stroke(Path(ellipseIn: CGRect(x: cx - r, y: cy - r, width: 2 * r, height: 2 * r)),
                          with: style, lineWidth: 0.4)
            }
        }
        .allowsHitTesting(false)
    }
}

/// A glass tab bar (Today, Learn, You, Rooms) with the gold knight as its own round button.
struct HomeAuroraTabBar: View {
    let palette: HomeAuroraPalette
    let play: () -> Void
    let learn: () -> Void
    let you: () -> Void
    let rooms: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            HStack(spacing: 0) {
                tab("Today", glyph: Glyphs.today, on: true) {}
                tab("Learn", glyph: Glyphs.coach, on: false, action: learn)
                tab("You", glyph: Glyphs.king, on: false, action: you)
                tab("Rooms", glyph: Glyphs.home, on: false, action: rooms)
            }
            .padding(.horizontal, 6)
            .frame(height: 64)
            .background {
                Capsule()
                    .fill(.ultraThinMaterial)
                    .overlay(Capsule().fill(palette.dark ? Color(hex: 0x14161E).opacity(0.55) : Color.white.opacity(0.6)))
                    .overlay(Capsule().strokeBorder(palette.line, lineWidth: 1))
                    .shadow(color: palette.shadow, radius: 18, y: 12)
            }
            Button(action: play) {
                Glyph(name: Glyphs.train, size: 32, weight: .bold)
                    .foregroundStyle(Color(hex: 0x2A1C08))
                    .frame(width: 64, height: 64)
                    .background {
                        Circle().fill(RadialGradient(stops: [.init(color: Color(hex: 0xFFF1CC), location: 0),
                                                             .init(color: Color(hex: 0xE8C27A), location: 0.45),
                                                             .init(color: Color(hex: 0xA66F25), location: 1)],
                                                     center: UnitPoint(x: 0.32, y: 0.26), startRadius: 0, endRadius: 40))
                    }
                    .overlay(Circle().strokeBorder(Color.white.opacity(0.25), lineWidth: 1))
                    .shadow(color: Color(hex: 0xE8C27A).opacity(0.45), radius: 15, y: 12)
            }
            .buttonStyle(HomeStagePress())
            .accessibilityLabel("Play")
        }
    }

    private func tab(_ title: String, glyph: String, on: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 3) {
                Glyph(name: glyph, size: 22, weight: .semibold)
                Text(title)
                    .font(.system(size: 10.5, weight: .semibold))
            }
            .foregroundStyle(on ? palette.ink : palette.ink3)
            .frame(maxWidth: .infinity)
            .frame(height: 52)
            .background(Capsule().fill(on ? palette.glassHi : .clear))
            .contentShape(Capsule())
        }
        .buttonStyle(HomeStagePress())
        .accessibilityLabel(title)
        .accessibilityAddTraits(on ? .isSelected : [])
    }
}
