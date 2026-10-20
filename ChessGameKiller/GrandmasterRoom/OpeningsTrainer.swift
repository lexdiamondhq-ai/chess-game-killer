import ChessKit
import SwiftUI

/// Plays one opening line from memory: the app makes the other side's moves,
/// the player makes theirs. A slip shows the right move and must be replayed.
@MainActor
@Observable
final class OpeningDrillRunner {
    let moves: [String]
    let side: Piece.Color
    let name: String
    private(set) var board = GameModel()
    private(set) var index = 0
    private(set) var mistakes = 0
    private(set) var arrows: [BoardArrow] = []
    private(set) var message = "Your move."
    private(set) var tone: DrillRunner.Tone = .coach
    private(set) var isDone = false
    /// Learn mode shows every move with an arrow first.
    let showsMoves: Bool
    @ObservationIgnored private var pending: Task<Void, Never>?

    init(moves: [String], side: Piece.Color, name: String, showsMoves: Bool) {
        self.moves = moves
        self.side = side
        self.name = name
        self.showsMoves = showsMoves
        board.humanColors = []
    }

    func start() { advance() }
    func cancel() { pending?.cancel() }

    func tap(_ square: Square) {
        guard !isDone, board.isHumanTurn else { return }
        let before = board.moveCount
        board.tap(square)
        if board.pendingPromotion != nil { board.promote(to: .queen) }
        guard board.moveCount != before, let played = board.lastPlayed else { return }
        board.humanColors = []
        if played.uci == moves[index] {
            index += 1
            arrows = []
            tone = .success
            message = "\(played.san). Right."
            advance()
        } else {
            mistakes += 1
            tone = .wrong
            let right = Notation.san(of: moves[index], fen: played.fenBefore) ?? moves[index]
            message = "Not in this line. It's \(right)."
            pending = Task { [weak self] in
                try? await Task.sleep(for: .milliseconds(700))
                guard let self, !Task.isCancelled else { return }
                self.board.undo()
                self.showArrow()
                self.board.humanColors = [self.side]
            }
        }
    }

    private func showArrow() {
        guard index < moves.count, let squares = Notation.squares(of: moves[index]) else { return }
        arrows = [BoardArrow(from: squares.from.notation, to: squares.to.notation, color: .green, dashed: true)]
    }

    private func advance() {
        pending?.cancel()
        pending = Task { [weak self] in
            guard let self else { return }
            while self.index < self.moves.count, self.board.sideToMove != self.side {
                try? await Task.sleep(for: .milliseconds(450))
                guard !Task.isCancelled else { return }
                self.board.playEngineMove(self.moves[self.index])
                SoundPlayer.shared.play(.move)
                self.index += 1
            }
            if self.index >= self.moves.count {
                self.isDone = true
                self.arrows = []
                self.tone = self.mistakes == 0 ? .success : .hint
                self.message = self.mistakes == 0 ? "Perfect. \(self.name) is in your fingers."
                    : "Done, with \(self.mistakes) slip\(self.mistakes == 1 ? "" : "s"). It'll come back sooner."
            } else {
                if self.showsMoves { self.showArrow() }
                if self.tone != .success || self.index == 0 {
                    self.tone = .coach
                    self.message = self.showsMoves ? "Play the arrow." : "Your move."
                }
                self.board.humanColors = [self.side]
            }
        }
    }
}

/// The opening library: search every named line, build a repertoire, and review what's due.
struct OpeningsView: View {
    let theme: BoardTheme
    @Environment(RepertoireStore.self) private var repertoire
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    @State private var reviewing: [RepertoireEntry] = []

    private let content = GrandmasterContent.shared

    private var families: [(name: String, lines: [OpeningLine])] {
        let all = content.openingFamilies
        guard !query.isEmpty else { return all }
        return all.filter { $0.name.localizedCaseInsensitiveContains(query)
            || $0.lines.contains { $0.name.localizedCaseInsensitiveContains(query) || $0.eco.localizedCaseInsensitiveContains(query) } }
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    let due = repertoire.due
                    Button {
                        reviewing = due
                    } label: {
                        HStack {
                            Label(due.isEmpty ? "Nothing due. Nice." : "Review \(due.count) line\(due.count == 1 ? "" : "s")",
                                  systemImage: "arrow.triangle.2.circlepath")
                            Spacer()
                            Text("\(repertoire.entries.count) in repertoire")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .disabled(due.isEmpty)
                    if !repertoire.entries.isEmpty {
                        NavigationLink("My repertoire") {
                            RepertoireList(theme: theme)
                        }
                    }
                } footer: {
                    Text("Lines come back on a schedule: tomorrow, then in 3, 7, 16 and 35 days as you get them right.")
                }
                Section("Openings") {
                    ForEach(families, id: \.name) { family in
                        NavigationLink {
                            OpeningFamilyView(name: family.name, lines: family.lines, theme: theme)
                        } label: {
                            HStack {
                                Text(family.name)
                                Spacer()
                                Text("\(family.lines.count)")
                                    .font(.caption.monospacedDigit())
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
            .searchable(text: $query, prompt: "Sicilian, Italian, B90…")
            .navigationTitle("Openings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { Button("Done") { dismiss() } }
            }
            .scrollContentBackground(.hidden)
            .background { TrainingBackdrop(theme: theme) }
        }
        .tint(theme.trainingAccent)
        .preferredColorScheme(theme.isDark ? .dark : nil)
        .fullScreenCover(isPresented: Binding(get: { !reviewing.isEmpty }, set: { if !$0 { reviewing = [] } })) {
            RepertoireReview(entries: reviewing, theme: theme)
                .environment(repertoire)
        }
    }
}

private struct OpeningFamilyView: View {
    let name: String
    let lines: [OpeningLine]
    let theme: BoardTheme

    var body: some View {
        List(lines) { line in
            NavigationLink {
                OpeningLineView(line: line, theme: theme)
            } label: {
                VStack(alignment: .leading, spacing: 3) {
                    Text(line.variation)
                    Text("\(line.eco) · " + Notation.numbered(Notation.sanLine(of: line.moves, fen: Position.standard.fen,
                                                                                 limit: 8), blackFirst: false))
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
        }
        .navigationTitle(name)
        .scrollContentBackground(.hidden)
        .background { TrainingBackdrop(theme: theme) }
    }
}

/// One line: watch it, practice it, add it to the repertoire.
private struct OpeningLineView: View {
    let line: OpeningLine
    let theme: BoardTheme
    @Environment(RepertoireStore.self) private var repertoire
    @State private var side: Piece.Color = .white
    @State private var runner: OpeningDrillRunner?

    var body: some View {
        GeometryReader { geo in
            let boardSide = max(200, min(geo.size.width - 24, geo.size.height * 0.56))
            VStack(spacing: 12) {
                Picker("Play as", selection: $side) {
                    Text("Play as White").tag(Piece.Color.white)
                    Text("Play as Black").tag(Piece.Color.black)
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, 16)
                if let runner {
                    TrainingBoardView(game: runner.board, theme: theme, flipped: side == .black, arrows: runner.arrows,
                                      onTap: { (square: Square) in runner.tap(square) })
                        .frame(width: boardSide, height: boardSide)
                    RoomMessage(text: runner.message, tone: runner.tone, theme: theme)
                        .padding(.horizontal, 16)
                }
                HStack(spacing: 10) {
                    Button {
                        restart(learn: true)
                    } label: {
                        Label("Learn", systemImage: "play.fill")
                    }
                    .buttonStyle(TrainingButtonStyle(theme: theme, prominent: false))
                    Button {
                        restart(learn: false)
                    } label: {
                        Label("Test me", systemImage: "brain.head.profile")
                    }
                    .buttonStyle(TrainingButtonStyle(theme: theme, prominent: false))
                    Button {
                        repertoire.add(line, side: side)
                    } label: {
                        Label(repertoire.contains(line, side: side) ? "Added" : "Add",
                              systemImage: repertoire.contains(line, side: side) ? "checkmark" : "plus")
                    }
                    .buttonStyle(TrainingButtonStyle(theme: theme))
                    .disabled(repertoire.contains(line, side: side))
                }
                .padding(.horizontal, 16)
                Spacer(minLength: 0)
            }
            .frame(width: geo.size.width)
        }
        .navigationTitle(line.variation)
        .navigationBarTitleDisplayMode(.inline)
        .background { TrainingBackdrop(theme: theme) }
        .onAppear {
            if runner == nil {
                side = line.naturalSide
                restart(learn: true)
            }
        }
        .onChange(of: side) { _, _ in restart(learn: true) }
        .onDisappear { runner?.cancel() }
    }

    private func restart(learn: Bool) {
        runner?.cancel()
        let made = OpeningDrillRunner(moves: line.moves, side: side, name: line.name, showsMoves: learn)
        runner = made
        made.start()
    }
}

private struct RepertoireList: View {
    let theme: BoardTheme
    @Environment(RepertoireStore.self) private var repertoire

    var body: some View {
        List {
            ForEach(repertoire.entries.sorted { $0.due < $1.due }) { entry in
                VStack(alignment: .leading, spacing: 3) {
                    Text(entry.name)
                    Text("\(entry.color == .white ? "White" : "Black") · next \(entry.due.formatted(.relative(presentation: .named)))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .swipeActions {
                    Button(role: .destructive) { repertoire.remove(entry) } label: { Label("Remove", systemImage: "trash") }
                }
            }
        }
        .navigationTitle("My repertoire")
        .scrollContentBackground(.hidden)
        .background { TrainingBackdrop(theme: theme) }
    }
}

/// Goes through the due lines one after another.
private struct RepertoireReview: View {
    let entries: [RepertoireEntry]
    let theme: BoardTheme
    @Environment(RepertoireStore.self) private var repertoire
    @Environment(\.dismiss) private var dismiss
    @State private var position = 0
    @State private var runner: OpeningDrillRunner?
    @State private var recorded = false

    var body: some View {
        GeometryReader { geo in
            let side = max(200, min(geo.size.width - 24, geo.size.height * 0.58))
            VStack(spacing: 12) {
                RoomHeader(title: entries.isEmpty ? "Review" : entries[safeIndex].name, subtitle: "Line \(position + 1) of \(entries.count)") { dismiss() }
                if let runner {
                    TrainingBoardView(game: runner.board, theme: theme, flipped: runner.side == .black, arrows: runner.arrows,
                                      onTap: { (square: Square) in runner.tap(square) })
                        .frame(width: side, height: side)
                    RoomMessage(text: runner.message, tone: runner.tone, theme: theme)
                        .padding(.horizontal, 16)
                    if runner.isDone {
                        Button(position + 1 < entries.count ? "Next line" : "Done") {
                            if position + 1 < entries.count {
                                position += 1
                                load()
                            } else {
                                dismiss()
                            }
                        }
                        .buttonStyle(TrainingButtonStyle(theme: theme))
                        .padding(.horizontal, 16)
                    }
                }
                Spacer(minLength: 0)
            }
            .frame(width: geo.size.width)
        }
        .background { TrainingBackdrop(theme: theme) }
        .onAppear { if runner == nil { load() } }
        .onChange(of: runner?.isDone) { _, done in
            guard done == true, !recorded, let runner, !entries.isEmpty else { return }
            recorded = true
            repertoire.reviewed(entries[safeIndex], clean: runner.mistakes == 0)
        }
        .onDisappear { runner?.cancel() }
    }

    private var safeIndex: Int { min(position, max(0, entries.count - 1)) }

    private func load() {
        runner?.cancel()
        recorded = false
        guard !entries.isEmpty else { return }
        let entry = entries[safeIndex]
        let made = OpeningDrillRunner(moves: entry.moves, side: entry.color, name: entry.name, showsMoves: false)
        runner = made
        made.start()
    }
}
