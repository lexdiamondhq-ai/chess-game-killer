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
    @ViewBuilder let status: () -> Status

    @AppStorage("rivalBanter") private var banterOn = true

    var body: some View {
        ZStack(alignment: .leading) {
            if isRival, banterOn, let line = match.rivalLine {
                Text("\u{201C}\(line.text)\u{201D}")
                    .font(.app(.footnote, weight: .medium))
                    .italic()
                    .foregroundStyle(Color.primary.opacity(0.72))
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                    .id("rival-\(line.id)")
                    .transition(.opacity.combined(with: .offset(y: 3)))
                    .accessibilityLabel("\(match.setup.level.rival.name) says: \(line.text)")
            } else if !isRival, let verdict = match.verdictLine {
                VerdictLine(review: verdict, theme: theme)
                    .id("verdict-\(verdict.id)")
                    .transition(.opacity.combined(with: .offset(y: 3)))
            } else {
                status()
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.3), value: isRival ? match.rivalLine?.id : match.verdictLine?.id)
        .onChange(of: match.rivalLine?.id) { _, id in
            // VoiceOver hears each remark once, as it is made.
            guard isRival, banterOn, id != nil, let line = match.rivalLine else { return }
            AccessibilityNotification.Announcement("\(match.setup.level.rival.name): \(line.text)").post()
        }
    }
}

/// The coach's verdict in a few words, like "Mistake · Nc3 was better", led by the grade's color.
private struct VerdictLine: View {
    let review: MoveReview
    let theme: BoardTheme

    var body: some View {
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
