import ChessKit
import SwiftUI

/// Rewind: a finished game told as a story. The board above, the game's line
/// below it to drag through, and Leo's word on each moment that mattered.
/// At a mistake: walk the better line as ghosts, as deep as the review level
/// goes, follow the other side's best tries or play your own move against
/// Stockfish, then take the move back and find it yourself.
struct RewindView: View {
    let theme: BoardTheme
    /// Play the same rival again, when the screen offers it.
    var onPlayAgain: ((SavedGame) -> Void)?

    @Environment(GameVault.self) private var vault
    @Environment(TrainingStore.self) private var training: TrainingStore?
    @Environment(\.dismiss) private var dismiss

    @State private var game: SavedGame
    @State private var ply: Int
    /// The better line being walked through, when "Show me" is on.
    @State private var explorer: LineExplorer?
    @State private var autoplay: Task<Void, Never>?
    /// The ply the line plays from; moving anywhere else on the game's line ends it.
    @State private var ghostAnchor: Int?
    @AppStorage(ReviewLevel.storageKey) private var levelID = ReviewLevel.club.rawValue
    private let engine: ChessEngine?
    private let opensLine: Bool
    @State private var chance: SecondChance?
    @State private var session: SessionPlan?

    init(game: SavedGame, theme: BoardTheme, startAt ply: Int? = nil, opensLine: Bool = false,
         engine: ChessEngine? = StockfishEngine.shared, onPlayAgain: ((SavedGame) -> Void)? = nil) {
        self.theme = theme
        self.onPlayAgain = onPlayAgain
        self.engine = engine
        self.opensLine = opensLine
        _game = State(initialValue: game)
        let first = game.toRewrite.first(where: { !game.rewritten.contains($0.ply) }) ?? game.keyMoments.first
        let start = ply ?? first.map { $0.ply - 1 } ?? game.moves.count
        _ply = State(initialValue: max(0, min(game.moves.count, start)))
    }

    private var accent: Color { theme.accent ?? RewindPalette.gold }
    private var moments: [SavedMoment] { game.keyMoments }

    /// The moment the board is on: the position before it was played, or just after.
    private var focused: SavedMoment? {
        moments.first { $0.ply == ply + 1 } ?? moments.first { $0.ply == ply }
    }

    private var level: ReviewLevel { ReviewLevel(rawValue: levelID) ?? .club }

    var body: some View {
        ZStack {
            ThemeBackdrop(theme: theme).ignoresSafeArea()
            GeometryReader { geo in
                let side = min(geo.size.width - 24, geo.size.height * 0.46, 620)
                VStack(spacing: 0) {
                    header
                    board
                        .frame(width: side, height: side)
                        .padding(.top, 8)
                    Lifeline(game: game, ply: $ply, ghost: ghostBranch, dotFill: theme.isDark ? Color(hex: 0x101114) : .white) { moment in
                        jump(to: moment)
                    }
                    .frame(height: explorer == nil ? 96 : 56)
                    .frame(maxWidth: 640)
                    .padding(.top, 14)
                    .padding(.horizontal, 8)
                    card
                        .frame(maxWidth: 640)
                        .padding(.top, 12)
                    Spacer(minLength: 0)
                }
                .frame(width: geo.size.width)
            }
        }
        .preferredColorScheme(theme.isDark ? .dark : nil)
        .tint(accent)
        .onChange(of: ply) { _, now in
            if now != ghostAnchor { stopGhost() }
        }
        .onChange(of: levelID) { _, _ in explorer?.setLevel(level) }
        .onAppear {
            if opensLine, explorer == nil { startGhost(autoplays: false) }
        }
        .onDisappear { stopGhost() }
        .sensoryFeedback(.selection, trigger: ply)
        .sheet(item: $chance) { chance in
            SecondChanceSheet(chance: chance, theme: theme) { solved in
                if solved {
                    vault.markRewritten(chance.moment.ply, in: game.id)
                    if let fresh = vault.game(game.id) { game = fresh }
                }
            }
        }
        .fullScreenCover(item: $session) { plan in
            if let training {
                SessionView(plan: plan, theme: theme).environment(training)
            }
        }
    }

    // MARK: Header

    private var header: some View {
        HStack {
            Button {
                dismiss()
            } label: {
                Image(systemName: "chevron.left")
                    .font(.title3.weight(.semibold))
                    .frame(width: 44, height: 44)
            }
            .tint(.primary)
            .accessibilityLabel("Back")
            Spacer()
            VStack(spacing: 2) {
                Text(explorer == nil ? "Rewind · vs \(game.opponent)" : "\(level.title) review · vs \(game.opponent)")
                    .font(.caption2.weight(.semibold))
                    .tracking(2.5)
                    .textCase(.uppercase)
                    .foregroundStyle(.secondary)
                Text(explorer == nil ? positionTitle : "What could have been")
                    .font(.system(.headline, design: .themed))
                    .contentTransition(.numericText())
            }
            Spacer()
            if let onPlayAgain, game.level != nil {
                Button {
                    dismiss()
                    onPlayAgain(game)
                } label: {
                    Image(systemName: "play.fill")
                        .font(.body.weight(.semibold))
                        .frame(width: 44, height: 44)
                }
                .tint(.primary)
                .accessibilityLabel("Play \(game.opponent) again")
            } else {
                Color.clear.frame(width: 44, height: 44)
            }
        }
        .padding(.horizontal, 8)
    }

    private var positionTitle: String {
        if ply == 0 { return "The start" }
        // The move being decided: before White's sixth move is "Move 6".
        return "Move \(min(game.moveCount, ply / 2 + 1)) of \(game.moveCount)"
    }

    // MARK: Board

    private var board: some View {
        let fen: String
        var hints: [MoveHint] = []
        var tints: [Square: Color] = [:]
        var ghosts: Set<Square> = []
        var onTap: ((Square) -> Void)?
        if let explorer {
            fen = explorer.fen
            ghosts = explorer.ghostSquares
            if let current = explorer.current, let squares = Notation.squares(of: current.uci) {
                tints[squares.from] = RewindPalette.gold.opacity(0.24)
            }
            // The line's next move, and the other side's best tries beside it.
            if let next = explorer.next, let squares = Notation.squares(of: next.uci) {
                hints.append(MoveHint(rank: 0, from: squares.from, to: squares.to, san: next.san,
                                      uci: next.uci, evaluation: .centipawns(0)))
            }
            if let branch = explorer.branches.first, let first = branch.moves.first, let squares = Notation.squares(of: first) {
                hints.append(MoveHint(rank: 1, from: squares.from, to: squares.to, san: branch.san,
                                      uci: first, evaluation: branch.evaluation))
            }
            if let selected = explorer.selected {
                tints[selected] = RewindPalette.gold.opacity(0.5)
            }
            onTap = { square in
                stopAutoplay()
                explorer.tap(square)
            }
        } else {
            fen = game.positions[min(ply, game.positions.count - 1)]
            if let focused, let squares = Notation.squares(of: focused.uci) {
                let color = RewindPalette.color(for: focused, rewritten: game.rewritten.contains(focused.ply))
                if focused.ply == ply + 1 {
                    // Before the move: where it went from, ringed.
                    tints[squares.from] = color.opacity(0.32)
                } else {
                    tints[squares.from] = color.opacity(0.22)
                    tints[squares.to] = color.opacity(0.38)
                }
            }
        }
        return PositionBoard(
            draft: PositionDraft(fen: fen) ?? .standard,
            theme: theme,
            flipped: !game.playerIsWhite,
            hints: hints,
            onTap: onTap,
            tints: tints,
            ghosts: ghosts,
            ghostColor: RewindPalette.gold
        )
        .animation(.easeInOut(duration: 0.35), value: fen)
    }

    private var ghostBranch: (ply: Int, value: Double)? {
        guard let explorer, let focused else { return nil }
        // Where the line stands now, or the engine's score before the move until it has looked.
        let mine = focused.byWhite == game.playerIsWhite ? focused.before : -focused.before
        return (focused.ply - 1, explorer.evaluation?.winningChances ?? mine)
    }

    // MARK: The card

    private var card: some View {
        VStack(alignment: .leading, spacing: 0) {
            ScrollView {
            VStack(alignment: .leading, spacing: 0) {
            if let explorer, let focused {
                ExplorerCard(
                    explorer: explorer, moment: focused, theme: theme, levelID: $levelID,
                    canTryIt: !game.rewritten.contains(focused.ply),
                    isPlaying: autoplay != nil,
                    onTouch: stopAutoplay,
                    onPlay: { startAutoplay() },
                    onTryIt: {
                        stopGhost()
                        takeBack(focused, note: RewindNote.make(for: focused, library: training?.library))
                    },
                    onClose: stopGhost
                )
            } else if let focused {
                momentCard(focused)
            } else {
                plainCard
            }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            }
            .scrollBounceBehavior(.basedOnSize)
            Spacer(minLength: 12)
            if explorer == nil { momentNav }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .fill(theme.isDark ? Color.white.opacity(0.06) : Color.white)
                .overlay {
                    RoundedRectangle(cornerRadius: 28, style: .continuous)
                        .strokeBorder(Color.primary.opacity(0.08), lineWidth: 1)
                }
        }
        .padding(.horizontal, 12)
        .animation(.snappy(duration: 0.25), value: focused?.ply)
        .animation(.snappy(duration: 0.25), value: explorer == nil)
    }

    private func momentCard(_ moment: SavedMoment) -> some View {
        let note = RewindNote.make(for: moment, library: training?.library)
        let rewritten = game.rewritten.contains(moment.ply)
        let color = RewindPalette.color(for: moment, rewritten: rewritten)
        let canFix = note.isLesson && moment.bestUCI != nil
        let skill = note.skill.flatMap { training?.library?.skill($0) }
        return VStack(alignment: .leading, spacing: 0) {
            HStack {
                Tag(text: rewritten ? "Rewritten" : note.tag, symbol: rewritten ? "checkmark" : nil, color: color)
                Spacer()
                Text(moment.numbered)
                    .font(.subheadline.weight(.semibold).monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            Text(rewritten ? "You found it." : note.title)
                .font(.system(.title2, design: .themed).weight(.semibold))
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 12)
            Text(rewritten ? "This moment is rewritten. \(game.leftToRewrite == 0 ? "Every moment in this game is fixed." : "\(game.leftToRewrite) left in this game.")" : note.detail)
                .font(.body)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 6)
            if canFix || skill != nil {
                HStack(spacing: 10) {
                    if canFix {
                        CardButton(title: "Show me", symbol: "circle.dashed") { startGhost() }
                        if !rewritten {
                            CardButton(title: "Take it back", symbol: "arrow.counterclockwise", prominent: true, accent: accent) {
                                takeBack(moment, note: note)
                            }
                        }
                    }
                    if let skill {
                        CardButton(title: "Practice", symbol: "graduationcap") {
                            session = training?.practicePlan(for: skill)
                        }
                    }
                }
                .padding(.top, 16)
            }
        }
    }

    private var plainCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(ply == 0 ? "The start" : moveName(ply))
                .font(.system(.title3, design: .themed).weight(.semibold))
            Text(moments.isEmpty
                 ? "A clean game: nothing here needs rewriting."
                 : "Drag along the line to move through the game, or tap a dot to jump to a moment.")
                .font(.body)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            if let accuracy = game.accuracy {
                Text("Accuracy \(accuracy)%  ·  \(game.result.title)")
                    .font(.subheadline.weight(.semibold).monospacedDigit())
                    .foregroundStyle(.tertiary)
                    .padding(.top, 4)
            }
        }
    }

    private func moveName(_ ply: Int) -> String {
        guard ply > 0, ply <= game.moves.count else { return "" }
        let number = (ply + 1) / 2
        return ply % 2 == 1 ? "\(number). \(game.moves[ply - 1])" : "\(number)... \(game.moves[ply - 1])"
    }

    /// Back and forward through the moments, with where you are among them.
    private var momentNav: some View {
        let previous = moments.last { $0.ply - 1 < ply && $0.ply != ply }
        let next = moments.first { $0.ply - 1 > ply }
        let index = focused.flatMap { f in moments.firstIndex { $0.ply == f.ply } }
        return HStack {
            Button {
                if let previous { jump(to: previous) }
            } label: {
                Label(previous?.numbered ?? "Start", systemImage: "chevron.left")
                    .labelStyle(.titleAndIcon)
            }
            .disabled(previous == nil)
            Spacer()
            Text(moments.isEmpty ? "No moments" : index.map { "\($0 + 1) of \(moments.count) moments" } ?? "\(moments.count) moments")
                .foregroundStyle(.tertiary)
            Spacer()
            Button {
                if let next { jump(to: next) }
            } label: {
                HStack(spacing: 4) {
                    Text(next?.numbered ?? "End")
                    Image(systemName: "chevron.right")
                }
            }
            .disabled(next == nil)
        }
        .font(.subheadline.weight(.semibold))
        .tint(.primary)
    }

    // MARK: Actions

    private func jump(to moment: SavedMoment) {
        withAnimation(.snappy) { ply = max(0, moment.ply - 1) }
    }

    /// Opens the better line from the moment on the board, and plays it unless told not to.
    private func startGhost(autoplays: Bool = true) {
        stopGhost()
        guard let focused else { return }
        var line = focused.bestLine
        if line.isEmpty, let best = focused.bestUCI { line = [best] }
        guard !line.isEmpty else { return }
        // The board shows the moment from before it was played.
        ghostAnchor = focused.ply - 1
        if ply != focused.ply - 1 { ply = focused.ply - 1 }
        let made = LineExplorer(root: focused.fenBefore, line: line, player: game.playerColor, level: level, engine: engine)
        guard !made.steps.isEmpty else { return }
        withAnimation(.snappy) { explorer = made }
        made.refresh()
        if autoplays {
            startAutoplay()
        } else if opensLine {
            made.go(to: 1)
        }
    }

    /// Plays the line one move at a time, waiting for the engine where the line runs on.
    private func startAutoplay() {
        stopAutoplay()
        guard let explorer else { return }
        if explorer.atEnd { explorer.go(to: 0) }
        autoplay = Task { @MainActor in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1.4))
                guard !Task.isCancelled else { return }
                if explorer.atEnd {
                    if explorer.isThinking, explorer.steps.count < explorer.level.depth { continue }
                    break
                }
                withAnimation(.easeInOut(duration: 0.35)) { explorer.stepForward() }
            }
            autoplay = nil
        }
    }

    private func stopAutoplay() {
        autoplay?.cancel()
        autoplay = nil
    }

    private func stopGhost() {
        stopAutoplay()
        explorer?.cancel()
        ghostAnchor = nil
        if explorer != nil { withAnimation(.snappy) { explorer = nil } }
    }

    private func takeBack(_ moment: SavedMoment, note: RewindNote) {
        guard let best = moment.bestUCI else { return }
        let mistake = GameMistake(
            id: "rewind-\(game.id.uuidString)-\(moment.ply)", fen: moment.fenBefore, best: best,
            played: moment.uci, skill: note.skill ?? "", title: note.title, created: .now, due: .now
        )
        let item = SessionItem(content: .mistake(mistake), role: .review)
        guard let runner = DrillRunner(item: item, library: training?.library, engine: StockfishEngine.shared) else { return }
        chance = SecondChance(moment: moment, runner: runner)
    }
}

/// Taking a move back: the position before it, against the clock of nobody, to find the better one.
struct SecondChance: Identifiable {
    let id = UUID()
    let moment: SavedMoment
    let runner: DrillRunner
}

private struct SecondChanceSheet: View {
    let chance: SecondChance
    let theme: BoardTheme
    let onFinish: (Bool) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var reported = false

    private var solved: Bool {
        guard let outcome = chance.runner.outcome else { return false }
        return outcome != .missed
    }

    var body: some View {
        ZStack {
            ThemeBackdrop(theme: theme).ignoresSafeArea()
            GeometryReader { geo in
                let side = min(geo.size.width - 32, geo.size.height * 0.56, 600)
                ScrollView {
                    VStack(spacing: 12) {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Second chance")
                                    .font(.caption.weight(.semibold))
                                    .tracking(2)
                                    .textCase(.uppercase)
                                    .foregroundStyle(.secondary)
                                Text(chance.moment.numbered)
                                    .font(.system(.headline, design: .themed))
                            }
                            Spacer()
                            Button(chance.runner.isDone ? "Done" : "Close") { dismiss() }
                                .font(.headline)
                        }
                        .padding(.horizontal, 16)
                        .padding(.top, 16)
                        DrillView(runner: chance.runner, theme: theme, boardSide: side)
                        if solved {
                            Label("Rewritten", systemImage: "checkmark.seal.fill")
                                .font(.headline)
                                .foregroundStyle(RewindPalette.gold)
                                .transition(.scale.combined(with: .opacity))
                        }
                    }
                    .frame(width: geo.size.width)
                }
            }
        }
        .preferredColorScheme(theme.isDark ? .dark : nil)
        .tint(theme.trainingAccent)
        .animation(.spring(response: 0.4, dampingFraction: 0.7), value: solved)
        .sensoryFeedback(.success, trigger: solved) { _, now in now }
        .onAppear { chance.runner.begin() }
        .onDisappear { chance.runner.cancel() }
        .onChange(of: chance.runner.outcome) { _, outcome in
            guard let outcome, !reported else { return }
            reported = true
            onFinish(outcome != .missed)
        }
    }
}

// MARK: The line, move by move

/// The better line from a moment: every move tappable, Leo's word on the one on
/// the board, where it leads, and the other side's best tries to follow instead.
private struct ExplorerCard: View {
    let explorer: LineExplorer
    let moment: SavedMoment
    let theme: BoardTheme
    @Binding var levelID: String
    let canTryIt: Bool
    let isPlaying: Bool
    let onTouch: () -> Void
    let onPlay: () -> Void
    let onTryIt: () -> Void
    let onClose: () -> Void

    private var level: ReviewLevel { explorer.level }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                Tag(text: explorer.ownMoveAt == nil ? "Ghost line" : "Your line", symbol: "circle.dashed",
                    color: RewindPalette.gold)
                Spacer()
                levelMenu
                Button(action: onClose) {
                    Image(systemName: "xmark")
                        .font(.footnote.weight(.bold))
                        .frame(width: 30, height: 30)
                        .background(Circle().fill(Color.primary.opacity(0.08)))
                }
                .tint(.primary)
                .accessibilityLabel("Back to the game")
            }
            moves.padding(.top, 12)
            Text(explorer.sentence)
                .font(.system(.headline, design: .themed))
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 12)
                .contentTransition(.opacity)
            outlook.padding(.top, 4)
            if !explorer.branches.isEmpty {
                branches.padding(.top, 12)
            }
            controls.padding(.top, 14)
        }
    }

    private var levelMenu: some View {
        Menu {
            Picker("Review", selection: $levelID) {
                ForEach(ReviewLevel.allCases) { level in
                    Text("\(level.title): \(level.blurb)").tag(level.rawValue)
                }
            }
        } label: {
            HStack(spacing: 4) {
                Text(level.title)
                Image(systemName: "chevron.up.chevron.down").font(.caption2.weight(.bold))
            }
            .font(.subheadline.weight(.semibold))
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(Capsule().fill(Color.primary.opacity(0.08)))
        }
        .tint(.primary)
        .accessibilityLabel("Review level, \(level.title)")
    }

    /// Every move of the line; the one on the board is lit.
    private var moves: some View {
        ScrollViewReader { reader in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    pill("Start", lit: explorer.cursor == 0, own: false) { explorer.go(to: 0) }
                        .id(0)
                    ForEach(explorer.steps) { step in
                        pill(step.numbered, lit: explorer.cursor == step.index + 1,
                             own: explorer.ownMoveAt == step.index) {
                            explorer.go(to: step.index + 1)
                        }
                        .id(step.index + 1)
                    }
                    if explorer.isThinking, explorer.atEnd {
                        ProgressView().controlSize(.small).padding(.horizontal, 8)
                    }
                }
            }
            .onChange(of: explorer.cursor) { _, cursor in
                withAnimation(.snappy) { reader.scrollTo(cursor, anchor: .center) }
            }
        }
    }

    private func pill(_ text: String, lit: Bool, own: Bool, action: @escaping () -> Void) -> some View {
        Button {
            onTouch()
            action()
        } label: {
            HStack(spacing: 4) {
                if own { Image(systemName: "hand.point.up.left.fill").font(.caption2) }
                Text(text)
            }
            .font(.subheadline.weight(.semibold).monospacedDigit())
            .lineLimit(1)
            .padding(.horizontal, 10)
            .frame(minHeight: 32)
            .foregroundStyle(lit ? RewindPalette.gold : Color.secondary)
            .background {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(lit ? RewindPalette.gold.opacity(0.16) : Color.primary.opacity(0.05))
            }
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var outlook: some View {
        if let evaluation = explorer.evaluation {
            HStack(spacing: 6) {
                Text("Here: \(LineNarrator.outlook(evaluation.winningChances))")
                if level.showsNumbers {
                    Text(evaluation.label)
                        .monospacedDigit()
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Capsule().fill(Color.primary.opacity(0.08)))
                }
            }
            .font(.subheadline)
            .foregroundStyle(.secondary)
        } else if explorer.isThinking {
            Text("Stockfish is looking…").font(.subheadline).foregroundStyle(.tertiary)
        }
    }

    /// The other side's best tries here (both sides' on Grandmaster), to follow instead.
    private var branches: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(explorer.playerToMove ? "Or you could play" : "If they try instead")
                .font(.caption.weight(.semibold))
                .tracking(1.5)
                .textCase(.uppercase)
                .foregroundStyle(.tertiary)
            ForEach(explorer.branches) { branch in
                Button {
                    onTouch()
                    withAnimation(.snappy) { explorer.follow(branch) }
                } label: {
                    HStack(spacing: 10) {
                        Text(branch.san)
                            .font(.subheadline.weight(.semibold))
                            .frame(minWidth: 54, alignment: .leading)
                        Text(branch.note)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        Spacer(minLength: 4)
                        if level.showsNumbers {
                            Text(branch.evaluation.label)
                                .font(.caption.weight(.semibold).monospacedDigit())
                                .foregroundStyle(.secondary)
                        }
                        Image(systemName: "arrow.turn.down.right")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.tertiary)
                    }
                    .padding(.horizontal, 12)
                    .frame(minHeight: 38)
                    .background {
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(Color.primary.opacity(0.05))
                    }
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var controls: some View {
        HStack(spacing: 8) {
            round("backward.end.fill", label: "Previous move", disabled: explorer.cursor == 0) {
                explorer.stepBack()
            }
            round(isPlaying ? "pause.fill" : "play.fill", label: isPlaying ? "Pause" : "Play the line", disabled: false) {
                if isPlaying { onTouch() } else { onPlay() }
            }
            round("forward.end.fill", label: "Next move", disabled: explorer.atEnd) {
                explorer.stepForward()
            }
            Spacer(minLength: 4)
            if canTryIt {
                Button(action: onTryIt) {
                    Label("Try it myself", systemImage: "arrow.counterclockwise")
                        .font(.subheadline.weight(.semibold))
                        .padding(.horizontal, 14)
                        .frame(minHeight: 44)
                        .foregroundStyle(.background)
                        .background(Capsule().fill(Color.primary.opacity(0.92)))
                }
                .buttonStyle(.plain)
            } else {
                Text("Tap a piece to try a move")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
        }
    }

    private func round(_ symbol: String, label: String, disabled: Bool, action: @escaping () -> Void) -> some View {
        Button {
            if symbol != "play.fill" && symbol != "pause.fill" { onTouch() }
            withAnimation(.easeInOut(duration: 0.3)) { action() }
        } label: {
            Image(systemName: symbol)
                .font(.footnote.weight(.bold))
                .frame(width: 44, height: 44)
                .background(Circle().fill(Color.primary.opacity(0.07)))
        }
        .tint(.primary)
        .disabled(disabled)
        .accessibilityLabel(label)
    }
}

// MARK: Small parts

private struct Tag: View {
    let text: String
    var symbol: String?
    let color: Color

    var body: some View {
        HStack(spacing: 6) {
            if let symbol {
                Image(systemName: symbol).font(.caption.weight(.bold))
            } else {
                Circle().fill(color).frame(width: 7, height: 7)
            }
            Text(text).font(.subheadline.weight(.semibold))
        }
        .foregroundStyle(color)
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(Capsule().fill(color.opacity(0.14)))
    }
}

private struct CardButton: View {
    let title: String
    let symbol: String
    var prominent = false
    var accent: Color = .primary
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 5) {
                Image(systemName: symbol).font(.body.weight(.semibold))
                Text(title).font(.footnote.weight(.semibold)).lineLimit(1).minimumScaleFactor(0.8)
            }
            .frame(maxWidth: .infinity, minHeight: 56)
            .foregroundStyle(prominent ? AnyShapeStyle(.background) : AnyShapeStyle(.primary))
            .background {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(prominent ? AnyShapeStyle(Color.primary.opacity(0.92)) : AnyShapeStyle(Color.primary.opacity(0.06)))
            }
            .overlay {
                if !prominent {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .strokeBorder(Color.primary.opacity(0.08), lineWidth: 1)
                }
            }
        }
        .buttonStyle(.plain)
    }
}
