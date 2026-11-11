import ChessKit
import SwiftUI

/// Making a challenge: your name, the clock and your side, then the link to send by text or email.
/// Below, a code to join someone else's game, and the friend games on this phone.
struct ChallengeComposerView: View {
    let composer: ChallengeComposer
    let theme: BoardTheme

    @Environment(ChallengeCenter.self) private var center
    @AppStorage(ChallengeName.key) private var name = ""
    @AppStorage("challenge.clock") private var control: TimeControl = .rapid10
    @AppStorage("challenge.side") private var side: SideChoice = .white
    @AppStorage("haptics") private var hapticsOn = true
    @State private var joining = false
    @State private var code = ""
    @State private var codeProblem: String?
    @State private var copied = false
    @State private var findText = ""
    @State private var pickingUsername = false
    @FocusState private var focus: Field?

    private enum Field {
        case code, find
    }

    private var friends: FriendDirectory { center.friends }

    /// The clocks a friend game offers, as on the server.
    static let clocks: [TimeControl] = [.blitz3Plus2, .blitz5, .rapid10, .rapid15Plus10, .unlimited]

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                if let created = composer.created {
                    createdContent(created)
                        .transition(.opacity.combined(with: .scale(scale: 0.98)))
                } else {
                    form
                        .transition(.opacity)
                }
            }
            .frame(maxWidth: 560)
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 20)
            .padding(.top, 12)
            .padding(.bottom, 28)
            .animation(.snappy(duration: 0.35), value: composer.created?.code)
        }
        .scrollDismissesKeyboard(.interactively)
        .safeAreaInset(edge: .top, spacing: 0) {
            ChallengeTopBar(title: composer.created == nil ? "Challenge a friend" : "Send the link", theme: theme,
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
        .sensoryFeedback(.success, trigger: composer.created?.code) { _, new in hapticsOn && new != nil }
        .sensoryFeedback(.selection, trigger: control) { _, _ in hapticsOn }
        .sensoryFeedback(.selection, trigger: side) { _, _ in hapticsOn }
        .sensoryFeedback(.selection, trigger: composer.recipient) { _, _ in hapticsOn }
        .task { await friends.refresh(name: name) }
        .onChange(of: findText) { _, text in friends.search(text) }
        .sheet(isPresented: $pickingUsername) {
            UsernamePicker(name: name, theme: theme)
                .environment(center)
        }
    }

    // MARK: Send to a friend by username

    private var sendToSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            ChallengeSectionTitle(title: "Your people")
            if friends.you == nil {
                usernameCard
            }
            if friends.people.isEmpty {
                HStack(alignment: .center, spacing: 14) {
                    AddFace(theme: theme, action: addFriend)
                    Text("Add a friend by username and they stay here. Not in the app yet? Create the challenge and send its link or QR code.")
                        .font(theme.challengeFont(13))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(.vertical, 4)
                .padding(.horizontal, 2)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(alignment: .top, spacing: 14) {
                        AddFace(theme: theme, action: addFriend)
                        ForEach(friends.people) { person in
                            PersonFace(person: person, isOn: composer.recipient == person, theme: theme) {
                                pick(composer.recipient == person ? nil : person)
                            }
                        }
                    }
                    .padding(.vertical, 4)
                    .padding(.horizontal, 2)
                }
                .scrollClipDisabled()
            }
            if let recipient = composer.recipient {
                RecipientRow(person: recipient, theme: theme) { pick(nil) }
                    .transition(.opacity.combined(with: .scale(scale: 0.97)))
            } else {
                findField
                findResults
            }
            if friends.you != nil {
                youRow
            }
        }
        .animation(.snappy(duration: 0.25), value: composer.recipient)
        .animation(.snappy(duration: 0.25), value: friends.results)
    }

    private var findField: some View {
        HStack(spacing: 10) {
            Text("@")
                .font(theme.challengeFont(17, .semibold))
                .foregroundStyle(theme.challengeAccent)
            TextField("Add a friend", text: $findText, prompt: Text("Add a friend by username or name"))
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .submitLabel(.search)
                .font(theme.challengeFont(17, .medium))
                .focused($focus, equals: .find)
            if friends.isSearching {
                ProgressView().controlSize(.small)
            } else if !findText.isEmpty {
                Button {
                    findText = ""
                } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(.tertiary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Clear")
            }
        }
        .padding(.horizontal, 16)
        .frame(height: 50)
        .challengeGlass(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    @ViewBuilder
    private var findResults: some View {
        let typed = findText.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: "@", with: "")
        if typed.count >= 2 {
            VStack(spacing: 0) {
                if friends.results.isEmpty, !friends.isSearching {
                    Text("Nobody by that name yet. Send them a link instead.")
                        .font(theme.challengeFont(14))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(14)
                }
                ForEach(Array(friends.results.enumerated()), id: \.element.id) { index, person in
                    if index > 0 {
                        Rectangle().fill(Color.primary.opacity(0.08)).frame(height: 0.5).padding(.leading, 62)
                    }
                    Button {
                        // Found is kept: they join Your people whether or not a game goes out now.
                        friends.add(person)
                        pick(person)
                    } label: {
                        PersonLine(person: person, theme: theme)
                    }
                    .buttonStyle(ChallengePressStyle())
                }
            }
            .challengeGlass(RoundedRectangle(cornerRadius: 18, style: .continuous))
            .transition(.opacity)
        }
    }

    /// The player's own username, with the way to change it.
    private var youRow: some View {
        Button {
            pickingUsername = true
        } label: {
            (Text("You're ").foregroundStyle(.secondary)
                + Text("@\(friends.you?.username ?? "")").fontWeight(.semibold).foregroundStyle(Color.primary)
                + Text("  ·  Change").foregroundStyle(theme.challengeAccent))
                .font(theme.challengeFont(13))
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    /// Before the player has a username: a clear card to pick one, first on the screen.
    private var usernameCard: some View {
        Button {
            pickingUsername = true
        } label: {
            HStack(spacing: 12) {
                Text("@")
                    .font(theme.challengeFont(19, .bold))
                    .foregroundStyle(theme.challengeAccent)
                    .frame(width: 38, height: 38)
                    .background(Circle().fill(theme.challengeAccent.opacity(0.14)))
                    .overlay(Circle().strokeBorder(theme.challengeAccent.opacity(0.35), lineWidth: 0.75))
                VStack(alignment: .leading, spacing: 2) {
                    Text("Pick your username")
                        .font(theme.challengeFont(16, .semibold))
                        .foregroundStyle(Color.primary)
                    Text("Friends find you by it and challenge you in the app.")
                        .font(theme.challengeFont(13))
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 8)
                Image(systemName: "chevron.right")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 12)
            .contentShape(Rectangle())
        }
        .buttonStyle(ChallengePressStyle())
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous)
            .strokeBorder(theme.challengeAccent.opacity(0.6), lineWidth: 1))
        .challengeGlass(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .accessibilityLabel("Pick your username. Friends find you by it and challenge you in the app.")
    }

    /// The Add tile: on to the find box, with nobody picked.
    private func addFriend() {
        composer.recipient = nil
        Task { @MainActor in focus = .find }
    }

    /// Picks a friend (or nobody). Sending needs the player's own username first.
    private func pick(_ person: FriendPerson?) {
        composer.recipient = person
        if person != nil {
            findText = ""
            friends.clearSearch()
            focus = nil
            if friends.you == nil { pickingUsername = true }
        }
    }

    // MARK: Before the challenge exists

    private var form: some View {
        VStack(alignment: .leading, spacing: 24) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Play a friend")
                    .font(theme.challengeFont(30, .bold))
                Text("Pick a friend by username, or send a link. They play in the app, or right in the browser.")
                    .font(theme.challengeFont(15))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.top, 8)

            sendToSection

            VStack(alignment: .leading, spacing: 10) {
                ChallengeSectionTitle(title: "Your name")
                ChallengeNameField(name: $name, theme: theme)
                Text("Your friend sees this name.")
                    .font(theme.challengeFont(12))
                    .foregroundStyle(.tertiary)
            }

            VStack(alignment: .leading, spacing: 10) {
                ChallengeSectionTitle(title: "Clock")
                HStack(spacing: 8) {
                    ForEach(Self.clocks) { clock in
                        ChallengeChip(title: clock.name, isOn: control == clock, theme: theme) {
                            control = clock
                        }
                        .accessibilityLabel(clock == .unlimited ? "No clock" : clock.detail)
                    }
                }
                Text(control.detail)
                    .font(theme.challengeFont(12))
                    .foregroundStyle(.secondary)
                    .contentTransition(.opacity)
                    .animation(.snappy(duration: 0.2), value: control)
            }

            VStack(alignment: .leading, spacing: 10) {
                ChallengeSectionTitle(title: "You play")
                ChallengeSidePicker(side: $side, theme: theme)
            }

            FairPlayCard(theme: theme)

            joinRow

            FriendGamesList(theme: theme)
        }
    }

    @ViewBuilder
    private var joinRow: some View {
        if joining {
            VStack(alignment: .leading, spacing: 10) {
                ChallengeSectionTitle(title: "Join a game")
                HStack(spacing: 10) {
                    TextField("Code", text: $code, prompt: Text("Code or link"))
                        .textInputAutocapitalization(.characters)
                        .autocorrectionDisabled()
                        .keyboardType(.asciiCapable)
                        .submitLabel(.join)
                        .font(.system(size: 17, weight: .semibold, design: .monospaced))
                        .padding(.horizontal, 16)
                        .frame(height: 50)
                        .challengeGlass(RoundedRectangle(cornerRadius: 14, style: .continuous))
                        .focused($focus, equals: .code)
                        .onSubmit(join)
                    Button("Join", action: join)
                        .buttonStyle(ChallengeButtonStyle(kind: .primary, theme: theme, height: 50))
                        .frame(width: 92)
                        .disabled(code.trimmingCharacters(in: .whitespaces).isEmpty)
                }
                if let codeProblem {
                    Text(codeProblem)
                        .font(theme.challengeFont(12))
                        .foregroundStyle(ChallengeColors.urgent)
                        .transition(.opacity)
                }
            }
            .transition(.opacity.combined(with: .move(edge: .top)))
        } else {
            Button {
                withAnimation(.snappy) { joining = true }
                focus = .code
            } label: {
                (Text("Have a code? ").foregroundStyle(.secondary)
                    + Text("Join a game").fontWeight(.semibold).foregroundStyle(theme.challengeAccent))
                    .font(theme.challengeFont(15))
                    .frame(maxWidth: .infinity, minHeight: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(ChallengePressStyle())
        }
    }

    private func join() {
        guard let found = ChallengeLink.code(fromText: code) else {
            withAnimation(.snappy) { codeProblem = "A code has 6 letters and numbers, like 7KQ 2XM." }
            return
        }
        codeProblem = nil
        focus = nil
        center.open(code: found)
    }

    // MARK: Once it exists

    private func createdContent(_ created: FriendGame) -> some View {
        let invite = ChallengeInviteContent(game: created, name: name)
        return VStack(spacing: 20) {
            VStack(spacing: 8) {
                Text("Your challenge is ready")
                    .font(theme.challengeFont(26, .bold))
                    .multilineTextAlignment(.center)
                Text(composer.recipient == nil
                     ? "Next to you? Let them scan. Far away? Send the link below."
                     : "Next to you? Let them scan. Or send the link below too.")
                    .font(theme.challengeFont(15))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.top, 12)

            if let delivery = composer.delivery {
                DeliveryRow(delivery: delivery, theme: theme) {
                    Task { await composer.deliver() }
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
            }

            codeCard(created, invite: invite)

            Text("The challenge stays open for 7 days. Find it under Friend games.")
                .font(theme.challengeFont(12))
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
        }
        .animation(.snappy(duration: 0.3), value: composer.delivery)
    }

    private func codeCard(_ created: FriendGame, invite: ChallengeInviteContent) -> some View {
        VStack(spacing: 12) {
            InviteQRCode(url: invite.url)
                .frame(width: 210, height: 210)
                .accessibilityLabel("QR code for the challenge. Your friend scans it with their camera.")
            Text("SCAN, OR TYPE THE CODE")
                .font(.app(.caption, weight: .semibold))
                .tracking(1.4)
                .foregroundStyle(.secondary)
                .padding(.top, 4)
            Text(ChallengeLink.spaced(created.code))
                .font(.system(size: 40, weight: .semibold, design: .monospaced))
                .tracking(3)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .textSelection(.enabled)
                .accessibilityLabel("Code \(created.code.map(String.init).joined(separator: " "))")
            Rectangle()
                .fill(Color.primary.opacity(0.1))
                .frame(height: 0.5)
                .padding(.vertical, 2)
            HStack(spacing: 18) {
                Label(created.clock?.label ?? "No clock", systemImage: "stopwatch")
                HStack(spacing: 6) {
                    PieceImage(piece: Piece(.king, color: created.seat.color, square: .e1), theme: theme, size: 18)
                        .frame(width: 18, height: 18)
                    Text("You play \(created.seat.name)")
                }
            }
            .font(theme.challengeFont(14, .medium))
            .foregroundStyle(Color.primary.opacity(0.85))
        }
        .padding(.vertical, 20)
        .padding(.horizontal, 16)
        .frame(maxWidth: .infinity)
        .challengeGlass(RoundedRectangle(cornerRadius: 24, style: .continuous))
    }

    /// The ways to send the link, as round buttons in a glass dock.
    private func shareDock(_ created: FriendGame) -> some View {
        let invite = ChallengeInviteContent(game: created, name: name)
        return HStack(spacing: 0) {
            SendDockButton(title: "Text", symbol: "message.fill", theme: theme) {
                ChallengeSharing.shared.text(invite) { sent in sentInvite(sent) }
            }
            SendDockButton(title: "Email", symbol: "envelope.fill", theme: theme) {
                ChallengeSharing.shared.mail(invite) { sent in sentInvite(sent) }
            }
            SendDockButton(title: copied ? "Copied" : "Copy link", symbol: copied ? "checkmark" : "link",
                       isOn: copied, theme: theme) {
                ChallengeSharing.copy(invite)
                withAnimation(.snappy) { copied = true }
                Task { @MainActor in
                    try? await Task.sleep(for: .seconds(2))
                    withAnimation(.snappy) { copied = false }
                }
            }
            SendDockButton(title: "More", symbol: "square.and.arrow.up", theme: theme) {
                ChallengeSharing.shared.share(invite) { sent in sentInvite(sent) }
            }
        }
        .padding(.vertical, 12)
        .padding(.horizontal, 6)
        .challengeGlass(RoundedRectangle(cornerRadius: 30, style: .continuous))
        .sensoryFeedback(.success, trigger: copied) { _, new in hapticsOn && new }
    }

    /// Sent: on to the board to wait there.
    private func sentInvite(_ sent: Bool) {
        guard sent else { return }
        composer.goToBoard()
    }

    // MARK: The bar at the foot

    private var bottomBar: some View {
        VStack(spacing: 10) {
            if let problem = composer.problem, composer.created == nil {
                Text(problem)
                    .font(theme.challengeFont(13))
                    .foregroundStyle(ChallengeColors.urgent)
                    .multilineTextAlignment(.center)
                    .transition(.opacity)
            }
            if composer.created == nil {
                Button {
                    focus = nil
                    if composer.recipient != nil, friends.you == nil {
                        pickingUsername = true
                        return
                    }
                    Task { await composer.create(name: name, clock: FriendClock(control), side: side) }
                } label: {
                    ZStack {
                        Label(composer.recipient.map { "Challenge \($0.name)" } ?? "Create challenge", systemImage: "paperplane.fill")
                            .lineLimit(1)
                            .opacity(composer.isCreating ? 0 : 1)
                        if composer.isCreating {
                            ProgressView()
                                .tint(theme.screenTone?.onIvory ?? Color.black.opacity(0.8))
                        }
                    }
                }
                .buttonStyle(ChallengeButtonStyle(kind: .primary, theme: theme))
                .disabled(composer.isCreating)
            } else {
                if let created = composer.created {
                    shareDock(created)
                }
                Button {
                    composer.goToBoard()
                } label: {
                    Label("Go to the board", systemImage: "checkerboard.rectangle")
                }
                .buttonStyle(ChallengeButtonStyle(kind: .primary, theme: theme))
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 12)
        .padding(.bottom, 8)
        .frame(maxWidth: 600)
        .frame(maxWidth: .infinity)
        .background { ChallengeBarBackground() }
        .animation(.snappy(duration: 0.25), value: composer.problem)
    }
}

/// One way to send the invite: a round glass button over its name.
private struct SendDockButton: View {
    let title: String
    let symbol: String
    var isOn = false
    let theme: BoardTheme
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 6) {
                Image(systemName: symbol)
                    .font(.system(size: 19, weight: .semibold))
                    .foregroundStyle(theme.challengeAccent)
                    .contentTransition(.symbolEffect(.replace))
                    .frame(width: 50, height: 50)
                    .background(Circle().fill(theme.challengeAccent.opacity(isOn ? 0.28 : 0.14)))
                    .overlay(Circle().strokeBorder(theme.challengeAccent.opacity(0.35), lineWidth: 0.75))
                Text(title)
                    .font(theme.challengeFont(11, .semibold))
                    .foregroundStyle(isOn ? theme.challengeAccent : Color.primary.opacity(0.85))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(ChallengePressStyle())
        .accessibilityLabel(title)
    }
}

/// A player's round face: the first letter of their name, a green ring while they're online.
struct PersonAvatar: View {
    let person: FriendPerson
    var size: CGFloat = 52
    let theme: BoardTheme

    var body: some View {
        Text(person.initial)
            .font(.system(size: size * 0.38, weight: .bold, design: .serif))
            .foregroundStyle(Color.black.opacity(0.82))
            .frame(width: size, height: size)
            .background(
                Circle().fill(LinearGradient(colors: [Color(hex: 0xEBC57A), Color(hex: 0x8A6A33)],
                                             startPoint: .topLeading, endPoint: .bottomTrailing))
            )
            .overlay {
                if person.online {
                    Circle()
                        .strokeBorder(Color(hex: 0x7FCF8C), lineWidth: 2)
                        .padding(-4)
                }
            }
            .accessibilityHidden(true)
    }
}

/// One of the player's people, in the row along the top: tap to send them the challenge.
private struct PersonFace: View {
    let person: FriendPerson
    let isOn: Bool
    let theme: BoardTheme
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 7) {
                PersonAvatar(person: person, theme: theme)
                    .overlay {
                        if isOn {
                            Circle().strokeBorder(theme.challengeAccent, lineWidth: 2.5).padding(-7)
                        }
                    }
                    .padding(6)
                Text(person.handle)
                    .font(theme.challengeFont(12, isOn ? .semibold : .medium))
                    .foregroundStyle(isOn ? theme.challengeAccent : Color.primary.opacity(0.85))
                    .lineLimit(1)
                    .frame(maxWidth: 74)
            }
        }
        .buttonStyle(ChallengePressStyle())
        .accessibilityLabel("\(person.name), \(person.handle)\(person.online ? ", online" : "")")
        .accessibilityAddTraits(isOn ? .isSelected : [])
    }
}

/// The first face in the row: add a friend.
private struct AddFace: View {
    let theme: BoardTheme
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 7) {
                Image(systemName: "plus")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(theme.challengeAccent)
                    .frame(width: 52, height: 52)
                    .overlay(Circle().strokeBorder(theme.challengeAccent.opacity(0.7),
                                                   style: StrokeStyle(lineWidth: 1.2, dash: [4, 4])))
                    .padding(6)
                Text("Add")
                    .font(theme.challengeFont(12, .medium))
                    .foregroundStyle(Color.primary.opacity(0.85))
            }
        }
        .buttonStyle(ChallengePressStyle())
        .accessibilityLabel("Add a friend")
    }
}

/// A player in the find results: face, name and username.
private struct PersonLine: View {
    let person: FriendPerson
    let theme: BoardTheme

    var body: some View {
        HStack(spacing: 12) {
            PersonAvatar(person: person, size: 38, theme: theme)
            VStack(alignment: .leading, spacing: 2) {
                Text(person.name)
                    .font(theme.challengeFont(16, .semibold))
                    .foregroundStyle(Color.primary)
                Text(person.online ? "\(person.handle) · online" : person.handle)
                    .font(theme.challengeFont(13))
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
            Image(systemName: "plus.circle.fill")
                .font(.system(size: 22))
                .foregroundStyle(theme.challengeAccent)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .contentShape(Rectangle())
    }
}

/// The friend the challenge goes to, with a way to change your mind.
private struct RecipientRow: View {
    let person: FriendPerson
    let theme: BoardTheme
    let clear: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            PersonAvatar(person: person, size: 38, theme: theme)
            VStack(alignment: .leading, spacing: 2) {
                Text("Sending to \(person.name)")
                    .font(theme.challengeFont(16, .semibold))
                Text("\(person.handle) gets it in the app\(person.online ? ", right now" : "")")
                    .font(theme.challengeFont(13))
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
            Button(action: clear) {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 22))
                    .foregroundStyle(.tertiary)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Don't send to \(person.name)")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous)
            .strokeBorder(theme.challengeAccent.opacity(0.6), lineWidth: 1))
        .challengeGlass(RoundedRectangle(cornerRadius: 18, style: .continuous))
    }
}

/// How sending to a friend by username went.
private struct DeliveryRow: View {
    let delivery: ChallengeComposer.Delivery
    let theme: BoardTheme
    let retry: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            switch delivery {
            case .sending(let person):
                ProgressView().controlSize(.small)
                Text("Sending to \(person.name)…")
            case .sent(let person):
                Image(systemName: "checkmark.circle.fill").foregroundStyle(Color(hex: 0x7FCF8C))
                Text("Sent to \(person.name). They'll see it when they open the app.")
            case .failed(_, let problem):
                Image(systemName: "exclamationmark.circle.fill").foregroundStyle(ChallengeColors.urgent)
                Text(problem)
                Spacer(minLength: 4)
                Button("Try again", action: retry)
                    .font(theme.challengeFont(13, .semibold))
                    .foregroundStyle(theme.challengeAccent)
            }
        }
        .font(theme.challengeFont(14, .medium))
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .challengeGlass(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}

/// A bar at the foot of a screen: frosted, with a hairline along its top.
struct ChallengeBarBackground: View {
    var body: some View {
        Rectangle()
            .fill(.ultraThinMaterial)
            .overlay(alignment: .top) {
                Rectangle()
                    .fill(Color.primary.opacity(0.1))
                    .frame(height: 0.5)
            }
            .ignoresSafeArea(edges: .bottom)
    }
}
