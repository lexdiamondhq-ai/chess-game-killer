import SwiftUI

/// The rival's latest remark, written quietly into its own line under its name, in place
/// of the status, for a few seconds; a newer remark replaces it at once. Nothing pops up
/// over the board or the players, so a remark never gets in the way of a move.
struct RivalRemark<Status: View>: View {
    let match: MatchController
    /// Only the rival's line shows remarks; the person's line always shows its status.
    var enabled = true
    @ViewBuilder let status: () -> Status

    @State private var shown: RivalLine?
    @AppStorage("rivalBanter") private var banterOn = true

    var body: some View {
        ZStack(alignment: .leading) {
            if enabled, banterOn, let line = shown {
                Text("\u{201C}\(line.text)\u{201D}")
                    .font(.system(size: 12.5, weight: .medium))
                    .italic()
                    .foregroundStyle(Color.primary.opacity(0.72))
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                    .id(line.id)
                    .transition(.opacity.combined(with: .offset(y: 3)))
                    .accessibilityLabel("\(match.setup.level.rival.name) says: \(line.text)")
            } else {
                status()
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.3), value: shown?.id)
        .onChange(of: match.rivalLine, initial: true) { _, line in
            shown = line
            guard let line else { return }
            Task { @MainActor in
                // Longer lines stay a little longer.
                try? await Task.sleep(for: .seconds(3.0 + Double(line.text.count) * 0.04))
                if shown?.id == line.id { shown = nil }
            }
        }
    }
}
