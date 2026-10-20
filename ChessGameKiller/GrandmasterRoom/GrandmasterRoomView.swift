import ChessKit
import SwiftUI

/// The Grandmaster Room: training for strong players. Guess the Move through
/// famous games, calculation and blindfold drills, endgames against perfect
/// play, and an opening repertoire on a review schedule.
struct GrandmasterRoomView: View {
    let theme: BoardTheme
    @Environment(PuzzleStore.self) private var puzzles
    @Environment(\.dismiss) private var dismiss
    @State private var repertoire = RepertoireStore.live()
    @State private var game: ClassicGame?
    @State private var endgame: EndgameStudy?
    @State private var showingCalculation = false
    @State private var showingOpenings = false

    private let content = GrandmasterContent.shared

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    intro
                    section("Guess the Move", symbol: "person.fill.questionmark",
                            text: "Sit in a grandmaster's chair. Guess every move of a famous game and get scored against the master.") {
                        ForEach(content.games) { game in
                            row(title: game.title, detail: "\(game.event) \(String(game.year)) · as \(game.hero == .white ? "White" : "Black")") {
                                self.game = game
                            }
                        }
                    }
                    section("Calculation", symbol: "brain.head.profile",
                            text: "Moves are read out but the pieces stay still. Play them in your head, then find the winner. Blindfold hides the pieces too.") {
                        row(title: "Start calculating", detail: "Short, medium or long lines, with or without the pieces") {
                            showingCalculation = true
                        }
                    }
                    section("Perfect Endgames", symbol: "flag.checkered.2.crossed",
                            text: "Win or hold the draw against an opponent who never errs, judged move by move by the Lichess tablebase.") {
                        ForEach(content.endgames) { study in
                            row(title: study.title, detail: String(repeating: "●", count: study.level)
                                + String(repeating: "○", count: 3 - study.level)) {
                                endgame = study
                            }
                        }
                    }
                    section("Openings", symbol: "books.vertical.fill",
                            text: "Every named opening, \(content.openings.count) lines. Build your repertoire and it comes back for review just before you'd forget it.") {
                        row(title: "Open the library",
                            detail: repertoire.due.isEmpty ? "\(repertoire.entries.count) lines in your repertoire"
                                : "\(repertoire.due.count) due for review") {
                            showingOpenings = true
                        }
                    }
                }
                .padding(16)
            }
            .background { TrainingBackdrop(theme: theme) }
            .navigationTitle("Grandmaster Room")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { Button("Done") { dismiss() } }
            }
        }
        .tint(theme.trainingAccent)
        .preferredColorScheme(theme.isDark ? .dark : nil)
        .fullScreenCover(item: $game) { game in
            GuessTheMoveView(game: game, theme: theme)
        }
        .fullScreenCover(item: $endgame) { study in
            EndgameView(study: study, theme: theme)
        }
        .fullScreenCover(isPresented: $showingCalculation) {
            CalculationView(theme: theme).environment(puzzles)
        }
        .fullScreenCover(isPresented: $showingOpenings) {
            OpeningsView(theme: theme).environment(repertoire)
        }
    }

    private var intro: some View {
        HStack(spacing: 14) {
            Image(systemName: "crown.fill")
                .font(.system(size: 30, weight: .semibold))
                .foregroundStyle(theme.trainingAccent)
                .shadow(color: theme.glows ? theme.trainingAccent.opacity(0.7) : .clear, radius: 12)
            Text("How grandmasters train: study the classics, calculate without moving pieces, know the endgames cold, and own your openings.")
                .font(.system(.subheadline, design: .themed))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func section<Rows: View>(_ title: String, symbol: String, text: String,
                                     @ViewBuilder rows: () -> Rows) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(title, systemImage: symbol)
                .font(.system(.title3, design: .themed).weight(.bold))
            Text(text)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            VStack(spacing: 0) { rows() }
                .trainingCard(theme, cornerRadius: 16)
        }
    }

    private func row(title: String, detail: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.system(.subheadline, design: .themed).weight(.semibold))
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                    Text(detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer(minLength: 8)
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 11)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
