import SwiftUI

/// The glass dock at the foot of the home: the five ways into the app, the same every day.
/// It never lights one up: it is a row of doors, not tabs. Once the clock card has scrolled
/// away, the dock folds to its icons and the clock rides along at its side.
struct HomeDock: View {
    let tone: HomeTone
    let upNext: HomeUpNext
    /// The clock card has scrolled out of sight.
    let compact: Bool
    let actions: HomeActions
    let openYou: () -> Void
    let primary: () -> Void

    @ScaledMetric(relativeTo: .body) private var icon: CGFloat = 25

    private struct Door: Identifiable {
        let title: String
        let glyph: String
        let hint: String
        let action: () -> Void
        var id: String { title }
    }

    private var doors: [Door] {
        [
            Door(title: "Train", glyph: Glyphs.train, hint: "Lessons with Coach Leo and the Grandmaster Room", action: actions.train),
            Door(title: "Puzzles", glyph: Glyphs.puzzles, hint: "Rated puzzles and Puzzle Rush", action: actions.puzzles),
            Door(title: "Analyze", glyph: Glyphs.analyze, hint: "Find the best move in any position", action: actions.analyze),
            Door(title: "Games", glyph: Glyphs.games, hint: "Your saved games, to replay and rewrite", action: actions.rewind),
            Door(title: "You", glyph: Glyphs.king, hint: "Your rating, your pieces and Settings", action: openYou),
        ]
    }

    var body: some View {
        HStack(spacing: 8) {
            if compact {
                HomeClockCapsule(upNext: upNext, tone: tone, action: primary)
                    .transition(.move(edge: .leading).combined(with: .opacity))
            }
            HStack(spacing: 0) {
                ForEach(doors) { door in
                    button(door)
                }
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 4)
            .frame(maxWidth: compact ? nil : 500)
            .homePane(Capsule(), tone: tone, weight: .bar)
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 6)
        .frame(maxWidth: .infinity)
        .animation(.spring(response: 0.42, dampingFraction: 0.86), value: compact)
        .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
    }

    private func button(_ door: Door) -> some View {
        Button(action: door.action) {
            VStack(spacing: 3) {
                Glyph(name: door.glyph, size: icon)
                if !compact {
                    Text(door.title)
                        .font(.caption2.weight(.medium))
                        .lineLimit(1)
                        .fixedSize()
                }
            }
            .foregroundStyle(tone.ink)
            .frame(minWidth: 44, maxWidth: compact ? 44 : .infinity, minHeight: compact ? 48 : 56)
            .contentShape(Rectangle())
        }
        .buttonStyle(HomePressStyle())
        .accessibilityLabel(door.title)
        .accessibilityHint(door.hint)
        .accessibilityShowsLargeContentViewer {
            Glyph(name: door.glyph, size: icon)
            Text(door.title)
        }
    }
}

/// Your own things in one glass panel: your puzzle rating, this week's games and your
/// training streak, then your games, your pieces and Settings. It opens from the dock's
/// You, or by pulling the board down, and comes from where it was asked for.
struct HomeYouPanel: View {
    let tone: HomeTone
    let rating: Int
    let gamesThisWeek: Int
    let streak: Int
    let gamesSaved: Int
    let piecesLine: String
    let actions: HomeActions
    let fromTop: Bool
    let close: () -> Void

    @AccessibilityFocusState private var titleFocused: Bool
    @State private var drag: CGFloat = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .center) {
                Text("You")
                    .font(HomeType.section)
                    .foregroundStyle(tone.ink)
                    .accessibilityAddTraits(.isHeader)
                    .accessibilityFocused($titleFocused)
                Spacer(minLength: 0)
                Button(action: close) {
                    Image(systemName: "xmark")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(tone.ink2)
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(HomePressStyle())
                .accessibilityLabel("Close")
            }
            HStack(spacing: 8) {
                stat(rating.formatted(), "Puzzle rating")
                stat("\(gamesThisWeek)", gamesThisWeek == 1 ? "Game this week" : "Games this week")
                stat(streak > 0 ? "\(streak)" : "–", streak == 1 ? "Day of training" : "Days in a row")
            }
            VStack(spacing: 0) {
                HomeLinkRow(glyph: Glyphs.games, title: "Your games", detail: gamesSaved == 0 ? "None yet" : "\(gamesSaved) saved",
                            tone: tone) { go(actions.rewind) }
                HomeHairline(tone: tone, inset: 46)
                HomeLinkRow(glyph: Glyphs.army, title: "Your pieces", detail: piecesLine, tone: tone) { go(actions.army) }
                HomeHairline(tone: tone, inset: 46)
                HomeLinkRow(glyph: Glyphs.settings, title: "Settings", detail: "Board look, sound, hints", tone: tone) { go(actions.settings) }
                if let premium = actions.premium {
                    HomeHairline(tone: tone, inset: 46)
                    HomeLinkRow(glyph: "crown", title: "Chess Game Killer Pro", detail: "Everything, with no limits", tone: tone) { go(premium) }
                }
            }
            .padding(.horizontal, 12)
            .homePane(RoundedRectangle(cornerRadius: 20, style: .continuous), tone: tone, weight: .well(lit: false))
        }
        .padding(16)
        .homePane(RoundedRectangle(cornerRadius: 32, style: .continuous), tone: tone)
        .offset(y: fromTop ? min(drag, 0) : max(drag, 0))
        .gesture(
            DragGesture(minimumDistance: 12)
                .onChanged { drag = $0.translation.height }
                .onEnded { value in
                    let away = fromTop ? value.predictedEndTranslation.height < -60 : value.predictedEndTranslation.height > 60
                    if away { close() }
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) { drag = 0 }
                }
        )
        .accessibilityElement(children: .contain)
        .accessibilityAddTraits(.isModal)
        .accessibilityAction(.escape, close)
        .onAppear { titleFocused = true }
    }

    private func stat(_ value: String, _ label: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value)
                .font(HomeType.number)
                .monospacedDigit()
                .foregroundStyle(tone.ink)
            Text(label)
                .font(.caption)
                .foregroundStyle(tone.ink2)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .homePane(RoundedRectangle(cornerRadius: 18, style: .continuous), tone: tone, weight: .well(lit: false))
        .accessibilityElement(children: .combine)
    }

    /// Closes the panel, then opens what was picked.
    private func go(_ action: @escaping () -> Void) {
        close()
        action()
    }
}

/// While the board is pulled down: a king in a ring that fills, under the status bar.
/// Let go once it is full and the You panel opens.
struct HomePullCue: View {
    let scroll: HomeScroll
    let tone: HomeTone
    let threshold: CGFloat
    let armed: Bool

    var body: some View {
        let pull = min(max(-scroll.y / threshold, 0), 1)
        ZStack {
            Circle()
                .stroke(tone.ink.opacity(0.22), lineWidth: 2)
            Circle()
                .trim(from: 0, to: pull)
                .stroke(tone.metal, style: StrokeStyle(lineWidth: 2, lineCap: .round))
                .rotationEffect(.degrees(-90))
            Glyph(name: Glyphs.king, size: 18)
                .foregroundStyle(pull >= 1 || armed ? tone.metal : tone.ink)
        }
        .frame(width: 36, height: 36)
        .background(Circle().fill(tone.canvas.opacity(0.4)))
        .scaleEffect(0.7 + 0.3 * pull)
        .opacity(Double(min(pull * 1.6, 1)))
        .frame(maxWidth: .infinity)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// Under the status bar once the page scrolls beneath it: the page dissolves into a soft
/// frost, so text never runs under the clock.
struct HomeTopEdge: View {
    let scroll: HomeScroll
    let tone: HomeTone
    /// How far the page scrolls before cards reach the status bar.
    let start: CGFloat
    let height: CGFloat

    var body: some View {
        let shown = min(max((scroll.y - start) / 60, 0), 1)
        ZStack {
            Rectangle().fill(.ultraThinMaterial)
            tone.canvas.opacity(0.74)
        }
        .mask {
            LinearGradient(stops: [
                .init(color: .black, location: 0),
                .init(color: .black, location: 0.62),
                .init(color: .clear, location: 1),
            ], startPoint: .top, endPoint: .bottom)
        }
        .frame(height: height)
        .frame(maxWidth: .infinity)
        .opacity(Double(shown))
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}
