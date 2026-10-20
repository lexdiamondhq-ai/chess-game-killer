import ChessKit
import StoreKit
import SwiftUI

/// Settings: the board's look with a live preview, how much the coach says,
/// sound and haptics, and the credits. Every choice is remembered.
struct SettingsSheet: View {
    @AppStorage("boardTheme") private var themeID: BoardTheme.ID = .neon
    @AppStorage("matchRival") private var matchRival = true
    @AppStorage("showBestMoves") private var showBestMoves = true
    @AppStorage("showSecondBest") private var showSecondBest = true
    @AppStorage("coachVerdicts") private var showVerdicts = true
    @AppStorage("soundEffects") private var soundOn = true
    @AppStorage("haptics") private var hapticsOn = true

    @Environment(\.dismiss) private var dismiss
    @Environment(\.requestReview) private var requestReview

    private var theme: BoardTheme { .named(themeID) }
    private var accent: Color { theme.accent ?? .accentColor }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    preview

                    section("Board") {
                        LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 12) {
                            ForEach(BoardTheme.all) { option in
                                ThemeCard(option: option, isSelected: option.id == themeID, theme: theme) {
                                    withAnimation(.easeInOut(duration: 0.35)) { themeID = option.id }
                                }
                            }
                        }
                        SettingsGroup(theme: theme) {
                            ToggleRow(title: "Match rival", subtitle: "Computer games use the rival's own board, not the one picked above",
                                      symbol: "person.crop.circle.badge.checkmark", isOn: $matchRival, theme: theme)
                        }
                    }

                    section("Coach") {
                        SettingsGroup(theme: theme) {
                            ToggleRow(title: "Best-move arrows", subtitle: "Solid for the best, dashed for the next",
                                      symbol: "sparkles", isOn: $showBestMoves, theme: theme)
                            rule
                            ToggleRow(title: "Second-best arrow", subtitle: "The dashed one. Off leaves just the best.",
                                      symbol: "lightbulb", isOn: $showSecondBest, theme: theme)
                                .disabled(!showBestMoves)
                            rule
                            ToggleRow(title: "Move verdicts", subtitle: "Grades every move you make",
                                      symbol: "star.fill", isOn: $showVerdicts, theme: theme)
                        }
                    }

                    section("Sound & feel") {
                        SettingsGroup(theme: theme) {
                            ToggleRow(title: "Sound effects", symbol: "speaker.wave.2.fill", isOn: $soundOn, theme: theme)
                            rule
                            ToggleRow(title: "Haptics", symbol: "iphone.radiowaves.left.and.right", isOn: $hapticsOn, theme: theme)
                        }
                    }

                    section("About") {
                        SettingsGroup(theme: theme) {
                            Button {
                                requestReview()
                            } label: {
                                LinkRowLabel(title: "Rate Chess Game Killer", symbol: "heart.fill", theme: theme)
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
        .tint(accent)
        .preferredColorScheme(theme.isDark ? .dark : nil)
    }

    // MARK: Pieces of the screen

    /// The chosen board with the arrows as they will look in a game.
    private var preview: some View {
        VStack(spacing: 14) {
            BoardPreview(theme: theme, showBest: showBestMoves, showSecond: showBestMoves && showSecondBest, size: 172)
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

    private var rule: some View {
        Divider().padding(.leading, 60)
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

/// A small board that is not for playing: it shows a theme with the best-move
/// arrows the way a game draws them. White is about to castle; Bg5 is the runner-up.
struct BoardPreview: View {
    let theme: BoardTheme
    let showBest: Bool
    let showSecond: Bool
    var size: CGFloat = 160

    private static let position = Position(fen: "r1bqk2r/ppp2ppp/2np1n2/2b1p3/2B1P3/2NP1N2/PPP2PPP/R1BQK2R w KQkq - 0 6")
    private static let best = (from: Square.e1, to: Square.g1)
    private static let second = (from: Square.c1, to: Square.g5)

    var body: some View {
        let inset = theme.frameInset(side: size)
        let sq = (size - inset * 2) / 8
        let corner = RoundedRectangle(cornerRadius: sq * 0.12, style: .continuous)
        ZStack(alignment: .topLeading) {
            if let art = theme.boardArt {
                BoardArt(name: art, flipped: false)
            }
            if let surface = theme.surface {
                LinearGradient(colors: surface, startPoint: .topLeading, endPoint: .bottomTrailing)
            }
            ZStack(alignment: .topLeading) {
                squares(size: sq)
                ForEach(Self.position?.pieces ?? [], id: \.square) { piece in
                    PieceImage(piece: piece, theme: theme, size: sq, onBoard: true)
                        .position(center(of: piece.square, size: sq))
                        .zIndex(Double(7 - piece.square.rankIndex))
                }
                if showBest, showSecond {
                    MoveArrow(from: center(of: Self.second.from, size: sq), to: center(of: Self.second.to, size: sq),
                              squareSize: sq, isBest: false, color: theme.secondArrow, glow: theme.arrowGlow)
                        .transition(.opacity)
                        .zIndex(10)
                }
                if showBest {
                    MoveArrow(from: center(of: Self.best.from, size: sq), to: center(of: Self.best.to, size: sq),
                              squareSize: sq, isBest: true, color: theme.bestArrow, glow: theme.arrowGlow)
                        .transition(.opacity)
                        .zIndex(11)
                }
            }
            .frame(width: sq * 8, height: sq * 8)
            .padding(inset)
        }
        .frame(width: size, height: size)
        .clipShape(corner)
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
        .animation(.easeInOut(duration: 0.25), value: showSecond)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Preview of the \(theme.name) board")
    }

    private func squares(size: CGFloat) -> some View {
        VStack(spacing: 0) {
            ForEach(0..<8, id: \.self) { row in
                HStack(spacing: 0) {
                    ForEach(0..<8, id: \.self) { column in
                        let isLight = (column + 7 - row) % 2 == 1
                        Rectangle()
                            .fill(theme.squareFill(isLight: isLight))
                            .overlay {
                                if let gridLine = theme.gridLine {
                                    Rectangle().strokeBorder(gridLine, lineWidth: 0.5)
                                }
                            }
                            .frame(width: size, height: size)
                    }
                }
            }
        }
    }

    private func center(of square: Square, size: CGFloat) -> CGPoint {
        CGPoint(x: (CGFloat(square.fileIndex) + 0.5) * size, y: (CGFloat(7 - square.rankIndex) + 0.5) * size)
    }
}

// MARK: - Rows and cards

/// One board look: a four-square swatch, its name, and a check when it is the current one.
private struct ThemeCard: View {
    let option: BoardTheme
    let isSelected: Bool
    /// The current theme, for the accent color.
    let theme: BoardTheme
    let select: () -> Void

    var body: some View {
        Button(action: select) {
            HStack(spacing: 12) {
                swatch
                Text(option.name)
                    .font(.headline)
                    .foregroundStyle(Color.primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
                    .frame(maxWidth: .infinity, alignment: .leading)
                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.title3)
                        .foregroundStyle(theme.accent ?? .accentColor)
                        .transition(.scale.combined(with: .opacity))
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
        .accessibilityLabel("\(option.name) board")
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

/// Glass on the dark themes; outlined in color when selected.
private struct SettingsCard: View {
    let theme: BoardTheme
    let selected: Bool
    let color: Color

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 18, style: .continuous)
        shape
            .fill(theme.isDark ? AnyShapeStyle(.ultraThinMaterial) : AnyShapeStyle(Color(.secondarySystemGroupedBackground)))
            .overlay {
                shape.strokeBorder(selected ? color : Color.primary.opacity(theme.isDark ? 0.12 : 0.08),
                                   lineWidth: selected ? 1.5 : 1)
            }
            .shadow(color: selected ? color.opacity(theme.glows ? 0.45 : 0.25) : .black.opacity(theme.glows ? 0 : 0.05),
                    radius: selected ? 12 : 6, y: theme.glows ? 0 : 2)
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
    ]

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
                            Label(credit.url.host ?? "Website", systemImage: "arrow.up.right")
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
