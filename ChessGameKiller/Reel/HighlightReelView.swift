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

    private var accent: Color { theme.accent ?? .accentColor }
    /// Rounded type on Neon, plain SF Pro on every other look, as in the game.
    private var design: Font.Design { theme.glows ? .rounded : .default }

    var body: some View {
        ZStack {
            ThemeBackdrop(theme: theme)
            VStack(spacing: 0) {
                Text("CHESS GAME KILLER")
                    .font(.system(size: 13, weight: .heavy, design: design))
                    .tracking(3)
                    .foregroundStyle(accent)
                    .padding(.top, wordmarkTop)
                Spacer(minLength: 0)
                content
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 20)
        }
        .environment(\.colorScheme, theme.isDark ? .dark : .light)
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
                .font(.system(size: 34, weight: .bold, design: design))
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
                    .font(.system(size: 14, weight: .heavy, design: design))
                    .tracking(1.5)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(moment.grade.color(on: theme).opacity(0.22), in: Capsule())
                    .foregroundStyle(moment.grade.color(on: theme))
                Spacer()
                if let piece = highlight.piece {
                    Label(piece, systemImage: "shield.lefthalf.filled")
                        .font(.system(size: 15, weight: .bold, design: design))
                        .foregroundStyle(theme.ink(for: reel.playerColor))
                        .lineLimit(1)
                }
                Text("Move \((moment.ply + 1) / 2)")
                    .font(.system(size: 15, weight: .semibold, design: design).monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            PositionBoard(draft: PositionDraft(fen: fen) ?? .empty, theme: theme,
                          flipped: reel.playerColor == .black, hints: arrow(for: moment, landed: landed))
                .aspectRatio(1, contentMode: .fit)
                .scaleEffect(landed ? 1 : 0.985)
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text(moment.san + glyph(moment.grade))
                    .font(.system(size: 40, weight: .heavy, design: design))
                    .foregroundStyle(landed ? moment.grade.color(on: theme) : .primary)
                Spacer()
                ReelEvalBar(chances: landed ? moment.after : moment.before, theme: theme)
                    .frame(width: 120, height: 10)
            }
            Text(highlight.line)
                .font(.system(size: 19, weight: .semibold, design: design))
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
            if highlight.kind == .blunder, let best = moment.best, landed {
                Text("\(best) was the move.")
                    .font(.system(size: 16, weight: .medium, design: design))
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
                .font(.system(size: 20, weight: .semibold, design: design))
                .multilineTextAlignment(.center)
            if let hero = reel.hero {
                VStack(spacing: 4) {
                    Text("PIECE OF THE MATCH")
                        .font(.system(size: 12, weight: .heavy, design: design))
                        .tracking(1.5)
                        .foregroundStyle(ArmyRank.gold)
                    Text(hero)
                        .font(.system(size: 17, weight: .semibold, design: design))
                        .multilineTextAlignment(.center)
                }
            }
            Text("Coached by Leo · Chess Game Killer")
                .font(.system(size: 14, weight: .medium, design: design))
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
            .font(.system(size: 22, weight: .black, design: design))
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
                .font(.system(size: 26, weight: .bold, design: design).monospacedDigit())
            Text(label)
                .font(.system(size: 13, weight: .medium, design: design))
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
                    .fill(theme.accent ?? .accentColor)
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
                    // The picture runs edge to edge; the wordmark waits below the island and the buttons.
                    ReelFrame(reel: reel, theme: theme, time: t, wordmarkTop: geo.safeAreaInsets.top + 62)
                        .onChange(of: cueIndex(at: t)) { _, index in speak(index) }
                }
                .ignoresSafeArea()
            }
            HStack(spacing: 4) {
                Button { stopVoice(); dismiss() } label: {
                    roundIcon("xmark")
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Close")
                Spacer()
                Button {
                    started = Date()
                    spoken = -1
                } label: {
                    roundIcon("arrow.counterclockwise")
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Play again")
                shareButton
            }
            .padding(.horizontal, 12)
            .padding(.top, 4)
        }
        .onAppear {
            // A victory theme still playing would talk over Leo.
            SoundPlayer.shared.stopAll(fade: 0.4)
            CoachVoice.shared.beginLesson()
            started = Date()
        }
        .onDisappear { stopVoice() }
        .alert("Couldn't make the video", isPresented: $exportFailed) {
            Button("Try again") { Task { await export() } }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Something went wrong while making it. The reel still plays here.")
        }
    }

    /// A 36 pt glass circle with a full 44 pt place to tap.
    private func roundIcon(_ symbol: String) -> some View {
        Image(systemName: symbol)
            .font(.system(size: 15, weight: .bold))
            .frame(width: 36, height: 36)
            .glassPane(Circle())
            .frame(width: 44, height: 44)
            .contentShape(Rectangle())
    }

    @ViewBuilder
    private var shareButton: some View {
        if let exported {
            ShareLink(item: exported, preview: SharePreview("My chess highlights")) {
                Label("Share", systemImage: "square.and.arrow.up")
                    .font(.system(size: 15, weight: .bold))
                    .padding(.horizontal, 14)
                    .frame(height: 36)
                    .background(theme.accent ?? .accentColor, in: Capsule())
                    .foregroundStyle(theme.isDark ? Color.black : Color.white)
                    .frame(height: 44)
                    .contentShape(Rectangle())
            }
        } else {
            Button {
                Task { await export() }
            } label: {
                HStack(spacing: 6) {
                    if exporting { ProgressView().controlSize(.small) }
                    Text(exporting ? "Making video…" : "Make video")
                }
                .font(.system(size: 15, weight: .bold))
                .padding(.horizontal, 14)
                .frame(height: 36)
                .glassPane(Capsule())
                .frame(height: 44)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(exporting)
        }
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
