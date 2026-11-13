import SwiftUI

/// The gold bar at the top of the Aurora home's page, above Next game (Alex, 2026-11-13: "a
/// quick way to play a game" and "if I am playing against someone I see that it's my turn";
/// picked A, one gold bar). When a friend or someone online is waiting on your move, it says so
/// and opens that game. When nobody is, the same bar is Quick play: one tap starts the rival up
/// next at once, with no film (or picks up the game against them already under way).
struct HomeAuroraQuickBar: View {
    enum Mode: Equatable {
        /// A game against a person waits on your move; `more` others wait too.
        case yourMove(HomeCurrentGame, more: Int)
        /// Nobody waits on you: start (or pick up) the game against the rival up next.
        case quickPlay(rival: String, detail: String, resume: Bool)
    }

    let mode: Mode
    let palette: HomeAuroraPalette
    let action: () -> Void

    /// Your move first: the game against a person that waits on you, the oldest wait first
    /// (the list comes your move first). Games against the computer don't count here.
    static func mode(games: [HomeCurrentGame], upNext: HomeUpNext) -> Mode {
        let waiting: [HomeCurrentGame] = games.filter { $0.isYourMove && $0.friendGame != nil }
        if let first = waiting.first {
            return .yourMove(first, more: waiting.count - 1)
        }
        let clock: String = upNext.timeControl.isTimed ? upNext.timeControl.name : "No clock"
        let side: String = upNext.playerColor == .black ? "You're Black" : "You're White"
        return .quickPlay(rival: upNext.rival.name, detail: "\(clock) · \(side)", resume: upNext.inProgress)
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
            .overlay(shape.strokeBorder(palette.gold.opacity(isYourMove ? 0.75 : 0.45), lineWidth: isYourMove ? 1.5 : 1))
            .shadow(color: palette.gold.opacity(isYourMove ? 0.28 : 0.12), radius: 14, y: 6)
            .contentShape(shape)
        }
        .buttonStyle(HomeStagePress())
        .accessibilityElement(children: .combine)
        .accessibilityLabel(spoken)
        .accessibilityHint(isYourMove ? "Opens the game" : "Starts the game")
        .animation(.snappy, value: mode)
    }

    private var isYourMove: Bool {
        if case .yourMove = mode { return true }
        return false
    }

    private var title: String {
        switch mode {
        case .yourMove(let game, _): return game.title
        case .quickPlay(let rival, _, let resume): return resume ? "Back to \(rival)" : "Quick play"
        }
    }

    private var detail: String {
        switch mode {
        case .yourMove(let game, let more): return Self.detail(game, more: more)
        case .quickPlay(let rival, let detail, let resume):
            // The rival's name fills the line, so Quick play keeps only the clock beside it:
            // "vs The Berserker · No clock" (the side was cut short on a phone).
            let clock: String = detail.components(separatedBy: " · ").first ?? detail
            return resume ? detail : "vs \(rival) · \(clock)"
        }
    }

    private var spoken: String {
        switch mode {
        case .yourMove: return "Your move, \(title), \(detail)"
        case .quickPlay: return "\(title), \(detail)"
        }
    }

    @ViewBuilder
    private var eyebrow: some View {
        if isYourMove {
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
    }

    /// The game's board in a small gold frame, or a gold bolt for Quick play.
    @ViewBuilder
    private var badge: some View {
        switch mode {
        case .yourMove(let game, _):
            let side: CGFloat = 60
            let pad: CGFloat = side * 0.055
            HomeAuroraBoard(fen: game.fen, flipped: game.flipped, lit: true)
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
        case .quickPlay(_, _, let resume):
            Image(systemName: resume ? "play.fill" : "bolt.fill")
                .font(.system(size: 20, weight: .bold))
                .foregroundStyle(Color(hex: 0x2A1E0F))
                .frame(width: 46, height: 46)
                .background(Circle().fill(HomeAuroraPalette.goldButton))
                .shadow(color: palette.gold.opacity(0.35), radius: 8, y: 4)
                .accessibilityHidden(true)
        }
    }

    private var button: some View {
        let words: String = isYourMove ? "Move" : "Play"
        return HStack(spacing: 5) {
            Text(words)
                .font(.system(size: 13.5, weight: .bold))
            Image(systemName: isYourMove ? "arrow.right" : "play.fill")
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
