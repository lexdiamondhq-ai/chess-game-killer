import ChessKit
import SwiftUI

/// Play online: the players waiting right now, each with a Play button to take them on, and
/// Find a game, which pairs you with the closest rating at your clock (or waits for someone).
/// Games are rated and follow the fair-play rules of friend games.
struct OnlineLobbyView: View {
    let lobby: OnlineLobby
    let theme: BoardTheme

    @Environment(ChallengeCenter.self) private var center
    @AppStorage(ChallengeName.key) private var name = ""
    @AppStorage("online.clock") private var control: TimeControl = .blitz5
    @AppStorage("haptics") private var hapticsOn = true

    private var clock: FriendClock {
        FriendClock(control) ?? FriendClock(initial: 300, increment: 0)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                header
                VStack(alignment: .leading, spacing: 10) {
                    ChallengeSectionTitle(title: "Your name")
                    ChallengeNameField(name: $name, theme: theme)
                }
                clockPicker
                waitingList
                OnlineFairPlayCard(theme: theme)
            }
            .frame(maxWidth: 560)
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 20)
            .padding(.top, 12)
            .padding(.bottom, 28)
        }
        .scrollDismissesKeyboard(.interactively)
        .safeAreaInset(edge: .top, spacing: 0) {
            ChallengeTopBar(title: "Play online", detail: lobby.you.map { "Your rating \($0.label)" }, theme: theme,
                            close: { center.dismiss() }) {
                Color.clear
            }
            .padding(.horizontal, 12)
            .padding(.top, 4)
            .padding(.bottom, 4)
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            bottomBar
        }
        .onAppear { lobby.start() }
        .animation(.snappy(duration: 0.3), value: lobby.players)
        .animation(.snappy(duration: 0.3), value: lobby.phase)
        .sensoryFeedback(.selection, trigger: control) { _, _ in hapticsOn }
        .sensoryFeedback(.success, trigger: lobby.phase) { _, new in hapticsOn && new == .starting }
    }

    // MARK: The parts

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Play someone online")
                .font(theme.challengeFont(30, .bold))
            Text("Rated games with players waiting now. Take one on, or find a game at your clock.")
                .font(theme.challengeFont(15))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.top, 8)
    }

    private var clockPicker: some View {
        VStack(alignment: .leading, spacing: 10) {
            ChallengeSectionTitle(title: "Clock")
            HStack(spacing: 8) {
                ForEach(OnlineLobby.clocks) { option in
                    ChallengeChip(title: option.name, isOn: control == option, theme: theme) {
                        control = option
                    }
                    .accessibilityLabel(option.detail)
                    .disabled(lobby.isSearching)
                }
            }
            Text(control.detail)
                .font(theme.challengeFont(12))
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private var waitingList: some View {
        let players = lobby.sorted(for: clock)
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                ChallengeSectionTitle(title: "Waiting now")
                if lobby.hasLoaded {
                    OnlineLiveDot(theme: theme)
                }
            }
            if players.isEmpty {
                emptyList
            } else {
                VStack(spacing: 0) {
                    ForEach(players) { player in
                        OnlinePlayerRow(player: player, theme: theme, sameClock: player.clock == clock,
                                        isChallenging: lobby.challenging == player.id,
                                        isBusy: lobby.challenging != nil || lobby.phase == .starting) {
                            Task { await lobby.challenge(player, name: name) }
                        }
                        if player.id != players.last?.id {
                            Divider().overlay(Color.white.opacity(0.06)).padding(.leading, 64)
                        }
                    }
                }
                .padding(.vertical, 4)
                .challengeGlass(RoundedRectangle(cornerRadius: 20, style: .continuous))
            }
        }
    }

    private var emptyList: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: lobby.hasLoaded ? "person.2" : "antenna.radiowaves.left.and.right")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(.secondary)
                .frame(width: 34, height: 34)
            VStack(alignment: .leading, spacing: 3) {
                Text(lobby.hasLoaded ? "Nobody is waiting right now" : "Looking for players…")
                    .font(theme.challengeFont(15, .semibold))
                Text("Find a game and you're first in line. Anyone who opens Play online sees you and can take you on.")
                    .font(theme.challengeFont(13))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(14)
        .challengeGlass(RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    private var bottomBar: some View {
        VStack(spacing: 10) {
            if let problem = lobby.problem {
                Text(problem)
                    .font(theme.challengeFont(13))
                    .foregroundStyle(ChallengeColors.urgent)
                    .multilineTextAlignment(.center)
                    .transition(.opacity)
            }
            switch lobby.phase {
            case .searching(let waitingClock, let since):
                VStack(spacing: 10) {
                    OnlineQuietCard(since: since, theme: theme,
                                    playRival: { center.playComputerInstead() },
                                    invite: { center.compose() })
                    OnlineSearchingBar(clock: waitingClock, since: since, theme: theme) {
                        Task { await lobby.cancel() }
                    }
                }
                .transition(.opacity.combined(with: .move(edge: .bottom)))
            case .starting:
                HStack(spacing: 10) {
                    ProgressView()
                    Text("Starting your game…")
                        .font(theme.challengeFont(16, .semibold))
                }
                .frame(maxWidth: .infinity, minHeight: 52)
                .challengeGlass(Capsule(style: .continuous))
            case .browsing:
                Button {
                    Task { await lobby.find(clock: clock, name: name) }
                } label: {
                    Label("Find a game · \(clock.label)", systemImage: "bolt.fill")
                }
                .buttonStyle(ChallengeButtonStyle(kind: .primary, theme: theme))
                .disabled(lobby.challenging != nil)
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 10)
        .padding(.bottom, 8)
        .frame(maxWidth: 560)
        .frame(maxWidth: .infinity)
        .animation(.snappy(duration: 0.25), value: lobby.problem)
    }
}

/// One waiting player: initial, name and rating, their clock and how long they have waited, and Play.
struct OnlinePlayerRow: View {
    let player: LobbyPlayer
    let theme: BoardTheme
    /// At the clock the player picked: shown first, with the accent.
    let sameClock: Bool
    let isChallenging: Bool
    let isBusy: Bool
    let play: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            ChallengeAvatar(name: player.name, theme: theme, size: 40, online: true)
            VStack(alignment: .leading, spacing: 2) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(player.name)
                        .font(theme.challengeFont(16, .semibold))
                        .lineLimit(1)
                    Text(player.ratingLabel)
                        .font(theme.challengeFont(13, .medium).monospacedDigit())
                        .foregroundStyle(.secondary)
                }
                Text("\(player.clock.kind) · \(player.clock.label) · \(Self.waited(player.waitingFor))")
                    .font(theme.challengeFont(12.5).monospacedDigit())
                    .foregroundStyle(sameClock ? AnyShapeStyle(theme.challengeAccent) : AnyShapeStyle(HierarchicalShapeStyle.secondary))
                    .lineLimit(1)
            }
            Spacer(minLength: 8)
            Button(action: play) {
                ZStack {
                    Text("Play").opacity(isChallenging ? 0 : 1)
                    if isChallenging { ProgressView().controlSize(.small) }
                }
            }
            .buttonStyle(ChallengeButtonStyle(kind: sameClock ? .primary : .glass, theme: theme, height: 38))
            .frame(width: 86)
            .disabled(isBusy)
            .accessibilityLabel("Play \(player.name), rated \(player.ratingLabel), \(player.clock.phrase)")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }

    /// "just now", "waiting 0:42", "waiting 3 min".
    static func waited(_ ms: Double) -> String {
        let seconds = Int(ms / 1000)
        if seconds < 5 { return "just now" }
        if seconds < 60 { return "waiting 0:\(String(format: "%02d", seconds))" }
        return "waiting \(seconds / 60) min"
    }
}

/// While waiting in the lobby: the clock, a count-up, and Cancel.
struct OnlineSearchingBar: View {
    let clock: FriendClock
    let since: Date
    let theme: BoardTheme
    let cancel: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            OnlineLiveDot(theme: theme, size: 10)
                .padding(.leading, 6)
            VStack(alignment: .leading, spacing: 1) {
                Text("Finding an opponent · \(clock.label)")
                    .font(theme.challengeFont(15, .semibold))
                    .lineLimit(1)
                TimelineView(.periodic(from: since, by: 1)) { context in
                    let seconds = max(0, Int(context.date.timeIntervalSince(since)))
                    Text("You're in the lobby · \(seconds / 60):\(String(format: "%02d", seconds % 60))")
                        .font(theme.challengeFont(12.5).monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Button("Cancel", action: cancel)
                .buttonStyle(ChallengeButtonStyle(kind: .glass, theme: theme, height: 40))
                .frame(width: 100)
        }
        .padding(6)
        .padding(.leading, 8)
        .challengeGlass(Capsule(style: .continuous))
        .accessibilityElement(children: .contain)
    }
}

/// After a quiet half minute in the lobby: a way to play right now, so waiting never ends in nothing.
struct OnlineQuietCard: View {
    let since: Date
    let theme: BoardTheme
    let playRival: () -> Void
    let invite: () -> Void

    /// How long the lobby waits before offering another way to play.
    static let patience: TimeInterval = 30

    var body: some View {
        TimelineView(.periodic(from: since, by: 1)) { context in
            let waited: TimeInterval = context.date.timeIntervalSince(since)
            if waited >= Self.patience {
                card
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
            }
        }
    }

    private var card: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("It's quiet right now")
                .font(theme.challengeFont(15, .semibold))
            Text("Keep waiting, or play now: a rival on this phone, or a friend with a link.")
                .font(theme.challengeFont(13))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 8) {
                Button("Play a rival", action: playRival)
                    .buttonStyle(ChallengeButtonStyle(kind: .primary, theme: theme, height: 40))
                Button("Invite a friend", action: invite)
                    .buttonStyle(ChallengeButtonStyle(kind: .glass, theme: theme, height: 40))
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .challengeGlass(RoundedRectangle(cornerRadius: 20, style: .continuous))
    }
}

/// A small dot in the accent that breathes, for "live".
struct OnlineLiveDot: View {
    let theme: BoardTheme
    var size: CGFloat = 7

    @State private var breathe = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Circle()
            .fill(theme.challengeAccent)
            .frame(width: size, height: size)
            .background {
                Circle()
                    .fill(theme.challengeAccent.opacity(0.35))
                    .scaleEffect(breathe ? 2.4 : 1)
                    .opacity(breathe ? 0 : 1)
            }
            .onAppear {
                guard !reduceMotion else { return }
                withAnimation(.easeOut(duration: 1.6).repeatForever(autoreverses: false)) { breathe = true }
            }
            .accessibilityHidden(true)
    }
}

/// The fair-play promise for games with players online.
struct OnlineFairPlayCard: View {
    let theme: BoardTheme

    static let text = "Online games are rated and fair: no hints or analysis. If you leave the app for over a minute, your opponent can claim the win. Screenshots are reported, and you can report a name or cheating from the game."

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "checkmark.shield.fill")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(theme.challengeAccent)
                .frame(width: 34, height: 34)
                .background(theme.challengeAccent.opacity(0.14), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            VStack(alignment: .leading, spacing: 3) {
                Text("Fair play")
                    .font(theme.challengeFont(15, .semibold))
                Text(Self.text)
                    .font(theme.challengeFont(13))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(14)
        .challengeGlass(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .accessibilityElement(children: .combine)
    }
}
