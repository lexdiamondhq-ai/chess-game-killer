import SwiftUI

/// The vote behind the crowd's last move, in the rival's line: a small gold bar and
/// "62% played Nf3". The bar fills as it appears.
struct CrowdVoteLine: View {
    let vote: CrowdVote
    let crowd: String
    let theme: BoardTheme

    @State private var filled = false

    private var gold: Color { theme.accent ?? Color(hex: 0xD6B26A) }

    var body: some View {
        HStack(spacing: 7) {
            Capsule()
                .fill(Color.primary.opacity(0.12))
                .frame(width: 34, height: 5)
                .overlay(alignment: .leading) {
                    Capsule()
                        .fill(gold)
                        .frame(width: 34 * (filled ? vote.share : 0), height: 5)
                }
            Text("\(vote.percent) played \(vote.san)")
                .font(.app(.footnote, weight: .medium).monospacedDigit())
                .foregroundStyle(Color.primary.opacity(0.72))
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
        .onAppear {
            withAnimation(.spring(response: 0.7, dampingFraction: 0.85).delay(0.1)) { filled = true }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(vote.percent) of \(crowd) played \(vote.san)")
    }
}
