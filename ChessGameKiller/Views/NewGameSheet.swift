import ChessKit
import SwiftUI

/// Which side the player wants against the computer.
enum SideChoice: String, CaseIterable, Identifiable {
    case white, black, random

    var id: Self { self }

    var color: Piece.Color {
        switch self {
        case .white: return .white
        case .black: return .black
        case .random: return Bool.random() ? .white : .black
        }
    }
}

/// How much the coach says during a game. Two switches, shown as one choice, in two words:
/// "grades" say how good your move was, "hints" say where to move.
enum CoachMode: CaseIterable, Identifiable {
    case full, verdicts, hints, silent

    var id: Self { self }

    var name: String {
        switch self {
        case .full: return "Grades + hints"
        case .verdicts: return "Grades"
        case .hints: return "Hints"
        case .silent: return "Just play"
        }
    }

    /// One line about the mode.
    var detail: String {
        switch self {
        case .full: return "Rates each move and spotlights your best move"
        case .verdicts: return "Rates each move, no hints. A fair test."
        case .hints: return "Spotlights your best move, no grades"
        case .silent: return "Just chess. The coach keeps quiet."
        }
    }

    var showsHints: Bool { self == .full || self == .hints }
    var showsVerdicts: Bool { self == .full || self == .verdicts }

    init(hints: Bool, verdicts: Bool) {
        switch (hints, verdicts) {
        case (true, true): self = .full
        case (true, false): self = .hints
        case (false, true): self = .verdicts
        case (false, false): self = .silent
        }
    }
}

/// Picks the rival, the side, the clock and the coach, then starts the game.
///
/// Side, clock and coach live in one card of three rows. A row shows its
/// current choice; tapping it unfolds the options in place, and picking one
/// folds it back up. Nothing is kept until the game starts: Cancel, or closing
/// the sheet, leaves every choice as it was.
struct NewGameSheet: View {
    /// The rows of the match card.
    private enum MatchRow {
        case side, clock, coach, stake
    }

    let theme: BoardTheme
    /// The rival of a game in progress that starting a new one would cost, so the person is asked first.
    let forfeits: String?
    let start: (MatchController.Setup) -> Void
    /// Opens Challenge a friend instead. Nil hides the row.
    var challenge: (() -> Void)? = nil

    @AppStorage("setup.side") private var side: SideChoice = .white
    @AppStorage("setup.level") private var level: MatchController.Level = .club
    @AppStorage("setup.clock") private var timeControl: TimeControl = .unlimited
    @AppStorage("showBestMoves") private var showBestMoves = false
    @AppStorage("coachVerdicts") private var showVerdicts = true

    @AppStorage("haptics") private var hapticsOn = true

    /// The choices on the sheet, kept only when the game starts.
    @State private var draftSide: SideChoice
    @State private var draftLevel: MatchController.Level
    @State private var draftClock: TimeControl
    @State private var draftCoach: CoachMode
    /// The piece the player means to put on the line. Never remembered: every stake is chosen afresh.
    @State private var draftStake: ArmySlot?
    /// The army, for On the line. Absent in tests that draw the sheet without one.
    @Environment(ArmyStore.self) private var army: ArmyStore?
    @State private var scrolledLevel: MatchController.Level?
    @State private var openRow: MatchRow?
    @State private var confirmingForfeit = false
    @Environment(\.dismiss) private var dismiss

    /// `stakesOpen` and `stake` are for pictures: On the line unfolded, with a piece already picked.
    init(theme: BoardTheme, forfeits: String? = nil, defaults: UserDefaults = .standard,
         stakesOpen: Bool = false, stake: ArmySlot? = nil,
         start: @escaping (MatchController.Setup) -> Void, challenge: (() -> Void)? = nil) {
        _openRow = State(initialValue: stakesOpen ? .stake : nil)
        _draftStake = State(initialValue: stake)
        self.theme = theme
        self.forfeits = forfeits
        self.start = start
        self.challenge = challenge
        let level = (defaults.object(forKey: "setup.level") as? Int).flatMap { MatchController.Level(rawValue: $0) } ?? .club
        _draftSide = State(initialValue: defaults.string(forKey: "setup.side").flatMap { SideChoice(rawValue: $0) } ?? .white)
        _draftLevel = State(initialValue: level)
        _draftClock = State(initialValue: defaults.string(forKey: "setup.clock").flatMap { TimeControl(rawValue: $0) } ?? .unlimited)
        _draftCoach = State(initialValue: CoachMode(
            hints: defaults.object(forKey: "showBestMoves") as? Bool ?? false,
            verdicts: defaults.object(forKey: "coachVerdicts") as? Bool ?? true
        ))
        _scrolledLevel = State(initialValue: level)
    }

    /// The choices from last time, for when the sheet is closed without starting.
    static func savedSetup(_ defaults: UserDefaults = .standard) -> MatchController.Setup {
        let side = defaults.string(forKey: "setup.side").flatMap { SideChoice(rawValue: $0) } ?? .white
        let level = (defaults.object(forKey: "setup.level") as? Int).flatMap { MatchController.Level(rawValue: $0) } ?? .club
        let clock = defaults.string(forKey: "setup.clock").flatMap { TimeControl(rawValue: $0) } ?? TimeControl.unlimited
        return MatchController.Setup(playerColor: side.color, level: level, timeControl: clock)
    }

    private var accent: Color { theme.accent ?? .accentColor }

    /// Keeps the choices for next time, then starts the game.
    private func play() {
        side = draftSide
        level = draftLevel
        timeControl = draftClock
        showBestMoves = draftCoach.showsHints
        showVerdicts = draftCoach.showsVerdicts
        start(MatchController.Setup(playerColor: draftSide.color, level: draftLevel, timeControl: draftClock,
                                    stake: stake))
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    if let challenge {
                        ChallengeEntryRow(theme: theme, action: challenge)
                    }

                    section("Your rival") {
                        rivalCarousel
                        dots
                    }

                    section("The match") {
                        matchCard
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 12)
                .padding(.bottom, 24)
                .animation(.spring(response: 0.42, dampingFraction: 0.86), value: openRow)
            }
            .sensoryFeedback(.selection, trigger: openRow) { _, _ in hapticsOn }
            .safeAreaInset(edge: .bottom) {
                Button {
                    if forfeits == nil { play() } else { confirmingForfeit = true }
                } label: {
                    Label(playTitle, systemImage: "play.fill")
                        .font(.app(.headline))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                }
                .buttonStyle(.borderedProminent)
                .buttonBorderShape(.capsule)
                .controlSize(.large)
                .tint(accent)
                .foregroundStyle(theme.isDark ? Color.black : Color.white)
                .padding(.horizontal, 20)
                .padding(.bottom, 8)
                .shadow(color: theme.glows ? accent.opacity(0.6) : .clear, radius: 14)
                .animation(.snappy, value: draftLevel)
                .confirmationDialog("Leave your game against \(forfeits ?? "your rival")?",
                                    isPresented: $confirmingForfeit, titleVisibility: .visible) {
                    Button("Resign and play \(draftLevel.rival.name)", role: .destructive) { play() }
                    Button("Keep playing", role: .cancel) {}
                } message: {
                    Text("It counts as a loss for your army.")
                }
            }
            .navigationTitle("New Game")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
        .presentationDetents([.large])
        .presentationBackground {
            ThemeBackdrop(theme: theme)
        }
        .tint(accent)
        .preferredColorScheme(theme.isDark ? .dark : nil)
    }

    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title.uppercased())
                .font(.app(.caption, weight: .semibold))
                .foregroundStyle(.secondary)
                .tracking(1)
                .accessibilityAddTraits(.isHeader)
            content()
        }
    }

    // MARK: The match card

    private var matchCard: some View {
        VStack(spacing: 0) {
            MatchRowButton(label: "Play as", value: sideName(draftSide), detail: nil, isOpen: openRow == .side,
                           theme: theme, icon: { sideIcon }) {
                toggle(.side)
            }
            if openRow == .side {
                HStack(spacing: 8) {
                    ForEach(SideChoice.allCases) { choice in
                        sideCard(choice)
                    }
                }
                .padding(.horizontal, 10)
                .padding(.top, 4)
                .padding(.bottom, 12)
                .transition(unfold)
            }
            rowDivider

            MatchRowButton(label: "Clock", value: draftClock.name, detail: draftClock.kind, isOpen: openRow == .clock,
                           theme: theme, icon: { Glyph(name: Glyphs.play, size: 22) }) {
                toggle(.clock)
            }
            if openRow == .clock {
                optionList {
                    ForEach(TimeControl.allCases) { control in
                        OptionRow(title: control.name, detail: control.detail, isOn: draftClock == control, theme: theme) {
                            choose { draftClock = control }
                        }
                    }
                }
            }
            rowDivider

            MatchRowButton(label: "Coach", value: draftCoach.name, detail: nil, isOpen: openRow == .coach,
                           theme: theme, icon: { Glyph(name: Glyphs.coach, size: 22) }) {
                toggle(.coach)
            }
            if openRow == .coach {
                optionList {
                    ForEach(CoachMode.allCases) { mode in
                        OptionRow(title: mode.name, detail: mode.detail, isOn: draftCoach == mode, theme: theme) {
                            choose { draftCoach = mode }
                        }
                    }
                }
            }

            if army != nil {
                rowDivider
                MatchRowButton(label: "On the line", value: stakeValue, detail: nil, isOpen: openRow == .stake,
                               theme: theme, icon: { stakeIcon }) {
                    toggle(.stake)
                }
                if openRow == .stake {
                    stakePicker
                        .transition(unfold)
                }
            }
        }
        .background {
            let shape = RoundedRectangle(cornerRadius: 22, style: .continuous)
            shape
                .fill(theme.isDark ? AnyShapeStyle(.ultraThinMaterial) : AnyShapeStyle(Color(.secondarySystemGroupedBackground)))
                .overlay { shape.strokeBorder(Color.primary.opacity(theme.isDark ? 0.12 : 0.08), lineWidth: 1) }
                .shadow(color: .black.opacity(theme.isDark ? 0.3 : 0.08), radius: 16, y: 6)
        }
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
    }

    /// The king of the chosen side, for the Play as row.
    @ViewBuilder
    private var sideIcon: some View {
        switch draftSide {
        case .white:
            PieceImage(piece: Piece(.king, color: .white, square: .e1), theme: theme, size: 24)
        case .black:
            PieceImage(piece: Piece(.king, color: .black, square: .e8), theme: theme, size: 24)
        case .random:
            ZStack {
                PieceImage(piece: Piece(.king, color: .black, square: .e8), theme: theme, size: 19)
                    .offset(x: 5, y: -2)
                PieceImage(piece: Piece(.king, color: .white, square: .e1), theme: theme, size: 19)
                    .offset(x: -5, y: 2)
            }
        }
    }

    private var rowDivider: some View {
        Rectangle()
            .fill(Color.primary.opacity(theme.isDark ? 0.08 : 0.06))
            .frame(height: 1)
            .padding(.leading, 58)
    }

    private var unfold: AnyTransition {
        .opacity.combined(with: .move(edge: .top))
    }

    private func optionList<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        VStack(spacing: 2) { content() }
            .padding(.horizontal, 10)
            .padding(.top, 4)
            .padding(.bottom, 10)
            .transition(unfold)
    }

    private func toggle(_ row: MatchRow) {
        openRow = openRow == row ? nil : row
    }

    /// Applies a choice, then folds the row back up a beat later so the check is seen.
    private func choose(_ change: @escaping () -> Void) {
        withAnimation(.snappy) { change() }
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(260))
            openRow = nil
        }
    }

    // MARK: On the line

    /// The stake that will count: the one picked, if it is still allowed with these choices.
    private var stake: ArmySlot? {
        guard let army, let draftStake, !draftCoach.showsHints,
              army.canStake(draftStake, against: draftLevel) else { return nil }
        return draftStake
    }

    /// The piece the chosen rival is holding, if any: the next game against it is a rescue.
    private var prisoner: ArmySlot? { army?.prisoner(of: draftLevel) }

    /// The colour the army's pieces are drawn in here: the side picked, White for Random.
    private var armyColor: Piece.Color { draftSide == .black ? .black : .white }

    private var playTitle: String {
        if let army, let stake { return "Play for \(army.displayName(of: stake))" }
        if let army, let prisoner { return "Rescue \(army.displayName(of: prisoner))" }
        return "Play \(draftLevel.rival.name)"
    }

    private var stakeValue: String {
        if let army, let stake { return army.displayName(of: stake) }
        if let army, let prisoner { return "Rescue \(army.displayName(of: prisoner))" }
        return "Nothing"
    }

    @ViewBuilder
    private var stakeIcon: some View {
        if let slot = stake ?? prisoner {
            PieceImage(piece: Piece(slot.kind, color: armyColor, square: .a1), theme: theme, size: 24)
        } else {
            Glyph(name: Glyphs.army, size: 22)
        }
    }

    /// Why nothing can go on the line right now, if that's the case.
    private var stakeBlocked: String? {
        guard let army else { return nil }
        let rival = draftLevel.rival.name
        if let prisoner {
            return "\(rival) is holding \(army.displayName(of: prisoner, capitalized: false)). Win this game to get it back. Nothing else can go on the line against \(rival) until then."
        }
        if army.stakeable.isEmpty {
            return "Pieces earn a name at Veteran (25 XP). Named pieces can go on the line."
        }
        if draftCoach.showsHints {
            return "Turn hints off in Coach to put a piece on the line."
        }
        return nil
    }

    private var stakePicker: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let reason = stakeBlocked {
                Text(reason)
                    .font(.app(.footnote))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            } else if let army {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        stakeCard(nil, army: army)
                        ForEach(army.stakeable) { slot in
                            stakeCard(slot, army: army)
                        }
                    }
                    .padding(.vertical, 2)
                }
                Text("Win: double XP and a trophy from \(draftLevel.rival.name). Lose: \(draftLevel.rival.name) keeps the piece until you beat \(draftLevel.rival.name) again.")
                    .font(.app(.footnote))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.horizontal, 14)
        .padding(.top, 4)
        .padding(.bottom, 12)
    }

    private func stakeCard(_ slot: ArmySlot?, army: ArmyStore) -> some View {
        let isSelected = stake == slot
        let record = slot.map { army.record(for: $0) }
        let name = slot.map { army.displayName(of: $0) } ?? "Nothing"
        return Button {
            choose { draftStake = slot }
        } label: {
            VStack(spacing: 4) {
                Group {
                    if let slot, let record {
                        let piece = Piece(slot.kind, color: armyColor, square: .a1)
                        PieceImage(piece: piece, theme: theme, size: 40)
                            .modifier(VeteranAura(rank: record.rank, piece: piece, theme: theme, size: 40, onBoard: false))
                    } else {
                        Image(systemName: "minus")
                            .font(.app(.title3, weight: .semibold))
                            .foregroundStyle(.secondary)
                    }
                }
                .frame(height: 42)
                Text(name)
                    .font(.app(.caption, weight: .bold))
                    .foregroundStyle(isSelected ? accent : Color.primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                Text(record.map { "\($0.rank.title) · \($0.xp) XP" } ?? "Just play")
                    .font(.app(.caption2))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .frame(width: 92)
            .frame(minHeight: 96)
            .background(card(selected: isSelected, color: accent, glow: theme.glows ? accent : nil))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(slot == nil ? "Nothing on the line" : "Put \(name) on the line")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    // MARK: Rivals

    private var rivalCarousel: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            LazyHStack(spacing: 12) {
                ForEach(Rival.all) { rival in
                    RivalCard(rival: rival, isSelected: draftLevel == rival.level, theme: theme,
                          holding: army?.prisoner(of: rival.level).map { army?.displayName(of: $0) ?? "" })
                        .containerRelativeFrame(.horizontal) { length, _ in length - 50 }
                        .scrollTransition(.interactive, axis: .horizontal) { content, phase in
                            content
                                .scaleEffect(phase.isIdentity ? 1 : 0.94)
                                .opacity(phase.isIdentity ? 1 : 0.6)
                        }
                        .id(rival.level)
                        .onTapGesture {
                            withAnimation(.snappy) { scrolledLevel = rival.level }
                        }
                        .accessibilityAddTraits(.isButton)
                        .accessibilityAction {
                            withAnimation(.snappy) { scrolledLevel = rival.level }
                        }
                }
            }
            .scrollTargetLayout()
            .padding(.vertical, 8)
        }
        .scrollTargetBehavior(.viewAligned)
        .scrollPosition(id: $scrolledLevel)
        .scrollClipDisabled()
        .safeAreaPadding(.horizontal, 25)
        .padding(.horizontal, -20)
        .onChange(of: scrolledLevel) { _, scrolled in
            if let scrolled, scrolled != draftLevel {
                withAnimation(.snappy) { draftLevel = scrolled }
            }
        }
    }

    private var dots: some View {
        HStack(spacing: 6) {
            ForEach(Rival.all) { rival in
                let isOn = rival.level == draftLevel
                Capsule()
                    .fill(isOn ? rival.hue : Color.secondary.opacity(0.3))
                    .frame(width: isOn ? 18 : 6, height: 6)
                    .shadow(color: isOn && theme.glows ? rival.hue.opacity(0.8) : .clear, radius: 6)
            }
        }
        .frame(maxWidth: .infinity)
        .animation(.snappy, value: draftLevel)
        .accessibilityHidden(true)
    }

    // MARK: Side

    private func sideCard(_ choice: SideChoice) -> some View {
        let isSelected = draftSide == choice
        let color: Color
        let glow: Color?
        switch choice {
        case .white:
            color = theme.whiteSide
            glow = theme.whiteGlow
        case .black:
            color = theme.blackSide
            glow = theme.blackGlow
        case .random:
            color = accent
            glow = theme.glows ? accent : nil
        }
        return Button {
            choose { draftSide = choice }
        } label: {
            VStack(spacing: 4) {
                sideArt(choice)
                    .frame(height: 46)
                Text(sideName(choice))
                    .font(.app(.caption, weight: .bold))
                    .foregroundStyle(isSelected ? color : Color.secondary)
            }
            .frame(maxWidth: .infinity)
            .frame(minHeight: 84)
            .background(card(selected: isSelected, color: color, glow: glow))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Play as \(sideName(choice))")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    @ViewBuilder
    private func sideArt(_ choice: SideChoice) -> some View {
        switch choice {
        case .white:
            PieceImage(piece: Piece(.king, color: .white, square: .e1), theme: theme, size: 44)
        case .black:
            PieceImage(piece: Piece(.king, color: .black, square: .e8), theme: theme, size: 44)
        case .random:
            ZStack {
                PieceImage(piece: Piece(.king, color: .black, square: .e8), theme: theme, size: 34)
                    .offset(x: 8, y: -4)
                PieceImage(piece: Piece(.king, color: .white, square: .e1), theme: theme, size: 34)
                    .offset(x: -8, y: 4)
            }
        }
    }

    /// White and Black, as in any chess game. Neon keeps its own colours' names.
    private func sideName(_ choice: SideChoice) -> String {
        switch choice {
        case .white: return theme.glows ? theme.whiteName : "White"
        case .black: return theme.glows ? theme.blackName : "Black"
        case .random: return "Random"
        }
    }

    private func card(selected: Bool, color: Color, glow: Color?) -> some View {
        let shape = RoundedRectangle(cornerRadius: 16, style: .continuous)
        return shape
            .fill(selected ? color.opacity(0.1) : Color.primary.opacity(theme.isDark ? 0.05 : 0.03))
            .overlay {
                shape.strokeBorder(selected ? color : Color.primary.opacity(theme.isDark ? 0.12 : 0.08),
                                   lineWidth: selected ? 1.5 : 1)
            }
            .shadow(color: selected ? (glow ?? color).opacity(theme.glows ? 0.45 : 0.25) : .clear, radius: 12)
    }
}

/// One rival in the carousel: sigil, name, rating, a line about its style, and strength bars.
private struct RivalCard: View {
    let rival: Rival
    let isSelected: Bool
    let theme: BoardTheme
    /// The name of the player's piece this rival is holding (On the line), if any.
    var holding: String? = nil

    private var holdingNote: String {
        holding.map { " Holding your \($0)." } ?? ""
    }

    var body: some View {
        HStack(spacing: 12) {
            RivalPortrait(rival: rival, size: 100, glows: theme.glows)
            VStack(alignment: .leading, spacing: 4) {
                Text(rival.name)
                    .font(.app(.title2, weight: .heavy))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                (Text(rival.level.name).foregroundStyle(rival.hue) + Text(" · Elo \(rival.elo)"))
                    .font(.app(.caption, weight: .semibold))
                    .foregroundStyle(.secondary)
                Text(rival.blurb)
                    .font(.app(.caption))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 2)
                if let holding {
                    Label("Holding \(holding)", systemImage: "lock.fill")
                        .font(.app(.caption2, weight: .bold))
                        .foregroundStyle(rival.hue)
                        .lineLimit(1)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(rival.hue.opacity(0.14), in: Capsule())
                        .padding(.top, 2)
                }
                HStack(spacing: 4) {
                    ForEach(0..<5, id: \.self) { index in
                        let lit = index < rival.strength
                        Capsule()
                            .fill(lit ? rival.hue : Color.primary.opacity(0.14))
                            .frame(width: 22, height: 5)
                            .shadow(color: lit && theme.glows ? rival.hue.opacity(0.8) : .clear, radius: 4)
                    }
                }
                .padding(.top, 6)
                .accessibilityHidden(true)
            }
            Spacer(minLength: 0)
        }
        .padding(.leading, 8)
        .padding(.trailing, 14)
        .frame(minHeight: 150)
        .background {
            let shape = RoundedRectangle(cornerRadius: 22, style: .continuous)
            shape
                .fill(theme.isDark ? AnyShapeStyle(.ultraThinMaterial) : AnyShapeStyle(Color(.secondarySystemGroupedBackground)))
                .overlay {
                    shape.strokeBorder(isSelected ? rival.hue : Color.primary.opacity(theme.isDark ? 0.12 : 0.08),
                                       lineWidth: isSelected ? 1.5 : 1)
                }
                .shadow(color: isSelected ? rival.hue.opacity(theme.glows ? 0.4 : 0.25) : .clear, radius: 16)
        }
        .contentShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .animation(.snappy, value: isSelected)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(rival.name), \(rival.level.name), \(rival.spokenElo). \(rival.blurb)\(holdingNote)")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

/// One row of the match card: an icon, what it sets, and the current choice.
private struct MatchRowButton<Icon: View>: View {
    let label: String
    let value: String
    let detail: String?
    let isOpen: Bool
    let theme: BoardTheme
    @ViewBuilder let icon: () -> Icon
    let action: () -> Void

    private var accent: Color { theme.accent ?? .accentColor }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                GlyphTile(theme: theme, content: icon)
                VStack(alignment: .leading, spacing: 2) {
                    Text(label.uppercased())
                        .font(.app(.caption2, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .tracking(1)
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text(value)
                            .font(.app(.callout, weight: .bold))
                            .foregroundStyle(.primary)
                            .contentTransition(.numericText())
                        if let detail {
                            Text(detail)
                                .font(.app(.footnote))
                                .foregroundStyle(.secondary)
                                .contentTransition(.opacity)
                        }
                    }
                    .lineLimit(1)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.down")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(isOpen ? accent : Color.secondary.opacity(0.7))
                    .rotationEffect(.degrees(isOpen ? 180 : 0))
            }
            .padding(.leading, 12)
            .padding(.trailing, 14)
            .frame(minHeight: 60)
            .background(isOpen ? Color.primary.opacity(theme.isDark ? 0.04 : 0.03) : .clear)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(label): \(value)")
        .accessibilityHint(isOpen ? "Closes the choices" : "Shows the choices")
        .accessibilityAddTraits(isOpen ? .isSelected : [])
    }
}

/// One choice inside an unfolded row, with a line about it and a check when chosen.
private struct OptionRow: View {
    let title: String
    let detail: String
    let isOn: Bool
    let theme: BoardTheme
    let action: () -> Void

    private var accent: Color { theme.accent ?? .accentColor }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 1) {
                    Text(title)
                        .font(.app(.subheadline, weight: .semibold))
                        .foregroundStyle(isOn ? Color.primary : Color.primary.opacity(0.85))
                    Text(detail)
                        .font(.app(.caption2))
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
                ZStack {
                    Circle()
                        .strokeBorder(Color.primary.opacity(0.18), lineWidth: 1.5)
                        .opacity(isOn ? 0 : 1)
                    Circle()
                        .fill(accent)
                        .shadow(color: theme.glows ? accent.opacity(0.6) : .clear, radius: 6)
                        .overlay {
                            Image(systemName: "checkmark")
                                .font(.system(size: 11, weight: .heavy))
                                .foregroundStyle(theme.isDark ? Color.black : Color.white)
                        }
                        .scaleEffect(isOn ? 1 : 0.4)
                        .opacity(isOn ? 1 : 0)
                }
                .frame(width: 22, height: 22)
            }
            .padding(.leading, 12)
            .padding(.trailing, 10)
            .padding(.vertical, 6)
            .frame(minHeight: 50)
            .background {
                let shape = RoundedRectangle(cornerRadius: 14, style: .continuous)
                shape
                    .fill(isOn ? accent.opacity(0.1) : .clear)
                    .overlay { shape.strokeBorder(isOn ? accent.opacity(0.35) : .clear, lineWidth: 1) }
                    .shadow(color: isOn && theme.glows ? accent.opacity(0.12) : .clear, radius: 10)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .animation(.snappy(duration: 0.25), value: isOn)
        .accessibilityLabel("\(title). \(detail)")
        .accessibilityAddTraits(isOn ? .isSelected : [])
    }
}

#Preview("Neon") {
    NewGameSheet(theme: .neon) { _ in }
}

#Preview("Fabergé") {
    NewGameSheet(theme: .faberge) { _ in }
}
