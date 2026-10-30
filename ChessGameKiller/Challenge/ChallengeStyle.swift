import ChessKit
import SwiftUI

// The look of Challenge a friend: glass bars and cards with hairline edges, plain SF Pro
// (rounded only on Neon), and the theme's one accent.

/// Frosted glass: the real Liquid Glass on iOS 26, a dark material with a hairline edge before it.
struct ChallengeGlass<S: InsettableShape>: ViewModifier {
    let shape: S

    func body(content: Content) -> some View {
        #if compiler(>=6.2)
        if #available(iOS 26.0, *) {
            content.glassEffect(.regular, in: shape)
        } else {
            fallback(content)
        }
        #else
        fallback(content)
        #endif
    }

    private func fallback(_ content: Content) -> some View {
        content
            .background(.ultraThinMaterial, in: shape)
            .background(Color.black.opacity(0.22), in: shape)
            .overlay { shape.strokeBorder(Color.white.opacity(0.13), lineWidth: 0.75) }
    }
}

extension View {
    func challengeGlass<S: InsettableShape>(_ shape: S) -> some View {
        modifier(ChallengeGlass(shape: shape))
    }
}

extension BoardTheme {
    /// The accent, or the system's when a look has none.
    var challengeAccent: Color { accent ?? .accentColor }
    /// Rounded type on Neon, plain SF Pro on every other look.
    var challengeDesign: Font.Design { glows ? .rounded : .default }

    func challengeFont(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font {
        .app(size: size, weight: weight)
    }
}

/// The red of a clock in its last seconds, used for what is urgent and nothing else.
enum ChallengeColors {
    static let urgent = Color(hex: 0xFF4D6D)
}

/// Sinks a touch while pressed.
struct ChallengePressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.965 : 1)
            .opacity(configuration.isPressed ? 0.85 : 1)
            .animation(.spring(response: 0.25, dampingFraction: 0.8), value: configuration.isPressed)
    }
}

/// A full-width capsule: filled with the accent, or glass.
struct ChallengeButtonStyle: ButtonStyle {
    enum Kind {
        case primary, glass, destructive
    }

    let kind: Kind
    let theme: BoardTheme
    var height: CGFloat = 52

    func makeBody(configuration: Configuration) -> some View {
        ChallengeButtonBody(configuration: configuration, kind: kind, theme: theme, height: height)
    }
}

private struct ChallengeButtonBody: View {
    let configuration: ButtonStyleConfiguration
    let kind: ChallengeButtonStyle.Kind
    let theme: BoardTheme
    let height: CGFloat

    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        let shape = Capsule(style: .continuous)
        configuration.label
            .font(theme.challengeFont(height < 48 ? 15 : 17, .semibold))
            .lineLimit(1)
            .minimumScaleFactor(0.8)
            .foregroundStyle(foreground)
            .padding(.horizontal, 18)
            .frame(maxWidth: .infinity, minHeight: height)
            .background {
                if kind == .primary {
                    shape.fill(theme.challengeAccent)
                        .overlay { shape.strokeBorder(Color.white.opacity(0.25), lineWidth: 0.75) }
                } else {
                    Color.clear.challengeGlass(shape)
                }
            }
            .contentShape(shape)
            .scaleEffect(configuration.isPressed ? 0.975 : 1)
            .opacity(isEnabled ? (configuration.isPressed ? 0.88 : 1) : 0.45)
            .animation(.spring(response: 0.25, dampingFraction: 0.8), value: configuration.isPressed)
    }

    private var foreground: Color {
        switch kind {
        case .primary: return Color.black.opacity(0.88)
        case .glass: return Color.primary
        case .destructive: return ChallengeColors.urgent
        }
    }
}

/// A round glass button for a bar: Close, the menu.
struct ChallengeBarButton: View {
    let symbol: String
    let label: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ChallengeBarIcon(symbol: symbol)
        }
        .buttonStyle(ChallengePressStyle())
        .accessibilityLabel(label)
    }
}

/// The icon of a bar button, also used as a menu's label.
struct ChallengeBarIcon: View {
    let symbol: String

    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: 15, weight: .semibold))
            .foregroundStyle(.primary)
            .frame(width: 36, height: 36)
            .background(Color.white.opacity(0.08), in: Circle())
            .overlay { Circle().strokeBorder(Color.white.opacity(0.1), lineWidth: 0.5) }
            .contentShape(Circle())
    }
}

/// The slim glass bar across the top: Close, a title, and one more button.
struct ChallengeTopBar<Trailing: View>: View {
    let title: String
    var detail: String? = nil
    let theme: BoardTheme
    let close: () -> Void
    @ViewBuilder var trailing: Trailing

    var body: some View {
        ZStack {
            VStack(spacing: 1) {
                Text(title)
                    .font(theme.challengeFont(15, .semibold))
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                if let detail {
                    Text(detail)
                        .font(theme.challengeFont(11, .medium))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .transition(.opacity)
                }
            }
            .padding(.horizontal, 48)
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.isHeader)
            HStack(spacing: 0) {
                ChallengeBarButton(symbol: "xmark", label: "Close", action: close)
                Spacer(minLength: 0)
                trailing
                    .frame(width: 36, height: 36)
            }
        }
        .padding(6)
        .frame(height: 48)
        .challengeGlass(Capsule(style: .continuous))
        .animation(.snappy(duration: 0.25), value: detail)
    }
}

/// A person's initial in a circle, with a dot that lights while they have the game open.
struct ChallengeAvatar: View {
    let name: String?
    let theme: BoardTheme
    var size: CGFloat = 38
    /// Nil hides the dot.
    var online: Bool? = nil

    var body: some View {
        let accent = theme.challengeAccent
        Text(initial)
            .font(.app(size: size * 0.42, weight: .semibold))
            .foregroundStyle(.primary)
            .frame(width: size, height: size)
            .background {
                Circle().fill(LinearGradient(colors: [accent.opacity(0.34), accent.opacity(0.1)],
                                             startPoint: .topLeading, endPoint: .bottomTrailing))
            }
            .overlay { Circle().strokeBorder(Color.white.opacity(0.16), lineWidth: 0.75) }
            .overlay(alignment: .bottomTrailing) {
                if let online {
                    Circle()
                        .fill(online ? accent : Color(white: 0.5))
                        .frame(width: size * 0.27, height: size * 0.27)
                        .overlay { Circle().strokeBorder(Color.black.opacity(0.55), lineWidth: 1.5) }
                        .offset(x: 1, y: 1)
                        .animation(.snappy, value: online)
                }
            }
            .accessibilityHidden(true)
    }

    private var initial: String {
        guard let first = name?.trimmingCharacters(in: .whitespacesAndNewlines).first else { return "?" }
        return String(first).uppercased()
    }
}

/// What a friend game promises, said before every challenge is made or taken.
struct FairPlayCard: View {
    let theme: BoardTheme

    static let text = "Friend games are fair: no hints or analysis. In a timed game, if you leave the app for over a minute, your friend can claim the win. Your friend is told if you take a screenshot."

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

/// A section's name, in small capitals.
struct ChallengeSectionTitle: View {
    let title: String

    var body: some View {
        Text(title.uppercased())
            .font(.app(.caption, weight: .semibold))
            .tracking(1.1)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityAddTraits(.isHeader)
    }
}

/// One choice in a row of choices, filled with the accent when chosen.
struct ChallengeChip: View {
    let title: String
    let isOn: Bool
    let theme: BoardTheme
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(theme.challengeFont(15, .semibold).monospacedDigit())
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .foregroundStyle(isOn ? Color.black.opacity(0.88) : Color.primary)
                .padding(.horizontal, 6)
                .frame(maxWidth: .infinity, minHeight: 44)
                .background {
                    let shape = Capsule(style: .continuous)
                    if isOn {
                        shape.fill(theme.challengeAccent)
                    } else {
                        Color.clear.challengeGlass(shape)
                    }
                }
                .contentShape(Capsule(style: .continuous))
        }
        .buttonStyle(ChallengePressStyle())
        .animation(.snappy(duration: 0.2), value: isOn)
        .accessibilityAddTraits(isOn ? .isSelected : [])
    }
}

/// The player's name, as friends will see it.
struct ChallengeNameField: View {
    @Binding var name: String
    let theme: BoardTheme
    var prompt = "Your name"

    var body: some View {
        TextField("Your name", text: $name, prompt: Text(prompt))
            .textContentType(.nickname)
            .textInputAutocapitalization(.words)
            .autocorrectionDisabled()
            .submitLabel(.done)
            .font(theme.challengeFont(17, .medium))
            .padding(.horizontal, 16)
            .frame(height: 50)
            .challengeGlass(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .onChange(of: name) { _, new in
                if new.count > ChallengeName.maxLength { name = String(new.prefix(ChallengeName.maxLength)) }
            }
    }
}

/// A short message floating at the top: a screenshot taken, a friend back, a draw declined.
struct ChallengeToastView: View {
    let toast: OnlineGame.Toast
    let theme: BoardTheme

    var body: some View {
        HStack(spacing: 9) {
            Image(systemName: toast.symbol)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(theme.challengeAccent)
            Text(toast.text)
                .font(theme.challengeFont(14, .medium))
                .lineLimit(2)
                .multilineTextAlignment(.leading)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .challengeGlass(Capsule(style: .continuous))
        .accessibilityElement(children: .combine)
    }
}

/// The White, Black and Random choice, each a king in its card.
struct ChallengeSidePicker: View {
    @Binding var side: SideChoice
    let theme: BoardTheme

    var body: some View {
        HStack(spacing: 10) {
            ForEach(SideChoice.allCases) { choice in
                card(choice)
            }
        }
    }

    private func card(_ choice: SideChoice) -> some View {
        let isOn = side == choice
        let shape = RoundedRectangle(cornerRadius: 16, style: .continuous)
        return Button {
            withAnimation(.snappy(duration: 0.22)) { side = choice }
        } label: {
            VStack(spacing: 6) {
                art(choice)
                    .frame(height: 40)
                Text(name(choice))
                    .font(theme.challengeFont(13, .semibold))
                    .foregroundStyle(isOn ? Color.primary : Color.secondary)
            }
            .frame(maxWidth: .infinity, minHeight: 86)
            .background {
                Color.clear.challengeGlass(shape)
                if isOn {
                    shape.fill(theme.challengeAccent.opacity(0.12))
                    shape.strokeBorder(theme.challengeAccent, lineWidth: 1.5)
                }
            }
            .contentShape(shape)
        }
        .buttonStyle(ChallengePressStyle())
        .accessibilityLabel("Play \(name(choice))")
        .accessibilityAddTraits(isOn ? .isSelected : [])
    }

    @ViewBuilder
    private func art(_ choice: SideChoice) -> some View {
        switch choice {
        case .white:
            PieceImage(piece: Piece(.king, color: .white, square: .e1), theme: theme, size: 38)
        case .black:
            PieceImage(piece: Piece(.king, color: .black, square: .e8), theme: theme, size: 38)
        case .random:
            ZStack {
                PieceImage(piece: Piece(.king, color: .black, square: .e8), theme: theme, size: 30)
                    .offset(x: 7, y: -3)
                PieceImage(piece: Piece(.king, color: .white, square: .e1), theme: theme, size: 30)
                    .offset(x: -7, y: 3)
            }
        }
    }

    private func name(_ choice: SideChoice) -> String {
        switch choice {
        case .white: return "White"
        case .black: return "Black"
        case .random: return "Random"
        }
    }
}
