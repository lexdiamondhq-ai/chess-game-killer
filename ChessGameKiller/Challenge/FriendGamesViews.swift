import SwiftUI

// The friend games on this phone, as rows: "vs Sam · Your move", "Their move", an open
// challenge, "You won · Checkmate". Tap one to open it; swipe a finished one away.
// The accent is the surrounding tint, so the rows take the one accent of wherever they sit.

/// Under the composer's form: every friend game on this phone, in a glass card.
struct FriendGamesList: View {
    let theme: BoardTheme

    @Environment(ChallengeCenter.self) private var center

    var body: some View {
        let games = center.store.sorted
        if !games.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                ChallengeSectionTitle(title: "Friend games")
                FriendGamesRows(games: games, design: theme.challengeDesign,
                                open: { center.play($0) }, remove: { center.remove($0) })
                    .challengeGlass(RoundedRectangle(cornerRadius: FriendGamesRows.radius, style: .continuous))
            }
            .task { await center.refreshGames() }
        }
    }
}

/// For the home screen: the friend games still going and the latest results, a few at a time.
/// Shows nothing when there are none, or when the app has no Challenge a friend in its environment.
struct FriendGamesCard: View {
    /// How many games show before "Show all".
    var limit = 4
    /// False leaves the rows bare, for a card of the caller's own.
    var drawsCard = true
    var design: Font.Design = .default

    @Environment(ChallengeCenter.self) private var center: ChallengeCenter?
    @State private var showsAll = false

    var body: some View {
        if let center, !center.store.games.isEmpty {
            card(center)
                .task { await center.refreshGames() }
        }
    }

    @ViewBuilder
    private func card(_ center: ChallengeCenter) -> some View {
        if drawsCard {
            rows(center)
                .challengeGlass(RoundedRectangle(cornerRadius: FriendGamesRows.radius, style: .continuous))
        } else {
            rows(center)
        }
    }

    private func rows(_ center: ChallengeCenter) -> some View {
        let games = center.store.sorted
        let shown = showsAll ? games : Array(games.prefix(limit))
        return VStack(spacing: 0) {
            FriendGamesRows(games: shown, design: design,
                            open: { center.play($0) }, remove: { center.remove($0) })
            if games.count > limit {
                FriendGamesRows.hairline
                Button {
                    withAnimation(.snappy(duration: 0.3)) { showsAll.toggle() }
                } label: {
                    Text(showsAll ? "Show fewer" : "Show all \(games.count)")
                        .font(.app(size: 15, weight: .semibold))
                        .foregroundStyle(.tint)
                        .frame(maxWidth: .infinity, minHeight: 48)
                        .contentShape(Rectangle())
                }
                .buttonStyle(FriendRowPressStyle())
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: FriendGamesRows.radius, style: .continuous))
    }
}

/// Friend games one under another, with hairlines between. One row at a time shows its Remove button.
struct FriendGamesRows: View {
    let games: [FriendGame]
    var design: Font.Design = .default
    let open: (FriendGame) -> Void
    let remove: (FriendGame) -> Void

    /// The code of the row swiped open.
    @State private var revealed: String? = nil

    static let radius: CGFloat = 20

    static var hairline: some View {
        Rectangle()
            .fill(Color.white.opacity(0.08))
            .frame(height: 0.5)
            .padding(.leading, 64)
    }

    var body: some View {
        VStack(spacing: 0) {
            ForEach(games, id: \.code) { game in
                FriendGameSwipeRow(game: game, design: design, revealed: $revealed,
                                   open: { open(game) }, remove: { remove(game) })
                if game.code != games.last?.code {
                    Self.hairline
                }
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: Self.radius, style: .continuous))
    }
}

/// One friend game: who, whose move or how it ended, and the clock.
struct FriendGameRow: View {
    let game: FriendGame
    var design: Font.Design = .default
    let open: () -> Void

    var body: some View {
        Button(action: open) {
            HStack(spacing: 12) {
                badge
                VStack(alignment: .leading, spacing: 2) {
                    Text(game.title)
                        .font(.app(size: 16, weight: .semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                    Text(game.statusLine)
                        .font(.app(size: 13, weight: game.isYourMove ? .semibold : .medium))
                        .foregroundStyle(game.isYourMove ? AnyShapeStyle(.tint) : AnyShapeStyle(.secondary))
                        .lineLimit(1)
                        .minimumScaleFactor(0.85)
                }
                Spacer(minLength: 8)
                Text(game.clock?.label ?? "No clock")
                    .font(.app(size: 13, weight: .medium).monospacedDigit())
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity, minHeight: 64, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(FriendRowPressStyle())
        .accessibilityLabel("\(game.title), \(game.statusLine), \(game.clock?.label ?? "No clock")")
    }

    /// The friend's initial; a paper plane while the link is out.
    private var badge: some View {
        ZStack {
            Circle()
                .fill(.tint)
                .opacity(game.isOver ? 0.1 : 0.22)
            Circle()
                .strokeBorder(Color.white.opacity(0.14), lineWidth: 0.75)
            if game.status == .waiting {
                Image(systemName: "paperplane.fill")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.tint)
            } else {
                Text(initial)
                    .font(.app(size: 16, weight: .semibold))
                    .foregroundStyle(game.isOver ? Color.secondary : Color.primary)
            }
        }
        .frame(width: 38, height: 38)
        .overlay(alignment: .topTrailing) {
            if game.isYourMove {
                Circle()
                    .fill(.tint)
                    .frame(width: 10, height: 10)
                    .overlay { Circle().strokeBorder(Color.black.opacity(0.5), lineWidth: 1.5) }
                    .offset(x: 2, y: -2)
            }
        }
        .accessibilityHidden(true)
    }

    private var initial: String {
        guard let first = game.opponentName?.trimmingCharacters(in: .whitespacesAndNewlines).first else { return "?" }
        return String(first).uppercased()
    }
}

/// A row lights up a little while pressed.
struct FriendRowPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(Color.white.opacity(configuration.isPressed ? 0.07 : 0))
            .animation(.easeOut(duration: 0.15), value: configuration.isPressed)
    }
}

/// A row that a finished game can be swiped off: a short swipe shows Remove, a long one removes it.
private struct FriendGameSwipeRow: View {
    let game: FriendGame
    let design: Font.Design
    @Binding var revealed: String?
    let open: () -> Void
    let remove: () -> Void

    @State private var offset: CGFloat = 0
    @State private var resting: CGFloat = 0
    @State private var axis: Axis? = nil
    @State private var lastSwipe = Date.distantPast
    @State private var width: CGFloat = 320

    /// How far a short swipe opens the row.
    private static let reveal: CGFloat = 84

    var body: some View {
        if game.isOver {
            row
                .simultaneousGesture(drag)
                .contentShape(.contextMenuPreview, RoundedRectangle(cornerRadius: 16, style: .continuous))
                .contextMenu {
                    Button(role: .destructive, action: removeNow) {
                        Label("Remove", systemImage: "trash")
                    }
                }
                .accessibilityAction(named: "Remove", removeNow)
        } else {
            row
        }
    }

    private var row: some View {
        FriendGameRow(game: game, design: design, open: tapped)
            .offset(x: offset)
            .background(alignment: .trailing) {
                if offset < 0 {
                    removeButton
                }
            }
            .onGeometryChange(for: CGFloat.self) { proxy in
                proxy.size.width
            } action: { new in
                width = new
            }
            .onChange(of: revealed) { _, code in
                if code != game.code, resting != 0 { settle(at: 0) }
            }
    }

    private var removeButton: some View {
        Button(action: removeNow) {
            Image(systemName: "trash.fill")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(.white)
                .opacity(-offset > 44 ? 1 : 0)
                .frame(width: max(-offset, 0))
                .frame(maxHeight: .infinity)
                .background(ChallengeColors.urgent)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Remove")
    }

    private var drag: some Gesture {
        DragGesture(minimumDistance: 14)
            .onChanged { value in
                let dx = value.translation.width
                let dy = value.translation.height
                if axis == nil {
                    axis = abs(dx) > abs(dy) * 1.2 ? Axis.horizontal : Axis.vertical
                }
                guard axis == .horizontal else { return }
                lastSwipe = .now
                let x = resting + dx
                // Past the closed position it gives only a little.
                offset = x > 0 ? x / 5 : x
            }
            .onEnded { value in
                defer { axis = nil }
                guard axis == .horizontal else { return }
                lastSwipe = .now
                let now = resting + value.translation.width
                let projected = resting + value.predictedEndTranslation.width
                if -now > max(width * 0.5, Self.reveal * 1.6) || -projected > width * 0.8 {
                    removeNow()
                } else if -projected > Self.reveal * 0.6 {
                    settle(at: -Self.reveal)
                } else {
                    settle(at: 0)
                }
            }
    }

    private func settle(at x: CGFloat) {
        withAnimation(.snappy(duration: 0.28)) { offset = x }
        resting = x
        if x != 0 {
            revealed = game.code
        } else if revealed == game.code {
            revealed = nil
        }
    }

    private func tapped() {
        // A tap on a row swiped open closes it; the end of a swipe isn't a tap.
        if resting != 0 || offset != 0 {
            settle(at: 0)
            return
        }
        guard Date.now.timeIntervalSince(lastSwipe) > 0.3 else { return }
        open()
    }

    private func removeNow() {
        withAnimation(.snappy(duration: 0.22)) { offset = -max(width, 320) }
        resting = 0
        if revealed == game.code { revealed = nil }
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(180))
            withAnimation(.snappy(duration: 0.3)) { remove() }
        }
    }
}
