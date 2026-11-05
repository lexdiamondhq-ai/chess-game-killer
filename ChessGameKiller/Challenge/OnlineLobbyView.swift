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
            if lobby.isSearching || lobby.phase == .starting {
                // The same seats from waiting to found, so the empty one fills in place.
                OnlineSeats(name: name, rating: lobby.you?.label, found: lobby.phase == .starting, theme: theme)
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
            }
            switch lobby.phase {
            case .searching(let waitingClock, let since):
                OnlineSearchingBar(clock: waitingClock, since: since, theme: theme) {
                    Task { await lobby.cancel() }
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

/// Finding a game (O2 on the Tap Moments page): you, VS, and an empty seat where a gold ring
/// turns until someone takes it. When a game is found the seat fills and VS flares.
struct OnlineSeats: View {
    let name: String
    /// Your rating, once the lobby knows it.
    let rating: String?
    let found: Bool
    let theme: BoardTheme

    @State private var arrived = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private static let seat: CGFloat = 54

    var body: some View {
        HStack(alignment: .top, spacing: 18) {
            yourSeat
            Text("VS")
                .font(theme.challengeFont(13, .bold))
                .foregroundStyle(theme.challengeAccent.opacity(found ? 1 : 0.45))
                .scaleEffect(found && !reduceMotion ? 1.25 : 1)
                .frame(height: Self.seat)
            theirSeat
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 6)
        .animation(.spring(response: 0.42, dampingFraction: 0.62), value: found)
        .onAppear {
            withAnimation(.spring(response: 0.5, dampingFraction: 0.8)) { arrived = true }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(found ? "Opponent found" : "Finding an opponent")
    }

    private var yourSeat: some View {
        let shift: CGFloat = arrived || reduceMotion ? 0 : -40
        return VStack(spacing: 6) {
            ChallengeAvatar(name: name.isEmpty ? nil : name, theme: theme, size: Self.seat)
            Text(rating.map { "You · \($0)" } ?? "You")
                .font(theme.challengeFont(12, .semibold).monospacedDigit())
                .lineLimit(1)
        }
        .offset(x: shift)
        .opacity(arrived ? 1 : 0)
    }

    private var theirSeat: some View {
        VStack(spacing: 6) {
            ZStack {
                if found {
                    Circle()
                        .fill(theme.challengeAccent)
                        .overlay {
                            Image(systemName: "checkmark")
                                .font(.system(size: 20, weight: .bold))
                                .foregroundStyle(Color.black.opacity(0.85))
                        }
                        .transition(.scale(scale: 0.3).combined(with: .opacity))
                } else {
                    Circle()
                        .fill(Color.white.opacity(0.06))
                        .overlay { Circle().strokeBorder(Color.white.opacity(0.14), lineWidth: 1) }
                    Text("?")
                        .font(theme.challengeFont(20, .semibold))
                        .foregroundStyle(.secondary)
                    OnlineSeekRing(color: theme.challengeAccent, still: reduceMotion)
                }
            }
            .frame(width: Self.seat, height: Self.seat)
            Text(found ? "Found" : "Finding…")
                .font(theme.challengeFont(12, .semibold))
                .foregroundStyle(found ? AnyShapeStyle(theme.challengeAccent) : AnyShapeStyle(HierarchicalShapeStyle.secondary))
                .lineLimit(1)
        }
    }
}

/// A short gold arc turning round the empty seat.
private struct OnlineSeekRing: View {
    let color: Color
    let still: Bool

    var body: some View {
        TimelineView(.animation(minimumInterval: nil, paused: still)) { context in
            let seconds: Double = context.date.timeIntervalSinceReferenceDate
            let turn: Double = still ? 0 : (seconds.truncatingRemainder(dividingBy: 1.1) / 1.1) * 360
            Circle()
                .trim(from: 0, to: 0.22)
                .stroke(color, style: StrokeStyle(lineWidth: 2, lineCap: .round))
                .rotationEffect(.degrees(turn))
        }
        .accessibilityHidden(true)
    }
}
