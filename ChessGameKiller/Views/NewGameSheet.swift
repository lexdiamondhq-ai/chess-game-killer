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

/// Picks the opponent, the side and the computer's level, then starts the game.
struct NewGameSheet: View {
    let theme: BoardTheme
    let start: (MatchController.Setup) -> Void

    @AppStorage("setup.opponent") private var opponent: MatchController.Opponent = .computer
    @AppStorage("setup.side") private var side: SideChoice = .white
    @AppStorage("setup.level") private var level: MatchController.Level = .club

    /// The choices from last time, for when the sheet is closed without starting.
    static func savedSetup(_ defaults: UserDefaults = .standard) -> MatchController.Setup {
        let opponent = defaults.string(forKey: "setup.opponent").flatMap { MatchController.Opponent(rawValue: $0) } ?? .computer
        let side = defaults.string(forKey: "setup.side").flatMap { SideChoice(rawValue: $0) } ?? .white
        let level = (defaults.object(forKey: "setup.level") as? Int).flatMap { MatchController.Level(rawValue: $0) } ?? .club
        return MatchController.Setup(opponent: opponent, playerColor: side.color, level: level)
    }

    private var accent: Color { theme.accent ?? .accentColor }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 26) {
                    section("Opponent") {
                        Picker("Opponent", selection: $opponent) {
                            ForEach(MatchController.Opponent.allCases) { opponent in
                                Label(opponent.title, systemImage: opponent.symbol).tag(opponent)
                            }
                        }
                        .pickerStyle(.segmented)
                    }

                    if opponent == .computer {
                        section("Play as") {
                            HStack(spacing: 12) {
                                ForEach(SideChoice.allCases) { choice in
                                    sideButton(choice)
                                }
                            }
                        }
                        section("Level") {
                            VStack(spacing: 8) {
                                ForEach(MatchController.Level.allCases) { option in
                                    levelRow(option)
                                }
                            }
                        }
                    } else {
                        Label("Pass the phone back and forth. The coach grades both of you.",
                              systemImage: "person.2.fill")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(20)
                .animation(.snappy, value: opponent)
            }
            .safeAreaInset(edge: .bottom) {
                Button {
                    start(MatchController.Setup(opponent: opponent, playerColor: side.color, level: level))
                } label: {
                    Text("Start Game")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .tint(accent)
                .foregroundStyle(theme.isDark ? Color.black : Color.white)
                .padding(.horizontal, 20)
                .padding(.bottom, 8)
                .shadow(color: theme.isDark ? accent.opacity(0.6) : .clear, radius: 12)
            }
            .navigationTitle("New Game")
            .navigationBarTitleDisplayMode(.inline)
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

    // MARK: Side

    private func sideButton(_ choice: SideChoice) -> some View {
        let isSelected = side == choice
        return Button {
            withAnimation(.snappy) { side = choice }
        } label: {
            VStack(spacing: 8) {
                sideArt(choice)
                    .frame(height: 56)
                Text(sideName(choice))
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(isSelected ? Color.primary : Color.secondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(card(selected: isSelected))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Play as \(sideName(choice))")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    @ViewBuilder
    private func sideArt(_ choice: SideChoice) -> some View {
        switch choice {
        case .white:
            PieceImage(piece: Piece(.king, color: .white, square: .e1), theme: theme, size: 56)
        case .black:
            PieceImage(piece: Piece(.king, color: .black, square: .e8), theme: theme, size: 56)
        case .random:
            ZStack {
                PieceImage(piece: Piece(.king, color: .black, square: .e8), theme: theme, size: 44)
                    .offset(x: 9, y: -4)
                PieceImage(piece: Piece(.king, color: .white, square: .e1), theme: theme, size: 44)
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

    // MARK: Level

    private func levelRow(_ option: MatchController.Level) -> some View {
        let isSelected = level == option
        return Button {
            withAnimation(.snappy) { level = option }
        } label: {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(option.name).font(.body.weight(.semibold))
                    Text(option.blurb).font(.footnote).foregroundStyle(.secondary)
                }
                Spacer()
                HStack(spacing: 4) {
                    ForEach(0..<5, id: \.self) { i in
                        Circle()
                            .fill(i <= option.rawValue ? accent : Color.secondary.opacity(0.25))
                            .frame(width: 7, height: 7)
                    }
                }
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(isSelected ? accent : Color.secondary.opacity(0.5))
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(card(selected: isSelected))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private func card(selected: Bool) -> some View {
        let shape = RoundedRectangle(cornerRadius: 16, style: .continuous)
        return shape
            .fill(theme.isDark ? AnyShapeStyle(.ultraThinMaterial) : AnyShapeStyle(Color(.secondarySystemGroupedBackground)))
            .overlay {
                shape.strokeBorder(selected ? accent : Color.secondary.opacity(theme.isDark ? 0.25 : 0.15),
                                   lineWidth: selected ? 2 : 1)
            }
            .shadow(color: selected && theme.isDark ? accent.opacity(0.45) : .clear, radius: 10)
    }
}
