import ChessKit
import SwiftUI

/// The glass dock at the foot of the home: the four ways into the app, the same every day.
/// It never lights one up: it is a row of doors, not tabs. Once the board window has scrolled
/// away, the dock folds to its icons and the window's button rides along at its side.
struct HomeDock: View {
    let tone: HomeTone
    let upNext: HomeUpNext
    /// The board window has scrolled out of sight.
    let compact: Bool
    let actions: HomeActions
    let openYou: () -> Void
    let primary: () -> Void

    @ScaledMetric(relativeTo: .body) private var icon: CGFloat = 25
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private struct Door: Identifiable {
        let title: String
        let glyph: String
        let hint: String
        let action: () -> Void
        var id: String { title }
    }

    private var doors: [Door] {
        [
            Door(title: "Train", glyph: Glyphs.train, hint: "Lessons with \(Coach.current.title) and the Grandmaster Room", action: actions.train),
            Door(title: "Puzzles", glyph: Glyphs.puzzles, hint: "Rated puzzles and Puzzle Rush", action: actions.puzzles),
            Door(title: "Analyze", glyph: Glyphs.analyze, hint: "Find the best move in any position", action: actions.analyze),
            Door(title: "You", glyph: Glyphs.king, hint: "Your pieces, your games and Settings", action: openYou),
        ]
    }

    var body: some View {
        HStack(spacing: 8) {
            if compact {
                HomeClockCapsule(upNext: upNext, tone: tone, action: primary)
                    .transition(reduceMotion ? .opacity : .move(edge: .leading).combined(with: .opacity))
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
        .animation(reduceMotion ? .easeOut(duration: 0.2) : .spring(response: 0.42, dampingFraction: 0.86), value: compact)
        .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
    }

    private func button(_ door: Door) -> some View {
        Button(action: door.action) {
            VStack(spacing: 3) {
                Glyph(name: door.glyph, size: icon)
                if !compact {
                    Text(door.title)
                        .font(.app(.caption2, weight: .medium))
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

/// Your own things in one glass panel: your pieces, your games and Settings (and Pro, once there is one).
/// It opens from the dock's You, or by pulling the board down, and comes from where it was
/// asked for. Everything else has its own door, so nothing here is found twice.
struct HomeYouPanel: View {
    let tone: HomeTone
    let piecesLine: String
    let gamesLine: String
    let actions: HomeActions
    let fromTop: Bool
    let close: () -> Void

    @AccessibilityFocusState private var titleFocused: Bool
    @State private var drag: CGFloat = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .center) {
                Text("You")
                    .font(HomeType.section)
                    .foregroundStyle(tone.ink)
                    .accessibilityAddTraits(.isHeader)
                    .accessibilityFocused($titleFocused)
                Spacer(minLength: 0)
                Button(action: close) {
                    Image(systemName: "xmark")
                        .font(.app(.body, weight: .semibold))
                        .foregroundStyle(tone.ink2)
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(HomePressStyle())
                .accessibilityLabel("Close")
                // The cross sits in the corner the card's inset leaves, its glyph in line with the rows' chevrons.
                .padding(.trailing, -14)
            }
            VStack(spacing: 0) {
                HomeLinkRow(title: "Your pieces", detail: piecesLine, tone: tone) { go(actions.army) }
                HomeHairline(tone: tone)
                HomeLinkRow(title: "Your games", detail: gamesLine, tone: tone) { go(actions.rewind) }
                HomeHairline(tone: tone)
                HomeLinkRow(title: "Settings", detail: "Board look, sound, hints", tone: tone) { go(actions.settings) }
                if let premium = actions.premium {
                    HomeHairline(tone: tone)
                    HomeLinkRow(title: "Chess Game Killer Pro", detail: "Everything, with no limits", tone: tone) { go(premium) }
                }
            }
        }
        .padding(.horizontal, HomeMetrics.inset)
        .padding(.top, 8)
        .padding(.bottom, 4)
        .homePane(RoundedRectangle(cornerRadius: HomeMetrics.cardRadius, style: .continuous), tone: tone)
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

    /// Closes the panel, then opens what was picked.
    private func go(_ action: @escaping () -> Void) {
        close()
        action()
    }
}

/// While the board is pulled down: a small glass tab under the status bar, a king in a ring
/// that fills, and the word "You". Let go once the ring is full and the You panel opens.
struct HomePullCue: View {
    let scroll: HomeScroll
    let tone: HomeTone
    let threshold: CGFloat
    let armed: Bool

    var body: some View {
        let pull = min(max(-scroll.y / threshold, 0), 1)
        let full = pull >= 1 || armed
        HStack(spacing: 7) {
            ZStack {
                Circle()
                    .stroke(tone.ink.opacity(0.22), lineWidth: 1.5)
                Circle()
                    .trim(from: 0, to: pull)
                    .stroke(tone.metal, style: StrokeStyle(lineWidth: 1.5, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                Glyph(name: Glyphs.king, size: 14)
                    .foregroundStyle(full ? tone.metal : tone.ink)
            }
            .frame(width: 26, height: 26)
            Text("You")
                .font(.app(.footnote, weight: .semibold))
                .foregroundStyle(full ? tone.metal : tone.ink)
        }
        .padding(.leading, 5)
        .padding(.trailing, 12)
        .padding(.vertical, 4)
        .homePane(Capsule(), tone: tone, weight: .bar)
        .scaleEffect(0.8 + 0.2 * pull)
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

/// Under the dock, and a little above it: the page dissolves into a soft frost before it
/// reaches the dock, so no card is ever seen cut by the dock or carrying on beneath it.
struct HomeBottomEdge: View {
    let tone: HomeTone
    /// How far above the dock the page starts to fade.
    let fade: CGFloat

    var body: some View {
        ZStack {
            Rectangle().fill(.ultraThinMaterial)
            tone.canvas.opacity(0.8)
        }
        .mask {
            VStack(spacing: 0) {
                LinearGradient(colors: [.clear, .black], startPoint: .top, endPoint: .bottom)
                    .frame(height: fade)
                Color.black
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// The board window's button, folded into the dock once the window has scrolled away: one
/// tap to resume or to start the next game, from anywhere on the page. It is the window's own
/// ivory button, so the way to play looks the same all the way down the page.
struct HomeClockCapsule: View {
    let upNext: HomeUpNext
    let tone: HomeTone
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            // The longest label that fits beside the dock, down to the play mark alone.
            ViewThatFits(in: .horizontal) {
                label(title, subtitle)
                label(title, shortSubtitle)
                label(title, nil)
                label(shortTitle, shortSubtitle)
                label(shortTitle, nil)
                Image(systemName: "play.fill")
                    .font(.app(.body, weight: .bold))
            }
            .foregroundStyle(tone.onIvory)
            .padding(.horizontal, 14)
            .frame(maxWidth: .infinity, minHeight: 56)
            .background { HomeIvoryFill(tone: tone) }
            .contentShape(Capsule())
        }
        .buttonStyle(HomePressStyle())
        .accessibilityLabel(upNext.inProgress ? "Resume your game against \(upNext.rival.name)" : "Play \(upNext.rival.name)")
        .accessibilityValue(subtitle)
        .accessibilityInputLabels(inputLabels)
    }

    private var inputLabels: [String] {
        upNext.inProgress ? ["Resume"] : ["Play", "Play \(upNext.rival.name)"]
    }

    private var title: String { upNext.inProgress ? "Resume" : "Play \(upNext.rival.name)" }
    private var shortTitle: String { upNext.inProgress ? "Resume" : "Play" }

    private var side: String {
        upNext.randomSide ? "Either side" : (upNext.playerColor == .white ? "White" : "Black")
    }

    /// The game in a few words: "White · No clock", "Your move · 4:12".
    private var subtitle: String {
        if upNext.inProgress {
            if let time = upNext.yourTime { return "\(shortSubtitle) · \(time.clockLabel)" }
            return shortSubtitle
        }
        return "\(side) · \(upNext.timeControl.name)"
    }

    /// Fewer words for a narrow capsule: whose move it is, or your side.
    private var shortSubtitle: String {
        upNext.inProgress ? (upNext.yourMove ? "Your move" : "Their move") : side
    }

    private func label(_ title: String, _ subtitle: String?) -> some View {
        VStack(spacing: 0) {
            Text(title)
                .font(.app(.subheadline, weight: .semibold))
            if let subtitle {
                Text(subtitle)
                    .font(.app(.caption).monospacedDigit())
                    .opacity(0.68)
            }
        }
        .lineLimit(1)
        .fixedSize()
    }
}
