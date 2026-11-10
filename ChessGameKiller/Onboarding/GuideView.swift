import SwiftUI

/// Settings › How it works: every hidden gesture and every rule that costs something, in
/// plain words, on one page. Brand names come second, after what the thing does.
struct GuideView: View {
    let theme: BoardTheme
    /// Closes Settings and opens the welcome again.
    let replayWelcome: () -> Void
    @State private var tipsReset = false

    private var accent: Color { theme.trainingAccent }

    /// The hidden gestures, by what they do. (Gesture, then what it's called in the app.)
    static let gestures: [(symbol: String, title: String, text: String)] = [
        ("circle.circle", "Tap the orb for the coach",
         "The round button in the middle of the dock opens the coach: grades, the best moves, undo and new game."),
        ("arrow.down", "Pull the home board down",
         "On the home screen, pull the board down to open You: your pieces, your games and Settings. The You button in the dock does the same."),
        ("rectangle.landscape.rotate", "Turn sideways against the Ashen King",
         "In a game against the Ashen King, turn your phone on its side to sit across his table. Turn it upright again for everything else."),
    ]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                group("Gestures") {
                    ForEach(Self.gestures, id: \.title) { item in
                        GuideRow(symbol: item.symbol, title: item.title, text: item.text, accent: accent)
                    }
                }
                group("Rules that cost something") {
                    ForEach(HouseRule.allCases) { rule in
                        HouseRuleRow(rule: rule, accent: accent)
                    }
                }
                Button {
                    TipBook.resetAll()
                    tipsReset = true
                } label: {
                    Label(tipsReset ? "Tips will show again" : "Show tips again",
                          systemImage: tipsReset ? "checkmark" : "lightbulb")
                        .font(.app(.body, weight: .semibold))
                }
                .disabled(tipsReset)
                Button {
                    replayWelcome()
                } label: {
                    Label("Replay the welcome", systemImage: "sparkles")
                        .font(.app(.body, weight: .semibold))
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 16)
        }
        .tint(accent)
        .background { TrainingBackdrop(theme: theme).ignoresSafeArea() }
        .navigationTitle("How it works")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func group<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(title.uppercased())
                .font(.app(.caption, weight: .semibold))
                .foregroundStyle(.secondary)
                .tracking(1)
            content()
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassPane(RoundedRectangle(cornerRadius: 20, style: .continuous))
    }
}

private struct GuideRow: View {
    let symbol: String
    let title: String
    let text: String
    let accent: Color

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: symbol)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(accent)
                .frame(width: 30)
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.app(.headline))
                Text(text)
                    .font(.app(.subheadline))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityElement(children: .combine)
    }
}
