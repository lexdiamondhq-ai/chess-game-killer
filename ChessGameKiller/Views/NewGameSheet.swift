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
    case full, arrows, verdicts, silent

    var id: Self { self }

    var name: String {
        switch self {
        case .full: return "Full coach"
        case .arrows: return "Arrows only"
        case .verdicts: return "Verdicts only"
        case .silent: return "Silent"
        }
    }

    var detail: String {
        switch self {
        case .full: return "Grades every move and shows the two best moves"
        case .arrows: return "Shows the two best moves, no grades"
        case .verdicts: return "Grades your moves, no arrows. A fair test."
        case .silent: return "Just chess. The coach keeps quiet."
        }
    }

    var showsArrows: Bool { self == .full || self == .arrows }
    var showsVerdicts: Bool { self == .full || self == .verdicts }

    init(arrows: Bool, verdicts: Bool) {
        switch (arrows, verdicts) {
        case (true, true): self = .full
        case (true, false): self = .arrows
        case (false, true): self = .verdicts
        case (false, false): self = .silent
        }
    }
}

/// Picks the opponent, the rival, the side, the clock and the coach, then starts the game.
struct NewGameSheet: View {
    let theme: BoardTheme
    let start: (MatchController.Setup) -> Void

    @AppStorage("setup.opponent") private var opponent: MatchController.Opponent = .computer
    @AppStorage("setup.side") private var side: SideChoice = .white
    @AppStorage("setup.level") private var level: MatchController.Level = .club
    @AppStorage("setup.clock") private var timeControl: TimeControl = .unlimited
    @AppStorage("showBestMoves") private var showBestMoves = true
    @AppStorage("coachVerdicts") private var showVerdicts = true

    @State private var scrolledLevel: MatchController.Level?
    @Environment(\.dismiss) private var dismiss

    /// The choices from last time, for when the sheet is closed without starting.
    static func savedSetup(_ defaults: UserDefaults = .standard) -> MatchController.Setup {
        let opponent = defaults.string(forKey: "setup.opponent").flatMap { MatchController.Opponent(rawValue: $0) } ?? .computer
        let side = defaults.string(forKey: "setup.side").flatMap { SideChoice(rawValue: $0) } ?? .white
        let level = (defaults.object(forKey: "setup.level") as? Int).flatMap { MatchController.Level(rawValue: $0) } ?? .club
        let clock = defaults.string(forKey: "setup.clock").flatMap { TimeControl(rawValue: $0) } ?? TimeControl.unlimited
        return MatchController.Setup(opponent: opponent, playerColor: side.color, level: level, timeControl: clock)
    }

    private var accent: Color { theme.accent ?? .accentColor }
    private var coachMode: CoachMode { CoachMode(arrows: showBestMoves, verdicts: showVerdicts) }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    section("Opponent") {
                        Picker("Opponent", selection: $opponent) {
                            ForEach(MatchController.Opponent.allCases) { opponent in
                                Label(opponent.title, systemImage: opponent.symbol).tag(opponent)
                            }
                        }
                        .pickerStyle(.segmented)
                    }

                    if opponent == .computer {
                        section("Your rival") {
                            rivalCarousel
                            dots
                        }
                        section("Play as") {
                            HStack(spacing: 10) {
                                ForEach(SideChoice.allCases) { choice in
                                    sideCard(choice)
                                }
                            }
                        }
                    } else {
                        Label("Pass the phone back and forth. The coach grades both of you.",
                              systemImage: "person.2.fill")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }

                    section("Clock") {
                        chipRow {
                            ForEach(TimeControl.allCases) { control in
                                Chip(title: control.name, isOn: timeControl == control, theme: theme) {
                                    withAnimation(.snappy) { timeControl = control }
                                }
                            }
                        }
                        note(timeControl.detail)
                    }

                    section("Coach") {
                        chipRow {
                            ForEach(CoachMode.allCases) { mode in
                                Chip(title: mode.name, isOn: coachMode == mode, theme: theme) {
                                    withAnimation(.snappy) {
                                        showBestMoves = mode.showsArrows
                                        showVerdicts = mode.showsVerdicts
                                    }
                                }
                            }
                        }
                        note(coachMode.detail)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 12)
                .padding(.bottom, 24)
                .animation(.snappy, value: opponent)
            }
            .safeAreaInset(edge: .bottom) {
                Button {
                    start(MatchController.Setup(opponent: opponent, playerColor: side.color, level: level, timeControl: timeControl))
                } label: {
                    Label(opponent == .computer ? "Play \(level.rival.name)" : "Start Game", systemImage: "play.fill")
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
                .shadow(color: theme.isDark ? accent.opacity(0.6) : .clear, radius: 14)
                .animation(.snappy, value: level)
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
            if theme.isDark {
                NeonBackdrop()
            } else {
                Color(.systemGroupedBackground)
            }
        }
        .tint(accent)
        .preferredColorScheme(theme.isDark ? .dark : nil)
        .onAppear { scrolledLevel = level }
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

    private func note(_ text: String) -> some View {
        Text(text)
            .font(.footnote)
            .foregroundStyle(.secondary)
            .contentTransition(.opacity)
    }

    private func chipRow<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) { content() }
                .padding(.horizontal, 20)
        }
        .padding(.horizontal, -20)
        .scrollClipDisabled()
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
                    .shadow(color: isOn && theme.isDark ? rival.hue.opacity(0.8) : .clear, radius: 6)
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
            glow = theme.isDark ? accent : nil
        }
        return Button {
            withAnimation(.snappy) { side = choice }
        } label: {
            VStack(spacing: 6) {
                sideArt(choice)
                    .frame(height: 52)
                Text(sideName(choice))
                    .font(.footnote.weight(.bold))
                    .foregroundStyle(isSelected ? color : Color.secondary)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 92)
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
            PieceImage(piece: Piece(.king, color: .white, square: .e1), theme: theme, size: 52)
        case .black:
            PieceImage(piece: Piece(.king, color: .black, square: .e8), theme: theme, size: 52)
        case .random:
            ZStack {
                PieceImage(piece: Piece(.king, color: .black, square: .e8), theme: theme, size: 40)
                    .offset(x: 9, y: -4)
                PieceImage(piece: Piece(.king, color: .white, square: .e1), theme: theme, size: 40)
                    .offset(x: -9, y: 4)
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
        let shape = RoundedRectangle(cornerRadius: 18, style: .continuous)
        return shape
            .fill(theme.isDark ? AnyShapeStyle(.ultraThinMaterial) : AnyShapeStyle(Color(.secondarySystemGroupedBackground)))
            .overlay {
                shape.strokeBorder(selected ? color : Color.primary.opacity(theme.isDark ? 0.12 : 0.08),
                                   lineWidth: selected ? 1.5 : 1)
            }
            .shadow(color: selected ? (glow ?? color).opacity(theme.isDark ? 0.45 : 0.25) : .clear, radius: 12)
    }
}

/// One rival in the carousel: sigil, name, rating, a line about its style, and strength bars.
private struct RivalCard: View {
    let rival: Rival
    let isSelected: Bool
    let theme: BoardTheme

    var body: some View {
        HStack(spacing: 12) {
            RivalPortrait(rival: rival, size: 100, glows: theme.isDark)
            VStack(alignment: .leading, spacing: 4) {
                Text(rival.name)
                    .font(.system(.title2, design: .rounded).weight(.heavy))
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
                            .shadow(color: lit && theme.isDark ? rival.hue.opacity(0.8) : .clear, radius: 4)
                    }
                }
                .padding(.top, 6)
                .accessibilityHidden(true)
            }
            Spacer(minLength: 0)
        }
        .padding(.leading, 8)
        .padding(.trailing, 14)
        .frame(height: 150)
        .background {
            let shape = RoundedRectangle(cornerRadius: 22, style: .continuous)
            shape
                .fill(theme.isDark ? AnyShapeStyle(.ultraThinMaterial) : AnyShapeStyle(Color(.secondarySystemGroupedBackground)))
                .overlay {
                    shape.strokeBorder(isSelected ? rival.hue : Color.primary.opacity(theme.isDark ? 0.12 : 0.08),
                                       lineWidth: isSelected ? 1.5 : 1)
                }
                .shadow(color: isSelected ? rival.hue.opacity(theme.isDark ? 0.4 : 0.25) : .clear, radius: 16)
        }
        .contentShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .animation(.snappy, value: isSelected)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(rival.name), \(rival.level.name), Elo \(rival.elo). \(rival.blurb)")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

/// A pill that is filled in when chosen.
private struct Chip: View {
    let title: String
    let isOn: Bool
    let theme: BoardTheme
    let action: () -> Void

    private var accent: Color { theme.accent ?? .accentColor }

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .padding(.horizontal, 14)
                .frame(height: 36)
                .foregroundStyle(isOn ? (theme.isDark ? Color.black : Color.white) : Color.primary.opacity(0.75))
                .background {
                    Capsule().fill(isOn ? AnyShapeStyle(accent) : AnyShapeStyle(Color.primary.opacity(theme.isDark ? 0.07 : 0.05)))
                }
                .overlay {
                    Capsule().strokeBorder(isOn ? Color.clear : Color.primary.opacity(0.1), lineWidth: 1)
                }
                .shadow(color: isOn && theme.isDark ? accent.opacity(0.45) : .clear, radius: 10)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isOn ? .isSelected : [])
    }
}

#Preview("Neon") {
    NewGameSheet(theme: .neon) { _ in }
}

#Preview("Walnut") {
    NewGameSheet(theme: .walnut) { _ in }
}
