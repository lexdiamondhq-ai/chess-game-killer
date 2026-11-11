import SwiftUI

/// "How Analyze works", unrolled as a parchment scroll over the analysis (Alex, 2026-11-11:
/// "slide up like a scroll about 3/4 of the way", option B). It stays in the app and works
/// offline; the same words live on the website's FAQ page (play/public/faq), which Support
/// still links to.
struct AnalyzeHelpScroll: View {
    @Environment(\.dismiss) private var dismiss

    /// One question and its answer. Answers use Markdown for the button names.
    struct Entry: Identifiable {
        let question: String
        let answer: LocalizedStringKey
        var id: String { question }
    }

    static let entries: [Entry] = [
        Entry(question: "Analyze a position",
              answer: "Tap the knight on Home, then take a photo of a real board, choose a screenshot, or set up a board by hand. Stockfish 17 finds the best moves right on your phone."),
        Entry(question: "Analyzing from a photo",
              answer: "Shoot the board from above, with all 64 squares in the picture and good light. Screenshots from other chess apps work too.\n\nReading takes up to a minute. Tap **Stop** to set the pieces up yourself instead. Your photo sits at the top of the analysis, so you can compare it with the board."),
        Entry(question: "A piece is wrong or missing",
              answer: "Tap **Edit pieces** beside your photo. Pick a piece from the row under the board and tap a square to place it. The eraser takes a piece off. Tap **Analyze** when it looks right."),
        Entry(question: "Rotate or Flip board?",
              answer: "**Rotate** (in Edit pieces) turns the position itself around. Use it when a photo was taken from the other side and the pieces came out upside down.\n\n**Flip board** only turns your view, so you can look from Black's side."),
        Entry(question: "It's the wrong side to move",
              answer: "Tap **White to move** (or Black) under the board to give the move to the other side. The analysis starts over."),
        Entry(question: "Which line is better?",
              answer: "The bar and the number show who is better. Plus is good for White, minus is good for Black.\n\n**The solid arrow is the best move.** The dotted arrow is second best. Tap a line to play its move, or **Play the line** to play the best moves out one at a time."),
        Entry(question: "Tilted or Flat",
              answer: "The switch under the board shows the carved 3D pieces tilted, or the board flat from above. Your choice is kept everywhere in the app."),
        Entry(question: "Still stuck?",
              answer: "Write to [beautyofchessapp@gmail.com](mailto:beautyofchessapp@gmail.com). A screenshot helps."),
    ]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                VStack(spacing: 6) {
                    Text("How Analyze Works")
                        .font(.custom(HomeAuroraCarving.plainFontName, size: 24, relativeTo: .title2))
                        .tracking(1.2)
                        .foregroundStyle(Parchment.title)
                        .multilineTextAlignment(.center)
                    Text("✦  ✦  ✦")
                        .font(.app(.caption))
                        .foregroundStyle(Parchment.gold)
                        .accessibilityHidden(true)
                }
                .frame(maxWidth: .infinity)
                .padding(.bottom, 2)

                ForEach(Self.entries) { entry in
                    VStack(alignment: .leading, spacing: 6) {
                        Text(entry.question)
                            .font(.custom(HomeAuroraCarving.plainFontName, size: 16, relativeTo: .headline))
                            .tracking(0.4)
                            .foregroundStyle(Parchment.heading)
                            .accessibilityAddTraits(.isHeader)
                        Text(entry.answer)
                            .font(.app(.subheadline))
                            .foregroundStyle(Parchment.ink)
                            .tint(Parchment.heading)
                            .lineSpacing(3)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            .padding(.horizontal, 30)
            .padding(.top, 44)
            .padding(.bottom, 40)
        }
        .scrollIndicators(.hidden)
        .overlay(alignment: .top) { ScrollRod().allowsHitTesting(false) }
        .overlay(alignment: .topTrailing) {
            Button { dismiss() } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(Parchment.heading)
                    .frame(width: 30, height: 30)
                    .background(Parchment.gold.opacity(0.18), in: Circle())
            }
            .padding(.top, 34)
            .padding(.trailing, 16)
            .accessibilityLabel("Close")
        }
        .environment(\.colorScheme, .light)
        .presentationDetents([.fraction(0.75)])
        .presentationDragIndicator(.hidden)
        .presentationCornerRadius(6)
        .presentationBackground { ParchmentPaper() }
    }
}

/// The scroll's colours: warm paper, brown ink, old gold.
private enum Parchment {
    static let title = Color(hex: 0x4A2F10)
    static let heading = Color(hex: 0x6D3F12)
    static let ink = Color(hex: 0x4B3920)
    static let gold = Color(hex: 0xA07A3A)
}

/// The unrolled paper: lighter where the light falls at the top, browner toward the edges.
private struct ParchmentPaper: View {
    var body: some View {
        ZStack {
            Color(hex: 0xEFDCB6)
            RadialGradient(colors: [Color(hex: 0xF7ECD3), Color(hex: 0xEFDCB6).opacity(0)],
                           center: .top, startRadius: 0, endRadius: 520)
            // Aged edges.
            LinearGradient(colors: [Color(hex: 0xB8894A).opacity(0.22), .clear, .clear, Color(hex: 0xB8894A).opacity(0.22)],
                           startPoint: .leading, endPoint: .trailing)
            LinearGradient(colors: [.clear, Color(hex: 0xC99C5A).opacity(0.28)],
                           startPoint: .center, endPoint: .bottom)
            PaperGrain()
        }
    }
}

/// Faint fibres, drawn the same every time so the paper never shimmers.
private struct PaperGrain: View {
    var body: some View {
        Canvas { context, size in
            var seed: UInt64 = 0x9E3779B97F4A7C15
            func next() -> CGFloat {
                seed = seed &* 6364136223846793005 &+ 1442695040888963407
                return CGFloat(seed >> 33) / CGFloat(UInt32.max >> 1)
            }
            for _ in 0..<420 {
                let x = next() * size.width, y = next() * size.height
                let length = 4 + next() * 14
                var path = Path()
                path.move(to: CGPoint(x: x, y: y))
                path.addLine(to: CGPoint(x: x + length, y: y + (next() - 0.5) * 3))
                context.stroke(path, with: .color(Color(hex: 0x8A6430).opacity(0.05 + next() * 0.06)),
                               lineWidth: 0.6)
            }
        }
        .allowsHitTesting(false)
    }
}

/// The gilded wooden rod the scroll hangs from, with a knob at each end.
private struct ScrollRod: View {
    private static let wood = LinearGradient(
        colors: [Color(hex: 0xE9C77E), Color(hex: 0xB8873A), Color(hex: 0x7A5420), Color(hex: 0xA77A35)],
        startPoint: .top, endPoint: .bottom)
    private static let knob = LinearGradient(
        colors: [Color(hex: 0xF3D58F), Color(hex: 0x9A6A1F), Color(hex: 0x6A4614)],
        startPoint: .top, endPoint: .bottom)

    var body: some View {
        ZStack {
            Capsule()
                .fill(Self.wood)
                .frame(height: 22)
                .shadow(color: .black.opacity(0.35), radius: 5, y: 3)
            HStack {
                knobView
                Spacer()
                knobView
            }
            .padding(.horizontal, 2)
        }
        .padding(.horizontal, -4)
        .padding(.top, 2)
        .accessibilityHidden(true)
    }

    private var knobView: some View {
        RoundedRectangle(cornerRadius: 6, style: .continuous)
            .fill(Self.knob)
            .frame(width: 18, height: 30)
    }
}

#Preview {
    Color.gray.sheet(isPresented: .constant(true)) { AnalyzeHelpScroll() }
}
