import ChessKit
import SwiftUI

/// Rewind: a finished game told as a story. The board above, the game's line
/// below it to drag through, and Leo's word on each moment that mattered.
/// At a mistake: watch the better line play out as ghosts, then take the move
/// back and find it yourself.
struct RewindView: View {
    let theme: BoardTheme
    /// Play the same rival again, when the screen offers it.
    var onPlayAgain: ((SavedGame) -> Void)?

    @Environment(GameVault.self) private var vault
    @Environment(TrainingStore.self) private var training: TrainingStore?
    @Environment(\.dismiss) private var dismiss

    @State private var game: SavedGame
    @State private var ply: Int
    @State private var ghostStep: Int?
    @State private var ghostTask: Task<Void, Never>?
    /// The ply the ghost line plays from; moving anywhere else ends it.
    @State private var ghostAnchor: Int?
    @State private var chance: SecondChance?
    @State private var session: SessionPlan?

    init(game: SavedGame, theme: BoardTheme, startAt ply: Int? = nil, onPlayAgain: ((SavedGame) -> Void)? = nil) {
        self.theme = theme
        self.onPlayAgain = onPlayAgain
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

    private var ghost: (positions: [String], moves: [String], uci: [String])? {
        guard ghostStep != nil, let focused else { return nil }
        let line = SavedGame.ghostLine(for: focused)
        return line.positions.isEmpty ? nil : line
    }

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
                    .frame(height: 96)
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
                Text(ghost == nil ? "Rewind · vs \(game.opponent)" : "Ghost line · vs \(game.opponent)")
                    .font(.caption2.weight(.semibold))
                    .tracking(2.5)
                    .textCase(.uppercase)
                    .foregroundStyle(.secondary)
                Text(ghost == nil ? positionTitle : "What could have been")
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
        return "Move \((ply + 1) / 2) of \(game.moveCount)"
    }

    // MARK: Board

    private var board: some View {
        let fen: String
        var hints: [MoveHint] = []
        var tints: [Square: Color] = [:]
        var ghosts: Set<Square> = []
        if let ghost, let step = ghostStep {
            let index = min(step, ghost.positions.count - 1)
            fen = ghost.positions[index]
            for uci in ghost.uci.prefix(index + 1) {
                if let squares = Notation.squares(of: uci) { ghosts.insert(squares.to) }
            }
            if let squares = Notation.squares(of: ghost.uci[index]) {
                tints[squares.from] = RewindPalette.gold.opacity(0.28)
                hints = [MoveHint(rank: 0, from: squares.from, to: squares.to, san: ghost.moves[index],
                                  uci: ghost.uci[index], evaluation: .centipawns(0))]
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
            tints: tints,
            ghosts: ghosts,
            ghostColor: RewindPalette.gold
        )
        .animation(.easeInOut(duration: 0.35), value: fen)
    }

    private var ghostBranch: (ply: Int, value: Double)? {
        guard ghost != nil, let focused else { return nil }
        // The engine's score before the move is what the better line keeps.
        let mine = focused.byWhite == game.playerIsWhite ? focused.before : -focused.before
        return (focused.ply - 1, mine)
    }

    // MARK: The card

    private var card: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let ghost, let focused {
                ghostCard(ghost, moment: focused)
            } else if let focused {
                momentCard(focused)
            } else {
                plainCard
            }
            Spacer(minLength: 12)
            momentNav
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
        .animation(.snappy(duration: 0.25), value: ghostStep)
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

    private func ghostCard(_ ghost: (positions: [String], moves: [String], uci: [String]), moment: SavedMoment) -> some View {
        let step = min(ghostStep ?? 0, ghost.moves.count - 1)
        let mineBest = moment.before
        let minePlayed = moment.after
        return VStack(alignment: .leading, spacing: 0) {
            HStack {
                Tag(text: "Ghost line", symbol: "circle.dashed", color: RewindPalette.gold)
                Spacer()
                Text("Move \(step + 1) of \(ghost.moves.count)")
                    .font(.subheadline.weight(.semibold).monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            HStack(spacing: 8) {
                ForEach(Array(ghost.moves.enumerated()), id: \.offset) { index, san in
                    Text(san)
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                        .frame(maxWidth: .infinity, minHeight: 34)
                        .foregroundStyle(index <= step ? RewindPalette.gold : Color.secondary)
                        .background {
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .fill(index <= step ? RewindPalette.gold.opacity(0.14) : Color.primary.opacity(0.05))
                        }
                }
            }
            .padding(.top, 12)
            Text("If you had played \(ghost.moves.first ?? "the engine's move")")
                .font(.system(.title3, design: .themed).weight(.semibold))
                .padding(.top, 12)
            Text(GhostVerdict.sentence(best: mineBest, played: minePlayed))
                .font(.body)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 4)
            HStack(spacing: 10) {
                CardButton(title: "Replay", symbol: "arrow.counterclockwise") { startGhost() }
                if !game.rewritten.contains(moment.ply) {
                    CardButton(title: "Try it myself", symbol: "play.fill", prominent: true, accent: accent) {
                        stopGhost()
                        takeBack(moment, note: RewindNote.make(for: moment, library: training?.library))
                    }
                } else {
                    CardButton(title: "Back to the game", symbol: "chevron.left") { stopGhost() }
                }
            }
            .padding(.top, 16)
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

    private func startGhost() {
        ghostTask?.cancel()
        guard let focused else { return }
        let count = SavedGame.ghostLine(for: focused).positions.count
        guard count > 0 else { return }
        // The board shows the moment from before it was played.
        ghostAnchor = focused.ply - 1
        if ply != focused.ply - 1 { ply = focused.ply - 1 }
        withAnimation(.snappy) { ghostStep = 0 }
        ghostTask = Task { @MainActor in
            for step in 1..<max(1, count) {
                try? await Task.sleep(for: .seconds(1.3))
                guard !Task.isCancelled else { return }
                withAnimation(.easeInOut(duration: 0.35)) { ghostStep = step }
            }
        }
    }

    private func stopGhost() {
        ghostTask?.cancel()
        ghostTask = nil
        ghostAnchor = nil
        if ghostStep != nil { withAnimation(.snappy) { ghostStep = nil } }
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
