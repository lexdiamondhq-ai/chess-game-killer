import ChessKit
import SwiftUI

/// Settings: the board's look with a live preview, how much the coach says,
/// sound and haptics, and the credits. Every choice is remembered.
struct SettingsSheet: View {
    @AppStorage("boardTheme") private var themeID: BoardTheme.ID = .gilded
    @AppStorage("matchRival") private var matchRival = false
    @AppStorage("showBestMoves") private var showBestMoves = false
    @AppStorage("showSecondBest") private var showSecondBest = true
    @AppStorage("coachVerdicts") private var showVerdicts = true
    @AppStorage(GhostVision.storageKey) private var ghostVisionOn = true
    @AppStorage("soundEffects") private var soundOn = true
    @AppStorage("haptics") private var hapticsOn = true
    @AppStorage("rivalBanter") private var banterOn = true
    @AppStorage("bigBoard") private var bigBoard = false
    @AppStorage("sculpted3D") private var sculpted3D = true
    @AppStorage(BoardTilt.storageKey) private var tilt = BoardTilt.auto
    @AppStorage(Heirloom.settingKey) private var heirloomOn = true
    @AppStorage(BoardTheme.coordinatesKey) private var coordinatesOn = true
    @AppStorage(HomeScreen.key) private var homeScreen = HomeScreen.defaultOn
    /// Shared with the lessons' speaker button and the highlight reel.
    @AppStorage("coachVoiceMuted") private var voiceMuted = false
    /// Out loud with the ring switch on silent. Read by CoachVoice when a lesson, reel or Leo's reply starts.
    @AppStorage(CoachVoice.speaksOnSilentKey) private var speaksOnSilent = false
    /// "Nice move", "Try again" and the like in puzzles and drills. Read by CoachReactions.
    @AppStorage(CoachReactions.storageKey) private var reactionsOn = true
    @AppStorage(ReviewLevel.storageKey) private var reviewLevel = ReviewLevel.club.rawValue

    @Environment(\.dismiss) private var dismiss
    @State private var offer: PremiumFeature?
    @State private var showingPremium = false

    private var theme: BoardTheme { .named(themeID) }
    private var accent: Color { theme.accent ?? .accentColor }

    /// What the Board view row says under its title.
    private var tiltNote: String {
        if theme.sculptedLook == nil { return BoardTilt.needsThreeD }
        return sculpted3D ? tilt.blurb : "Turns 3D pieces on. " + tilt.blurb
    }

    /// Choosing a board view also turns 3D pieces on, since only the 3D board tilts.
    private var tiltChoice: Binding<BoardTilt> {
        Binding(get: { tilt }, set: { choice in
            tilt = choice
            sculpted3D = true
        })
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    preview

                    PremiumSettingsCard(theme: theme) { showingPremium = true }

                    section("Board") {
                        themeGrid(Self.looks)
                        Text("Rival boards")
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .padding(.top, 6)
                        themeGrid(BoardTheme.rivals)
                        SettingsGroup(theme: theme) {
                            if theme.sculptedLook != nil {
                                ToggleRow(title: "3D pieces", subtitle: "Carved pieces that lift, glide and fall. Off draws the same set flat.",
                                          symbol: "cube", isOn: $sculpted3D, theme: theme)
                                rule
                            }
                            // Always shown, so the tilt is easy to find. Picking a view turns 3D pieces on;
                            // a look without a 3D board says which looks have one.
                            PickerRow(title: "Board view", subtitle: tiltNote, symbol: "perspective", theme: theme) {
                                Picker("Board view", selection: tiltChoice) {
                                    ForEach(BoardTilt.allCases) { choice in
                                        Text(choice.title).tag(choice)
                                    }
                                }
                                .disabled(theme.sculptedLook == nil)
                            }
                            rule
                            ToggleRow(title: "Coordinates", subtitle: "Letters and numbers around the board. Off gives the squares more room.",
                                      symbol: "textformat.abc", isOn: $coordinatesOn, theme: theme)
                            rule
                            ToggleRow(title: "Match rival", subtitle: "Computer games use the rival's own board, not the one picked above.",
                                      symbol: "person.crop.circle.badge.checkmark", isOn: $matchRival, theme: theme)
                            rule
                            ToggleRow(title: "Piece history", subtitle: "Your pieces wear what they've been through: gold seams, a promoted pawn's collar, notches, patina.",
                                      symbol: "seal", isOn: $heirloomOn, theme: theme)
                            rule
                            ToggleRow(title: "Big Board", subtitle: "The board fills the screen. Swipe up from the bottom for the tools, sideways on the board to replay moves.",
                                      symbol: "arrow.up.left.and.arrow.down.right", isOn: $bigBoard, theme: theme)
                            rule
                            ToggleRow(title: "Home screen", subtitle: "Open on a home page: the board up top, your week, and every mode one tap away.",
                                      symbol: "house", isOn: $homeScreen, theme: theme)
                        }
                    }

                    section("Coach") {
                        CoachPicker(theme: theme)
                            .padding(.bottom, 4)
                        SettingsGroup(theme: theme) {
                            ToggleRow(title: "Move hints", subtitle: "Spotlights the coach's best move and says it under the board. Off for a fair game.",
                                      symbol: "sparkles", isOn: $showBestMoves, theme: theme)
                            rule
                            ToggleRow(title: "Runner-up in the coach", subtitle: "The coach panel lists a second choice too. The board only ever lights the best.",
                                      symbol: "lightbulb", isOn: $showSecondBest, theme: theme)
                                .disabled(!showBestMoves)
                            rule
                            ToggleRow(title: "See ahead", subtitle: "Ghost Vision. Hold the board to see the computer's line a few moves ahead. Slide left to step back through it. Counts as help.",
                                      symbol: "eye", isOn: $ghostVisionOn, theme: theme)
                            rule
                            ToggleRow(title: "Move grades", subtitle: "Rates each move you play, from Best to Blunder.",
                                      symbol: "star.fill", isOn: $showVerdicts, theme: theme)
                            rule
                            PickerRow(title: "Game review", subtitle: (ReviewLevel(rawValue: reviewLevel) ?? .club).blurb,
                                      symbol: "backward.circle", theme: theme) {
                                Picker("Game review", selection: $reviewLevel) {
                                    ForEach(ReviewLevel.allCases) { level in
                                        Text(level.title).tag(level.rawValue)
                                    }
                                }
                            }
                        }
                    }

                    section("Sound & feel") {
                        SettingsGroup(theme: theme) {
                            ToggleRow(title: "Sound effects", symbol: "speaker.wave.2.fill", isOn: $soundOn, theme: theme)
                            rule
                            ToggleRow(title: "Haptics", symbol: "iphone.radiowaves.left.and.right", isOn: $hapticsOn, theme: theme)
                            rule
                            ToggleRow(title: "Rival banter", subtitle: "Rivals talk to you during the game.",
                                      symbol: "bubble.left.fill", isOn: $banterOn, theme: theme)
                            rule
                            ToggleRow(title: "Coach's voice", subtitle: "\(Coach.current.name) reads lessons and highlight reels aloud. Captions always show.",
                                      symbol: "waveform", isOn: Binding(get: { !voiceMuted }, set: { voiceMuted = !$0 }), theme: theme)
                            rule
                            ToggleRow(title: "Speak on silent", subtitle: "Lessons, reels and Talk It Through play out loud even with the ring switch on silent. Off, the coach goes quiet with it, like the game's sounds.",
                                      symbol: "bell.slash.fill", isOn: $speaksOnSilent, theme: theme)
                                .disabled(voiceMuted)
                            rule
                            ToggleRow(title: "Voice reactions", subtitle: reactionsSubtitle,
                                      symbol: "bubble.left.and.text.bubble.right.fill", isOn: $reactionsOn, theme: theme)
                                .disabled(voiceMuted)
                        }
                    }

                    section("About") {
                        SettingsGroup(theme: theme) {
                            // Every gesture and every rule that costs something, in plain words.
                            NavigationLink {
                                GuideView(theme: theme) {
                                    Welcome.reset()
                                    dismiss()
                                }
                            } label: {
                                LinkRowLabel(title: "How it works", symbol: "questionmark.circle", theme: theme)
                            }
                            .buttonStyle(.plain)
                            rule
                            NavigationLink {
                                LicensesView(theme: theme)
                            } label: {
                                LinkRowLabel(title: "Open-source licenses", symbol: "doc.text", theme: theme)
                            }
                            .buttonStyle(.plain)
                            rule
                            // The GPL, which Stockfish comes under, gives every player the source.
                            Link(destination: URL(string: "https://github.com/lexdiamondhq-ai/chess-game-killer")!) {
                                LinkRowLabel(title: "Source code", symbol: "chevron.left.forwardslash.chevron.right", theme: theme)
                            }
                            .buttonStyle(.plain)
                            rule
                            HStack(spacing: 12) {
                                IconTile(symbol: "info.circle", theme: theme)
                                Text("Version")
                                    .font(.body.weight(.semibold))
                                Spacer(minLength: 0)
                                Text(Self.version)
                                    .font(.subheadline.monospacedDigit())
                                    .foregroundStyle(.secondary)
                            }
                            .padding(.horizontal, 14)
                            .padding(.vertical, 12)
                            .accessibilityElement(children: .combine)
                        }
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 12)
                .padding(.bottom, 24)
                .animation(.easeInOut(duration: 0.35), value: themeID)
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                        .fontWeight(.semibold)
                }
            }
        }
        .presentationDetents([.large])
        .presentationBackground {
            SheetBackdrop(theme: theme)
        }
        .premiumOffer($offer)
        .sheet(isPresented: $showingPremium) {
            PremiumOfferView(feature: nil)
        }
        .tint(accent)
        .preferredColorScheme(theme.isDark ? .dark : nil)
    }

    // MARK: Pieces of the screen

    /// The chosen board with a piece tapped, its moves and hints as they look in a game.
    private var preview: some View {
        VStack(spacing: 14) {
            BoardPreview(theme: theme, showBest: showBestMoves, size: 172,
                         threeD: theme.sculptedLook != nil && sculpted3D)
                .padding(.top, 6)
            Text("Live preview")
                .font(.caption.weight(.semibold))
                .tracking(1.5)
                .textCase(.uppercase)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 18)
        .background(SettingsCard(theme: theme, selected: false, color: accent))
    }

    private var reactionsSubtitle: String {
        "Now and then in puzzles and drills, \(Coach.current.name) says \"Nice move\", \"Try again\" or \"Brilliant!\""
    }

    private var rule: some View {
        Divider().padding(.leading, 60)
    }

    /// Every look that is not a rival's own board, in the menu's order.
    private static let looks = BoardTheme.all.filter { look in !BoardTheme.rivals.contains { $0.id == look.id } }

    private func themeGrid(_ options: [BoardTheme]) -> some View {
        LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 12) {
            ForEach(options) { option in
                let open: Bool = RivalBoardsEarned.opens(option)
                ThemeCard(option: option, isSelected: option.id == themeID, theme: theme, locked: !open) {
                    if open {
                        withAnimation(.easeInOut(duration: 0.35)) { themeID = option.id }
                    } else {
                        offer = .boardLooks
                    }
                }
            }
        }
    }

    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title.uppercased())
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .tracking(1)
            content()
        }
    }

    /// "0.1.0 (1)" from the bundle.
    static var version: String {
        let info = Bundle.main.infoDictionary
        let short = info?["CFBundleShortVersionString"] as? String ?? "0"
        let build = info?["CFBundleVersion"] as? String ?? "0"
        return "\(short) (\(build))"
    }
}

// MARK: - The live preview

/// A small board that is not for playing: it shows a theme the way a game draws it,
/// with the king tapped and its moves dotted. With hints on, castling, the coach's pick,
/// is in the spotlight.
struct BoardPreview: View {
    let theme: BoardTheme
    let showBest: Bool
    var size: CGFloat = 160
    /// The look's real 3D board, with the same position and marks.
    var threeD = false

    @AppStorage(BoardTheme.coordinatesKey) private var showsCoordinates = true

    private static let position = Position(fen: "r1bqk2r/ppp2ppp/2np1n2/2b1p3/2B1P3/2NP1N2/PPP2PPP/R1BQK2R w KQkq - 0 6")
    private static let best = (from: Square.e1, to: Square.g1)
    /// The tapped king and where it can go.
    private static let selected = Square.e1
    private static let targets: Set<Square> = [.d2, .e2, .f1, .g1]

    var body: some View {
        if threeD, SculptedAssets.shared.isLoaded, let position = Self.position {
            // As tall as the flat preview, and as wide as the angled board needs.
            SculptedStillBoard(position: position, look: theme.sculptedLook ?? .gilded, hints: stillHints,
                               selected: Self.selected, targets: Self.targets)
                .frame(width: size * SculptedBoardView.aspect, height: size)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Preview of the \(theme.name) board")
        } else {
            flatPreview
        }
    }

    private var stillHints: [SculptedHint] {
        showBest ? [SculptedHint(from: Self.best.from, to: Self.best.to, isBest: true)] : []
    }

    @ViewBuilder
    private var flatPreview: some View {
        let inset = theme.frameInset(side: size, coordinates: showsCoordinates)
        let sq = (size - inset * 2) / 8
        let corner = RoundedRectangle(cornerRadius: sq * 0.12, style: .continuous)
        ZStack(alignment: .topLeading) {
            ZStack {
                if let art = theme.boardArt {
                    BoardArt(name: art, flipped: false, coordinates: showsCoordinates)
                }
                if let surface = theme.surface {
                    LinearGradient(colors: surface, startPoint: .topLeading, endPoint: .bottomTrailing)
                }
                squares(size: sq)
                    .padding(inset)
            }
            .frame(width: size, height: size)
            .clipShape(corner)
            // Only the picture is clipped, so a king on the far rank may rise above the frame.
            ZStack(alignment: .topLeading) {
                ForEach(Self.position?.pieces ?? [], id: \.square) { piece in
                    PieceImage(piece: piece, theme: theme, size: sq, onBoard: true)
                        .position(center(of: piece.square, size: sq))
                        // Nearer rows in front, and left to right within a row, so overlaps never flicker.
                        .zIndex(Double((7 - piece.square.rankIndex) * 8 + piece.square.fileIndex))
                }
            }
            .frame(width: sq * 8, height: sq * 8)
            .padding(inset)
        }
        .frame(width: size, height: size)
        .overlay {
            if let edge = theme.boardEdge {
                corner.strokeBorder(edge, lineWidth: 1)
            }
        }
        .background {
            ForEach(Array(theme.boardShadows.enumerated()), id: \.offset) { index, color in
                corner.fill(color)
                    .blur(radius: sq * (theme.isDark ? 0.3 + 0.35 * CGFloat(index) : 0.25))
                    .offset(y: theme.isDark ? 0 : sq * 0.08)
            }
        }
        .animation(.easeInOut(duration: 0.25), value: showBest)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Preview of the \(theme.name) board")
    }

    private func squares(size: CGFloat) -> some View {
        VStack(spacing: 0) {
            ForEach(0..<8, id: \.self) { row in
                HStack(spacing: 0) {
                    ForEach(0..<8, id: \.self) { column in
                        squareView(Square(file: column, rank: 7 - row), size: size)
                    }
                }
            }
        }
    }

    /// One square as the game draws it: the tapped king's square, the hint spotlight,
    /// and a dot (or a ring around a piece) where the king can go.
    private func squareView(_ square: Square, size: CGFloat) -> some View {
        let isLight = (square.fileIndex + square.rankIndex) % 2 == 1
        let isTarget = Self.targets.contains(square)
        return ZStack {
            Rectangle().fill(theme.squareFill(isLight: isLight))
            if let gridLine = theme.gridLine {
                Rectangle().strokeBorder(gridLine, lineWidth: 0.5)
            }
            let lit = square == Self.best.from || square == Self.best.to
            if showBest, !lit {
                Rectangle().fill(Color.black.opacity(HintSpotlight.dim))
            }
            if square == Self.selected {
                Rectangle().fill(theme.selected)
                if let ring = theme.selectedRing {
                    Rectangle().strokeBorder(ring, lineWidth: size * 0.035)
                }
            }
            if showBest, lit {
                SpotlightMark(size: size, isTarget: square == Self.best.to)
            }
            if isTarget {
                MoveDot(occupied: Self.position?.piece(at: square) != nil,
                        hint: showBest && square == Self.best.to ? true : nil,
                        color: theme.hint, glow: theme.hintGlow, size: size)
            }
        }
        .frame(width: size, height: size)
    }

    private func center(of square: Square, size: CGFloat) -> CGPoint {
        CGPoint(x: (CGFloat(square.fileIndex) + 0.5) * size, y: (CGFloat(7 - square.rankIndex) + 0.5) * size)
    }
}

// MARK: - Rows and cards

/// One board look: a four-square swatch, its name, and a check on the swatch when it is the current one.
private struct ThemeCard: View {
    let option: BoardTheme
    let isSelected: Bool
    /// The current theme, for the accent color.
    let theme: BoardTheme
    /// Premium's, or a rival's not yet beaten: a crown in place of the check.
    var locked = false
    let select: () -> Void

    var body: some View {
        Button(action: select) {
            HStack(spacing: 12) {
                swatch
                    .overlay(alignment: .topTrailing) {
                        if isSelected {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.system(size: 17, weight: .semibold))
                                .symbolRenderingMode(.palette)
                                .foregroundStyle(Color.black, theme.accent ?? .accentColor)
                                .background(Circle().fill(Color.black).padding(-1.5))
                                .offset(x: 7, y: -7)
                                .transition(.scale.combined(with: .opacity))
                        }
                    }
                Text(option.name)
                    .font(.headline)
                    .foregroundStyle(locked ? Color.secondary : Color.primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                if locked {
                    Image(systemName: "crown.fill")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(theme.accent ?? .accentColor)
                        .accessibilityHidden(true)
                }
            }
            .padding(.horizontal, 14)
            .frame(maxWidth: .infinity)
            .frame(height: 72)
            .background(SettingsCard(theme: theme, selected: isSelected, color: theme.accent ?? .accentColor))
            .contentShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
        .buttonStyle(.plain)
        .animation(.snappy, value: isSelected)
        .accessibilityLabel(locked ? "\(option.name) board, Premium" : "\(option.name) board")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private var swatch: some View {
        ZStack {
            if let art = option.boardArt {
                Image(art).resizable().interpolation(.high).scaledToFill()
            } else {
                if let surface = option.surface {
                    LinearGradient(colors: surface, startPoint: .topLeading, endPoint: .bottomTrailing)
                }
                checker
            }
        }
        .frame(width: 44, height: 44)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(option.boardEdge ?? Color.black.opacity(0.08), lineWidth: 1)
        }
        .shadow(color: option.backdrop != nil ? .black.opacity(0.35)
                    : option.isDark ? Color(hex: 0x3CDCE6).opacity(0.35) : .black.opacity(0.1), radius: 6)
        .accessibilityHidden(true)
    }

    private var checker: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                Rectangle().fill(option.light)
                Rectangle().fill(option.dark)
            }
            HStack(spacing: 0) {
                Rectangle().fill(option.dark)
                Rectangle().fill(option.light)
            }
        }
    }
}

/// A switch with an icon tile and an optional line under the title.
private struct ToggleRow: View {
    let title: String
    var subtitle: String?
    let symbol: String
    @Binding var isOn: Bool
    let theme: BoardTheme

    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        Toggle(isOn: $isOn) {
            HStack(spacing: 12) {
                IconTile(symbol: symbol, theme: theme)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.body.weight(.semibold))
                    if let subtitle {
                        Text(subtitle)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .opacity(isEnabled ? 1 : 0.4)
        }
        .tint(theme.accent ?? .accentColor)
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }
}

/// A choice with an icon tile, a line under the title, and a menu of options on the right.
private struct PickerRow<Choice: View>: View {
    let title: String
    var subtitle: String?
    let symbol: String
    let theme: BoardTheme
    @ViewBuilder let choice: Choice

    var body: some View {
        HStack(spacing: 12) {
            IconTile(symbol: symbol, theme: theme)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.body.weight(.semibold))
                if let subtitle {
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 8)
            choice
                .pickerStyle(.menu)
                .labelsHidden()
                .tint(theme.accent ?? .accentColor)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }
}

/// A row that leads somewhere: icon tile, title, chevron.
private struct LinkRowLabel: View {
    let title: String
    let symbol: String
    let theme: BoardTheme

    var body: some View {
        HStack(spacing: 12) {
            IconTile(symbol: symbol, theme: theme)
            Text(title)
                .font(.body.weight(.semibold))
                .foregroundStyle(Color.primary)
            Spacer(minLength: 0)
            Image(systemName: "chevron.right")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .contentShape(Rectangle())
    }
}

/// A rounded square with a symbol in the accent color.
private struct IconTile: View {
    let symbol: String
    let theme: BoardTheme

    var body: some View {
        let accent = theme.accent ?? .accentColor
        Image(systemName: symbol)
            .font(.system(size: 15, weight: .semibold))
            .foregroundStyle(accent)
            .frame(width: 34, height: 34)
            .background(accent.opacity(theme.isDark ? 0.14 : 0.12), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
            .accessibilityHidden(true)
    }
}

/// Rows stacked in one card.
private struct SettingsGroup<Content: View>: View {
    let theme: BoardTheme
    @ViewBuilder let content: Content

    var body: some View {
        VStack(spacing: 0) {
            content
        }
        .background(SettingsCard(theme: theme, selected: false, color: theme.accent ?? .accentColor))
    }
}

/// The app's glass, outlined in color when selected.
private struct SettingsCard: View {
    let theme: BoardTheme
    let selected: Bool
    let color: Color

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 18, style: .continuous)
        GlassSurface(shape: shape)
            .overlay {
                if selected {
                    shape.strokeBorder(color, lineWidth: 1.5)
                        .shadow(color: color.opacity(theme.glows ? 0.45 : 0.2), radius: theme.glows ? 10 : 6)
                }
            }
    }
}

/// The backdrop for a sheet, in the theme's colors.
struct SheetBackdrop: View {
    let theme: BoardTheme

    var body: some View {
        ThemeBackdrop(theme: theme)
    }
}

// MARK: - Licenses

/// What the app is built on, and the terms each part comes with.
struct LicensesView: View {
    let theme: BoardTheme

    private struct Credit: Identifiable {
        let name: String
        let license: String
        let detail: String
        let url: URL

        var id: String { name }
    }

    private static let credits: [Credit] = [
        Credit(name: "Stockfish 17", license: "GPL v3",
               detail: "The engine behind every rival and the coach, running on your phone.",
               url: URL(string: "https://stockfishchess.org")!),
        Credit(name: "ChessKit", license: "MIT",
               detail: "The rules of chess: legal moves, check, checkmate and notation.",
               url: URL(string: "https://github.com/chesskit-app/chesskit-swift")!),
        Credit(name: "ChessKitEngine", license: "MIT",
               detail: "Runs Stockfish inside the app.",
               url: URL(string: "https://github.com/chesskit-app/chesskit-engine")!),
        Credit(name: "cburnett pieces", license: "GPL v2 or later",
               detail: "Piece artwork by Colin M.L. Burnett, via Lichess. The Neon set is recolored from it.",
               url: URL(string: "https://github.com/lichess-org/lila/tree/master/public/piece/cburnett")!),
        Credit(name: "Lichess puzzle database", license: "CC0",
               detail: "The puzzles and Puzzle Rush: positions from real games, rated by Lichess players.",
               url: URL(string: "https://database.lichess.org/#puzzles")!),
    ]

    /// "ChessKit on GitHub", or the site's own name, such as "stockfishchess.org".
    private func linkTitle(_ credit: Credit) -> String {
        let host = credit.url.host ?? "Website"
        return host == "github.com" ? "\(credit.name) on GitHub" : host
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Text("Chess Game Killer is built on open source, and is open source itself under the GPL because it ships with Stockfish.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .padding(.bottom, 4)
                ForEach(Self.credits) { credit in
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(alignment: .firstTextBaseline) {
                            Text(credit.name)
                                .font(.headline)
                            Spacer(minLength: 8)
                            Text(credit.license)
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(theme.accent ?? .accentColor)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 3)
                                .background((theme.accent ?? .accentColor).opacity(0.14), in: Capsule())
                        }
                        Text(credit.detail)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                        Link(destination: credit.url) {
                            Label(linkTitle(credit), systemImage: "arrow.up.right")
                                .font(.caption.weight(.semibold))
                        }
                        .padding(.top, 2)
                    }
                    .padding(14)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(SettingsCard(theme: theme, selected: false, color: theme.accent ?? .accentColor))
                    .accessibilityElement(children: .combine)
                }
                Link(destination: URL(string: "https://github.com/lexdiamondhq-ai/chess-game-killer")!) {
                    Label("Chess Game Killer source code", systemImage: "chevron.left.forwardslash.chevron.right")
                        .font(.subheadline.weight(.semibold))
                }
                .padding(.top, 8)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
        }
        .background(SheetBackdrop(theme: theme))
        .navigationTitle("Licenses")
        .navigationBarTitleDisplayMode(.inline)
    }
}

#Preview("Neon") {
    SettingsSheet()
        .onAppear { UserDefaults.standard.set("neon", forKey: "boardTheme") }
}

#Preview("Fabergé") {
    SettingsSheet()
        .onAppear { UserDefaults.standard.set("faberge", forKey: "boardTheme") }
}
