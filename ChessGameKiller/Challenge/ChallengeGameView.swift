import ChessKit
import SwiftUI
import UIKit

/// A friend game: the friend above the board and you below it, as in the app's executive look,
/// under a slim glass bar and over a glass dock (Offer draw, Resign, Flip). Before the friend joins
/// it is the lobby, waiting with the code; once over, the end card with Rematch.
/// No hints, no coach, no analysis and no undo: a fair game.
struct ChallengeGameView: View {
    let game: OnlineGame
    let theme: BoardTheme

    @Environment(ChallengeCenter.self) private var center
    @AppStorage("sculpted3D") private var sculpted3D = true
    @AppStorage("haptics") private var hapticsOn = true
    @State private var confirming: Confirmation?
    @State private var copied = false

    enum Confirmation: Identifiable {
        case resign, abort, leave, cancelChallenge

        var id: Self { self }
    }

    private static let spacing: CGFloat = 12
    private static let plateHeight: CGFloat = 50
    private static let ribbonHeight: CGFloat = 24
    /// As on the game screen: the board stops growing here, and so does the column around it.
    private static let maxBoardSide: CGFloat = 680

    var body: some View {
        Group {
            if game.phase == .loading {
                loading
            } else {
                GeometryReader { geo in
                    layout(in: geo.size)
                }
                .padding(.horizontal, 12)
            }
        }
        .overlay(alignment: .top) {
            notices
        }
        .safeAreaInset(edge: .top, spacing: 8) {
            topBar
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            foot
        }
        .confirmationDialog(confirmTitle, isPresented: confirmingBinding, titleVisibility: .visible,
                            presenting: confirming) { item in
            confirmActions(item)
        } message: { item in
            Text(confirmMessage(item))
        }
        .sensoryFeedback(.warning, trigger: game.toast?.id) { _, _ in
            hapticsOn && game.toast?.isWarning == true
        }
        .sensoryFeedback(.success, trigger: game.phase) { old, new in
            hapticsOn && old == .waiting && new == .playing
        }
        .animation(.snappy(duration: 0.35), value: game.phase)
        .onAppear { game.refreshIdleTimer() }
    }

    // MARK: Layout

    /// Which side sits at the top of the board: Black from White's side, and the other way round.
    private var topSeat: FriendSeat { game.match.isBoardFlipped ? .white : .black }

    private func layout(in size: CGSize) -> some View {
        let aspect = BoardView.aspect(theme, setting: sculpted3D)
        let spare = size.height - Self.plateHeight * 2 - Self.ribbonHeight - Self.spacing * 5
        let width = max(0, min(size.width, spare * aspect, Self.maxBoardSide))
        return VStack(spacing: Self.spacing) {
            Spacer(minLength: 0)
            FriendPlate(game: game, seat: topSeat, theme: theme)
                .frame(height: Self.plateHeight)
            BoardView(match: game.match, theme: theme)
                .frame(width: width, height: width / aspect)
            FriendPlate(game: game, seat: topSeat.opposite, theme: theme)
                .frame(height: Self.plateHeight)
            MoveRibbon(moves: game.ribbon, theme: theme)
                .frame(height: Self.ribbonHeight)
            Spacer(minLength: 0)
        }
        .frame(maxWidth: Self.maxBoardSide)
        .frame(maxWidth: .infinity)
        .animation(.snappy(duration: 0.45), value: topSeat)
    }

    private var loading: some View {
        VStack(spacing: 16) {
            if let problem = game.loadProblem {
                Image(systemName: "wifi.exclamationmark")
                    .font(.system(size: 24, weight: .semibold))
                    .foregroundStyle(theme.challengeAccent)
                    .frame(width: 64, height: 64)
                    .challengeGlass(Circle())
                Text(problem)
                    .font(theme.challengeFont(16, .medium))
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                Button("Try again") {
                    Task { await game.refresh() }
                }
                .buttonStyle(ChallengeButtonStyle(kind: .glass, theme: theme, height: 46))
                .frame(maxWidth: 220)
            } else {
                ProgressView()
                    .controlSize(.large)
                Text("Opening the game…")
                    .font(theme.challengeFont(15))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: The bar across the top

    private var topBar: some View {
        ChallengeTopBar(title: game.title, detail: connectionDetail, theme: theme, close: close) {
            Menu {
                Button {
                    UIPasteboard.general.string = ChallengeLink.inviteURL(for: game.code).absoluteString
                } label: {
                    Label("Copy link", systemImage: "link")
                }
                Button {
                    ChallengeSharing.shared.share(invite) { _ in }
                } label: {
                    Label("Share link", systemImage: "square.and.arrow.up")
                }
                Button {
                    withAnimation(.snappy) { game.match.flipBoard() }
                } label: {
                    Label("Flip board", systemImage: "arrow.up.arrow.down")
                }
            } label: {
                ChallengeBarIcon(symbol: "ellipsis")
            }
            .accessibilityLabel("More")
        }
        .padding(.horizontal, 12)
        .padding(.top, 4)
    }

    private var connectionDetail: String? {
        switch game.connection {
        case .offline: return "Reconnecting…"
        case .elsewhere: return "Open somewhere else"
        case .connecting, .live: return nil
        }
    }

    private var invite: ChallengeInviteContent {
        ChallengeInviteContent(game: game.record, name: center.playerName)
    }

    // MARK: Banners and toasts

    private var notices: some View {
        VStack(spacing: 8) {
            if game.cameBack {
                banner(symbol: "exclamationmark.triangle.fill", text: "You left the game. Leaving for 20 seconds forfeits.",
                       urgent: true) {
                    game.dismissCameBack()
                }
                .transition(.move(edge: .top).combined(with: .opacity))
            }
            if game.connection == .elsewhere {
                HStack(spacing: 10) {
                    Image(systemName: "rectangle.on.rectangle")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(theme.challengeAccent)
                    Text("This game is open somewhere else.")
                        .font(theme.challengeFont(14, .medium))
                        .lineLimit(2)
                    Spacer(minLength: 4)
                    Button("Play here") {
                        game.playHere()
                    }
                    .font(theme.challengeFont(14, .semibold))
                    .foregroundStyle(theme.challengeAccent)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 11)
                .challengeGlass(Capsule(style: .continuous))
                .transition(.move(edge: .top).combined(with: .opacity))
            }
            if let toast = game.toast {
                ChallengeToastView(toast: toast, theme: theme)
                    .id(toast.id)
                    .onTapGesture { game.dismissToast() }
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 4)
        .frame(maxWidth: 560)
        .animation(.spring(response: 0.4, dampingFraction: 0.86), value: game.toast?.id)
        .animation(.spring(response: 0.4, dampingFraction: 0.86), value: game.cameBack)
        .animation(.spring(response: 0.4, dampingFraction: 0.86), value: game.connection)
    }

    private func banner(symbol: String, text: String, urgent: Bool, dismiss: @escaping () -> Void) -> some View {
        Button(action: dismiss) {
            HStack(spacing: 10) {
                Image(systemName: symbol)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(urgent ? ChallengeColors.urgent : theme.challengeAccent)
                Text(text)
                    .font(theme.challengeFont(14, .medium))
                    .foregroundStyle(.primary)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 11)
            .challengeGlass(Capsule(style: .continuous))
        }
        .buttonStyle(ChallengePressStyle())
        .accessibilityHint("Dismisses this message")
    }

    // MARK: The foot

    /// The dock keeps its place in every phase, so the board never jumps; the lobby and end cards
    /// rise over it from the bottom.
    private var foot: some View {
        dock
            .opacity(game.phase == .playing ? 1 : 0)
            .allowsHitTesting(game.phase == .playing)
            .overlay(alignment: .top) {
                if game.drawOfferedToMe {
                    drawBanner
                        .fixedSize(horizontal: false, vertical: true)
                        .alignmentGuide(.top) { $0[.bottom] + 10 }
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .overlay(alignment: .bottom) {
                Group {
                    if game.phase == .waiting {
                        lobbyCard
                    } else if game.phase == .over {
                        endCard
                    }
                }
                .fixedSize(horizontal: false, vertical: true)
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
            .animation(.spring(response: 0.42, dampingFraction: 0.86), value: game.drawOfferedToMe)
            .animation(.spring(response: 0.42, dampingFraction: 0.86), value: game.phase)
    }

    private var dock: some View {
        HStack(spacing: 0) {
            DockButton(title: drawTitle, symbol: "equal.circle", isOn: game.drawOfferedByMe, theme: theme) {
                Task {
                    if game.drawOfferedToMe { await game.acceptDraw() } else { await game.offerDraw() }
                }
            }
            .disabled(game.drawOfferedByMe || game.sending != nil)
            DockButton(title: game.canAbort ? "Abort" : "Resign", symbol: "flag", theme: theme) {
                confirming = game.canAbort ? .abort : .resign
            }
            .disabled(game.sending != nil)
            DockButton(title: "Flip", symbol: Glyphs.flip, theme: theme) {
                withAnimation(.snappy) { game.match.flipBoard() }
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .challengeGlass(Capsule(style: .continuous))
        .frame(maxWidth: 520)
        .padding(.horizontal, 16)
        .padding(.top, 6)
        .padding(.bottom, 6)
    }

    private var drawTitle: String {
        if game.drawOfferedByMe { return "Draw offered" }
        if game.drawOfferedToMe { return "Accept draw" }
        return "Offer draw"
    }

    private var drawBanner: some View {
        HStack(spacing: 12) {
            ChallengeAvatar(name: game.opponentName, theme: theme, size: 32)
            Text("\(game.opponentName) offers a draw")
                .font(theme.challengeFont(15, .semibold))
                .lineLimit(2)
                .minimumScaleFactor(0.85)
            Spacer(minLength: 6)
            Button("Decline") {
                Task { await game.declineDraw() }
            }
            .buttonStyle(ChallengeButtonStyle(kind: .glass, theme: theme, height: 38))
            .fixedSize()
            Button("Accept") {
                Task { await game.acceptDraw() }
            }
            .buttonStyle(ChallengeButtonStyle(kind: .primary, theme: theme, height: 38))
            .fixedSize()
        }
        .disabled(game.sending != nil)
        .padding(.leading, 12)
        .padding(.trailing, 10)
        .padding(.vertical, 10)
        .challengeGlass(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .frame(maxWidth: 520)
        .padding(.horizontal, 16)
    }

    private var lobbyCard: some View {
        VStack(spacing: 14) {
            HStack(spacing: 10) {
                WaitingDot(color: theme.challengeAccent)
                Text("Waiting for your friend to open the link")
                    .font(theme.challengeFont(15, .semibold))
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            VStack(spacing: 4) {
                Text(ChallengeLink.spaced(game.code))
                    .font(.system(size: 34, weight: .semibold, design: .monospaced))
                    .tracking(3)
                    .textSelection(.enabled)
                    .accessibilityLabel("Code \(game.code.map(String.init).joined(separator: " "))")
                Text(lobbyDetail)
                    .font(theme.challengeFont(13))
                    .foregroundStyle(.secondary)
            }
            HStack(spacing: 10) {
                Menu {
                    Button {
                        ChallengeSharing.shared.text(invite) { _ in }
                    } label: {
                        Label("Text", systemImage: "message")
                    }
                    Button {
                        ChallengeSharing.shared.mail(invite) { _ in }
                    } label: {
                        Label("Email", systemImage: "envelope")
                    }
                    Button {
                        ChallengeSharing.shared.share(invite) { _ in }
                    } label: {
                        Label("More…", systemImage: "square.and.arrow.up")
                    }
                    Button {
                        ChallengeSharing.copy(invite)
                        withAnimation(.snappy) { copied = true }
                        Task { @MainActor in
                            try? await Task.sleep(for: .seconds(2))
                            withAnimation(.snappy) { copied = false }
                        }
                    } label: {
                        Label("Copy link", systemImage: "link")
                    }
                } label: {
                    Label(copied ? "Copied" : "Send again", systemImage: copied ? "checkmark" : "paperplane.fill")
                }
                .menuStyle(.button)
                .buttonStyle(ChallengeButtonStyle(kind: .primary, theme: theme, height: 46))
                Button {
                    confirming = .cancelChallenge
                } label: {
                    Text("Cancel challenge")
                }
                .buttonStyle(ChallengeButtonStyle(kind: .destructive, theme: theme, height: 46))
                .disabled(game.sending != nil)
            }
        }
        .padding(18)
        .challengeGlass(RoundedRectangle(cornerRadius: 28, style: .continuous))
        .frame(maxWidth: 520)
        .padding(.horizontal, 16)
        .padding(.bottom, 6)
        .sensoryFeedback(.success, trigger: copied) { _, new in hapticsOn && new }
    }

    /// "10+0 · You play White".
    private var lobbyDetail: String {
        "\(game.clock?.label ?? "No clock") · You play \(game.seat.name)"
    }

    /// The result, then Done beside Rematch: compact, so it rises over the dock without covering the board.
    private var endCard: some View {
        VStack(spacing: 14) {
            VStack(spacing: 4) {
                Text(game.resultHeadline ?? "Game over")
                    .font(theme.challengeFont(22, .bold))
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                Text(game.resultDetail)
                    .font(theme.challengeFont(13))
                    .foregroundStyle(.secondary)
                if canRematch, game.rematchStage == .offered {
                    Text("\(game.opponentName) wants a rematch")
                        .font(theme.challengeFont(14, .semibold))
                        .foregroundStyle(theme.challengeAccent)
                        .padding(.top, 4)
                        .transition(.opacity)
                }
            }
            .accessibilityElement(children: .combine)
            HStack(spacing: 10) {
                Button("Done") {
                    center.dismiss()
                }
                .buttonStyle(ChallengeButtonStyle(kind: .glass, theme: theme))
                if canRematch {
                    rematch
                }
            }
        }
        .padding(18)
        .challengeGlass(RoundedRectangle(cornerRadius: 28, style: .continuous))
        .frame(maxWidth: 520)
        .padding(.horizontal, 16)
        .padding(.bottom, 6)
        .animation(.snappy(duration: 0.25), value: game.rematchStage)
    }

    /// A rematch needs both players: not for a challenge nobody took.
    private var canRematch: Bool {
        guard let state = game.state else { return false }
        return state.white.seated && state.black.seated
    }

    /// The rematch half of the end card's row.
    @ViewBuilder
    private var rematch: some View {
        switch game.rematchStage {
        case .none:
            rematchButton("Rematch")
        case .offered:
            rematchButton("Accept")
        case .ready:
            rematchButton("Open rematch")
        case .asked:
            rematchProgress("Waiting for \(game.opponentName)…")
        case .starting:
            rematchProgress("Starting…")
        }
    }

    private func rematchButton(_ title: String) -> some View {
        Button {
            Task { await game.askForRematch() }
        } label: {
            Label(title, systemImage: "arrow.triangle.2.circlepath")
        }
        .buttonStyle(ChallengeButtonStyle(kind: .primary, theme: theme))
        .disabled(game.sending != nil)
    }

    private func rematchProgress(_ title: String) -> some View {
        HStack(spacing: 8) {
            ProgressView()
                .controlSize(.small)
            Text(title)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
        .font(theme.challengeFont(15, .semibold))
        .foregroundStyle(.secondary)
        .padding(.horizontal, 14)
        .frame(maxWidth: .infinity, minHeight: 52)
        .challengeGlass(Capsule(style: .continuous))
        .accessibilityElement(children: .combine)
    }

    // MARK: Leaving, resigning, cancelling

    private func close() {
        // Closing a timed game under way is leaving it, and leaving forfeits.
        if game.phase == .playing, game.isTimed {
            confirming = .leave
        } else {
            center.dismiss()
        }
    }

    private var confirmingBinding: Binding<Bool> {
        Binding(get: { confirming != nil }, set: { if !$0 { confirming = nil } })
    }

    private var confirmTitle: String {
        switch confirming {
        case .resign?: return "Resign this game?"
        case .abort?: return "Abort this game?"
        case .leave?: return "Leave and forfeit?"
        case .cancelChallenge?: return "Cancel this challenge?"
        case nil: return ""
        }
    }

    private func confirmMessage(_ item: Confirmation) -> String {
        switch item {
        case .resign: return "\(game.opponentName) wins."
        case .abort: return "Neither of you has moved yet, so nobody wins or loses."
        case .leave: return "In a timed game, being away for 20 seconds loses the game."
        case .cancelChallenge: return "The link stops working, and your friend can't join."
        }
    }

    @ViewBuilder
    private func confirmActions(_ item: Confirmation) -> some View {
        switch item {
        case .resign:
            Button("Resign", role: .destructive) { Task { await game.resign() } }
            Button("Keep playing", role: .cancel) {}
        case .abort:
            Button("Abort", role: .destructive) { Task { await game.resign() } }
            Button("Keep playing", role: .cancel) {}
        case .leave:
            Button("Leave", role: .destructive) { center.dismiss() }
            Button("Keep playing", role: .cancel) {}
        case .cancelChallenge:
            Button("Cancel challenge", role: .destructive) { Task { await game.cancelChallenge() } }
            Button("Keep it open", role: .cancel) {}
        }
    }
}

// MARK: - The players' lines

/// One player's line above or below the board: their initial, name and state, what they have
/// taken, and their clock. The friend's line says when they are away, with the seconds left.
struct FriendPlate: View {
    let game: OnlineGame
    let seat: FriendSeat
    let theme: BoardTheme

    private var isMe: Bool { seat == game.seat }
    private var color: Piece.Color { seat.color }
    private var accent: Color { theme.challengeAccent }

    var body: some View {
        HStack(spacing: 12) {
            avatar
            VStack(alignment: .leading, spacing: 3) {
                Text(name)
                    .font(theme.challengeFont(16, .semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                status
            }
            Spacer(minLength: 8)
            if game.clock != nil, game.phase != .waiting || isMe {
                FriendClockBox(game: game, seat: seat, theme: theme)
            }
        }
        .padding(.horizontal, 4)
        .animation(.snappy(duration: 0.3), value: isActive)
        .animation(.snappy(duration: 0.3), value: inCheck)
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private var avatar: some View {
        if isMe {
            ChallengeAvatar(name: game.myName.isEmpty ? "You" : game.myName, theme: theme, size: 38)
        } else if game.phase == .waiting {
            ChallengeAvatar(name: nil, theme: theme, size: 38)
        } else {
            ChallengeAvatar(name: game.opponentName, theme: theme, size: 38,
                            online: game.phase == .playing ? game.isOnline(seat) : nil)
        }
    }

    private var name: String {
        if isMe { return "You" }
        return game.phase == .waiting ? "Your friend" : game.opponentName
    }

    /// The side to move, in a game under way.
    private var isActive: Bool {
        game.phase == .playing && game.state?.turn == seat && !(isMe && game.pending != nil)
    }

    private var inCheck: Bool {
        guard game.phase == .playing, let king = game.match.game.checkedKing else { return false }
        return game.match.game.piece(at: king)?.color == color
    }

    @ViewBuilder
    private var status: some View {
        if game.phase == .waiting {
            Text(isMe ? "You play \(seat.name)" : "Not here yet")
                .font(theme.challengeFont(12.5))
                .foregroundStyle(.secondary)
        } else if !isMe, game.phase == .playing, game.awaySecondsLeft(for: seat) != nil {
            TimelineView(.periodic(from: .now, by: 0.25)) { _ in
                let left = game.awaySecondsLeft(for: seat) ?? 0
                HStack(spacing: 5) {
                    Image(systemName: "figure.walk.departure")
                        .font(.system(size: 11, weight: .semibold))
                    Text("Away · \(left)s")
                        .font(theme.challengeFont(12.5, .semibold).monospacedDigit())
                        .contentTransition(.numericText(countsDown: true))
                }
                .foregroundStyle(ChallengeColors.urgent)
                .accessibilityLabel("Away. Forfeits in \(left) seconds")
            }
        } else {
            HStack(spacing: 6) {
                if inCheck {
                    CheckTag(color: theme.check)
                        .transition(.scale.combined(with: .opacity))
                } else if isActive {
                    Circle()
                        .fill(accent)
                        .frame(width: 6, height: 6)
                        .transition(.scale.combined(with: .opacity))
                }
                Text(statusText)
                    .font(theme.challengeFont(12.5, isActive ? .medium : .regular))
                    .foregroundStyle(isActive ? Color.primary.opacity(0.8) : Color.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
                    .layoutPriority(1)
                FriendCaptures(game: game, theme: theme, by: color)
            }
        }
    }

    private var statusText: String {
        if game.phase == .over, let result = game.state?.result {
            guard result.reason.wasPlayed else { return seat.name }
            if result.winner == seat { return "Winner" }
            return result.winner == nil ? "Draw" : "Lost"
        }
        if inCheck { return isMe ? "Your king is in check" : "King in check" }
        if isActive { return isMe ? "Your move" : "To move" }
        if !isMe, game.phase == .playing, !game.isOnline(seat) { return "Offline" }
        return seat.name
    }
}

/// The pieces a side has taken, small and overlapping, with the material lead.
private struct FriendCaptures: View {
    let game: OnlineGame
    let theme: BoardTheme
    let by: Piece.Color

    private static let size: CGFloat = 15

    var body: some View {
        let taken = game.captured(by: by)
        let lead = game.materialLead(for: by)
        ViewThatFits(in: .horizontal) {
            strip(taken, lead: lead, stacked: true)
            strip(taken, lead: lead, stacked: false)
            EmptyView()
        }
        .animation(.snappy(duration: 0.3), value: taken)
        .accessibilityHidden(true)
    }

    private func strip(_ taken: [CapturedCount], lead: Int, stacked: Bool) -> some View {
        HStack(spacing: stacked ? 4 : 3) {
            ForEach(taken) { entry in
                if stacked {
                    HStack(spacing: -Self.size * 0.55) {
                        ForEach(0..<entry.count, id: \.self) { _ in
                            image(of: entry.kind)
                        }
                    }
                } else {
                    HStack(spacing: 0) {
                        image(of: entry.kind)
                        if entry.count > 1 {
                            Text("\(entry.count)")
                                .font(.system(size: 9.5, weight: .semibold).monospacedDigit())
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
            if lead > 0 {
                Text("+\(lead)")
                    .font(.system(size: 11.5, weight: .semibold).monospacedDigit())
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func image(of kind: Piece.Kind) -> some View {
        Image(theme.imageName(for: Piece(kind, color: by.opposite, square: .a1)))
            .resizable()
            .interpolation(.high)
            .scaledToFit()
            .frame(width: Self.size, height: Self.size)
    }
}

/// A side's time, read from the server: a quiet box that turns solid while it runs, red in the last ten seconds.
struct FriendClockBox: View {
    let game: OnlineGame
    let seat: FriendSeat
    let theme: BoardTheme

    var body: some View {
        let running = game.isClockRunning(for: seat)
        TimelineView(.periodic(from: .now, by: running ? 0.1 : 60)) { _ in
            let left = game.timeLeft(for: seat) ?? 0
            let urgent = running && left < 10_000
            let shape = RoundedRectangle(cornerRadius: 9, style: .continuous)
            Text(FriendClockMath.label(left))
                .font(.system(size: 21, weight: .medium).monospacedDigit())
                .foregroundStyle(running ? Color.black.opacity(0.88) : Color.secondary)
                .lineLimit(1)
                .padding(.horizontal, 12)
                .padding(.vertical, 5)
                .background {
                    if running {
                        shape.fill(urgent ? ChallengeColors.urgent : Color.white.opacity(0.92))
                    } else {
                        shape.fill(Color.primary.opacity(0.04))
                            .overlay(shape.strokeBorder(Color.primary.opacity(0.1), lineWidth: 0.5))
                    }
                }
                .accessibilityLabel("\(seat.name) has \(FriendClockMath.label(left)) left")
        }
        .animation(.snappy(duration: 0.25), value: running)
    }
}

/// A soft dot that breathes while the lobby waits.
private struct WaitingDot: View {
    let color: Color
    @State private var breathing = false

    var body: some View {
        Circle()
            .fill(color)
            .frame(width: 8, height: 8)
            .background {
                Circle()
                    .fill(color.opacity(0.35))
                    .scaleEffect(breathing ? 2.6 : 1)
                    .opacity(breathing ? 0 : 1)
            }
            .onAppear {
                withAnimation(.easeOut(duration: 1.6).repeatForever(autoreverses: false)) { breathing = true }
            }
            .accessibilityHidden(true)
    }
}
