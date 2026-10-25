import ChessKit
import SwiftUI

/// Right under the clock card: Challenge a friend, as a sealed move. In a game adjourned over
/// the board, the next move went into an envelope and was sealed; here the envelope is the
/// invite. A small glass card with the envelope, its wax seal in the pieces' metal, and one
/// line on how it travels. The whole card is the button; it opens the challenge composer.
struct HomeChallengeCard: View {
    let tone: HomeTone
    let action: () -> Void

    @ScaledMetric(relativeTo: .title3) private var art: CGFloat = 58
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: HomeMetrics.cardRadius, style: .continuous)
        Button(action: action) {
            HStack(spacing: 16) {
                if !typeSize.isAccessibilitySize {
                    HomeSealedEnvelope(tone: tone)
                        .frame(width: min(art, 76), height: min(art, 76) * 0.72)
                        .padding(.vertical, 4)
                }
                words
                Image(systemName: "chevron.forward")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(tone.ink3)
            }
            .padding(.horizontal, HomeMetrics.inset + 4)
            .padding(.vertical, 18)
            .frame(maxWidth: .infinity, alignment: .leading)
            .homePane(shape, tone: tone)
            .contentShape(shape)
        }
        .buttonStyle(HomePressStyle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Challenge a friend")
        .accessibilityHint("Send a game by text or email. They can play in a browser, no app needed.")
        .accessibilityAddTraits(.isButton)
        .accessibilityInputLabels(["Challenge a friend", "Challenge", "Friend"])
    }

    private var words: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text("Challenge a friend")
                .font(HomeType.title)
                .foregroundStyle(tone.ink)
            Text("Seal a game in a link. Send it by text or email.")
                .font(.subheadline)
                .foregroundStyle(tone.ink2)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
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

/// Under Challenge a friend: Play online, for a game with someone waiting right now. Two kings
/// face each other across a hairline, with a live dot between them; the line says how many
/// players are waiting when the lobby has answered. The whole card is the button.
struct HomeOnlineCard: View {
    let tone: HomeTone
    let pieceTheme: BoardTheme
    /// Players waiting in the lobby, nil until known.
    let waiting: Int?
    let action: () -> Void

    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: HomeMetrics.cardRadius, style: .continuous)
        Button(action: action) {
            HStack(spacing: 16) {
                if !typeSize.isAccessibilitySize {
                    HomeFacingKings(tone: tone, pieceTheme: pieceTheme)
                        .frame(width: 58, height: 44)
                }
                VStack(alignment: .leading, spacing: 3) {
                    Text("Play online")
                        .font(HomeType.title)
                        .foregroundStyle(tone.ink)
                    Text(line)
                        .font(.subheadline)
                        .foregroundStyle(tone.ink2)
                        .fixedSize(horizontal: false, vertical: true)
                        .contentTransition(.numericText())
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                Image(systemName: "chevron.forward")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(tone.ink3)
            }
            .padding(.horizontal, HomeMetrics.inset + 4)
            .padding(.vertical, 16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .homePane(shape, tone: tone)
            .contentShape(shape)
        }
        .buttonStyle(HomePressStyle())
        .animation(.snappy(duration: 0.3), value: waiting)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Play online")
        .accessibilityValue(line)
        .accessibilityHint("Rated games with players waiting now. Take one on, or find a game.")
        .accessibilityAddTraits(.isButton)
        .accessibilityInputLabels(["Play online", "Online", "Find a game"])
    }

    private var line: String {
        switch waiting {
        case let count? where count == 1: return "1 player waiting now. Take them on."
        case let count? where count > 1: return "\(count) players waiting now. Take one on."
        default: return "Rated games with players online now."
        }
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
