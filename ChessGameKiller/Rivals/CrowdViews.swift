import SwiftUI

/// The Crowd picked: hundreds of gold dots rush in from everywhere and settle into a ring, a
/// few hundred real players behind each one. Picking another crowd scatters them and they
/// regroup, more of them for a stronger crowd. With Reduce Motion on, the ring simply appears.
struct CrowdSwarm: View {
    let rival: Rival
    var size: CGFloat = 100
    /// Flipping it to true sends the dots out and back in again: the crowd just picked.
    var picked = false

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var startedAt = Date()
    @State private var running = true

    /// More players, more dots.
    private var count: Int { 40 + rival.strength * 22 }

    var body: some View {
        TimelineView(.animation(paused: reduceMotion || !running)) { timeline in
            Canvas { context, canvas in
                let elapsed = reduceMotion ? 10 : timeline.date.timeIntervalSince(startedAt)
                draw(in: &context, size: canvas, elapsed: elapsed)
            }
        }
        .frame(width: size, height: size)
        .background {
            Circle()
                .fill(RadialGradient(colors: [rival.hue.opacity(0.16), .clear], center: .center,
                                     startRadius: 0, endRadius: size * 0.5))
        }
        .task(id: "\(rival.slug)-\(picked)") {
            // The dots stop moving once every one has landed, so a still sheet costs nothing.
            startedAt = Date()
            running = true
            try? await Task.sleep(for: .seconds(2))
            running = false
        }
        .accessibilityHidden(true)
    }

    private func draw(in context: inout GraphicsContext, size canvas: CGSize, elapsed: Double) {
        let side = min(canvas.width, canvas.height)
        let center = CGPoint(x: canvas.width / 2, y: canvas.height / 2)
        var seed: UInt64 = 0x51_7CC1 &+ UInt64(rival.strength)
        for _ in 0..<count {
            let angle = CrowdRing.next(&seed) * .pi * 2
            let reach = 0.27 + pow(CrowdRing.next(&seed), 0.7) * 0.2
            let dotRadius = side * (0.7 + CrowdRing.next(&seed) * 0.8) / 100
            let fromAngle = CrowdRing.next(&seed) * .pi * 2
            let fromReach = 0.9 + CrowdRing.next(&seed) * 0.6
            let delay = CrowdRing.next(&seed) * 0.45
            let alpha = 0.45 + CrowdRing.next(&seed) * 0.55
            let t = min(1, max(0, (elapsed - delay) / 1.1))
            let eased = 1 - pow(1 - t, 3)
            let target = CGPoint(x: center.x + cos(angle) * side * reach, y: center.y + sin(angle) * side * reach)
            let start = CGPoint(x: center.x + cos(fromAngle) * side * fromReach,
                                y: center.y + sin(fromAngle) * side * fromReach)
            let point = CGPoint(x: start.x + (target.x - start.x) * eased, y: start.y + (target.y - start.y) * eased)
            let dot = CGRect(x: point.x - dotRadius, y: point.y - dotRadius, width: dotRadius * 2, height: dotRadius * 2)
            context.fill(Path(ellipseIn: dot), with: .color(rival.hue.opacity(alpha * (0.3 + 0.7 * eased))))
        }
    }
}

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

#Preview("Swarm") {
    HStack {
        CrowdSwarm(rival: MatchController.Level.beginner.rival)
        CrowdSwarm(rival: MatchController.Level.grandmaster.rival)
    }
    .padding()
    .background(Color.black)
}
