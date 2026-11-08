import Accessibility
import SwiftUI

/// A quiet word written into a player's line under their name, in place of the status, for a
/// few seconds: the rival's remark in the rival's line, the coach's verdict on the person's last
/// move in theirs. Nothing pops up over the board or the dock, so it never gets in the way of a
/// move. The match decides what shows and for how long, so a line that is drawn again (the coach
/// opening, the summary closing) never replays an old remark.
struct PlateRemark<Status: View>: View {
    let match: MatchController
    let theme: BoardTheme
    /// The rival's line shows its remarks; the person's line shows the coach's verdicts.
    let isRival: Bool
    /// In the game's dock, where the line is short: the coach's verdict stacks its grade over
    /// its advice, so neither is cut (Alex, 2026-11-07).
    var stacked = false
    /// The rival's line is drawn larger than the person's (Alex, 2026-11-08).
    var scale: CGFloat = 1
    @ViewBuilder let status: () -> Status

    @AppStorage("rivalBanter") private var banterOn = true

    var body: some View {
        ZStack(alignment: .leading) {
            if isRival, banterOn, let line = match.rivalLine {
                Text("\u{201C}\(line.text)\u{201D}")
                    .font(.app(.footnote, weight: .medium, scale: scale))
                    .italic()
                    .foregroundStyle(Color.primary.opacity(0.72))
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                    .id("rival-\(line.id)")
                    .transition(.opacity.combined(with: .offset(y: 3)))
                    .accessibilityLabel("\(match.setup.rival.name) says: \(line.text)")
            } else if isRival, let vote = shownVote {
                CrowdVoteLine(vote: vote, crowd: "players rated \(match.setup.rival.spokenElo)", theme: theme, scale: scale)
                    .id("vote-\(match.game.plyCount)")
                    .transition(.opacity.combined(with: .offset(y: 3)))
            } else if !isRival, let verdict = match.verdictLine {
                VerdictLine(review: verdict, theme: theme, stacked: stacked)
                    .id("verdict-\(verdict.id)")
                    .transition(.opacity.combined(with: .offset(y: 3)))
            } else {
                status()
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.3), value: isRival ? match.rivalLine?.id : match.verdictLine?.id)
        .animation(.easeInOut(duration: 0.3), value: shownVote)
        .onChange(of: match.rivalLine?.id) { _, id in
            // VoiceOver hears each remark once, as it is made.
            guard isRival, banterOn, id != nil, let line = match.rivalLine else { return }
            AccessibilityNotification.Announcement("\(match.setup.rival.name): \(line.text)").post()
        }
    }
}

extension PlateRemark {
    /// The vote behind the crowd's last move, while it is your turn to answer it.
    private var shownVote: CrowdVote? {
        guard !match.isOver, !match.isComputerThinking, match.game.isHumanTurn else { return nil }
        return match.crowdVote
    }
}

/// The coach's verdict in a few words, like "Mistake · Nc3 was better", led by the grade's color.
private struct VerdictLine: View {
    let review: MoveReview
    let theme: BoardTheme
    var stacked = false

    var body: some View {
        if stacked { stackedLines } else { oneLine }
    }

    /// The grade in bold in its color, the better move under it.
    private var stackedLines: some View {
        VStack(alignment: .leading, spacing: 1) {
            HStack(spacing: 6) {
                Circle()
                    .fill(review.grade.color(on: theme))
                    .frame(width: 6, height: 6)
                Text(review.title)
                    .font(.app(.subheadline, weight: .bold))
                    .foregroundStyle(review.grade.color(on: theme))
            }
            if let advice {
                Text(advice.replacingOccurrences(of: "· ", with: ""))
                    .font(.app(.caption, weight: .medium))
                    .foregroundStyle(Color.primary.opacity(0.72))
            }
        }
        .lineLimit(1)
        .minimumScaleFactor(0.8)
        .fixedSize(horizontal: false, vertical: true)
        .accessibilityElement(children: .combine)
    }

    private var oneLine: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(review.grade.color(on: theme))
                .frame(width: 6, height: 6)
            Text(review.title)
                .font(.app(.footnote, weight: .semibold))
                .foregroundStyle(review.grade.color(on: theme))
            if let advice {
                Text(advice)
                    .font(.app(.footnote))
                    .foregroundStyle(Color.primary.opacity(0.72))
            }
        }
        .lineLimit(1)
        .minimumScaleFactor(0.75)
        .accessibilityElement(children: .combine)
    }

    /// What would have been better, for the grades that cost something.
    private var advice: String? {
        guard let best = review.best else { return nil }
        switch review.grade {
        case .inaccuracy, .mistake: return "· \(best) was better"
        case .blunder: return "· \(best) was the move"
        case .checkmate, .best, .excellent, .good: return nil
        }
    }
}
