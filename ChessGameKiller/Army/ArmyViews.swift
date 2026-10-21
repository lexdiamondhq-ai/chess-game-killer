import ChessKit
import SwiftUI

extension ArmyStore {
    /// The army slot of a piece on the board, when it is one of the player's
    /// pieces in a game that counts (against the computer, from the usual start).
    func slot(of placed: PlacedPiece, in match: MatchController) -> ArmySlot? {
        guard
            match.setup.opponent == .computer,
            placed.piece.color == match.setup.playerColor,
            let start = match.game.ledger?.origin(of: placed.square)
        else { return nil }
        return ArmySlot(start: start, color: placed.piece.color)
    }

    /// The army name of the piece a verdict is about, in a game that counts.
    func pieceName(for review: MoveReview, in match: MatchController) -> String? {
        guard match.setup.opponent == .computer, match.game.ledger != nil else { return nil }
        return name(ofPieceFrom: review.origin, color: match.setup.playerColor)
    }
}

extension ArmyRank {
    static let gold = Color(hex: 0xFFD27A)

    /// The rank's color: the piece's side color, or gold for a Legend.
    func color(for piece: Piece, theme: BoardTheme) -> Color {
        self == .legend ? Self.gold : theme.sideColor(piece.color)
    }
}

// MARK: How a veteran piece looks

/// Draws a piece's rank around it: a soft glow for a Veteran, a battle scar
/// for Elite, and a breathing golden glow for a Legend.
struct VeteranAura: ViewModifier {
    let rank: ArmyRank
    let piece: Piece
    let theme: BoardTheme
    let size: CGFloat
    var onBoard = true

    func body(content: Content) -> some View {
        content
            .background {
                if rank >= .veteran {
                    if rank == .legend {
                        halo.phaseAnimator([0.5, 1.0]) { view, phase in
                            view.opacity(phase).scaleEffect(0.92 + 0.08 * phase)
                        } animation: { _ in .easeInOut(duration: 1.6) }
                    } else {
                        halo
                    }
                }
            }
            .overlay {
                if rank >= .elite {
                    ScarMark(size: size, raised: onBoard && theme.spritePieces)
                        .mask { content }
                        .allowsHitTesting(false)
                }
            }
    }

    private var color: Color { rank.color(for: piece, theme: theme) }

    /// A pool of light under a standing 3D piece, a round glow behind a flat one.
    @ViewBuilder
    private var halo: some View {
        let strength = rank == .legend ? 0.85 : rank == .elite ? 0.6 : 0.45
        if onBoard && theme.spritePieces {
            Ellipse()
                .fill(RadialGradient(colors: [color.opacity(strength), color.opacity(0)],
                                     center: .center, startRadius: 0, endRadius: size * 0.5))
                .frame(width: size * 1.0, height: size * 0.42)
                .offset(y: size * 0.2)
                .blur(radius: size * 0.04)
        } else {
            Circle()
                .fill(RadialGradient(colors: [color.opacity(strength), color.opacity(0)],
                                     center: .center, startRadius: 0, endRadius: size * 0.55))
                .frame(width: size * 1.1, height: size * 1.1)
        }
    }
}

/// A healed cut across the piece: one bright slash with three stitches.
/// It is masked to the piece, so it only shows where the piece is.
private struct ScarMark: View {
    let size: CGFloat
    /// 3D pieces rise above their square, so the scar sits higher.
    let raised: Bool

    var body: some View {
        Canvas { context, canvas in
            let s = canvas.width
            let top = raised ? 0.04 : 0.3
            let from = CGPoint(x: s * 0.37, y: s * top)
            let to = CGPoint(x: s * 0.62, y: s * (top + 0.24))
            var cut = Path()
            cut.move(to: from)
            cut.addLine(to: to)

            var stitches = Path()
            let dx = to.x - from.x, dy = to.y - from.y
            let length = (dx * dx + dy * dy).squareRoot()
            let normal = CGPoint(x: -dy / length * s * 0.05, y: dx / length * s * 0.05)
            for t in [0.25, 0.5, 0.75] {
                let p = CGPoint(x: from.x + dx * t, y: from.y + dy * t)
                stitches.move(to: CGPoint(x: p.x - normal.x, y: p.y - normal.y))
                stitches.addLine(to: CGPoint(x: p.x + normal.x, y: p.y + normal.y))
            }

            let line = max(1, s * 0.03)
            let shade = StrokeStyle(lineWidth: line * 1.8, lineCap: .round)
            let light = StrokeStyle(lineWidth: line, lineCap: .round)
            context.stroke(cut, with: .color(.black.opacity(0.55)), style: shade)
            context.stroke(stitches, with: .color(.black.opacity(0.45)), style: StrokeStyle(lineWidth: line * 1.4, lineCap: .round))
            context.stroke(cut, with: .color(.white.opacity(0.92)), style: light)
            context.stroke(stitches, with: .color(.white.opacity(0.8)), style: StrokeStyle(lineWidth: line * 0.7, lineCap: .round))
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

/// The name of the selected piece, floating over it on the board.
struct ArmyNameTag: View {
    let name: String
    let rank: ArmyRank
    let color: Color

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: rank == .legend ? "crown.fill" : "shield.lefthalf.filled")
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(color)
            Text(name)
                .font(.system(.caption, design: .themed).weight(.bold))
            Text(rank.title.uppercased())
                .font(.system(size: 8, weight: .heavy, design: .themed))
                .tracking(0.6)
                .foregroundStyle(color)
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 5)
        .background(.ultraThinMaterial, in: Capsule())
        .overlay { Capsule().strokeBorder(color.opacity(0.7), lineWidth: 1) }
        .shadow(color: color.opacity(0.45), radius: 8)
        .fixedSize()
    }
}

// MARK: After a game

/// A banner at the top of the game screen when a piece earns a name, a scar or gold.
struct ArmyNewsBanner: View {
    let news: ArmyNews
    let color: Piece.Color
    let theme: BoardTheme
    let open: () -> Void

    var body: some View {
        let piece = Piece(news.slot.kind, color: color, square: .a1)
        let tint = news.rank.color(for: piece, theme: theme)
        Button(action: open) {
            HStack(spacing: 12) {
                PieceImage(piece: piece, theme: theme, size: 38)
                    .modifier(VeteranAura(rank: news.rank, piece: piece, theme: theme, size: 38, onBoard: false))
                VStack(alignment: .leading, spacing: 2) {
                    Text(news.label)
                        .font(.system(size: 10, weight: .heavy, design: .themed))
                        .tracking(0.8)
                        .foregroundStyle(tint)
                    Text(news.headline)
                        .font(.system(.subheadline, design: .themed).weight(.semibold))
                        .foregroundStyle(.primary)
                        .multilineTextAlignment(.leading)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.bold))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .trainingCard(theme, tint: tint, cornerRadius: 18)
        }
        .buttonStyle(.plain)
        .accessibilityHint("Opens your army")
    }
}

/// After a game: the piece that did the most, in the coach's end-of-game panel.
struct PieceOfTheMatchCard: View {
    let hero: MatchHero
    let color: Piece.Color
    let theme: BoardTheme
    @Environment(ArmyStore.self) private var store

    var body: some View {
        let record = store.record(for: hero.slot)
        let piece = Piece(hero.slot.kind, color: color, square: .a1)
        let tint = record.rank == .recruit ? ArmyRank.gold : record.rank.color(for: piece, theme: theme)
        HStack(spacing: 12) {
            PieceImage(piece: piece, theme: theme, size: 40)
                .modifier(VeteranAura(rank: max(record.rank, .veteran), piece: piece, theme: theme,
                                      size: 40, onBoard: false))
            VStack(alignment: .leading, spacing: 2) {
                Text("PIECE OF THE MATCH")
                    .font(.system(size: 10, weight: .heavy, design: .themed))
                    .tracking(0.8)
                    .foregroundStyle(tint)
                Text(hero.line)
                    .font(.system(.subheadline, design: .themed).weight(.semibold))
                    .fixedSize(horizontal: false, vertical: true)
                Text("+\(ArmyStore.heroXP) XP · \(record.honors) \(record.honors == 1 ? "honor" : "honors")")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
            Image(systemName: "star.fill")
                .font(.title3)
                .foregroundStyle(tint)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .trainingCard(theme, tint: tint, cornerRadius: 16)
        .accessibilityElement(children: .combine)
    }
}

// MARK: The Army screen

/// Your sixteen pieces, each with its own name, rank and record.
struct ArmyView: View {
    let theme: BoardTheme
    /// The side the player usually takes, so the pieces look like theirs.
    let color: Piece.Color
    @Environment(ArmyStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var selected: ArmySlot?
    @State private var confirmingReset = false

    private static let backRank: [ArmySlot] = [
        .queensRook, .queensKnight, .queensBishop, .queen, .king, .kingsBishop, .kingsKnight, .kingsRook,
    ]
    private static let pawns: [ArmySlot] = [.aPawn, .bPawn, .cPawn, .dPawn, .ePawn, .fPawn, .gPawn, .hPawn]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 18) {
                    header
                    formation
                    if !decorated.isEmpty { honorRoll }
                    ranksCard
                    Text("Games against the computer from the usual starting position count.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
            }
            .background { TrainingBackdrop(theme: theme) }
            .navigationTitle("Your Army")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Done") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button(role: .destructive) {
                            confirmingReset = true
                        } label: {
                            Label("Retire the Whole Army", systemImage: "arrow.counterclockwise")
                        }
                    } label: {
                        Label("Army Settings", systemImage: "ellipsis.circle")
                    }
                }
            }
            .confirmationDialog("Retire the whole army?", isPresented: $confirmingReset, titleVisibility: .visible) {
                Button("Erase Every Piece's Record", role: .destructive) { store.reset() }
            } message: {
                Text("Names, scars and records will be erased. Training isn't affected.")
            }
            .sheet(item: $selected) { slot in
                PieceDetailView(slot: slot, color: color, theme: theme)
                    .environment(store)
                    .presentationDetents([.medium, .large])
            }
        }
        .tint(theme.trainingAccent)
        .preferredColorScheme(theme.isDark ? .dark : nil)
    }

    private var header: some View {
        VStack(spacing: 6) {
            Text("Every piece remembers.")
                .font(.system(.title3, design: .themed).weight(.bold))
            Text("Win with them and they earn a name, then a battle scar, then a golden glow.")
                .font(.system(.subheadline, design: .themed))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(.top, 4)
    }

    /// The army lined up as it starts: pawns in front, the back rank behind.
    private var formation: some View {
        VStack(spacing: 10) {
            row(Self.pawns)
            row(Self.backRank)
        }
        .padding(.vertical, 16)
        .padding(.horizontal, 8)
        .trainingCard(theme)
    }

    private func row(_ slots: [ArmySlot]) -> some View {
        HStack(spacing: 0) {
            ForEach(slots) { slot in
                Button { selected = slot } label: { cell(slot) }
                    .buttonStyle(.plain)
                    .frame(maxWidth: .infinity)
            }
        }
    }

    private func cell(_ slot: ArmySlot) -> some View {
        let record = store.record(for: slot)
        let piece = Piece(slot.kind, color: color, square: .a1)
        return VStack(spacing: 4) {
            PieceImage(piece: piece, theme: theme, size: 36)
                .modifier(VeteranAura(rank: record.rank, piece: piece, theme: theme, size: 36, onBoard: false))
            Text(record.name ?? " ")
                .font(.system(size: 9, weight: .bold, design: .themed))
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .foregroundStyle(record.rank.color(for: piece, theme: theme))
            RankPips(rank: record.rank, color: record.rank.color(for: piece, theme: theme))
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(record.name ?? slot.title), \(slot.title), \(record.rank.title), \(record.wins) wins")
    }

    /// The pieces with the most experience.
    private var decorated: [ArmySlot] {
        ArmySlot.allCases
            .filter { store.record(for: $0).xp > 0 }
            .sorted { store.record(for: $0).xp > store.record(for: $1).xp }
            .prefix(5)
            .map { $0 }
    }

    private var honorRoll: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Most Decorated")
                .font(.system(.headline, design: .themed))
            ForEach(decorated) { slot in
                Button { selected = slot } label: { honorRow(slot) }
                    .buttonStyle(.plain)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .trainingCard(theme)
    }

    private func honorRow(_ slot: ArmySlot) -> some View {
        let record = store.record(for: slot)
        let piece = Piece(slot.kind, color: color, square: .a1)
        let tint = record.rank.color(for: piece, theme: theme)
        return HStack(spacing: 12) {
            PieceImage(piece: piece, theme: theme, size: 34)
                .modifier(VeteranAura(rank: record.rank, piece: piece, theme: theme, size: 34, onBoard: false))
            VStack(alignment: .leading, spacing: 1) {
                Text(record.name ?? slot.title)
                    .font(.system(.subheadline, design: .themed).weight(.semibold))
                Text("\(record.rank.title) · \(slot.title)")
                    .font(.caption)
                    .foregroundStyle(tint)
            }
            Spacer(minLength: 0)
            VStack(alignment: .trailing, spacing: 1) {
                Text("\(record.wins) wins")
                    .font(.system(.subheadline, design: .themed).weight(.semibold).monospacedDigit())
                Text("\(record.captures) taken")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
        }
        .contentShape(Rectangle())
    }

    private var ranksCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Ranks")
                .font(.system(.headline, design: .themed))
            ForEach(ArmyRank.allCases, id: \.self) { rank in
                let piece = Piece(.knight, color: color, square: .a1)
                HStack(spacing: 12) {
                    PieceImage(piece: piece, theme: theme, size: 30)
                        .modifier(VeteranAura(rank: rank, piece: piece, theme: theme, size: 30, onBoard: false))
                    VStack(alignment: .leading, spacing: 1) {
                        Text(rank.title)
                            .font(.system(.subheadline, design: .themed).weight(.semibold))
                        Text(rank.reward)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 0)
                    Text("\(rank.threshold) XP")
                        .font(.caption.weight(.semibold).monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            }
            Text("XP: 1 per game, 3 per win, 2 more if the piece is still standing, 2 per pawn's worth taken, 10 per promotion, 20 per checkmate. Stronger rivals are worth more, up to 3× against Singularity. Games with Undo or a played hint earn half. Leaving a game unfinished counts as a loss. Piece of the Match earns +5, revenge on a rival that keeps taking a piece earns +15.")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .trainingCard(theme)
    }
}

/// Small dots under a piece: one per rank above Recruit.
private struct RankPips: View {
    let rank: ArmyRank
    let color: Color

    var body: some View {
        HStack(spacing: 2) {
            ForEach(1..<ArmyRank.allCases.count, id: \.self) { index in
                Circle()
                    .fill(index <= rank.rawValue ? color : Color.primary.opacity(0.15))
                    .frame(width: 4, height: 4)
            }
        }
    }
}

/// One piece's story: its name, rank, progress and record.
struct PieceDetailView: View {
    let slot: ArmySlot
    let color: Piece.Color
    let theme: BoardTheme
    @Environment(ArmyStore.self) private var store
    @State private var renaming = false
    @State private var draftName = ""

    var body: some View {
        let record = store.record(for: slot)
        let piece = Piece(slot.kind, color: color, square: .a1)
        let tint = record.rank.color(for: piece, theme: theme)
        ScrollView {
            VStack(spacing: 18) {
                PieceImage(piece: piece, theme: theme, size: 110)
                    .modifier(VeteranAura(rank: record.rank, piece: piece, theme: theme, size: 110, onBoard: false))
                    .padding(.top, 24)
                VStack(spacing: 4) {
                    HStack(spacing: 6) {
                        Text(record.name ?? slot.title)
                            .font(.system(.title2, design: .themed).weight(.bold))
                        if record.name != nil {
                            Button {
                                draftName = record.name ?? ""
                                renaming = true
                            } label: {
                                Image(systemName: "pencil.circle.fill")
                                    .font(.title3)
                                    .foregroundStyle(.secondary)
                            }
                            .accessibilityLabel("Rename")
                        }
                    }
                    Text("\(record.rank.title) · \(slot.title)")
                        .font(.system(.subheadline, design: .themed).weight(.semibold))
                        .foregroundStyle(tint)
                }
                progress(record, tint: tint)
                if record.nemesis != nil || !record.revenge.isEmpty {
                    rivals(record, tint: tint)
                }
                stats(record)
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 24)
        }
        .background { TrainingBackdrop(theme: theme) }
        .preferredColorScheme(theme.isDark ? .dark : nil)
        .alert("Rename", isPresented: $renaming) {
            TextField("Name", text: $draftName)
            Button("Save") { store.rename(slot, to: draftName) }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Up to 20 characters.")
        }
        .onChange(of: draftName) { _, name in
            // The store keeps 20 characters, so stop the typing there instead of
            // cutting the name on Save.
            if name.count > 20 { draftName = String(name.prefix(20)) }
        }
    }

    @ViewBuilder
    private func progress(_ record: PieceRecord, tint: Color) -> some View {
        if let next = record.rank.next {
            let from = record.rank.threshold
            let fraction = Double(record.xp - from) / Double(next.threshold - from)
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("\(record.xp) XP")
                        .font(.caption.weight(.semibold).monospacedDigit())
                    Spacer()
                    Text("\(next.threshold - record.xp) to \(next.title)")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
                ProgressView(value: min(1, max(0, fraction)))
                    .tint(tint)
                Text(next.reward)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(14)
            .trainingCard(theme, tint: tint, cornerRadius: 16)
        } else {
            Text("\(record.xp) XP. A Legend of your army.")
                .font(.system(.subheadline, design: .themed).weight(.semibold))
                .foregroundStyle(tint)
        }
    }

    /// Which rival keeps taking this piece, and the rivals it has beaten back.
    private func rivals(_ record: PieceRecord, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            if let nemesis = record.nemesis {
                let rival = nemesis.level.rival
                let avenged = record.revenge.contains(nemesis.level.rawValue)
                HStack(spacing: 10) {
                    RivalSigil(rival: rival, size: 30, glows: theme.glows)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(avenged ? "Old rival: \(rival.name)" : "Nemesis: \(rival.name)")
                            .font(.system(.subheadline, design: .themed).weight(.semibold))
                        Text(avenged
                             ? "Took it \(nemesis.times) times. Revenge taken."
                             : "Has taken it \(nemesis.times) times. Win against \(rival.name) and take something back for revenge.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            if !record.revenge.isEmpty {
                HStack(spacing: 6) {
                    Text("Revenge on")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    ForEach(record.revenge.sorted(), id: \.self) { raw in
                        if let level = MatchController.Level(rawValue: raw) {
                            Text(level.rival.name)
                                .font(.caption.weight(.bold))
                                .padding(.horizontal, 8)
                                .padding(.vertical, 3)
                                .background(level.rival.hue.opacity(0.2), in: Capsule())
                                .foregroundStyle(level.rival.hue)
                        }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .trainingCard(theme, tint: tint, cornerRadius: 16)
    }

    private func stats(_ record: PieceRecord) -> some View {
        let items: [(String, Int)] = [
            ("Games", record.games), ("Wins", record.wins), ("Captures", record.captures),
            ("Material Taken", record.captureValue), ("Checkmates", record.mates),
            ("Promotions", record.promotions), ("Times Fallen", record.falls),
            ("Piece of the Match", record.honors),
        ]
        return LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
            ForEach(items, id: \.0) { item in
                VStack(spacing: 2) {
                    Text("\(item.1)")
                        .font(.system(.title3, design: .themed).weight(.bold).monospacedDigit())
                    Text(item.0)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .trainingCard(theme, cornerRadius: 14)
            }
        }
    }
}
