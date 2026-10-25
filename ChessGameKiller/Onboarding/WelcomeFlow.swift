import ChessKit
import SwiftUI

/// The first run, four short pages over the chosen board's light: what the app is, how much
/// chess you've played, which board you like, and the three rules that cost something.
/// The last page starts the first game. Under a minute, and Skip is always there.
struct WelcomeFlow: View {
    /// False while a game is under way (the tour opened again from Settings): the last page
    /// then just closes, since starting a game would cost the one in progress.
    var canStartGame = true
    /// Called once, after the choices are saved: true to start the first game now.
    let finish: (_ play: Bool, _ choice: WelcomeChoice) -> Void

    @State private var page: Int
    @State private var choice = WelcomeChoice()
    @AppStorage("sculpted3D") private var sculpted3D = true
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private static let pages = 4

    init(canStartGame: Bool = true, page: Int = 0,
         finish: @escaping (_ play: Bool, _ choice: WelcomeChoice) -> Void) {
        self.canStartGame = canStartGame
        self.finish = finish
        _page = State(initialValue: min(max(page, 0), Self.pages - 1))
    }

    private var theme: BoardTheme { .named(choice.look) }
    private var accent: Color { theme.accent ?? .accentColor }
    private var rival: Rival { choice.experience.level.rival }

    var body: some View {
        ZStack {
            ThemeBackdrop(theme: theme)
                .ignoresSafeArea()
                .animation(.easeInOut(duration: 0.4), value: choice.look)
            VStack(spacing: 0) {
                topBar
                Spacer(minLength: 12)
                current
                    .id(page)
                    .transition(pageTransition)
                Spacer(minLength: 12)
                dots
                    .padding(.bottom, 18)
                buttons
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 12)
            .frame(maxWidth: 520)
        }
        .environment(\.colorScheme, .dark)
        .tint(accent)
        .animation(reduceMotion ? .easeOut(duration: 0.2) : .spring(response: 0.45, dampingFraction: 0.88), value: page)
    }

    private var pageTransition: AnyTransition {
        reduceMotion ? .opacity : .asymmetric(insertion: .move(edge: .trailing).combined(with: .opacity),
                                              removal: .move(edge: .leading).combined(with: .opacity))
    }

    // MARK: Chrome

    private var topBar: some View {
        HStack {
            if page > 0 {
                Button {
                    page -= 1
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.body.weight(.semibold))
                        .frame(width: 36, height: 36)
                }
                .accessibilityLabel("Back")
            }
            Spacer()
            if page < Self.pages - 1 {
                Button("Skip") { done(play: false) }
                    .font(.body.weight(.semibold))
            }
        }
        .foregroundStyle(.secondary)
        .frame(height: 44)
    }

    private var dots: some View {
        HStack(spacing: 7) {
            ForEach(0..<Self.pages, id: \.self) { index in
                Capsule()
                    .fill(index == page ? accent : Color.white.opacity(0.22))
                    .frame(width: index == page ? 18 : 6, height: 6)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Page \(page + 1) of \(Self.pages)")
    }

    @ViewBuilder
    private var buttons: some View {
        let last = page == Self.pages - 1
        VStack(spacing: 6) {
            Button {
                if last { done(play: canStartGame) } else { page += 1 }
            } label: {
                Text(primaryTitle)
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
            }
            .buttonStyle(.borderedProminent)
            .buttonBorderShape(.capsule)
            .controlSize(.large)
            .tint(accent)
            .foregroundStyle(Color.black)
            if last, canStartGame {
                Button("Look around first") { done(play: false) }
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 6)
            }
        }
    }

    private var primaryTitle: String {
        guard page == Self.pages - 1 else { return "Continue" }
        return canStartGame ? "Play \(rival.name)" : "Done"
    }

    private func done(play: Bool) {
        choice.apply()
        Welcome.markSeen()
        finish(play, choice)
    }

    // MARK: Pages

    @ViewBuilder
    private var current: some View {
        switch page {
        case 0: hello
        case 1: experience
        case 2: look
        default: rules
        }
    }

    private func heading(_ title: String, _ subtitle: String? = nil) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.system(.largeTitle, design: .themed).weight(.bold))
                .fixedSize(horizontal: false, vertical: true)
            if let subtitle {
                Text(subtitle)
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var hello: some View {
        VStack(alignment: .leading, spacing: 28) {
            Glyph(name: Glyphs.king, size: 44)
                .foregroundStyle(accent)
            heading("Chess, with a coach beside you")
            VStack(alignment: .leading, spacing: 18) {
                WelcomeRow(glyph: Glyphs.play, title: "Play",
                           text: "Five computer rivals, from first moves to grandmaster.", accent: accent)
                WelcomeRow(glyph: Glyphs.coach, title: "Learn",
                           text: "\(Coach.current.title) grades every move and shows you a better one.", accent: accent)
                WelcomeRow(glyph: Glyphs.army, title: "Grow",
                           text: "Your pieces remember every game, earn experience and get names.", accent: accent)
            }
        }
    }

    private var experience: some View {
        VStack(alignment: .leading, spacing: 22) {
            heading("How much chess have you played?", "This picks your first rival. You can change it before any game.")
            VStack(spacing: 10) {
                ForEach(Experience.allCases) { level in
                    ExperienceCard(level: level, isSelected: choice.experience == level, accent: accent) {
                        withAnimation(.snappy) { choice.experience = level }
                    }
                }
            }
        }
    }

    private var look: some View {
        VStack(alignment: .leading, spacing: 22) {
            heading("Pick your board", "More looks wait in Settings.")
            BoardPreview(theme: theme, showBest: false, size: 230,
                         threeD: sculpted3D && SculptedAssets.shared.isLoaded)
                .frame(maxWidth: .infinity)
                .animation(.easeInOut(duration: 0.3), value: choice.look)
            HStack(spacing: 10) {
                ForEach(Welcome.looks, id: \.self) { id in
                    LookChip(look: .named(id), isSelected: choice.look == id, accent: accent) {
                        withAnimation(.easeInOut(duration: 0.3)) { choice.look = id }
                    }
                }
            }
        }
    }

    private var rules: some View {
        VStack(alignment: .leading, spacing: 22) {
            heading("Three things to know", "Before they cost you anything.")
            VStack(alignment: .leading, spacing: 18) {
                ForEach(HouseRule.onWelcome) { rule in
                    HouseRuleRow(rule: rule, accent: accent)
                }
            }
            Text("All of this is in Settings under How it works.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }
}

/// An icon, a bold word and one line.
private struct WelcomeRow: View {
    let glyph: String
    let title: String
    let text: String
    let accent: Color

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            Glyph(name: glyph, size: 26)
                .foregroundStyle(accent)
                .frame(width: 30)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.headline)
                Text(text)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

/// One answer to "how much have you played", on glass, with the first rival it leads to.
private struct ExperienceCard: View {
    let level: Experience
    let isSelected: Bool
    let accent: Color
    let select: () -> Void

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 18, style: .continuous)
        Button(action: select) {
            HStack(spacing: 12) {
                RivalPortrait(rival: level.level.rival, size: 40, glows: false)
                VStack(alignment: .leading, spacing: 2) {
                    Text(level.title)
                        .font(.body.weight(.semibold))
                        .foregroundStyle(.primary)
                    Text(level.detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(isSelected ? accent : Color.white.opacity(0.3))
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .glassPane(shape, tint: isSelected ? accent.opacity(0.18) : nil)
            .overlay { shape.strokeBorder(isSelected ? accent.opacity(0.7) : .clear, lineWidth: 1) }
            .contentShape(shape)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

/// A look's name on glass, under the preview.
private struct LookChip: View {
    let look: BoardTheme
    let isSelected: Bool
    let accent: Color
    let select: () -> Void

    var body: some View {
        Button(action: select) {
            Text(look.name)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(isSelected ? accent : Color.primary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 11)
                .glassPane(Capsule(), tint: isSelected ? accent.opacity(0.18) : nil)
                .overlay { Capsule().strokeBorder(isSelected ? accent.opacity(0.7) : .clear, lineWidth: 1) }
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(look.name) board")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

/// A rule: its icon, a short title and the one-line why.
struct HouseRuleRow: View {
    let rule: HouseRule
    let accent: Color

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: rule.symbol)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(accent)
                .frame(width: 30)
            VStack(alignment: .leading, spacing: 3) {
                Text(rule.title)
                    .font(.headline)
                Text(rule.text)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityElement(children: .combine)
    }
}
