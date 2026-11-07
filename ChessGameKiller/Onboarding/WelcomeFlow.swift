import ChessKit
import SwiftUI

/// The first run: a tour of what the app does that others don't, seven pages with a moving
/// scene each, then your name, how much chess you've played and which board you like. The last
/// page starts the first game. Skip is always there and goes straight to the questions.
struct WelcomeFlow: View {
    /// False while a game is under way (the tour opened again from Settings): the last page
    /// then just closes, since starting a game would cost the one in progress.
    var canStartGame = true
    /// Called once, after the choices are saved: true to start the first game now.
    let finish: (_ play: Bool, _ choice: WelcomeChoice) -> Void

    @State private var page: Int
    @State private var choice = WelcomeChoice()
    @State private var name = YourName.current() ?? ""
    @FocusState private var nameFocused: Bool
    @AppStorage("sculpted3D") private var sculpted3D = true
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private static let tour = TourPage.allCases.count
    /// The questions after the tour.
    private static let namePage = tour
    private static let experiencePage = tour + 1
    private static let lookPage = tour + 2
    static let pages = tour + 3

    init(canStartGame: Bool = true, page: Int = 0,
         finish: @escaping (_ play: Bool, _ choice: WelcomeChoice) -> Void) {
        self.canStartGame = canStartGame
        self.finish = finish
        _page = State(initialValue: min(max(page, 0), Self.pages - 1))
    }

    private var theme: BoardTheme { .named(choice.look) }
    private var accent: Color { TourPalette.gold }
    private var rival: Rival { choice.experience.level.rival }
    private var tourPage: TourPage? { TourPage(rawValue: page) }

    var body: some View {
        ZStack {
            TourStage(light: tourPage?.light ?? TourPalette.gold.opacity(0.18))
                .ignoresSafeArea()
            VStack(spacing: 0) {
                topBar
                current
                    .id(page)
                    .transition(pageTransition)
                    .frame(maxHeight: .infinity)
                    .padding(.vertical, 8)
                dots
                    .padding(.bottom, 18)
                buttons
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 12)
            .frame(maxWidth: 520)
        }
        .environment(\.colorScheme, .dark)
        .foregroundStyle(TourPalette.ink)
        .tint(accent)
        .animation(reduceMotion ? .easeOut(duration: 0.2) : .spring(response: 0.5, dampingFraction: 0.88), value: page)
        .gesture(swipe)
    }

    private var pageTransition: AnyTransition {
        reduceMotion ? .opacity : .asymmetric(insertion: .move(edge: .trailing).combined(with: .opacity),
                                              removal: .move(edge: .leading).combined(with: .opacity))
    }

    /// Through the tour by swiping, as well as with the button.
    private var swipe: some Gesture {
        DragGesture(minimumDistance: 30)
            .onEnded { value in
                guard abs(value.translation.width) > abs(value.translation.height) * 1.5 else { return }
                if value.translation.width < -50, page < Self.pages - 1 { advance() }
                if value.translation.width > 50, page > 0 { page -= 1 }
            }
    }

    // MARK: Chrome

    private var topBar: some View {
        HStack {
            if page > 0 {
                Button {
                    page -= 1
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.app(.body, weight: .semibold))
                        .frame(width: 36, height: 36)
                }
                .accessibilityLabel("Back")
            }
            Spacer()
            if page < Self.tour {
                Button("Skip") { page = Self.namePage }
                    .font(.app(.body, weight: .semibold))
            }
        }
        .foregroundStyle(TourPalette.ink.opacity(0.64))
        .frame(height: 44)
    }

    private var dots: some View {
        HStack(spacing: 7) {
            ForEach(0..<Self.pages, id: \.self) { index in
                Capsule()
                    .fill(index == page ? accent : TourPalette.ink.opacity(0.22))
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
                if last { done(play: canStartGame) } else { advance() }
            } label: {
                Text(primaryTitle)
                    .font(.app(.headline))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
            }
            .buttonStyle(TourIvoryStyle())
            if last, canStartGame {
                Button("Look around first") { done(play: false) }
                    .font(.app(.subheadline, weight: .semibold))
                    .foregroundStyle(TourPalette.ink.opacity(0.64))
                    .padding(.vertical, 6)
            }
        }
    }

    private var primaryTitle: String {
        if page == 0 { return "Begin" }
        if page == Self.namePage, YourName.clean(name) == nil { return "Skip for now" }
        guard page == Self.pages - 1 else { return "Continue" }
        return canStartGame ? "Play \(rival.name)" : "Done"
    }

    private func advance() {
        if page == Self.namePage { saveName() }
        page += 1
    }

    /// A name typed here becomes the one the app and friends use. Left empty, any name already
    /// given on a challenge stays.
    private func saveName() {
        nameFocused = false
        if YourName.clean(name) != nil { YourName.save(name) }
    }

    private func done(play: Bool) {
        saveName()
        choice.apply()
        Welcome.markSeen()
        finish(play, choice)
    }

    // MARK: Pages

    @ViewBuilder
    private var current: some View {
        if let tourPage {
            TourPageView(page: tourPage)
        } else {
            switch page {
            case Self.namePage: nameQuestion
            case Self.experiencePage: experience
            default: look
            }
        }
    }

    private func heading(_ title: String, _ gold: String, _ subtitle: String? = nil) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            (Text(title + " ") + Text(gold).italic().foregroundColor(TourPalette.gold))
                .font(.system(size: 34, weight: .medium, design: .serif))
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
            if let subtitle {
                Text(subtitle)
                    .font(.app(.subheadline))
                    .foregroundStyle(TourPalette.ink.opacity(0.64))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var nameQuestion: some View {
        VStack(alignment: .leading, spacing: 26) {
            Spacer(minLength: 0)
            Glyph(name: Glyphs.coach, size: 44)
                .foregroundStyle(accent)
            heading("What should \(Coach.current.name)", "call you?",
                    "Your name on the home, in your coach's notes, and on games with friends.")
            TextField("", text: $name, prompt: Text("Your first name").foregroundStyle(TourPalette.ink.opacity(0.3)))
                .font(.system(size: 26, weight: .medium, design: .serif))
                .textContentType(.givenName)
                .textInputAutocapitalization(.words)
                .autocorrectionDisabled()
                .submitLabel(.continue)
                .focused($nameFocused)
                .onSubmit(advance)
                .onChange(of: name) { _, new in
                    if new.count > YourName.maxLength { name = String(new.prefix(YourName.maxLength)) }
                }
                .padding(.vertical, 12)
                .overlay(alignment: .bottom) {
                    Rectangle().fill(nameFocused ? accent : TourPalette.ink.opacity(0.25)).frame(height: 1)
                }
            if let named = YourName.clean(name) {
                Text(YourName.address("Good to see you.", name: named))
                    .font(.app(.subheadline))
                    .foregroundStyle(TourPalette.gold)
                    .transition(.opacity)
            }
            Spacer(minLength: 0)
        }
        .animation(.easeOut(duration: 0.2), value: YourName.clean(name) == nil)
    }

    private var experience: some View {
        VStack(alignment: .leading, spacing: 22) {
            Spacer(minLength: 0)
            heading("How much chess", "have you played?", "This picks your first rival. You can change it before any game.")
            VStack(spacing: 10) {
                ForEach(Experience.allCases) { level in
                    ExperienceCard(level: level, isSelected: choice.experience == level, accent: accent) {
                        withAnimation(.snappy) { choice.experience = level }
                    }
                }
            }
            Spacer(minLength: 0)
        }
    }

    private var look: some View {
        VStack(alignment: .leading, spacing: 22) {
            Spacer(minLength: 0)
            heading("Pick", "your board.", "More looks wait in Settings.")
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
            Spacer(minLength: 0)
        }
    }
}

/// The welcome's one solid button: ivory on the dark stage.
private struct TourIvoryStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(TourPalette.onIvory)
            .padding(.vertical, 6)
            .frame(minHeight: 50)
            .background {
                Capsule()
                    .fill(LinearGradient(colors: [Color(hex: 0xF7F0E2), Color(hex: 0xE9DFCB)], startPoint: .top, endPoint: .bottom))
                    .shadow(color: TourPalette.goldHigh.opacity(0.35), radius: 15, y: 8)
            }
            .contentShape(Capsule())
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .opacity(configuration.isPressed ? 0.9 : 1)
            .animation(.spring(response: 0.25, dampingFraction: 0.8), value: configuration.isPressed)
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
                        .font(.app(.body, weight: .semibold))
                        .foregroundStyle(.primary)
                    Text(level.detail)
                        .font(.app(.caption))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(isSelected ? accent : Color.primary.opacity(0.3))
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
                .font(.app(.subheadline, weight: .semibold))
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
                    .font(.app(.headline))
                Text(rule.text)
                    .font(.app(.subheadline))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityElement(children: .combine)
    }
}
