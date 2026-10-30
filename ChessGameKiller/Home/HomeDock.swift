import ChessKit
import SwiftUI

/// The glass dock at the foot of the home: four doors into the app, the same every day, and in
/// the middle the jewel, a gold knight (HomeJewel). A tap on the jewel plays the game the board
/// window shows, or resumes it; holding it opens the shortcuts above it (HomeShortcutsPanel).
/// The doors never light up: they are doors, not tabs. Once the board window has scrolled away,
/// the doors fold to their icons and the jewel opens into a gold bar with the game on it.
struct HomeDock: View {
    let tone: HomeTone
    let upNext: HomeUpNext
    /// The board window has scrolled out of sight.
    let compact: Bool
    /// The shortcuts are open: the jewel is drawn over the veil instead, wearing a cross.
    let open: Bool
    let actions: HomeActions
    let openYou: () -> Void
    let primary: () -> Void
    let hold: () -> Void
    /// Where the bar is, in the home's space, so the shortcuts rise from the jewel.
    let placed: (CGRect) -> Void

    @ScaledMetric(relativeTo: .body) private var icon: CGFloat = 25
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// The bar's width, for the jewel's share of it once the doors fold.
    @State private var barWidth: CGFloat = 0

    /// How far the jewel stands above the bar's middle at rest.
    static let raise: CGFloat = 16
    /// The bar's inset around the doors.
    private static let inset: CGFloat = 6
    /// A folded door: its icon alone, still a finger wide.
    private static let foldedDoor: CGFloat = 44

    private struct Door: Identifiable {
        let title: String
        let glyph: String
        let hint: String
        let action: () -> Void
        var id: String { title }
    }

    /// Train wears the coach's capped pawn: the knight is the jewel's.
    private var doors: [Door] {
        [
            Door(title: "Train", glyph: Glyphs.coach, hint: "Lessons with \(Coach.current.title) and the Grandmaster Room", action: actions.train),
            Door(title: "Puzzles", glyph: Glyphs.puzzles, hint: "Rated puzzles and Puzzle Rush", action: actions.puzzles),
            Door(title: "Analyze", glyph: Glyphs.analyze, hint: "Find the best move in any position", action: actions.analyze),
            Door(title: "You", glyph: Glyphs.king, hint: "Your pieces, your games and Settings", action: openYou),
        ]
    }

    /// The jewel's place between the doors: room for the round jewel at rest, and all the
    /// folded doors leave once they fold.
    private var slot: CGFloat {
        guard compact else { return HomeJewel.size + 14 }
        let left: CGFloat = barWidth - 2 * Self.inset - 4 * Self.foldedDoor
        return max(left, HomeJewel.size)
    }

    var body: some View {
        let doors = self.doors
        let slot = self.slot
        let lift: CGFloat = compact ? 0 : -Self.raise
        HStack(spacing: 0) {
            button(doors[0])
            button(doors[1])
            Color.clear
                .frame(width: slot)
                .accessibilityHidden(true)
            button(doors[2])
            button(doors[3])
        }
        .padding(.horizontal, Self.inset)
        .padding(.vertical, 4)
        .frame(maxWidth: 500)
        .onGeometryChange(for: CGRect.self) { proxy in
            proxy.frame(in: .named(HomeView.root))
        } action: { frame in
            barWidth = frame.width
            placed(frame)
        }
        .homePane(Capsule(), tone: tone, weight: .bar)
        // Over the glass rather than in it, so the jewel stands proud of the bar, crisp.
        .overlay {
            HomeJewel(tone: tone, upNext: upNext, face: compact ? .folded : .rest,
                      foldedWidth: slot - 8, tap: primary, hold: hold)
                .offset(y: lift)
                .opacity(open ? 0 : 1)
                // Read first: it is the way to play.
                .accessibilitySortPriority(1)
        }
        .accessibilityElement(children: .contain)
        .padding(.top, Self.raise)
        .padding(.horizontal, 16)
        .padding(.bottom, 6)
        .frame(maxWidth: .infinity)
        .animation(reduceMotion ? .easeOut(duration: 0.2) : .spring(response: 0.42, dampingFraction: 0.86), value: compact)
        .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
    }

    private func button(_ door: Door) -> some View {
        Button(action: door.action) {
            VStack(spacing: 3) {
                Glyph(name: door.glyph, size: icon)
                if !compact {
                    Text(door.title)
                        .font(.app(.caption2, weight: .medium))
                        .lineLimit(1)
                        .fixedSize()
                }
            }
            .foregroundStyle(tone.ink)
            .frame(minWidth: Self.foldedDoor, maxWidth: compact ? Self.foldedDoor : .infinity, minHeight: compact ? 48 : 56)
            .contentShape(Rectangle())
        }
        .buttonStyle(HomePressStyle())
        .accessibilityLabel(door.title)
        .accessibilityHint(door.hint)
        .accessibilityShowsLargeContentViewer {
            Glyph(name: door.glyph, size: icon)
            Text(door.title)
        }
    }
}

/// The jewel in the middle of the dock: a gold knight. A tap plays the game the board window
/// shows, or resumes the one under way; held, it opens the shortcuts. At rest it is round and
/// stands proud of the bar. Once the window has scrolled away it opens into a gold bar with the
/// game on it ("Resume", "Your move · 4:12"), so the way to play rides along down the page.
/// With the shortcuts open it wears a cross and closes them.
struct HomeJewel: View {
    enum Face: Equatable {
        case rest, folded, open
    }

    let tone: HomeTone
    let upNext: HomeUpNext
    let face: Face
    /// How wide the gold bar is once folded.
    var foldedWidth: CGFloat = HomeJewel.size
    let tap: () -> Void
    /// Holding it opens the shortcuts (nil once they're open).
    var hold: (() -> Void)? = nil

    @State private var pressed = false

    /// The round jewel's width.
    static let size: CGFloat = 62
    /// The gold bar's height once folded, inside the dock's.
    static let foldedHeight: CGFloat = 46

    var body: some View {
        let folded = face == .folded
        let width: CGFloat = folded ? foldedWidth : Self.size
        let height: CGFloat = folded ? Self.foldedHeight : Self.size
        content
            .foregroundStyle(tone.onIvory)
            .frame(width: width, height: height)
            .background { HomeJewelGold(tone: tone, round: !folded, lit: face == .open) }
            .scaleEffect(pressed ? 0.93 : 1)
            .animation(.spring(response: 0.25, dampingFraction: 0.75), value: pressed)
            .contentShape(Capsule())
            // The hold comes first, so a tap waits only until the finger lifts.
            .onLongPressGesture(minimumDuration: 0.35, perform: held, onPressingChanged: { pressing in
                pressed = pressing
            })
            .onTapGesture(perform: tap)
            .accessibilityElement(children: .ignore)
            .accessibilityAddTraits(.isButton)
            .accessibilityLabel(spokenLabel)
            .accessibilityValue(face == .open ? "" : subtitle)
            .accessibilityHint(hold == nil ? "" : "Hold for shortcuts")
            .accessibilityAction(.default, tap)
            .accessibilityActions {
                if let hold {
                    Button("Shortcuts", action: hold)
                }
            }
            .accessibilityInputLabels(inputLabels)
            .accessibilityShowsLargeContentViewer {
                Glyph(name: Glyphs.train, size: 32)
                Text(face == .open ? "Close" : title)
            }
    }

    private func held() {
        hold?()
    }

    @ViewBuilder
    private var content: some View {
        switch face {
        case .open:
            Image(systemName: "xmark")
                .font(.system(size: 20, weight: .semibold))
        case .rest:
            Glyph(name: Glyphs.train, size: 32)
                .offset(y: -1)
        case .folded:
            // The longest words that fit the bar, down to the knight alone.
            ViewThatFits(in: .horizontal) {
                row(title, subtitle)
                row(title, shortSubtitle)
                row(title, nil)
                row(shortTitle, nil)
                Glyph(name: Glyphs.train, size: 24)
            }
            .padding(.horizontal, 14)
        }
    }

    private func row(_ title: String, _ subtitle: String?) -> some View {
        HStack(spacing: 8) {
            Glyph(name: Glyphs.train, size: 22)
            VStack(alignment: .leading, spacing: 0) {
                Text(title)
                    .font(.app(.subheadline, weight: .semibold))
                if let subtitle {
                    Text(subtitle)
                        .font(.app(.caption).monospacedDigit())
                        .opacity(0.68)
                }
            }
            .lineLimit(1)
            .fixedSize()
        }
    }

    private var title: String { upNext.inProgress ? "Resume" : "Play \(upNext.rival.name)" }
    private var shortTitle: String { upNext.inProgress ? "Resume" : "Play" }

    private var side: String {
        upNext.randomSide ? "Either side" : (upNext.playerColor == .white ? "White" : "Black")
    }

    /// The game in a few words: "White · No clock", "Your move · 4:12".
    private var subtitle: String {
        if upNext.inProgress {
            if let time = upNext.yourTime { return "\(shortSubtitle) · \(time.clockLabel)" }
            return shortSubtitle
        }
        return "\(side) · \(upNext.timeControl.name)"
    }

    /// Fewer words for a narrow bar: whose move it is, or your side.
    private var shortSubtitle: String {
        upNext.inProgress ? (upNext.yourMove ? "Your move" : "Their move") : side
    }

    private var spokenLabel: String {
        if face == .open { return "Close shortcuts" }
        return upNext.inProgress ? "Resume your game against \(upNext.rival.name)" : "Play \(upNext.rival.name)"
    }

    private var inputLabels: [String] {
        if face == .open { return ["Close"] }
        return upNext.inProgress ? ["Resume"] : ["Play", "Play \(upNext.rival.name)"]
    }
}

/// The jewel's gold: the pieces' metal lit from the top left like the board's pieces, with a
/// bright edge, a sheen across its top and a warm glow on the glass around it. Round, it sits
/// in a dark setting ringed with a fine line of gold.
struct HomeJewelGold: View {
    let tone: HomeTone
    let round: Bool
    var lit = false

    var body: some View {
        let gold = EllipticalGradient(colors: [tone.jewelLight, tone.metal, tone.jewelDeep],
                                      center: UnitPoint(x: 0.35, y: 0.28),
                                      startRadiusFraction: 0, endRadiusFraction: 0.9)
        let edge = LinearGradient(colors: [Color.white.opacity(0.75), tone.metal.opacity(0.35), tone.jewelDeep],
                                  startPoint: .top, endPoint: .bottom)
        let sheen = LinearGradient(colors: [Color.white.opacity(0.3), Color.white.opacity(0)],
                                   startPoint: .top, endPoint: UnitPoint(x: 0.5, y: 0.55))
        let setting: Double = round ? 1 : 0
        ZStack {
            Capsule()
                .fill(tone.canvas.opacity(0.92))
                .padding(-3.5)
                .opacity(setting)
            Capsule()
                .strokeBorder(tone.metal.opacity(0.42), lineWidth: 0.75)
                .padding(-5.5)
                .opacity(setting)
            Capsule()
                .fill(gold)
                .shadow(color: tone.metal.opacity(lit ? 0.55 : 0.3), radius: lit ? 18 : 12)
                .shadow(color: Color.black.opacity(0.4), radius: 5, y: 3)
            Capsule()
                .fill(sheen)
                .padding(2.5)
            Capsule()
                .strokeBorder(edge, lineWidth: 1)
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// One of the jewel's shortcuts.
struct HomeShortcut: Identifiable {
    let title: String
    let glyph: String
    let hint: String
    /// Something is happening there now (players waiting online): a small green dot.
    var live = false
    let action: () -> Void

    var id: String { title }
}

/// What the jewel holds, rising out of it on a long press: the five rivals, to play one at
/// once, and the other ways to a game (Online, a friend, Today's Move, a real board through the
/// camera). A pick closes it and goes; so does a tap anywhere around it, or on the jewel.
struct HomeShortcutsPanel: View {
    let tone: HomeTone
    /// The rival the board window offers: lit among the five.
    let next: MatchController.Level
    /// A game is under way: a rival opens the New Game sheet, which asks before ending it.
    let underWay: Bool
    let shortcuts: [HomeShortcut]
    let playRival: (MatchController.Level) -> Void
    let close: () -> Void

    @AccessibilityFocusState private var titleFocused: Bool
    @ScaledMetric(relativeTo: .caption2) private var orb: CGFloat = 46

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Play a rival")
                .font(.app(.footnote, weight: .semibold))
                .foregroundStyle(tone.ink2)
                .padding(.leading, 4)
                .accessibilityAddTraits(.isHeader)
                .accessibilityFocused($titleFocused)
            HStack(alignment: .top, spacing: 0) {
                ForEach(Rival.all) { rival in
                    rivalButton(rival)
                }
            }
            HomeHairline(tone: tone)
                .padding(.horizontal, 4)
                .padding(.vertical, 2)
            HStack(alignment: .top, spacing: 0) {
                ForEach(shortcuts) { shortcut in
                    shortcutButton(shortcut)
                }
            }
        }
        .padding(.horizontal, 10)
        .padding(.top, 14)
        .padding(.bottom, 12)
        .homePane(RoundedRectangle(cornerRadius: HomeMetrics.cardRadius, style: .continuous), tone: tone)
        .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
        .accessibilityElement(children: .contain)
        .accessibilityAddTraits(.isModal)
        .accessibilityAction(.escape, close)
        .onAppear { titleFocused = true }
    }

    private func rivalButton(_ rival: Rival) -> some View {
        let isNext = rival.level == next
        let size: CGFloat = min(orb, 56)
        return Button { pick { playRival(rival.level) } } label: {
            VStack(spacing: 5) {
                Image(rival.glowName)
                    .resizable()
                    .interpolation(.high)
                    .scaledToFit()
                    .frame(width: size, height: size)
                    .background {
                        if isNext {
                            Circle()
                                .fill(RadialGradient(colors: [rival.light.opacity(0.34), rival.light.opacity(0)],
                                                     center: .center, startRadius: 0, endRadius: size * 0.75))
                                .frame(width: size * 1.5, height: size * 1.5)
                        }
                    }
                Text(rival.name)
                    .font(.app(.caption2, weight: .semibold))
                    .foregroundStyle(isNext ? tone.ink : tone.ink2)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 2)
            .contentShape(Rectangle())
        }
        .buttonStyle(HomePressStyle())
        .accessibilityLabel(underWay ? "New game against \(rival.name)" : "Play \(rival.name)")
        .accessibilityValue(rival.spokenElo)
        .accessibilityHint(isNext ? "Up next" : "")
    }

    private func shortcutButton(_ shortcut: HomeShortcut) -> some View {
        Button { pick(shortcut.action) } label: {
            VStack(spacing: 6) {
                Glyph(name: shortcut.glyph, size: 24)
                    .foregroundStyle(tone.ink)
                    .frame(width: 48, height: 48)
                    .background {
                        Circle()
                            .fill(tone.ink.opacity(0.08))
                            .overlay { Circle().strokeBorder(tone.ink.opacity(0.16), lineWidth: 0.75) }
                    }
                    .overlay(alignment: .topTrailing) {
                        if shortcut.live {
                            Circle()
                                .fill(tone.live)
                                .frame(width: 8, height: 8)
                                .overlay { Circle().stroke(tone.canvas, lineWidth: 1.5) }
                                .offset(x: -3, y: 3)
                        }
                    }
                Text(shortcut.title)
                    .font(.app(.caption2, weight: .medium))
                    .foregroundStyle(tone.ink)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .minimumScaleFactor(0.85)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 2)
            .contentShape(Rectangle())
        }
        .buttonStyle(HomePressStyle())
        .accessibilityLabel(shortcut.title)
        .accessibilityHint(shortcut.hint)
    }

    /// Closes the panel, then opens what was picked.
    private func pick(_ action: @escaping () -> Void) {
        close()
        action()
    }
}

/// Once, after a first game: a small note above the jewel that it holds shortcuts. A tap
/// puts it away; it goes by itself after a few seconds.
struct HomeJewelTip: View {
    let tone: HomeTone
    let close: () -> Void

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 18, style: .continuous)
        Button(action: close) {
            HStack(spacing: 9) {
                Image(systemName: AppTip.jewelShortcuts.symbol)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(tone.metal)
                Text(AppTip.jewelShortcuts.text)
                    .font(.app(.footnote, weight: .semibold))
                    .foregroundStyle(tone.ink)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .homePane(shape, tone: tone, weight: .bar)
            .contentShape(shape)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Tip. \(AppTip.jewelShortcuts.text)")
        .accessibilityHint("Dismisses the tip")
    }
}

/// Your own things in one glass panel: your pieces, your games and Settings (and Pro, once there is one).
/// It opens from the dock's You, or by pulling the board down, and comes from where it was
/// asked for. Everything else has its own door, so nothing here is found twice.
struct HomeYouPanel: View {
    let tone: HomeTone
    let piecesLine: String
    let gamesLine: String
    let actions: HomeActions
    let fromTop: Bool
    let close: () -> Void

    @AccessibilityFocusState private var titleFocused: Bool
    @State private var drag: CGFloat = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .center) {
                Text("You")
                    .font(HomeType.section)
                    .foregroundStyle(tone.ink)
                    .accessibilityAddTraits(.isHeader)
                    .accessibilityFocused($titleFocused)
                Spacer(minLength: 0)
                Button(action: close) {
                    Image(systemName: "xmark")
                        .font(.app(.body, weight: .semibold))
                        .foregroundStyle(tone.ink2)
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(HomePressStyle())
                .accessibilityLabel("Close")
                // The cross sits in the corner the card's inset leaves, its glyph in line with the rows' chevrons.
                .padding(.trailing, -14)
            }
            VStack(spacing: 0) {
                HomeLinkRow(title: "Your pieces", detail: piecesLine, tone: tone) { go(actions.army) }
                HomeHairline(tone: tone)
                HomeLinkRow(title: "Your games", detail: gamesLine, tone: tone) { go(actions.rewind) }
                HomeHairline(tone: tone)
                HomeLinkRow(title: "Settings", detail: "Board look, sound, hints", tone: tone) { go(actions.settings) }
                if let premium = actions.premium {
                    HomeHairline(tone: tone)
                    HomeLinkRow(title: "Chess Game Killer Pro", detail: "Everything, with no limits", tone: tone) { go(premium) }
                }
            }
        }
        .padding(.horizontal, HomeMetrics.inset)
        .padding(.top, 8)
        .padding(.bottom, 4)
        .homePane(RoundedRectangle(cornerRadius: HomeMetrics.cardRadius, style: .continuous), tone: tone)
        .offset(y: fromTop ? min(drag, 0) : max(drag, 0))
        .gesture(
            DragGesture(minimumDistance: 12)
                .onChanged { drag = $0.translation.height }
                .onEnded { value in
                    let away = fromTop ? value.predictedEndTranslation.height < -60 : value.predictedEndTranslation.height > 60
                    if away { close() }
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) { drag = 0 }
                }
        )
        .accessibilityElement(children: .contain)
        .accessibilityAddTraits(.isModal)
        .accessibilityAction(.escape, close)
        .onAppear { titleFocused = true }
    }

    /// Closes the panel, then opens what was picked.
    private func go(_ action: @escaping () -> Void) {
        close()
        action()
    }
}

/// While the board is pulled down: a small glass tab under the status bar, a king in a ring
/// that fills, and the word "You". Let go once the ring is full and the You panel opens.
struct HomePullCue: View {
    let scroll: HomeScroll
    let tone: HomeTone
    let threshold: CGFloat
    let armed: Bool

    var body: some View {
        let pull = min(max(-scroll.y / threshold, 0), 1)
        let full = pull >= 1 || armed
        HStack(spacing: 7) {
            ZStack {
                Circle()
                    .stroke(tone.ink.opacity(0.22), lineWidth: 1.5)
                Circle()
                    .trim(from: 0, to: pull)
                    .stroke(tone.metal, style: StrokeStyle(lineWidth: 1.5, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                Glyph(name: Glyphs.king, size: 14)
                    .foregroundStyle(full ? tone.metal : tone.ink)
            }
            .frame(width: 26, height: 26)
            Text("You")
                .font(.app(.footnote, weight: .semibold))
                .foregroundStyle(full ? tone.metal : tone.ink)
        }
        .padding(.leading, 5)
        .padding(.trailing, 12)
        .padding(.vertical, 4)
        .homePane(Capsule(), tone: tone, weight: .bar)
        .scaleEffect(0.8 + 0.2 * pull)
        .opacity(Double(min(pull * 1.6, 1)))
        .frame(maxWidth: .infinity)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// Under the status bar once the page scrolls beneath it: the page dissolves into a soft
/// frost, so text never runs under the clock.
struct HomeTopEdge: View {
    let scroll: HomeScroll
    let tone: HomeTone
    /// How far the page scrolls before cards reach the status bar.
    let start: CGFloat
    let height: CGFloat

    var body: some View {
        let shown = min(max((scroll.y - start) / 60, 0), 1)
        ZStack {
            Rectangle().fill(.ultraThinMaterial)
            tone.canvas.opacity(0.74)
        }
        .mask {
            LinearGradient(stops: [
                .init(color: .black, location: 0),
                .init(color: .black, location: 0.62),
                .init(color: .clear, location: 1),
            ], startPoint: .top, endPoint: .bottom)
        }
        .frame(height: height)
        .frame(maxWidth: .infinity)
        .opacity(Double(shown))
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// Under the dock, and a little above it: the page dissolves into a soft frost before it
/// reaches the dock, so no card is ever seen cut by the dock or carrying on beneath it.
struct HomeBottomEdge: View {
    let tone: HomeTone
    /// How far above the dock the page starts to fade.
    let fade: CGFloat

    var body: some View {
        ZStack {
            Rectangle().fill(.ultraThinMaterial)
            tone.canvas.opacity(0.8)
        }
        .mask {
            VStack(spacing: 0) {
                LinearGradient(colors: [.clear, .black], startPoint: .top, endPoint: .bottom)
                    .frame(height: fade)
                Color.black
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}
