import AVFoundation
import ChessKit
import SwiftUI

/// One frame of the reel at a given time. Everything on it comes from the time,
/// so the same view plays on screen and renders the exported video.
struct ReelFrame: View {
    let reel: GameReel
    let theme: BoardTheme
    let time: Double
    /// Where the wordmark sits from the top. On the phone it clears the island and the buttons.
    var wordmarkTop: CGFloat = 34
    /// False on the phone, where the wordmark sits in the top bar instead. Its place is
    /// kept, so the picture lands where it does in the video.
    var showsWordmark = true

    private var accent: Color { theme.trainingAccent }
    /// Rounded type on Neon, plain SF Pro on every other look, as in the game.
    private var design: Font.Design { theme.glows ? .rounded : .default }

    var body: some View {
        ZStack {
            TrainingBackdrop(theme: theme)
            VStack(spacing: 0) {
                Text("BEAUTY OF CHESS")
                    .font(.app(size: 13, weight: .heavy))
                    .tracking(3)
                    .foregroundStyle(accent)
                    .opacity(showsWordmark ? 1 : 0)
                    .padding(.top, wordmarkTop)
                Spacer(minLength: 0)
                content
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 20)
        }
        .environment(\.colorScheme, theme.screenIsDark ? .dark : .light)
    }

    @ViewBuilder
    private var content: some View {
        switch reel.scene(at: time) {
        case .intro(let progress):
            intro(progress)
        case .highlight(let index, let t):
            highlight(reel.highlights[index], number: index + 1, time: t)
        case .outro(let progress):
            outro(progress)
        }
    }

    private func intro(_ progress: Double) -> some View {
        let shown = min(1, progress * 3)
        return VStack(spacing: 18) {
            Text("\(reel.player) vs \(reel.opponent)")
                .font(.app(size: 34, weight: .bold))
                .multilineTextAlignment(.center)
            resultBadge
            HStack(spacing: 18) {
                if let accuracy = reel.accuracy {
                    stat("\(accuracy)%", "accuracy")
                }
                // A zero says nothing, so it isn't shown.
                if reel.moveCount > 0 {
                    stat("\(reel.moveCount)", reel.moveCount == 1 ? "move" : "moves")
                }
                if !reel.highlights.isEmpty {
                    stat("\(reel.highlights.count)", reel.highlights.count == 1 ? "highlight" : "highlights")
                }
            }
        }
        .opacity(shown)
        .scaleEffect(0.92 + 0.08 * shown)
    }

    private func highlight(_ highlight: GameReel.Highlight, number: Int, time t: Double) -> some View {
        let moment = highlight.moment
        let landed = t >= GameReel.moveLandsAt
        let fen = landed ? moment.fenAfter : moment.fenBefore
        let fadeIn = min(1, t / 0.35)
        return VStack(spacing: 16) {
            HStack {
                Text(highlight.kind.title.uppercased())
                    .font(.app(size: 14, weight: .heavy))
                    .tracking(1.5)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(moment.grade.color(on: theme).opacity(0.22), in: Capsule())
                    .foregroundStyle(moment.grade.color(on: theme))
                Spacer()
                if let piece = highlight.piece {
                    Label(piece, systemImage: "shield.lefthalf.filled")
                        .font(.app(size: 15, weight: .bold))
                        .foregroundStyle(theme.ink(for: reel.playerColor))
                        .lineLimit(1)
                }
                Text("Move \((moment.ply + 1) / 2)")
                    .font(.app(size: 15, weight: .semibold).monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            PositionBoard(draft: PositionDraft(fen: fen) ?? .empty, theme: theme,
                          flipped: reel.playerColor == .black, hints: arrow(for: moment, landed: landed))
                .aspectRatio(1, contentMode: .fit)
                .scaleEffect(landed ? 1 : 0.985)
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text(moment.san + glyph(moment.grade))
                    .font(.app(size: 40, weight: .heavy))
                    .foregroundStyle(landed ? moment.grade.color(on: theme) : .primary)
                Spacer()
                ReelEvalBar(chances: landed ? moment.after : moment.before, theme: theme)
                    .frame(width: 120, height: 10)
            }
            Text(highlight.line)
                .font(.app(size: 19, weight: .semibold))
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
            if highlight.kind == .blunder, let best = moment.best, landed {
                Text("\(best) was the move.")
                    .font(.app(size: 16, weight: .medium))
                    .foregroundStyle(.secondary)
            }
        }
        .opacity(fadeIn)
    }

    private func outro(_ progress: Double) -> some View {
        VStack(spacing: 18) {
            PositionBoard(draft: PositionDraft(fen: reel.finalFEN) ?? .empty, theme: theme,
                          flipped: reel.playerColor == .black)
                .aspectRatio(1, contentMode: .fit)
                .frame(maxWidth: 260)
            resultBadge
            Text(reel.endLine)
                .font(.app(size: 20, weight: .semibold))
                .multilineTextAlignment(.center)
            // The card ends on Leo's line. The Piece of the Match lives on Home, in Your army.
            Text("Coached by \(Coach.current.name) · Beauty of Chess")
                .font(.app(size: 14, weight: .medium))
                .foregroundStyle(.secondary)
        }
        .opacity(min(1, progress * 4))
    }

    /// The result as it is for the player: the accent for a win, quiet otherwise.
    private var resultBadge: some View {
        let (text, color): (String, Color) = switch reel.result {
        case .win: ("WIN", accent)
        case .loss: ("LOSS", .secondary)
        case .draw: ("DRAW", .secondary)
        }
        return Text(text)
            .font(.app(size: 22, weight: .black))
            .tracking(4)
            .padding(.horizontal, 22)
            .padding(.vertical, 8)
            .background(color.opacity(0.2), in: Capsule())
            .overlay(Capsule().strokeBorder(color.opacity(0.7), lineWidth: 1.5))
            .foregroundStyle(color)
    }

    private func stat(_ value: String, _ label: String) -> some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.app(size: 26, weight: .bold).monospacedDigit())
            Text(label)
                .font(.app(size: 13, weight: .medium))
                .foregroundStyle(.secondary)
        }
    }

    private func arrow(for moment: ReelMoment, landed: Bool) -> [MoveHint] {
        guard !landed, let squares = Notation.squares(of: moment.uci) else { return [] }
        return [MoveHint(rank: 0, from: squares.from, to: squares.to, san: moment.san, uci: moment.uci,
                         evaluation: .centipawns(0))]
    }

    private func glyph(_ grade: MoveReview.Grade) -> String {
        switch grade {
        case .best, .checkmate: return "!"
        case .excellent: return "!"
        case .inaccuracy: return "?!"
        case .mistake: return "?"
        case .blunder: return "??"
        case .good: return ""
        }
    }
}

/// Winning chances as a two-tone bar, the mover's share from the left.
private struct ReelEvalBar: View {
    let chances: Double
    let theme: BoardTheme

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.primary.opacity(0.15))
                Capsule()
                    .fill(theme.trainingAccent)
                    .frame(width: max(4, geo.size.width * (chances + 1) / 2))
            }
        }
    }
}

/// Plays the reel with Leo's voice, and makes a video of it to share.
struct HighlightReelView: View {
    let reel: GameReel
    let theme: BoardTheme
    @Environment(\.dismiss) private var dismiss
    @State private var started = Date()
    @State private var spoken = -1
    @State private var exporting = false
    @State private var exported: URL?
    @State private var exportFailed = false

    var body: some View {
        ZStack(alignment: .top) {
            GeometryReader { geo in
                TimelineView(.animation) { context in
                    let t = min(reel.length, context.date.timeIntervalSince(started))
                    // The picture runs edge to edge; the wordmark is in the bar, its place kept below it.
                    ReelFrame(reel: reel, theme: theme, time: t, wordmarkTop: geo.safeAreaInsets.top + 30,
                              showsWordmark: false)
                        .onChange(of: cueIndex(at: t)) { _, index in speak(index) }
                }
                .ignoresSafeArea()
            }
            // One slim line: Close, the name, then Play again and Share as plain gold icons.
            HStack(spacing: 0) {
                Button { stopVoice(); dismiss() } label: {
                    plainIcon("xmark", color: .primary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Close")
                Spacer()
                Button {
                    started = Date()
                    spoken = -1
                } label: {
                    plainIcon("arrow.counterclockwise", color: theme.trainingAccent)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Play again")
                shareButton
            }
            // The name sits in the true middle of the screen, whatever is on either side.
            .overlay {
                Text("BEAUTY OF CHESS")
                    .font(.app(size: 13, weight: .heavy))
                    .tracking(3)
                    .foregroundStyle(theme.trainingAccent)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .padding(.horizontal, 96)
                    .accessibilityAddTraits(.isHeader)
                    .allowsHitTesting(false)
            }
            .padding(.horizontal, 8)
            .padding(.top, 4)
        }
        .onAppear {
            // A victory theme still playing would talk over Leo.
            SoundPlayer.shared.stopAll(fade: 0.4)
            CoachVoice.shared.beginLesson()
            started = Date()
        }
        .onDisappear { stopVoice() }
        // The page's light or dark, kept to the reel so the game behind it stays as it is.
        .environment(\.colorScheme, theme.screenIsDark ? .dark : .light)
        .alert("Couldn't make the video", isPresented: $exportFailed) {
            Button("Try again") { Task { await export() } }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Something went wrong while making it. The reel still plays here.")
        }
    }

    /// A plain icon, no bubble, with a full 44 pt place to tap.
    private func plainIcon(_ symbol: String, color: Color) -> some View {
        Image(systemName: symbol)
            .font(.system(size: 18, weight: .semibold))
            .foregroundStyle(color)
            .frame(width: 44, height: 44)
            .contentShape(Rectangle())
    }

    /// One tap: makes the video the first time, then opens the share sheet.
    private var shareButton: some View {
        Button {
            if let exported {
                present(exported)
            } else {
                Task {
                    await export()
                    if let exported { present(exported) }
                }
            }
        } label: {
            ZStack {
                if exporting {
                    ProgressView()
                        .controlSize(.small)
                        .tint(theme.trainingAccent)
                        .frame(width: 44, height: 44)
                } else {
                    plainIcon("square.and.arrow.up", color: theme.trainingAccent)
                }
            }
        }
        .buttonStyle(.plain)
        .disabled(exporting)
        .accessibilityLabel(exporting ? "Making video" : "Share video")
    }

    private func present(_ url: URL) {
        guard let top = ChallengePresenter.top() else { return }
        let sheet = UIActivityViewController(activityItems: [url], applicationActivities: nil)
        if let popover = sheet.popoverPresentationController {
            popover.sourceView = top.view
            popover.sourceRect = CGRect(x: top.view.bounds.maxX - 40, y: top.view.safeAreaInsets.top + 26,
                                        width: 1, height: 1)
            popover.permittedArrowDirections = [.up]
        }
        top.present(sheet, animated: true)
    }

    private func cueIndex(at time: Double) -> Int {
        reel.narration.lastIndex { $0.time <= time } ?? -1
    }

    private func speak(_ index: Int) {
        guard index > spoken, reel.narration.indices.contains(index) else { return }
        spoken = index
        let text = reel.narration[index].text
        Task { await CoachVoice.shared.say(text) }
    }

    private func stopVoice() {
        CoachVoice.shared.endLesson()
    }

    private func export() async {
        exporting = true
        defer { exporting = false }
        do {
            exported = try await ReelExporter.export(reel, theme: theme)
        } catch {
            exportFailed = true
        }
    }
}
