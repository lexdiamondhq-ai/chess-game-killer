import ChessKit
import SwiftUI

/// Where everything in the King's hall sits on a sideways phone. The films are drawn 1920 by
/// 1080 and fill the screen; a phone is wider than that, so the picture loses a little of its
/// top and more of its foot (the table's pedestal), never its sides, where the dragons are.
struct BroadcastLayout: Equatable {
    static let scene = CGSize(width: 1920, height: 1080)
    /// Of the height that doesn't fit, the share cut from the top.
    static let topShare: CGFloat = 0.15

    let size: CGSize

    /// Points for each of the film's pixels.
    var scale: CGFloat { max(size.width / Self.scene.width, size.height / Self.scene.height) }

    /// The film's frame on the screen.
    var sceneFrame: CGRect {
        let width = Self.scene.width * scale
        let height = Self.scene.height * scale
        return CGRect(x: (size.width - width) / 2, y: -(height - size.height) * Self.topShare,
                      width: width, height: height)
    }

    /// The screen's height for a height in the film.
    func y(_ sceneY: CGFloat) -> CGFloat { sceneFrame.minY + sceneY * scale }

    /// The board floats in the sky between the two heads, above the far ruins: as large as
    /// that gap allows. A flat board is narrower, so it may come a little lower.
    func boardFrame(aspect: CGFloat) -> CGRect {
        let flat = aspect < 1.1
        let top = max(8, y(24))
        let floor = y(flat ? 575 : 545)
        let widest = (flat ? 560 : 640) * scale
        let width = max(0, min((floor - top) * aspect, widest))
        let height = width / max(aspect, 0.01)
        return CGRect(x: (size.width - width) / 2, y: top, width: width, height: height)
    }
}

/// The King's hall: the game against the Ashen King with the phone on its side. His films and
/// your challenger's play behind the real board, which is played on as always; the clocks sit
/// under it and Tilted / Flat by your challenger. Turning the phone upright brings back the
/// game screen with everything else.
struct BroadcastView: View {
    let match: MatchController
    let theme: BoardTheme

    @State private var stage = BroadcastStage()
    @AppStorage("sculpted3D") private var sculpted3D = true
    @AppStorage(BoardTilt.storageKey) private var tilt = BoardTilt.tilted
    @Environment(\.scenePhase) private var scenePhase
    /// The result's words, a moment after the game ends.
    @State private var showsResult = false

    private static let gold = Color(hex: 0xE8C27A)

    var body: some View {
        GeometryReader { geo in
            let layout = BroadcastLayout(size: geo.size)
            let board = layout.boardFrame(aspect: BoardView.aspect(theme, setting: sculpted3D, framing: tilt.framing))
            ZStack(alignment: .topLeading) {
                Color.black
                scene(layout.sceneFrame)
                foot(height: geo.size.height)
                BoardView(match: match, theme: theme, framing: tilt.framing)
                    .frame(width: board.width, height: board.height)
                    .offset(x: board.minX, y: board.minY)
                underBoard
                    .frame(width: geo.size.width)
                    .offset(y: board.maxY + 8)
                corners(safe: geo.safeAreaInsets)
                    .frame(width: geo.size.width, height: geo.size.height)
            }
            // The film is taller than the screen: everything hangs from the top, not the middle.
            .frame(width: geo.size.width, height: geo.size.height, alignment: .topLeading)
            .clipped()
        }
        .ignoresSafeArea()
        .environment(\.colorScheme, .dark)
        .statusBarHidden()
        .persistentSystemOverlays(.hidden)
        .onAppear {
            stage.begin(match)
            showsResult = match.isOver
        }
        .onDisappear { stage.end() }
        .onChange(of: BroadcastStage.Beat(match)) { old, new in
            stage.follow(from: old, to: new)
            guard new.over != old.over || new.game != old.game else { return }
            // The ending plays first; then its words.
            withAnimation(.easeInOut(duration: 0.8).delay(new.over ? 3.5 : 0)) { showsResult = new.over }
        }
        .onChange(of: scenePhase) { _, phase in stage.setPaused(phase != .active) }
    }

    /// The still plate, and over it the King's film, the dragons' wing beats in the sky, and
    /// the challenger's film, cut to his shape.
    private func scene(_ frame: CGRect) -> some View {
        ZStack {
            if let plate = BroadcastStage.plate {
                Image(uiImage: plate)
                    .resizable()
            }
            if let king = stage.king {
                BroadcastFilm(view: king.view)
            }
            if let sky = stage.sky {
                // The dragons' wing beats: only the top of the sky, where they fly.
                BroadcastFilm(view: sky)
                    .frame(height: frame.height * BroadcastScript.skyShare)
                    .frame(maxHeight: .infinity, alignment: .top)
            }
            if let knight = stage.knight {
                BroadcastFilm(view: knight.view)
            }
        }
        .frame(width: frame.width, height: frame.height)
        .offset(x: frame.minX, y: frame.minY)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    /// A little shade along the foot, so the names and the switch read over the flagstones.
    private func foot(height: CGFloat) -> some View {
        LinearGradient(colors: [.clear, .black.opacity(0.5)], startPoint: .top, endPoint: .bottom)
            .frame(height: 76)
            .offset(y: height - 76)
            .allowsHitTesting(false)
    }

    /// Under the board: the two clocks, yours on the left, and at the end the result.
    @ViewBuilder
    private var underBoard: some View {
        if showsResult, match.isOver {
            result
                .transition(.opacity)
        } else if let clock = match.clock {
            clocks(clock)
        }
    }

    private func clocks(_ clock: ChessClock) -> some View {
        let you = match.setup.playerColor
        return HStack(spacing: 6) {
            ClockLabel(clock: clock, color: you, owner: "Your clock", theme: theme, size: 13)
            Rectangle()
                .fill(Color.white.opacity(0.25))
                .frame(width: 1, height: 12)
            ClockLabel(clock: clock, color: you.opposite, owner: "\(match.setup.rival.name)'s clock", theme: theme, size: 13)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .glassPane(Capsule())
        .frame(maxWidth: .infinity)
    }

    private var result: some View {
        VStack(spacing: 2) {
            Text(resultTitle)
                .font(.custom(HomeCarvingFont.plain, fixedSize: 17))
                .tracking(1.5)
                .foregroundStyle(Self.gold)
            Text("Turn your phone upright for the summary")
                .font(.app(size: 11, weight: .medium))
                .foregroundStyle(.white.opacity(0.75))
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 7)
        .glassPane(Capsule())
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
    }

    private var resultTitle: String {
        guard let winner = match.winner else { return "Drawn" }
        return match.game.humanColors.contains(winner) ? "The King has fallen" : "The King stands"
    }

    /// Lower left, by your challenger: Tilted / Flat and his name. Lower right: the King's.
    private func corners(safe: EdgeInsets) -> some View {
        HStack(alignment: .bottom) {
            VStack(alignment: .leading, spacing: 6) {
                BoardViewSwitch(theme: theme)
                    .frame(height: 32)
                name("Wolf Knight")
            }
            Spacer(minLength: 0)
            name(match.setup.rival.name)
        }
        .padding(.leading, max(safe.leading, 16) + 4)
        .padding(.trailing, max(safe.trailing, 16) + 4)
        .padding(.bottom, 12)
        .frame(maxHeight: .infinity, alignment: .bottom)
    }

    private func name(_ text: String) -> some View {
        Text(text.uppercased())
            .font(.custom(HomeCarvingFont.plain, fixedSize: 11))
            .tracking(1.6)
            .foregroundStyle(.white.opacity(0.88))
            .shadow(color: .black.opacity(0.8), radius: 3, y: 1)
            .lineLimit(1)
    }
}
