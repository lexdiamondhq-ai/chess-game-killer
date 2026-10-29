import ChessKit
import SwiftUI

/// Right under the clock card: one card for a game with a person, as Chess.com and Lichess
/// keep online play and playing a friend side by side under one Play. Two faces inside it:
/// Online, lit, for someone waiting right now; and A friend, a sealed envelope, for a game
/// sent by link. The header says how many players are waiting once the lobby has answered.
struct HomePlayPersonCard: View {
    let tone: HomeTone
    let pieceTheme: BoardTheme
    /// Players waiting in the lobby, nil until known.
    let waiting: Int?
    let online: () -> Void
    let friend: () -> Void

    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: HomeMetrics.cardRadius, style: .continuous)
        VStack(alignment: .leading, spacing: 12) {
            header
            faces
        }
        .padding(HomeMetrics.inset)
        .frame(maxWidth: .infinity, alignment: .leading)
        .homePane(shape, tone: tone)
        .animation(.snappy(duration: 0.3), value: waiting)
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            Text("Play a person")
                .font(HomeType.title)
                .foregroundStyle(tone.ink)
                .accessibilityAddTraits(.isHeader)
            Spacer(minLength: 8)
            if let waiting, waiting > 0 {
                HStack(spacing: 6) {
                    Circle()
                        .fill(tone.metal)
                        .frame(width: 6, height: 6)
                    Text("\(waiting) waiting")
                        .font(.footnote)
                        .foregroundStyle(tone.ink2)
                        .contentTransition(.numericText())
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(waiting == 1 ? "1 player waiting" : "\(waiting) players waiting")
            }
        }
        .padding(.horizontal, 4)
    }

    @ViewBuilder
    private var faces: some View {
        let layout = typeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(spacing: 10)) : AnyLayout(HStackLayout(alignment: .top, spacing: 10))
        layout {
            HomePlayFace(title: "Online", label: "Play online", line: "Rated, at your clock", lit: true, tone: tone,
                         hint: "Rated games with players waiting now. Take one on, or find a game.",
                         inputLabels: ["Play online", "Online", "Find a game"], action: online) {
                HomeFacingKings(tone: tone, pieceTheme: pieceTheme)
                    .frame(width: 58, height: 44)
            }
            HomePlayFace(title: "A friend", label: "Challenge a friend", line: "Send a link by text", lit: false, tone: tone,
                         hint: "Send a game by text or email. They can play in a browser, no app needed.",
                         inputLabels: ["Challenge a friend", "Challenge", "Friend"], action: friend) {
                HomeSealedEnvelope(tone: tone)
                    .frame(width: 52, height: 37)
                    .padding(.vertical, 3.5)
            }
        }
    }
}

/// One face of the Play a person card: a small drawing, a name and one line. The whole face
/// is the button. The lit face is the one most people want.
struct HomePlayFace<Art: View>: View {
    let title: String
    /// What VoiceOver says for the face.
    let label: String
    let line: String
    let lit: Bool
    let tone: HomeTone
    let hint: String
    let inputLabels: [String]
    let action: () -> Void
    @ViewBuilder let art: () -> Art

    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: HomeMetrics.innerRadius, style: .continuous)
        Button(action: action) {
            VStack(alignment: .leading, spacing: 2) {
                if !typeSize.isAccessibilitySize {
                    art()
                        .padding(.bottom, 8)
                }
                Text(title)
                    .font(HomeType.score)
                    .foregroundStyle(tone.ink)
                Text(line)
                    .font(.footnote)
                    .foregroundStyle(tone.ink2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(14)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .homePane(shape, tone: tone, weight: .well(lit: lit))
            .contentShape(shape)
        }
        .buttonStyle(HomePressStyle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(label)
        .accessibilityValue(line)
        .accessibilityHint(hint)
        .accessibilityAddTraits(.isButton)
        .accessibilityInputLabels(inputLabels)
    }
}

/// An envelope drawn in fine lines, its flap closed by a wax seal stamped with a knight.
/// The seal catches the light once when the card first shows.
struct HomeSealedEnvelope: View {
    let tone: HomeTone

    @State private var glint: CGFloat = -1
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        GeometryReader { geo in
            let width: CGFloat = geo.size.width
            let height: CGFloat = geo.size.height
            let seal: CGFloat = height * 0.5
            let flapTip: CGFloat = height * 0.56
            ZStack(alignment: .topLeading) {
                paper
                HomeEnvelopeFlap(depth: 0.56)
                    .stroke(tone.ink.opacity(0.42), style: StrokeStyle(lineWidth: 1, lineJoin: .round))
                HomeEnvelopeFold()
                    .stroke(tone.ink.opacity(0.16), lineWidth: 0.75)
                waxSeal(seal)
                    .position(x: width / 2, y: flapTip)
            }
        }
        .rotationEffect(.degrees(-5))
        .accessibilityHidden(true)
        .onAppear(perform: shine)
    }

    private var paper: some View {
        let shape = RoundedRectangle(cornerRadius: 4, style: .continuous)
        return shape
            .fill(LinearGradient(colors: [tone.ink.opacity(0.14), tone.ink.opacity(0.05)],
                                 startPoint: .top, endPoint: .bottom))
            .overlay { shape.strokeBorder(tone.ink.opacity(0.42), lineWidth: 1) }
            .shadow(color: .black.opacity(0.35), radius: 6, y: 3)
    }

    private func waxSeal(_ size: CGFloat) -> some View {
        let wax = RadialGradient(colors: [tone.metal, tone.metal.opacity(0.78)],
                                 center: UnitPoint(x: 0.35, y: 0.3), startRadius: 0, endRadius: size * 0.7)
        return ZStack {
            Circle().fill(wax)
            Circle()
                .strokeBorder(tone.onIvory.opacity(0.28), lineWidth: 0.75)
                .padding(size * 0.12)
            Glyph(name: Glyphs.challenge, size: size * 0.5)
                .foregroundStyle(tone.onIvory.opacity(0.78))
            glintBand(size)
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
        .shadow(color: .black.opacity(0.4), radius: 3, y: 2)
    }

    /// A soft band of light that crosses the seal once.
    private func glintBand(_ size: CGFloat) -> some View {
        let travel: CGFloat = glint * size * 1.4
        return LinearGradient(colors: [.clear, .white.opacity(0.55), .clear], startPoint: .leading, endPoint: .trailing)
            .frame(width: size * 0.45)
            .rotationEffect(.degrees(20))
            .offset(x: travel)
            .blendMode(.plusLighter)
    }

    private func shine() {
        guard !reduceMotion else { return }
        glint = -1
        withAnimation(.easeInOut(duration: 1.1).delay(0.6)) { glint = 1 }
    }
}

/// The flap: from the top corners down to a point in the middle.
struct HomeEnvelopeFlap: Shape {
    /// How far down the flap's point comes, as a share of the height.
    let depth: CGFloat

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let inset: CGFloat = 1.5
        path.move(to: CGPoint(x: rect.minX + inset, y: rect.minY + inset))
        path.addLine(to: CGPoint(x: rect.midX, y: rect.minY + rect.height * depth))
        path.addLine(to: CGPoint(x: rect.maxX - inset, y: rect.minY + inset))
        return path
    }
}

/// The two faint folds from the bottom corners, as on the back of a real envelope.
struct HomeEnvelopeFold: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let inset: CGFloat = 1.5
        let meet = CGPoint(x: rect.midX, y: rect.minY + rect.height * 0.5)
        path.move(to: CGPoint(x: rect.minX + inset, y: rect.maxY - inset))
        path.addLine(to: meet)
        path.addLine(to: CGPoint(x: rect.maxX - inset, y: rect.maxY - inset))
        return path
    }
}

/// A white king and a black king facing each other across a hairline, a live dot on the line.
struct HomeFacingKings: View {
    let tone: HomeTone
    let pieceTheme: BoardTheme

    @State private var breathe = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            Rectangle()
                .fill(tone.ink.opacity(0.22))
                .frame(width: 0.75, height: 30)
            PieceImage(piece: Piece(.king, color: .white, square: .e1), theme: pieceTheme, size: 30)
                .offset(x: -14)
            PieceImage(piece: Piece(.king, color: .black, square: .e8), theme: pieceTheme, size: 30)
                .offset(x: 14)
            Circle()
                .fill(tone.metal)
                .frame(width: 6, height: 6)
                .background {
                    Circle()
                        .fill(tone.metal.opacity(0.4))
                        .scaleEffect(breathe ? 2.6 : 1)
                        .opacity(breathe ? 0 : 1)
                }
                .offset(y: 19)
        }
        .accessibilityHidden(true)
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(.easeOut(duration: 1.8).repeatForever(autoreverses: false)) { breathe = true }
        }
    }
}
