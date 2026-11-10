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
            // The jewel's place: as wide as its slot and no taller than nothing, so the bar
            // keeps the doors' height.
            Color.clear
                .frame(width: slot, height: 0)
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
    /// Counts the taps at rest: each one sends a glint across the gold before the game opens.
    @State private var vaults = 0
    /// Mid-glint: a second tap waits for the first.
    @State private var vaulting = false
    @AppStorage("haptics") private var hapticsOn = true
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

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
            .background {
                HomeJewelGold(tone: tone, round: !folded, lit: face == .open)
                    .overlay {
                        if face == .rest {
                            JewelSheen(trigger: vaults)
                        }
                    }
            }
            .background {
                if face == .rest {
                    JewelLandingRing(color: tone.metal, trigger: vaults)
                }
            }
            .scaleEffect(pressed ? 0.93 : 1)
            .animation(.spring(response: 0.25, dampingFraction: 0.75), value: pressed)
            .contentShape(Capsule())
            // The hold comes first, so a tap waits only until the finger lifts.
            .onLongPressGesture(minimumDuration: 0.35, perform: held, onPressingChanged: { pressing in
                pressed = pressing
            })
            .onTapGesture(perform: tapped)
            .sensoryFeedback(.impact(flexibility: .soft, intensity: 0.75), trigger: vaults) { _, _ in hapticsOn }
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

    /// At rest the jewel catches the light first and the game opens as it fades; otherwise straight away.
    private func tapped() {
        guard face == .rest, !reduceMotion else {
            tap()
            return
        }
        guard !vaulting else { return }
        vaulting = true
        vaults += 1
        Task { @MainActor in
            try? await Task.sleep(for: Self.vaultLanding)
            vaulting = false
            tap()
        }
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
                .modifier(KnightVaultEffect(trigger: vaults))
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

/// Rooms, from the bar or a hold on the gold knight: only the ways to a game that the Today
/// page doesn't already hold (Alex, 2026-11-08: "Lets go with all"). A person online, a friend,
/// a new game on your own side and clock, and your games. Today's Move, Puzzles, Analyze and
/// the coach live on Today, so they are not repeated here. The rivals' hall joins them, the
/// fifth room, as the review proposed once the hall landed. Your Grudge has its room beside the
/// rivals since its Home card gave way to Chess DNA (Alex, 2026-11-09: "place in rooms").
enum HomeShortcutKind: String, CaseIterable, Identifiable {
    case online, friend, newGame, rivals, grudge, games

    var id: String { rawValue }

    /// What Rooms offers: Online and A friend only when the app can reach other players.
    static func list(online: Bool) -> [HomeShortcutKind] {
        online ? allCases : allCases.filter { !$0.needsOnline }
    }

    var needsOnline: Bool { self == .online || self == .friend }

    var title: String {
        switch self {
        case .online: return "Online"
        case .friend: return "A friend"
        case .newGame: return "New game"
        case .rivals: return "Rivals"
        case .grudge: return "Your Grudge"
        case .games: return "Your games"
        }
    }

    var glyph: String {
        switch self {
        case .online: return Glyphs.online
        case .friend: return Glyphs.challenge
        case .newGame: return Glyphs.play
        // The shield the hall's own door wore on Home.
        case .rivals: return "shield.lefthalf.filled"
        // The Grudge burns red behind its king.
        case .grudge: return "flame.fill"
        case .games: return Glyphs.games
        }
    }

    var hint: String {
        switch self {
        case .online: return "Play someone at your level now"
        case .friend: return "Send a friend a game by link"
        case .newGame: return "Pick your side, clock and rival"
        case .rivals: return "The five rivals, and the one to beat next"
        case .grudge: return "The rival that remembers every game"
        case .games: return "Look back at the games you've played"
        }
    }
}

/// One of the jewel's shortcuts.
struct HomeShortcut: Identifiable {
    let kind: HomeShortcutKind
    /// Something is happening there now (players waiting online): a small green dot.
    var live = false
    let action: () -> Void

    var id: HomeShortcutKind { kind }
    var title: String { kind.title }
    var glyph: String { kind.glyph }
    var hint: String { kind.hint }
}

/// What the jewel holds, rising out of it on a long press: the five rivals, to play one at
/// once, and under them the shortcuts in rows of four (see `HomeShortcutKind`). A pick closes
/// it and goes; so does a tap anywhere around it, or on the jewel.
struct HomeShortcutsPanel: View {
    /// Four to a row under the five rivals.
    static let perRow = 4

    /// Rooms sit in one row when there are four or five; six sit in two even rows of three.
    /// Elsewhere, four to a row.
    private var columns: [GridItem] {
        let rooms: Int = shortcuts.count > 5 ? 3 : max(shortcuts.count, 1)
        let count: Int = asRooms ? rooms : Self.perRow
        return Array(repeating: GridItem(.flexible(), spacing: 0, alignment: .top), count: count)
    }

    let tone: HomeTone
    /// The rival the board window offers: lit among the five.
    let next: MatchController.Level
    /// A game is under way: a rival opens the New Game sheet, which asks before ending it.
    let underWay: Bool
    let shortcuts: [HomeShortcut]
    let playRival: (MatchController.Level) -> Void
    let close: () -> Void
    /// Rooms on the Aurora home: no rivals here (they have their own row on the page, Alex
    /// 2026-11-07), and a grabber in place of the jewel's cross; a drag down closes it.
    var asRooms = false

    @AccessibilityFocusState private var titleFocused: Bool
    @State private var drag: CGFloat = 0
    @ScaledMetric(relativeTo: .caption2) private var orb: CGFloat = 46

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if asRooms {
                Capsule()
                    .fill(tone.ink.opacity(0.25))
                    .frame(width: 38, height: 4)
                    .frame(maxWidth: .infinity)
                    .padding(.bottom, 2)
                    .accessibilityHidden(true)
                Text("Rooms")
                    .font(.system(size: 20, weight: .medium, design: .serif))
                    .foregroundStyle(tone.ink)
                    .padding(.leading, 6)
                    .padding(.bottom, 4)
                    .accessibilityAddTraits(.isHeader)
                    .accessibilityFocused($titleFocused)
            } else {
                Text("Face a rival")
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
            }
            LazyVGrid(columns: columns, spacing: 12) {
                ForEach(shortcuts) { shortcut in
                    shortcutButton(shortcut)
                }
            }
        }
        .padding(.horizontal, 10)
        .padding(.top, 14)
        .padding(.bottom, 12)
        .homePane(RoundedRectangle(cornerRadius: HomeMetrics.cardRadius, style: .continuous), tone: tone)
        .offset(y: drag)
        .gesture(DragGesture(minimumDistance: 8)
            .onChanged { value in if asRooms { drag = max(0, value.translation.height) } }
            .onEnded { value in
                guard asRooms else { return }
                if value.translation.height > 70 || value.predictedEndTranslation.height > 160 {
                    close()
                } else {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) { drag = 0 }
                }
            })
        .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
        .accessibilityElement(children: .contain)
        .accessibilityAddTraits(.isModal)
        .accessibilityAction(.escape, close)
        .onAppear { titleFocused = true }
    }

    /// Each rival's coin a little bigger than the one before, so the row climbs toward the
    /// Ashen King.
    private func coinSize(_ rival: Rival) -> CGFloat {
        min(orb, 56) * (0.8 + 0.07 * CGFloat(rival.level.rawValue))
    }

    private func rivalButton(_ rival: Rival) -> some View {
        let isNext = rival.level == next
        let size = coinSize(rival)
        return Button { pick { playRival(rival.level) } } label: {
            VStack(spacing: 3) {
                RivalCoin(rival: rival, size: size)
                    .padding(2)
                    .overlay {
                        // The rival up next wears a gold ring.
                        if isNext {
                            Circle()
                                .strokeBorder(tone.metal, lineWidth: 1.5)
                                .shadow(color: tone.metal.opacity(0.5), radius: 6)
                        }
                    }
                    // The coins sit on one line however big they grow.
                    .frame(height: coinSize(Rival.all[Rival.all.count - 1]) + 4, alignment: .bottom)
                Text(rival.shortName)
                    .font(.app(.caption2, weight: .semibold))
                    .foregroundStyle(tone.ink)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                Text(rival.elo.replacingOccurrences(of: "~", with: ""))
                    .font(.app(.caption2).monospacedDigit())
                    .foregroundStyle(tone.ink2)
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
                    HomeLinkRow(title: "Beauty of Chess Pro", detail: "Everything, with no limits", tone: tone) { go(premium) }
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
