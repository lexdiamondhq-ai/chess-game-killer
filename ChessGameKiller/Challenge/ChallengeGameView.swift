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
    @Environment(\.colorScheme) private var colorScheme
    @AppStorage("sculpted3D") private var sculpted3D = true
    @AppStorage(BoardTilt.storageKey) private var tilt = BoardTilt.tilted
    @AppStorage("haptics") private var hapticsOn = true
    @State private var confirming: Confirmation?
    @State private var copied = false
    /// The React row is open over the dock.
    @State private var reacting = false
    /// "Try again" on a game that would not open is fetching it now.
    @State private var retrying = false

    enum Confirmation: Identifiable {
        case resign, abort, leave, cancelChallenge, reportName, reportCheating

        var id: Self { self }
    }

    private static let spacing: CGFloat = 12
    private static let plateHeight: CGFloat = 58
    private static let ribbonHeight: CGFloat = 32
    /// As on the game screen: the board stops growing here, and so does the column around it.
    private static let maxBoardSide: CGFloat = 680

    // The body is split in two, with the haptic conditions as functions, so the
    // compiler can type-check it in reasonable time.
    var body: some View {
        screen
            .confirmationDialog(confirmTitle, isPresented: confirmingBinding, titleVisibility: .visible,
                                presenting: confirming) { item in
                confirmActions(item)
            } message: { item in
                Text(confirmMessage(item))
            }
            .sensoryFeedback(.warning, trigger: game.toast?.id, condition: warningBuzz)
            .sensoryFeedback(.success, trigger: game.phase, condition: joinedBuzz)
            .sensoryFeedback(.impact(weight: .medium), trigger: game.drawOfferedToMe, condition: drawOfferBuzz)
            .animation(.snappy(duration: 0.35), value: game.phase)
            .onAppear { game.refreshIdleTimer() }
            .onChange(of: BoardView.playsIn3D(theme, setting: sculpted3D), initial: true) { _, threeD in
                game.timeSounds(threeD: threeD)
            }
    }

    private var screen: some View {
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
        .background {
            FriendMarble(theme: theme)
        }
        .safeAreaInset(edge: .top, spacing: 8) {
            topBar
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            foot
        }
    }

    /// A warning buzz with a notice that matters, such as a screenshot.
    private func warningBuzz(_ old: Int?, _ new: Int?) -> Bool {
        guard hapticsOn, let toast = game.toast else { return false }
        return toast.isWarning
    }

    /// A tap on the wrist when the other side offers a draw.
    private func drawOfferBuzz(_ old: Bool, _ new: Bool) -> Bool {
        hapticsOn && new
    }

    /// A success buzz the moment the friend joins.
    private func joinedBuzz(_ old: OnlineGame.Phase, _ new: OnlineGame.Phase) -> Bool {
        guard hapticsOn else { return false }
        return old == .waiting && new == .playing
    }

    // MARK: Layout

    /// Which side sits at the top of the board: Black from White's side, and the other way round.
    private var topSeat: FriendSeat { game.match.isBoardFlipped ? .white : .black }

    private func layout(in size: CGSize) -> some View {
        let aspect = BoardView.aspect(theme, setting: sculpted3D, framing: tilt.framing)
        let spare = size.height - Self.plateHeight * 2 - Self.ribbonHeight - Self.spacing * 5
        let width = max(0, min(size.width, spare * aspect, Self.maxBoardSide))
        // The block sits high, under the bar, rather than floating in the middle with a gap
        // above it: a quarter of what is left goes above it, the rest below (Alex's pick B Rich,
        // 2026-11-27).
        let left = max(0, spare - width / aspect)
        return VStack(spacing: Self.spacing) {
            Color.clear.frame(height: left * 0.25)
            FriendPlate(game: game, seat: topSeat, theme: theme)
                .frame(height: Self.plateHeight)
            // This screen follows Light or dark, so the frame's letters take a dark ink on the
            // light page, where the pale one was all but invisible.
            BoardView(match: game.match, theme: theme, framing: tilt.framing, frameLabel: theme.frameLabel(on: colorScheme))
                .frame(width: width, height: width / aspect)
                .overlay {
                    // A square board seen from straight above wears a gold rim; the tilted
                    // 3D board has its own frame.
                    if abs(aspect - 1) < 0.02 {
                        FriendBoardRim()
                    }
                }
            FriendPlate(game: game, seat: topSeat.opposite, theme: theme)
                .frame(height: Self.plateHeight)
                // Confirm moves: while a move waits, the gold Play bar stands in the plate's place.
                .opacity(game.held == nil ? 1 : 0)
                .accessibilityHidden(game.held != nil)
                .overlay {
                    if let held = game.held, game.phase == .playing {
                        // Your clock still runs while the move waits, so it stays in sight beside
                        // the bar (Alex's pick 7A, screen review 2026-11-19).
                        HStack(spacing: 10) {
                            PlayMoveBar(san: held.san, theme: theme,
                                        play: { game.playHeld() }, takeBack: { game.takeBackHeld() })
                            if game.clock != nil {
                                FriendClockBox(game: game, seat: game.seat, theme: theme)
                                    .fixedSize()
                            }
                        }
                        .padding(.horizontal, 4)
                        .transition(.opacity.combined(with: .scale(scale: 0.96)))
                    }
                }
                .animation(.snappy(duration: 0.25), value: game.held)
            HStack(spacing: 8) {
                // The moves on their own glass, as in a rival game.
                MoveRibbon(moves: game.ribbon, theme: theme)
                    .padding(.horizontal, 14)
                    .frame(maxHeight: .infinity)
                    .glassPane(Capsule())
                BoardViewSwitch(theme: theme)
            }
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
                Button {
                    guard !retrying else { return }
                    retrying = true
                    Task {
                        await game.refresh()
                        retrying = false
                    }
                } label: {
                    if retrying {
                        ProgressView()
                    } else {
                        Text("Try again")
                    }
                }
                .buttonStyle(ChallengeButtonStyle(kind: .glass, theme: theme, height: 46))
                .frame(maxWidth: 220)
                .disabled(retrying)
            } else {
                // Most games open in a blink: the loader shows only when one doesn't.
                Group {
                    KnightWait(size: 44)
                    Text("Opening the game…")
                        .font(theme.challengeFont(15))
                        .foregroundStyle(.secondary)
                }
                .modifier(LateFadeIn())
            }
        }
        .padding(.horizontal, 32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: The bar across the top

    private var topBar: some View {
        ChallengeTopBar(title: game.title, detail: connectionDetail, theme: theme, close: close) {
            // The invite links only while the friend hasn't come, and no Flip: it is in the dock,
            // as in a rival game (Alex's pick 11A, screen review 2026-11-19).
            if game.phase == .waiting || game.canReport {
                Menu {
                    if game.phase == .waiting {
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
                    }
                    if game.canReport {
                        Section("Report \(game.opponentName)") {
                            Button {
                                confirming = .reportName
                            } label: {
                                Label(game.reported.contains(.reportName) ? "Name reported" : "Offensive name",
                                      systemImage: "person.crop.circle.badge.exclamationmark")
                            }
                            .disabled(game.reported.contains(.reportName))
                            Button {
                                confirming = .reportCheating
                            } label: {
                                Label(game.reported.contains(.reportCheating) ? "Cheating reported" : "Cheating",
                                      systemImage: "exclamationmark.shield")
                            }
                            .disabled(game.reported.contains(.reportCheating))
                        }
                    }
                } label: {
                    ChallengeBarIcon(symbol: "ellipsis")
                }
                .accessibilityLabel("More")
            }
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
                banner(symbol: "exclamationmark.triangle.fill",
                       text: "You left the game. Away for over \(game.graceWords), \(game.opponentName) can claim the win.",
                       urgent: true) {
                    game.dismissCameBack()
                }
                .transition(.move(edge: .top).combined(with: .opacity))
            } else if game.showsFairPlay {
                banner(symbol: "checkmark.shield.fill", text: fairPlayLine, urgent: false) {
                    game.dismissFairPlay()
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
        .animation(.spring(response: 0.4, dampingFraction: 0.86), value: game.showsFairPlay)
        .animation(.spring(response: 0.4, dampingFraction: 0.86), value: game.connection)
    }

    /// The fair-play rules, on the first screen of a game.
    private var fairPlayLine: String {
        var line = "Fair play: no hints or analysis."
        if game.hasLeaveRule {
            line += " Leave for over \(game.graceWords) and \(game.opponentName) can claim the win."
        } else if game.isTimed {
            line += " If you leave, your clock keeps running."
        } else if let days = game.days {
            line += " You have \(DailyDays.label(days)) for each move: close the app between moves."
        }
        return line + " \(game.opponentName) is told if you take a screenshot."
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
            // Room for the end card's second row, so it never stands over the moves or your plate.
            .padding(.top, canReview ? Self.reviewRow : 0)
            .overlay(alignment: .top) {
                if game.phase == .playing, game.offersClaim {
                    claimBanner
                        .fixedSize(horizontal: false, vertical: true)
                        .alignmentGuide(.top) { $0[.bottom] + 10 }
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                } else if game.drawOfferedToMe {
                    drawBanner
                        .fixedSize(horizontal: false, vertical: true)
                        .alignmentGuide(.top) { $0[.bottom] + 10 }
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                } else if reacting, game.canReact {
                    reactionRow
                        .fixedSize()
                        .alignmentGuide(.top) { $0[.bottom] + 8 }
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
            .animation(.spring(response: 0.42, dampingFraction: 0.86), value: game.offersClaim)
            .animation(.spring(response: 0.42, dampingFraction: 0.86), value: game.phase)
    }

    private var dock: some View {
        HStack(spacing: 0) {
            FriendDockButton(title: drawTitle, symbol: "equal", isOn: game.drawOfferedByMe, theme: theme) {
                Task {
                    if game.drawOfferedToMe { await game.acceptDraw() } else { await game.offerDraw() }
                }
            }
            .disabled(game.drawOfferedByMe || game.sending != nil)
            FriendDockButton(title: game.endsAnyTime ? "End" : game.canAbort ? "Abort" : "Resign", symbol: "flag", theme: theme) {
                confirming = game.canAbort ? .abort : .resign
            }
            .disabled(game.sending != nil)
            if game.canReact {
                FriendDockButton(title: "React", symbol: "face.smiling", isOn: reacting, theme: theme) {
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.82)) { reacting.toggle() }
                }
            }
            FriendDockButton(title: "Flip", symbol: "arrow.triangle.2.circlepath", theme: theme) {
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

    /// The quick bubbles React offers, in a row over the dock. A tap sends one and folds the row.
    private var reactionRow: some View {
        HStack(spacing: 8) {
            ForEach(FriendReaction.allCases) { reaction in
                Button {
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.82)) { reacting = false }
                    Task { await game.react(reaction) }
                } label: {
                    FriendBubbleLabel(reaction: reaction, theme: theme)
                }
                .buttonStyle(ChallengePressStyle())
                .accessibilityLabel("Send \(reaction.words)")
            }
        }
        .padding(.horizontal, 12)
    }

    private var drawTitle: String {
        if game.drawOfferedByMe { return "Draw offered" }
        if game.drawOfferedToMe { return "Accept the draw" }
        return "Offer a draw"
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

    /// The friend left and stayed away: claim the win, or keep waiting.
    private var claimBanner: some View {
        HStack(spacing: 12) {
            ChallengeAvatar(name: game.opponentName, theme: theme, size: 32, online: false)
            // Two lines, as the draw offer has. Beside the two buttons there is room for about
            // ten letters a line: on one line this read "Sam left the…", over "Away for over…",
            // which the friend's line above the board already says in red.
            Text("\(game.opponentName) left the game")
                .font(theme.challengeFont(15, .semibold))
                .lineLimit(2)
                .minimumScaleFactor(0.85)
                .accessibilityLabel("\(game.opponentName) left the game, away for over \(game.graceWords)")
            Spacer(minLength: 6)
            Button("Wait") {
                game.keepWaiting()
            }
            .buttonStyle(ChallengeButtonStyle(kind: .glass, theme: theme, height: 38))
            .fixedSize()
            Button("Claim win") {
                Task { await game.claimWin() }
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
                Text("Waiting for your friend to join")
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
        "\(game.paceLabel) · You play \(game.seat.name)"
    }

    /// The result beside Rematch, in one row about the dock's height, so it takes the dock's place
    /// without covering the board or your plate. The close button in the top bar leaves.
    private var endCard: some View {
        // Worked out first, so the view below stays quick to type-check.
        let offered = rematchOffered
        let lineWeight: Font.Weight = offered ? .semibold : .regular
        let lineColor: Color = offered ? theme.challengeAccent : .secondary
        return VStack(spacing: 8) {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(game.resultHeadline ?? "Game over")
                        .font(theme.challengeFont(17, .bold))
                        .lineLimit(2)
                        .minimumScaleFactor(0.8)
                    Text(endLine)
                        .font(theme.challengeFont(13, lineWeight))
                        .foregroundStyle(lineColor)
                        .lineLimit(2)
                        .minimumScaleFactor(0.85)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityElement(children: .combine)
                endButton
                    .frame(width: 148)
            }
            .padding(.leading, 12)
            // A game that was really played can be looked back on, as a rival game can (Alex,
            // 2026-11-11, audit pick O1).
            if canReview {
                Button {
                    center.review(game)
                } label: {
                    Label("Review game", systemImage: "backward.circle")
                }
                .buttonStyle(ChallengeButtonStyle(kind: .glass, theme: theme, height: Self.reviewHeight))
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 8)
        .challengeGlass(RoundedRectangle(cornerRadius: 30, style: .continuous))
        .frame(maxWidth: 520)
        .padding(.horizontal, 16)
        .padding(.bottom, 6)
        .animation(.snappy(duration: 0.25), value: game.rematchStage)
    }

    /// The game was really played, with moves to look back on: not one aborted or never taken.
    private var canReview: Bool {
        guard game.phase == .over, let state = game.state, let result = state.result else { return false }
        return result.reason.wasPlayed && !state.moves.isEmpty
    }

    private static let reviewHeight: CGFloat = 40
    /// How much taller Review game makes the end card than the dock it stands in for.
    private static let reviewRow: CGFloat = reviewHeight + 8

    /// The friend asked for a rematch and is waiting on you.
    private var rematchOffered: Bool { canRematch && game.rematchStage == .offered }

    /// Under the result: where the rematch stands, or how the game ended.
    private var endLine: String {
        guard canRematch else { return game.resultDetail }
        switch game.rematchStage {
        case .offered: return "\(game.opponentName) wants a rematch"
        case .asked where opponentLeft: return "\(game.opponentName) has left."
        case .asked: return "Rematch asked. Waiting for \(game.opponentName)."
        case .starting: return "Starting the rematch…"
        case .ready: return "The rematch is ready"
        case .none: return game.resultDetail
        }
    }

    /// Rematch when both players were there, else Done.
    @ViewBuilder
    private var endButton: some View {
        if canRematch {
            rematch
        } else {
            Button("Done") {
                center.dismiss()
            }
            .buttonStyle(ChallengeButtonStyle(kind: .glass, theme: theme))
        }
    }

    /// A rematch needs both players: not for a challenge nobody took.
    private var canRematch: Bool {
        guard let state = game.state else { return false }
        return state.white.seated && state.black.seated
    }

    /// The game is over and the other player has closed it: a rematch asked of them now would
    /// wait for good. (They can still ask for one themselves, which shows as an offer.)
    private var opponentLeft: Bool {
        guard game.phase == .over, canRematch, !game.isOnline(game.opponentSeat) else { return false }
        return game.rematchStage == .none || game.rematchStage == .asked
    }

    /// Paired in the lobby, where another opponent is one tap away. A friend's game keeps
    /// Rematch: the friend finds the ask when they next open the game.
    private var isLobbyGame: Bool { game.state?.online ?? false }

    /// The rematch half of the end card's row.
    @ViewBuilder
    private var rematch: some View {
        if opponentLeft, isLobbyGame {
            Button {
                center.playOnline()
            } label: {
                Label("New opponent", systemImage: "bolt.fill")
            }
            .buttonStyle(ChallengeButtonStyle(kind: .primary, theme: theme))
        } else if opponentLeft, game.rematchStage == .asked {
            Button("Done") {
                center.dismiss()
            }
            .buttonStyle(ChallengeButtonStyle(kind: .glass, theme: theme))
        } else {
            rematchStageButton
        }
    }

    @ViewBuilder
    private var rematchStageButton: some View {
        switch game.rematchStage {
        case .none:
            rematchButton("Rematch")
        case .offered:
            rematchButton("Accept")
        case .ready:
            rematchButton("Open")
        case .asked:
            rematchProgress("Waiting")
        case .starting:
            rematchProgress("Starting")
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
            KnightWait(size: 18)
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
        // Closing a timed game under way is leaving it: the clock runs on (and in a friend game, away
        // long enough, the friend can claim the win).
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
        case .abort?: return game.endsAnyTime ? "End this game?" : "Abort this game?"
        case .leave?: return "Leave the game?"
        case .cancelChallenge?: return "Cancel this challenge?"
        case .reportName?: return "Report \(game.opponentName)'s name?"
        case .reportCheating?: return "Report \(game.opponentName) for cheating?"
        case nil: return ""
        }
    }

    private func confirmMessage(_ item: Confirmation) -> String {
        switch item {
        case .resign: return "\(game.opponentName) wins."
        case .abort:
            return game.endsAnyTime
                ? "This game has no clock, so it ends with no result. Nobody wins or loses."
                : "Neither of you has moved yet, so nobody wins or loses."
        case .leave:
            return game.hasLeaveRule
                ? "Your clock keeps running. Away for over \(game.graceWords), \(game.opponentName) can claim the win."
                : "Your clock keeps running while you're away."
        case .cancelChallenge: return "The link stops working, and your friend can't join."
        case .reportName: return "Their name is hidden from now on, and we'll take a look."
        case .reportCheating: return "We'll take a look at this game."
        }
    }

    @ViewBuilder
    private func confirmActions(_ item: Confirmation) -> some View {
        switch item {
        case .resign:
            Button("Resign", role: .destructive) { Task { await game.resign() } }
            Button("Keep playing", role: .cancel) {}
        case .abort:
            Button("Abort", role: .destructive) { Task { await game.abort() } }
            Button("Keep playing", role: .cancel) {}
        case .leave:
            Button("Leave", role: .destructive) { center.dismiss() }
            Button("Keep playing", role: .cancel) {}
        case .cancelChallenge:
            Button("Cancel challenge", role: .destructive) { Task { await game.cancelChallenge() } }
            Button("Keep it open", role: .cancel) {}
        case .reportName:
            Button("Report name", role: .destructive) { Task { await game.reportOpponent(.reportName) } }
            Button("Cancel", role: .cancel) {}
        case .reportCheating:
            Button("Report cheating", role: .destructive) { Task { await game.reportOpponent(.reportCheating) } }
            Button("Cancel", role: .cancel) {}
        }
    }
}

// MARK: - Confirm moves

/// The gold bar under the board while the player's move waits: ✕ takes it back, ✓ (or the
/// words) plays it. The board itself takes a move back too, with a tap anywhere on it.
struct PlayMoveBar: View {
    let san: String
    let theme: BoardTheme
    let play: () -> Void
    let takeBack: () -> Void

    @AppStorage("haptics") private var hapticsOn = true

    private static let ink = Color(red: 0.10, green: 0.08, blue: 0.04)

    var body: some View {
        HStack(spacing: 0) {
            round("xmark", label: "Take back", action: cancel)
            Button(action: confirm) {
                Text("Play \(san)")
                    .font(theme.challengeFont(17, .semibold))
                    .foregroundStyle(Self.ink)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Play \(san)")
            round("checkmark", label: "Play \(san)", action: confirm)
        }
        .padding(.horizontal, 6)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background {
            Capsule(style: .continuous)
                .fill(theme.challengeAccent.gradient)
                .shadow(color: theme.challengeAccent.opacity(0.35), radius: 10, y: 2)
        }
        .padding(.vertical, 2)
    }

    private func round(_ symbol: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(Self.ink)
                .frame(width: 38, height: 38)
                .background(Circle().fill(Self.ink.opacity(0.12)))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }

    private func cancel() {
        if hapticsOn { UIImpactFeedbackGenerator(style: .light).impactOccurred() }
        withAnimation(.snappy(duration: 0.22)) { takeBack() }
    }

    private func confirm() {
        if hapticsOn { UIImpactFeedbackGenerator(style: .rigid).impactOccurred() }
        withAnimation(.snappy(duration: 0.22)) { play() }
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
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(name)
                        .font(theme.challengeFont(16, .semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                    if let rating {
                        Text(rating)
                            .font(theme.challengeFont(13, .medium).monospacedDigit())
                            .foregroundStyle(.secondary)
                            .accessibilityLabel("rated \(rating)")
                    }
                }
                status
            }
            Spacer(minLength: 8)
            if game.clock != nil, game.phase != .waiting || isMe {
                FriendClockBox(game: game, seat: seat, theme: theme)
            } else if game.days != nil, game.phase == .playing, game.state?.turn == seat {
                FriendDaysBox(game: game, seat: seat, theme: theme)
            }
        }
        .padding(.horizontal, 10)
        .frame(maxHeight: .infinity)
        // Each player on a gilded card, as in a rival game; the side to move glows
        // (Alex's pick B Rich, 2026-11-27).
        .glassPane(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay {
            if isActive {
                PolishedEdge(shape: RoundedRectangle(cornerRadius: 18, style: .continuous), edge: .lit)
                    .transition(.opacity)
            }
        }
        .overlay(alignment: .topTrailing) {
            // A quick bubble this side sent (React), popping up over its line.
            if let bubble = game.bubbles[seat] {
                FriendBubbleLabel(reaction: bubble.reaction, theme: theme)
                    .id(bubble.id)
                    .offset(x: -14, y: -18)
                    .transition(.scale(scale: 0.6, anchor: .bottomTrailing).combined(with: .opacity))
                    .accessibilityLabel("\(name): \(bubble.reaction.words)")
            }
        }
        .animation(.spring(response: 0.35, dampingFraction: 0.7), value: game.bubbles[seat])
        .animation(.snappy(duration: 0.3), value: isActive)
        .animation(.snappy(duration: 0.3), value: inCheck)
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private var avatar: some View {
        if isMe {
            ChallengeAvatar(name: game.myName.isEmpty ? "You" : game.myName, theme: theme, size: 38, crest: true)
        } else if game.phase == .waiting {
            ChallengeAvatar(name: nil, theme: theme, size: 38, crest: true)
        } else {
            // The dot stays after the game, so it shows whether a rematch can be answered.
            ChallengeAvatar(name: game.opponentName, theme: theme, size: 38, online: game.isOnline(seat), crest: true)
        }
    }

    /// The rating in a game paired online: "1250", or "1200?" while it is still settling.
    private var rating: String? {
        game.state?.ratings?[seat].label
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
                    Text(left > 0 ? "Away · \(left)s" : "Left the game")
                        .font(theme.challengeFont(12.5, .semibold).monospacedDigit())
                        .contentTransition(.numericText(countsDown: true))
                    if left == 0, !game.offersClaim {
                        Button("Claim win") {
                            Task { await game.claimWin() }
                        }
                        .font(theme.challengeFont(12.5, .bold))
                        .foregroundStyle(theme.challengeAccent)
                        .disabled(game.sending != nil)
                    }
                }
                .foregroundStyle(ChallengeColors.urgent)
                .accessibilityLabel(left > 0 ? "Away. You can claim the win in \(left) seconds" : "Left the game. You can claim the win")
            }
        } else {
            HStack(spacing: 6) {
                if inCheck {
                    CheckTag(color: theme.check)
                        .transition(.scale.combined(with: .opacity))
                }
                if isActive && !inCheck {
                    // Whose move it is, on a small gold pill.
                    Text(statusText)
                        .font(theme.challengeFont(11.5, .semibold))
                        .foregroundStyle(Color(hex: 0x2A1C08))
                        .lineLimit(1)
                        .padding(.horizontal, 9)
                        .padding(.vertical, 3)
                        .background {
                            Capsule().fill(LinearGradient(colors: [Color(hex: 0xEDCB82), Color(hex: 0xC49543)],
                                                          startPoint: .top, endPoint: .bottom))
                        }
                        .shadow(color: Color(hex: 0xD9AE5A).opacity(0.45), radius: 5)
                        .layoutPriority(1)
                        .transition(.scale.combined(with: .opacity))
                } else {
                    Text(statusText)
                        .font(theme.challengeFont(12.5, .regular))
                        .foregroundStyle(Color.secondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.85)
                        .layoutPriority(1)
                }
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
        if isMe, game.phase == .playing, game.isSendingSlowly { return "Sending your move…" }
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

    @AppStorage("haptics") private var hapticsOn = true
    /// Counts the times the person's own clock crossed into its last ten seconds, for the buzz.
    @State private var lowWarnings = 0

    var body: some View {
        let running = game.isClockRunning(for: seat)
        TimelineView(.periodic(from: .now, by: running ? 0.1 : 60)) { _ in
            let left = game.timeLeft(for: seat) ?? 0
            let urgent = running && left < 10_000
            let shape = RoundedRectangle(cornerRadius: 9, style: .continuous)
            // As wide as its widest reading, so the last ten seconds don't change the box.
            ZStack {
                Text("0:00.0").hidden()
                Text(FriendClockMath.label(left))
            }
                // One soft tick and a buzz as the person's own time runs into its last ten seconds.
                .onChange(of: left < 10_000) { _, low in
                    guard low, running, seat == game.seat else { return }
                    SoundPlayer.shared.play(.select)
                    lowWarnings += 1
                }
                .font(.system(size: 21, weight: .medium).monospacedDigit())
                .foregroundStyle(running ? (urgent ? Color.black.opacity(0.88) : runningInk) : Color.secondary)
                .lineLimit(1)
                .padding(.horizontal, 12)
                .padding(.vertical, 5)
                .background {
                    if running {
                        shape.fill(urgent ? ChallengeColors.urgent : runningFace)
                    } else {
                        shape.fill(Color.primary.opacity(0.04))
                            .overlay(shape.strokeBorder(Color.primary.opacity(0.1), lineWidth: 0.5))
                    }
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("\(seat.name) has \(FriendClockMath.label(left)) left")
        }
        .animation(.snappy(duration: 0.25), value: running)
        .sensoryFeedback(.impact(weight: .medium), trigger: lowWarnings) { _, _ in hapticsOn }
    }

    /// A running clock's face: the home's one solid fill (ivory in the dark, the set's ink in
    /// Light), or bright white on the older home.
    private var runningFace: Color { theme.screenTone?.ivory ?? Color.white.opacity(0.92) }
    private var runningInk: Color { theme.screenTone?.onIvory ?? Color.black.opacity(0.88) }
}

/// A daily game: the time the side to move has left, "1d 4h", in the same quiet box as a clock.
struct FriendDaysBox: View {
    let game: OnlineGame
    let seat: FriendSeat
    let theme: BoardTheme

    var body: some View {
        TimelineView(.periodic(from: .now, by: 30)) { _ in
            let left = game.daysLeft() ?? 0
            let urgent = left < 3_600_000
            let shape = RoundedRectangle(cornerRadius: 9, style: .continuous)
            HStack(spacing: 5) {
                Image(systemName: "hourglass")
                    .font(.system(size: 13, weight: .semibold))
                Text(DailyDays.left(left))
                    .font(.system(size: 17, weight: .medium).monospacedDigit())
            }
            .foregroundStyle(urgent ? ChallengeColors.urgent : theme.challengeAccent)
            .lineLimit(1)
            .padding(.horizontal, 11)
            .padding(.vertical, 6)
            .background {
                shape.fill(Color.primary.opacity(0.04))
                    .overlay(shape.strokeBorder(Color.primary.opacity(0.1), lineWidth: 0.5))
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("\(seat.name) has \(DailyDays.left(left)) left to move")
        }
    }
}

/// A soft dot that breathes while the lobby waits.
private struct WaitingDot: View {
    let color: Color
    @State private var breathing = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

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
                guard !reduceMotion else { return }
                withAnimation(.easeOut(duration: 1.6).repeatForever(autoreverses: false)) { breathing = true }
            }
            .accessibilityHidden(true)
    }
}

/// The gold rim round a board seen from straight above (Alex's pick B Rich, 2026-11-27).
private struct FriendBoardRim: View {
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let dark = scheme == .dark
        let shape = RoundedRectangle(cornerRadius: 3, style: .continuous)
        shape
            .inset(by: -3)
            .strokeBorder(LinearGradient(colors: [Polish.goldCatch(dark: dark), Polish.goldBase(dark: dark),
                                                  Polish.goldDeep(dark: dark), Polish.goldBase(dark: dark)],
                                         startPoint: .topLeading, endPoint: .bottomTrailing),
                          lineWidth: 2)
            .padding(-3)
            .shadow(color: Color.black.opacity(dark ? 0.4 : 0.22), radius: 12, y: 8)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }
}

/// The page under a friend game: Home's veined marble, faint, so the game sits in the same room
/// as the rest of the app instead of on a bare page. Neon keeps its own light.
private struct FriendMarble: View {
    let theme: BoardTheme

    var body: some View {
        if !theme.glows {
            Image(theme.screenIsDark ? "home-marble-dark" : "home-marble")
                .resizable()
                .scaledToFill()
                .opacity(theme.screenIsDark ? 0.5 : 0.6)
                .mask(LinearGradient(stops: [.init(color: .black, location: 0),
                                             .init(color: .black.opacity(0.55), location: 0.7),
                                             .init(color: .black.opacity(0.35), location: 1)],
                                     startPoint: .top, endPoint: .bottom))
                .ignoresSafeArea()
                .allowsHitTesting(false)
                .accessibilityHidden(true)
        }
    }
}

/// A dock control in a friend game: its icon in a small dark coin with a gold rim, its name under
/// it, so the row reads as one set (Alex's pick, 2026-11-27: "the icons look off"). Neon keeps the
/// app's plain dock control.
private struct FriendDockButton: View {
    let title: String
    let symbol: String
    var isOn: Bool? = nil
    let theme: BoardTheme
    let action: () -> Void

    @State private var taps = 0
    @AppStorage("haptics") private var hapticsOn = true
    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        if theme.glows {
            DockButton(title: title, symbol: symbol, isOn: isOn, theme: theme, action: action)
        } else {
            Button {
                taps += 1
                action()
            } label: {
                VStack(spacing: 4) {
                    FriendCoin(symbol: symbol, lit: isOn == true)
                    Text(title)
                        .font(.app(.caption2, weight: .medium))
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                        .foregroundStyle(Color.primary.opacity(0.8))
                }
                .opacity(isEnabled ? 1 : 0.5)
                .frame(maxWidth: .infinity, minHeight: 48)
                .contentShape(Rectangle())
            }
            .buttonStyle(ChallengePressStyle())
            .sensoryFeedback(.impact(weight: .light), trigger: taps) { _, _ in hapticsOn }
            .accessibilityLabel(title)
            .accessibilityValue(isOn.map { $0 ? "On" : "Off" } ?? "")
            .accessibilityAddTraits(isOn == nil ? [] : .isToggle)
            .accessibilityShowsLargeContentViewer()
        }
    }
}

/// The coin a dock icon sits in: dark espresso, a gold rim, the icon in gold. Lit, it fills with gold.
private struct FriendCoin: View {
    let symbol: String
    var lit = false

    private static let size: CGFloat = 34

    var body: some View {
        let rim = LinearGradient(colors: [Polish.goldCatch(dark: false), Polish.goldBase(dark: false), Polish.goldDeep(dark: false)],
                                 startPoint: .topLeading, endPoint: .bottomTrailing)
        Image(systemName: symbol)
            .font(.system(size: 14.5, weight: .semibold))
            .foregroundStyle(lit ? Color(hex: 0x2A1C08) : Polish.goldBase(dark: true))
            .frame(width: Self.size, height: Self.size)
            .background {
                if lit {
                    Circle().fill(LinearGradient(colors: [Color(hex: 0xEDCB82), Color(hex: 0xC49543)],
                                                 startPoint: .top, endPoint: .bottom))
                } else {
                    Circle().fill(RadialGradient(colors: [Color(hex: 0x3A2A18), Color(hex: 0x120C06)],
                                                 center: UnitPoint(x: 0.35, y: 0.3), startRadius: 0, endRadius: Self.size * 0.7))
                }
            }
            .overlay { Circle().strokeBorder(rim, lineWidth: 1.25) }
            .shadow(color: .black.opacity(0.2), radius: 3, y: 2)
            .animation(.snappy(duration: 0.25), value: lit)
    }
}

/// A quick bubble: its emoji and words on a white chip with a gold rim.
private struct FriendBubbleLabel: View {
    let reaction: FriendReaction
    let theme: BoardTheme

    var body: some View {
        HStack(spacing: 5) {
            Text(reaction.emoji)
                .font(.system(size: 14))
            Text(reaction.words)
                .font(theme.challengeFont(13, .semibold))
                .foregroundStyle(Color(hex: 0x2A2116))
                .lineLimit(1)
        }
        .padding(.horizontal, 11)
        .padding(.vertical, 6)
        .background(Capsule().fill(Color.white))
        .overlay { Capsule().strokeBorder(Polish.goldBase(dark: false).opacity(0.85), lineWidth: 1) }
        .shadow(color: .black.opacity(0.18), radius: 6, y: 3)
    }
}
