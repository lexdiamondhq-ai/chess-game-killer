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
    /// The coach's spoken reactions: "Try again" on a slip, a cheer for a line played from memory.
    @ObservationIgnored var reactions: Reacting?

    init(moves: [String], side: Piece.Color, name: String, showsMoves: Bool) {
        self.moves = moves
        self.side = side
        self.name = name
        self.showsMoves = showsMoves
        reactions = CoachReactions.shared
        board.humanColors = []
    }

    func start() { advance() }
    func cancel() { pending?.cancel() }

    /// The line's next move, or nil once it's played out.
    var nextMove: String? { index < moves.count ? moves[index] : nil }

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
            if mistakes == 1 { reactions?.react(.tryAgain, strict: false) }
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
                // Following the arrows is no feat; playing the whole line from memory is.
                if !self.showsMoves {
                    self.reactions?.react(self.mistakes == 0 ? .nice : .afterHelp, strict: false)
                }
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

/// Behind the Openings door: the player's repertoire with what's due, a short list of
/// the openings most players start with, and every named line a tap or a search away.
struct OpeningsView: View {
    let theme: BoardTheme
    @Environment(RepertoireStore.self) private var repertoire
    @Environment(TrainingStore.self) private var training: TrainingStore?
    @State private var query = ""
    @State private var reviewing: [RepertoireEntry] = []
    @State private var offer: PremiumFeature?

    private var allOpen: Bool { Premium.shared.opens(.allOpenings) }

    /// Grouped once: there are thousands of lines.
    static let families = GrandmasterContent.shared.openingFamilies

    /// Where most players start: a few for White, and Black's main answers. Each holds every
    /// line filed under it, so the Queen's Gambit has its Declined and Accepted lines too and
    /// the London System its accelerated ones.
    static let popular: [(name: String, lines: [OpeningLine])] = {
        let all = GrandmasterContent.shared.openings
        func lines(_ belongs: (OpeningLine) -> Bool) -> [OpeningLine] {
            all.filter(belongs).sorted { ($0.moves.count, $0.name) < ($1.moves.count, $1.name) }
        }
        func family(_ name: String) -> (name: String, lines: [OpeningLine]) {
            (name, lines { $0.family == name })
        }
        let shelf: [(name: String, lines: [OpeningLine])] = [
            family("Italian Game"),
            family("Ruy Lopez"),
            ("Queen's Gambit", lines { $0.family.hasPrefix("Queen's Gambit") }),
            ("London System", lines { $0.name.contains("London System") && !$0.name.contains("Defensive") }),
            family("English Opening"),
            family("Sicilian Defense"),
            family("French Defense"),
            family("Caro-Kann Defense"),
            family("Queen's Gambit Declined"),
            ("Slav Defense", lines { $0.family == "Slav Defense" || $0.family.hasPrefix("Semi-Slav Defense") }),
            family("King's Indian Defense"),
            family("Scandinavian Defense"),
        ]
        return shelf.filter { !$0.lines.isEmpty }
    }()

    private var matches: [(name: String, lines: [OpeningLine])] {
        Self.families.filter { family in
            family.name.localizedCaseInsensitiveContains(query)
                || family.lines.contains { $0.name.localizedCaseInsensitiveContains(query) || $0.eco.localizedCaseInsensitiveContains(query) }
        }
    }

    var body: some View {
        TrainScreen(theme: theme, title: "Openings",
                    intro: query.isEmpty ? "Pick a few lines you like and learn them. \(Coach.current.name) brings each one back just before you'd forget it." : nil) {
            if query.isEmpty {
                repertoireCard
                TrainSectionTitle(text: "Where most players start")
                familyList(Self.popular)
                everyOpening
                    .padding(.top, 8)
            } else if !allOpen {
                PremiumLimitCard(feature: .allOpenings, accent: theme.trainingAccent)
                    .padding(.top, 20)
            } else if matches.isEmpty {
                Text("No opening matches \u{201C}\(query)\u{201D}.")
                    .font(.system(.subheadline, design: .themed))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
                    .padding(.top, 30)
            } else {
                familyList(Array(matches.prefix(40)))
            }
        }
        .searchable(text: $query, prompt: "Sicilian, Italian, B90…")
        .fullScreenCover(isPresented: Binding(get: { !reviewing.isEmpty }, set: { if !$0 { reviewing = [] } })) {
            RepertoireReview(entries: reviewing, theme: theme)
                .environment(repertoire)
                .environment(training)
        }
        .premiumOffer($offer)
    }

    @ViewBuilder
    private var everyOpening: some View {
        let row = TrainRow(symbol: "books.vertical.fill", title: "Every opening",
                           detail: "All \(GrandmasterContent.shared.openings.count) named lines, A to Z, with their ECO codes.",
                           value: allOpen ? nil : "Premium", theme: theme)
        if allOpen {
            NavigationLink {
                AllOpeningsView(theme: theme)
            } label: {
                row
            }
            .buttonStyle(.plain)
        } else {
            Button { offer = .allOpenings } label: { row }
                .buttonStyle(.plain)
        }
    }

    /// The repertoire: what's due today, or how to start one.
    private var repertoireCard: some View {
        let due = repertoire.due
        let count = repertoire.entries.count
        return VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text("YOUR REPERTOIRE")
                    .font(.system(.caption, design: .themed).weight(.bold))
                    .tracking(1)
                    .foregroundStyle(theme.trainingAccent)
                Spacer()
                if count > 0 {
                    Text(count == 1 ? "1 line" : "\(count) lines")
                        .font(.system(.footnote, design: .themed).weight(.semibold).monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            }
            Text(count == 0 ? "Start your repertoire"
                 : due.isEmpty ? "Nothing due today" : (due.count == 1 ? "1 line to review" : "\(due.count) lines to review"))
                .font(.system(.title3, design: .themed).weight(.bold))
            Text(count == 0
                 ? "Open an opening below, pick a line and tap Add. Reviews come back tomorrow, then in 3, 7, 16 and 35 days."
                 : due.isEmpty ? "Every line is fresh. The next one comes back \(nextDue)."
                 : "Play each line from memory. A clean run sends it further out; a slip brings it back tomorrow.")
                .font(.system(.subheadline, design: .themed))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            if !due.isEmpty {
                Button {
                    // A review counts as the day's free opening drill.
                    if Premium.shared.use(.openingDrill, key: "review") { reviewing = due } else { offer = .openingDrill }
                } label: {
                    Label("Review", systemImage: "arrow.triangle.2.circlepath")
                }
                .buttonStyle(TrainingButtonStyle(theme: theme))
            }
            if count > 0 {
                NavigationLink {
                    RepertoireList(theme: theme)
                } label: {
                    HStack {
                        Text("My repertoire")
                            .font(.system(.subheadline, design: .themed).weight(.semibold))
                            .foregroundStyle(theme.trainingAccent)
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(.tertiary)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(18)
        .trainingCard(theme, tint: theme.trainingAccent)
    }

    private var nextDue: String {
        guard let next = repertoire.entries.map(\.due).min() else { return "soon" }
        return next.formatted(.relative(presentation: .named))
    }

    private func familyList(_ families: [(name: String, lines: [OpeningLine])]) -> some View {
        VStack(spacing: 0) {
            ForEach(Array(families.enumerated()), id: \.element.name) { index, family in
                NavigationLink {
                    OpeningFamilyView(name: family.name, lines: family.lines, theme: theme)
                } label: {
                    OpeningFamilyRow(name: family.name, lines: family.lines)
                }
                .buttonStyle(.plain)
                if index < families.count - 1 {
                    Divider().opacity(0.4).padding(.leading, 16)
                }
            }
        }
        .trainingCard(theme)
    }
}

/// One opening family in a list: its name, who plays it and how many lines it has.
private struct OpeningFamilyRow: View {
    let name: String
    let lines: [OpeningLine]

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(name)
                    .font(.system(.subheadline, design: .themed).weight(.semibold))
                    .foregroundStyle(.primary)
                Text(caption)
                    .font(.system(.caption, design: .themed))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Image(systemName: "chevron.right")
                .font(.caption.weight(.bold))
                .foregroundStyle(.tertiary)
                .accessibilityHidden(true)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }

    private var caption: String {
        let side = lines.first.map { $0.naturalSide == .white ? "For White" : "For Black" } ?? ""
        let count = lines.count == 1 ? "1 line" : "\(lines.count) lines"
        return side.isEmpty ? count : "\(side) · \(count)"
    }
}

/// Every opening family, A to Z.
private struct AllOpeningsView: View {
    let theme: BoardTheme

    var body: some View {
        List(OpeningsView.families, id: \.name) { family in
            NavigationLink {
                OpeningFamilyView(name: family.name, lines: family.lines, theme: theme)
            } label: {
                OpeningFamilyRow(name: family.name, lines: family.lines)
            }
            .listRowInsets(EdgeInsets())
            .listRowBackground(Color.white.opacity(0.05))
        }
        .navigationTitle("Every opening")
        .navigationBarTitleDisplayMode(.inline)
        .scrollContentBackground(.hidden)
        .background { TrainingBackdrop(theme: theme) }
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
                        .font(.system(.subheadline, design: .themed).weight(.semibold))
                    Text("\(line.eco) · " + Notation.numbered(Notation.sanLine(of: line.moves, fen: Position.standard.fen,
                                                                                 limit: 8), blackFirst: false))
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            .listRowBackground(Color.white.opacity(0.05))
        }
        .navigationTitle(name)
        .navigationBarTitleDisplayMode(.inline)
        .scrollContentBackground(.hidden)
        .background { TrainingBackdrop(theme: theme) }
    }
}

/// One line: watch it, practice it, add it to the repertoire.
private struct OpeningLineView: View {
    let line: OpeningLine
    let theme: BoardTheme
    @Environment(RepertoireStore.self) private var repertoire
    @Environment(TrainingStore.self) private var training: TrainingStore?
    @State private var side: Piece.Color = .white
    @State private var runner: OpeningDrillRunner?
    /// A master game from this line, opened in Guess the Move.
    @State private var modelGame: ClassicGame?
    @State private var offer: PremiumFeature?

    /// Master games that followed this line, found once.
    private var modelGames: [ClassicGame] { GrandmasterContent.shared.masterGames(following: line.moves, limit: 6) }

    var body: some View {
        GeometryReader { geo in
            let boardSide: CGFloat = max(200, min(geo.size.width - 24, geo.size.height * 0.56))
            ScrollView {
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
                        // Testing a line is the day's free opening drill; the same line again is free.
                        if Premium.shared.use(.openingDrill, key: line.id) { restart(learn: false) } else { offer = .openingDrill }
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
                // While testing, the most played move would give the answer away.
                if let runner, runner.showsMoves || runner.isDone {
                    OpeningStatsPanel(fen: runner.board.fen, lineMove: runner.nextMove, theme: theme)
                        .padding(.horizontal, 16)
                }
                let games = modelGames
                if !games.isEmpty {
                    OpeningModelGames(games: games, theme: theme) { game in
                        if Premium.shared.opens(.masterGames) { modelGame = game } else { offer = .masterGames }
                    }
                        .padding(.horizontal, 16)
                }
            }
            .padding(.bottom, 24)
            .frame(width: geo.size.width)
            }
            .scrollBounceBehavior(.basedOnSize)
        }
        .fullScreenCover(item: $modelGame) { game in
            GuessTheMoveView(game: game, theme: theme)
                .environment(training)
        }
        .premiumOffer($offer)
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
    @Environment(TrainingStore.self) private var training: TrainingStore?
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
            training?.recordPractice(xp: runner.mistakes == 0 ? 8 : 4)
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
