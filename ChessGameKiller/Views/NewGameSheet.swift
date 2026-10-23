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

/// How much the coach says during a game. Two switches, shown as one choice.
enum CoachMode: CaseIterable, Identifiable {
    case full, hints, verdicts, silent

    var id: Self { self }

    var name: String {
        switch self {
        case .full: return "Full coach"
        case .hints: return "Hints only"
        case .verdicts: return "Verdicts only"
        case .silent: return "Silent"
        }
    }

    /// One line about the mode. How many hints it promises follows the
    /// second-best setting, so the text matches what the game marks.
    func detail(twoHints: Bool) -> String {
        switch self {
        case .full: return twoHints ? "Grades every move and marks your two best moves" : "Grades every move and marks your best move"
        case .hints: return twoHints ? "Marks your two best moves, no grades" : "Marks your best move, no grades"
        case .verdicts: return "Grades your moves, no hints. A fair test."
        case .silent: return "Just chess. The coach keeps quiet."
        }
    }

    /// A couple of words for the match card, next to the name.
    var short: String {
        switch self {
        case .full: return "hints + grades"
        case .hints: return "no grades"
        case .verdicts: return "no hints"
        case .silent: return "just chess"
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
/// folds it back up.
struct NewGameSheet: View {
    /// The rows of the match card.
    private enum MatchRow {
        case side, clock, coach
    }

    let theme: BoardTheme
    let start: (MatchController.Setup) -> Void
    /// Opens Challenge a friend instead. Nil hides the row.
    var challenge: (() -> Void)? = nil

    @AppStorage("setup.side") private var side: SideChoice = .white
    @AppStorage("setup.level") private var level: MatchController.Level = .club
    @AppStorage("setup.clock") private var timeControl: TimeControl = .unlimited
    @AppStorage("showBestMoves") private var showBestMoves = false
    @AppStorage("coachVerdicts") private var showVerdicts = true
    @AppStorage("showSecondBest") private var showSecondBest = true

    @AppStorage("haptics") private var hapticsOn = true

    @State private var scrolledLevel: MatchController.Level?
    @State private var openRow: MatchRow?
    /// The coach as it was when the sheet opened, so Cancel can put it back.
    @State private var coachOnOpen: CoachMode?
    @Environment(\.dismiss) private var dismiss

    /// The choices from last time, for when the sheet is closed without starting.
    static func savedSetup(_ defaults: UserDefaults = .standard) -> MatchController.Setup {
        let side = defaults.string(forKey: "setup.side").flatMap { SideChoice(rawValue: $0) } ?? .white
        let level = (defaults.object(forKey: "setup.level") as? Int).flatMap { MatchController.Level(rawValue: $0) } ?? .club
        let clock = defaults.string(forKey: "setup.clock").flatMap { TimeControl(rawValue: $0) } ?? TimeControl.unlimited
        return MatchController.Setup(playerColor: side.color, level: level, timeControl: clock)
    }

    private var accent: Color { theme.accent ?? .accentColor }
    private var coachMode: CoachMode { CoachMode(hints: showBestMoves, verdicts: showVerdicts) }

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
                        if openRow == nil {
                            Text("Tap a row to change it")
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                                .frame(maxWidth: .infinity)
                                .transition(.opacity)
                        }
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
                    start(MatchController.Setup(playerColor: side.color, level: level, timeControl: timeControl))
                } label: {
                    Label("Play \(level.rival.name)", systemImage: "play.fill")
                        .font(.headline)
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
                .animation(.snappy, value: level)
            }
            .navigationTitle("New Game")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        // The coach keys reach the running game at once, so a
                        // choice that was only tried out goes back on Cancel.
                        if let coachOnOpen, coachOnOpen != coachMode {
                            showBestMoves = coachOnOpen.showsHints
                            showVerdicts = coachOnOpen.showsVerdicts
                        }
                        dismiss()
                    }
                }
            }
        }
        .presentationDetents([.large])
        .presentationBackground {
            ThemeBackdrop(theme: theme)
        }
        .tint(accent)
        .preferredColorScheme(theme.isDark ? .dark : nil)
        .onAppear {
            scrolledLevel = level
            coachOnOpen = coachMode
        }
    }

    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title.uppercased())
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .tracking(1)
            content()
        }
    }

    // MARK: The match card

    private var matchCard: some View {
        VStack(spacing: 0) {
            MatchRowButton(label: "Play as", value: sideName(side), detail: nil, isOpen: openRow == .side,
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

            MatchRowButton(label: "Clock", value: timeControl.name, detail: timeControl.kind, isOpen: openRow == .clock,
                           theme: theme, icon: { Image(systemName: "stopwatch") }) {
                toggle(.clock)
            }
            if openRow == .clock {
                optionList {
                    ForEach(TimeControl.allCases) { control in
                        OptionRow(title: control.name, detail: control.detail, isOn: timeControl == control, theme: theme) {
                            choose { timeControl = control }
                        }
                    }
                }
            }
            rowDivider

            MatchRowButton(label: "Coach", value: coachMode.name, detail: coachMode.short, isOpen: openRow == .coach,
                           theme: theme, icon: { Image(systemName: "graduationcap.fill") }) {
                toggle(.coach)
            }
            if openRow == .coach {
                optionList {
                    ForEach(CoachMode.allCases) { mode in
                        OptionRow(title: mode.name, detail: mode.detail(twoHints: showSecondBest), isOn: coachMode == mode, theme: theme) {
                            choose {
                                showBestMoves = mode.showsHints
                                showVerdicts = mode.showsVerdicts
                            }
                        }
                    }
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
        switch side {
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

    // MARK: Rivals

    private var rivalCarousel: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            LazyHStack(spacing: 12) {
                ForEach(Rival.all) { rival in
                    RivalCard(rival: rival, isSelected: level == rival.level, theme: theme)
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
            if let scrolled, scrolled != level {
                withAnimation(.snappy) { level = scrolled }
            }
        }
    }

    private var dots: some View {
        HStack(spacing: 6) {
            ForEach(Rival.all) { rival in
                let isOn = rival.level == level
                Capsule()
                    .fill(isOn ? rival.hue : Color.secondary.opacity(0.3))
                    .frame(width: isOn ? 18 : 6, height: 6)
                    .shadow(color: isOn && theme.glows ? rival.hue.opacity(0.8) : .clear, radius: 6)
            }
        }
        .frame(maxWidth: .infinity)
        .animation(.snappy, value: level)
        .accessibilityHidden(true)
    }

    // MARK: Side

    private func sideCard(_ choice: SideChoice) -> some View {
        let isSelected = side == choice
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
            choose { side = choice }
        } label: {
            VStack(spacing: 4) {
                sideArt(choice)
                    .frame(height: 46)
                Text(sideName(choice))
                    .font(.caption.weight(.bold))
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

    private func sideName(_ choice: SideChoice) -> String {
        switch choice {
        case .white: return theme.whiteName
        case .black: return theme.blackName
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

    var body: some View {
        HStack(spacing: 12) {
            RivalPortrait(rival: rival, size: 100, glows: theme.glows)
            VStack(alignment: .leading, spacing: 4) {
                Text(rival.name)
                    .font(.system(.title2, design: .themed).weight(.heavy))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                (Text(rival.level.name).foregroundStyle(rival.hue) + Text(" · Elo \(rival.elo)"))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Text(rival.blurb)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 2)
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
        .accessibilityLabel("\(rival.name), \(rival.level.name), Elo \(rival.elo). \(rival.blurb)")
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
                icon()
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(accent)
                    .frame(width: 34, height: 34)
                    .background(accent.opacity(0.12), in: RoundedRectangle(cornerRadius: 11, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 11, style: .continuous)
                            .strokeBorder(accent.opacity(0.18), lineWidth: 1)
                    }
                VStack(alignment: .leading, spacing: 2) {
                    Text(label.uppercased())
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .tracking(1)
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text(value)
                            .font(.system(.callout, design: .themed).weight(.bold))
                            .foregroundStyle(.primary)
                            .contentTransition(.numericText())
                        if let detail {
                            Text(detail)
                                .font(.footnote)
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
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(isOn ? Color.primary : Color.primary.opacity(0.85))
                    Text(detail)
                        .font(.caption2)
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
