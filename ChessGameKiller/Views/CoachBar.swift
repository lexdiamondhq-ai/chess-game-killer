import SwiftUI

/// The coach at the bottom of the screen: how good the last move was,
/// what would have been better, and the two best moves now.
struct CoachBar: View {
    let match: MatchController
    let theme: BoardTheme

    var body: some View {
        let tint = match.review?.grade.color ?? theme.accent ?? .accentColor
        VStack(alignment: .leading, spacing: 12) {
            verdict
            footer
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background { background(tint: tint) }
        .animation(.snappy(duration: 0.3), value: match.review)
        .animation(.snappy(duration: 0.3), value: match.hints)
        .animation(.snappy(duration: 0.3), value: match.isComputerThinking)
    }

    // MARK: Verdict on the last move

    @ViewBuilder
    private var verdict: some View {
        if let review = match.review {
            HStack(alignment: .center, spacing: 12) {
                GradeBadge(grade: review.grade, glows: theme.glows)
                VStack(alignment: .leading, spacing: 2) {
                    Text(review.title)
                        .font(.headline)
                        .foregroundStyle(review.grade.color)
                    Text(review.detail)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 4)
                if let evaluation = review.evaluation {
                    Text(evaluation.label)
                        .font(.system(.subheadline, design: .themed).weight(.bold).monospacedDigit())
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(review.grade.color.opacity(0.18), in: Capsule())
                        .accessibilityLabel("Score \(evaluation.label)")
                }
            }
            .id(review.id)
            .transition(.push(from: .bottom))
            .accessibilityElement(children: .combine)
        } else if match.engineFailed {
            message(symbol: "exclamationmark.triangle.fill", title: "Coach offline",
                    detail: "Stockfish didn't answer. Undo and try again, or play a friend.")
        } else {
            message(symbol: "sparkles", title: "Your coach",
                    detail: "Make a move and I'll tell you how good it was.")
        }
    }

    private func message(symbol: String, title: String, detail: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: symbol)
                .font(.title3)
                .foregroundStyle(theme.accent ?? .accentColor)
                .frame(width: 38, height: 38)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.headline)
                Text(detail).font(.subheadline).foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .combine)
    }

    // MARK: The two best moves now

    @ViewBuilder
    private var footer: some View {
        if match.isComputerThinking {
            HStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text("Computer is thinking")
                    .font(.footnote.weight(.medium))
                    .foregroundStyle(.secondary)
            }
            .transition(.opacity)
        } else if !match.hints.isEmpty {
            HStack(spacing: 16) {
                ForEach(match.hints) { hint in
                    HStack(spacing: 8) {
                        ArrowSample(color: hint.rank == 0 ? theme.bestArrow : theme.secondArrow, dashed: hint.rank != 0)
                        Text(hint.rank == 0 ? "Best" : "Next best")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                        Text(hint.san)
                            .font(.system(.footnote, design: .themed).weight(.bold))
                    }
                    .accessibilityElement(children: .combine)
                }
                Spacer(minLength: 0)
            }
            .transition(.opacity)
        }
    }

    // MARK: Background

    @ViewBuilder
    private func background(tint: Color) -> some View {
        let shape = RoundedRectangle(cornerRadius: 20, style: .continuous)
        if theme.isDark {
            shape
                .fill(.ultraThinMaterial)
                .overlay {
                    shape.strokeBorder(
                        LinearGradient(colors: [tint.opacity(0.9), tint.opacity(0.15)],
                                       startPoint: .topLeading, endPoint: .bottomTrailing),
                        lineWidth: 1
                    )
                }
                .shadow(color: tint.opacity(0.35), radius: 16)
        } else {
            shape
                .fill(Color(.secondarySystemGroupedBackground))
                .shadow(color: .black.opacity(0.08), radius: 10, y: 3)
        }
    }
}

/// A round badge for a move grade, like a star for the best move or "??" for a blunder.
struct GradeBadge: View {
    let grade: MoveReview.Grade
    var glows = false

    var body: some View {
        ZStack {
            Circle().fill(grade.color)
            switch grade.mark {
            case .symbol(let name):
                Image(systemName: name)
                    .font(.system(size: 17, weight: .bold))
            case .text(let text):
                Text(text)
                    .font(.system(size: 16, weight: .heavy, design: .themed))
            }
        }
        .foregroundStyle(.black.opacity(0.8))
        .frame(width: 38, height: 38)
        .shadow(color: glows ? grade.color.opacity(0.8) : .clear, radius: 8)
        .accessibilityHidden(true)
    }
}

/// A short line in the arrow's style, for the legend under the coach.
struct ArrowSample: View {
    let color: Color
    let dashed: Bool

    var body: some View {
        Path { path in
            path.move(to: CGPoint(x: 2, y: 5))
            path.addLine(to: CGPoint(x: 24, y: 5))
        }
        .stroke(color, style: StrokeStyle(lineWidth: dashed ? 3 : 4, lineCap: dashed ? .butt : .round,
                                          dash: dashed ? [5, 3] : []))
        .frame(width: 26, height: 10)
        .accessibilityHidden(true)
    }
}

extension MoveReview.Grade {
    enum Mark {
        case symbol(String)
        case text(String)
    }

    var color: Color {
        switch self {
        case .checkmate: return Color(hex: 0xFFD54A)
        case .best: return Color(hex: 0x3DFF9A)
        case .excellent: return Color(hex: 0x5BE0B0)
        case .good: return Color(hex: 0x8FD7FF)
        case .inaccuracy: return Color(hex: 0xF7D046)
        case .mistake: return Color(hex: 0xFF9A3C)
        case .blunder: return Color(hex: 0xFF4D6D)
        }
    }

    /// Chess's own marks where they exist: ?! inaccuracy, ? mistake, ?? blunder.
    var mark: Mark {
        switch self {
        case .checkmate: return .symbol("crown.fill")
        case .best: return .symbol("star.fill")
        case .excellent: return .symbol("hand.thumbsup.fill")
        case .good: return .symbol("checkmark")
        case .inaccuracy: return .text("?!")
        case .mistake: return .text("?")
        case .blunder: return .text("??")
        }
    }
}
