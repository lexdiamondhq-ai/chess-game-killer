import SwiftUI

/// The gold "Your move" bar at the top of the Aurora home's page, above Next game (Alex,
/// 2026-11-13: "if I am playing against someone I see that it's my turn"; picked A, one gold
/// bar). It shows only while a friend or someone online waits on your move, and opens that game.
/// It used to turn into Quick play when nobody waited; that is gone (Alex, 2026-11-25: "Since play
/// is a part of the lower right, maybe we should remove the top quick plays"; picked A), since the
/// gold Play coin in the bottom bar opens Quick play.
struct HomeAuroraQuickBar: View {
    enum Mode: Equatable {
        /// A game against a person waits on your move; `more` others wait too.
        case yourMove(HomeCurrentGame, more: Int)
    }

    let mode: Mode
    let palette: HomeAuroraPalette
    let action: () -> Void

    /// The game against a person that waits on you, the oldest wait first (the list comes your
    /// move first), or nil when nobody waits and the bar stays hidden. Games against the computer
    /// don't count here.
    static func mode(games: [HomeCurrentGame]) -> Mode? {
        let waiting: [HomeCurrentGame] = games.filter { $0.isYourMove && $0.friendGame != nil }
        guard let first = waiting.first else { return nil }
        return .yourMove(first, more: waiting.count - 1)
    }

    /// "Friend · 1d 4h left · +1 more", "Online · 1500 · +2 more".
    static func detail(_ game: HomeCurrentGame, more: Int) -> String {
        var parts: [String] = [game.kind == .online ? "Online" : "Friend"]
        if let deadline = game.friendGame?.deadline {
            parts.append("\(DailyDays.left(deadline.timeIntervalSinceNow * 1000)) left")
        } else if let clock = game.friendGame?.clock?.label {
            parts.append(clock)
        }
        if more > 0 { parts.append("+\(more) more") }
        return parts.joined(separator: " · ")
    }

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 22, style: .continuous)
        Button(action: action) {
            HStack(spacing: 12) {
                badge
                VStack(alignment: .leading, spacing: 2) {
                    eyebrow
                    Text(title)
                        .font(.system(size: 21, weight: .regular, design: .serif))
                        .foregroundStyle(palette.ink)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                    Text(detail)
                        .font(.system(size: 12.5))
                        .foregroundStyle(palette.ink2)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
                Spacer(minLength: 0)
                button
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity, minHeight: 84)
            .background(shape.fill(palette.card))
            .background {
                // A warm gold wash across the bar.
                LinearGradient(colors: [palette.gold.opacity(palette.dark ? 0.2 : 0.16),
                                        palette.gold.opacity(palette.dark ? 0.06 : 0.04)],
                               startPoint: .topLeading, endPoint: .bottomTrailing)
                    .clipShape(shape)
                    .allowsHitTesting(false)
            }
            .overlay {
                if Polish.level == .off {
                    shape.strokeBorder(palette.gold.opacity(0.75), lineWidth: 1.5)
                } else {
                    // Your move: the brightest edge on the page.
                    PolishedEdge(shape: shape, edge: .lit, dark: palette.dark)
                }
            }
            .shadow(color: palette.gold.opacity(Polish.pick(0.28, 0.3, 0.36, 0.46)), radius: 14, y: 6)
            .contentShape(shape)
        }
        .buttonStyle(HomeStagePress())
        .accessibilityElement(children: .combine)
        .accessibilityLabel(spoken)
        .accessibilityHint("Opens the game")
        .animation(.snappy, value: mode)
    }

    private var game: HomeCurrentGame {
        switch mode { case .yourMove(let game, _): return game }
    }

    private var title: String { game.title }

    private var detail: String {
        switch mode { case .yourMove(let game, let more): return Self.detail(game, more: more) }
    }

    private var spoken: String { "Your move, \(title), \(detail)" }

    private var eyebrow: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(palette.rose)
                .frame(width: 7, height: 7)
                .background(Circle().fill(palette.rose.opacity(0.22)).frame(width: 13, height: 13))
            Text("YOUR MOVE")
                .font(.system(size: 10, weight: .bold))
                .tracking(1.4)
                .foregroundStyle(palette.gold)
        }
    }

    /// The game's board in a small gold frame.
    private var badge: some View {
        let side: CGFloat = 60
        let pad: CGFloat = side * 0.055
        return HomeAuroraBoard(fen: game.fen, flipped: game.flipped, lit: true)
            .frame(width: side - 2 * pad, height: side - 2 * pad)
            .padding(pad)
            .background(
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .fill(LinearGradient(stops: [.init(color: Color(hex: 0xF3D99A), location: 0),
                                                 .init(color: Color(hex: 0x9C6B2C), location: 0.45),
                                                 .init(color: Color(hex: 0xE9C47C), location: 0.7),
                                                 .init(color: Color(hex: 0x7E5520), location: 1)],
                                         startPoint: .topLeading, endPoint: .bottomTrailing))
            )
            .shadow(color: .black.opacity(0.35), radius: 8, y: 5)
            .accessibilityHidden(true)
    }

    private var button: some View {
        HStack(spacing: 5) {
            Text("Move")
                .font(.system(size: 13.5, weight: .bold))
            Image(systemName: "arrow.right")
                .font(.system(size: 10.5, weight: .bold))
        }
        .foregroundStyle(Color(hex: 0x2A1E0F))
        .padding(.horizontal, 14)
        .frame(height: 34)
        .background(Capsule().fill(HomeAuroraPalette.goldButton))
        .layoutPriority(1)
        .accessibilityHidden(true)
    }
}
