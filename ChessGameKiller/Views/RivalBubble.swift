import SwiftUI

/// The rival's remark in a speech bubble beside its portrait. It pops in, stays a
/// few seconds and goes; a newer remark replaces it at once.
struct RivalBubble: View {
    let match: MatchController
    let theme: BoardTheme

    @State private var shown: RivalLine?
    @AppStorage("rivalBanter") private var banterOn = true

    private var accent: Color { theme.accent ?? .accentColor }

    var body: some View {
        ZStack(alignment: .leading) {
            if banterOn, let line = shown {
                bubble(line.text)
                    .id(line.id)
                    .transition(.asymmetric(
                        insertion: .scale(scale: 0.6, anchor: .leading).combined(with: .opacity),
                        removal: .opacity
                    ))
            }
        }
        .animation(.spring(response: 0.34, dampingFraction: 0.68), value: shown?.id)
        .allowsHitTesting(false)
        .onChange(of: match.rivalLine, initial: true) { _, line in
            shown = line
            guard let line else { return }
            Task { @MainActor in
                // Longer lines stay a little longer.
                try? await Task.sleep(for: .seconds(2.6 + Double(line.text.count) * 0.03))
                if shown?.id == line.id { shown = nil }
            }
        }
    }

    private func bubble(_ text: String) -> some View {
        HStack(spacing: 0) {
            // The tail, pointing back at the portrait.
            Triangle()
                .fill(.regularMaterial)
                .frame(width: 7, height: 12)
                .offset(x: 1)
            Text(text)
                .font(.system(size: 13.5, weight: .semibold))
                .foregroundStyle(.primary)
                .lineLimit(2)
                .minimumScaleFactor(0.85)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 11)
                .padding(.vertical, 7)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 13, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 13, style: .continuous)
                        .strokeBorder(accent.opacity(0.35), lineWidth: 0.75)
                )
        }
        .shadow(color: .black.opacity(0.25), radius: 8, y: 3)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(match.setup.level.rival.name) says: \(text)")
    }
}

/// A small triangle pointing left.
private struct Triangle: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.maxX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.midY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        path.closeSubpath()
        return path
    }
}

extension View {
    /// The rival's speech bubble over the plate's name and status, beside the portrait.
    func rivalBubble(_ match: MatchController, theme: BoardTheme, show: Bool, avatarWidth: CGFloat) -> some View {
        overlay(alignment: .leading) {
            if show {
                RivalBubble(match: match, theme: theme)
                    .padding(.leading, avatarWidth + 4)
                    .padding(.trailing, 8)
            }
        }
    }
}
