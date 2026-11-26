import ChessKit
import SwiftUI

/// Opens Learn's vine page.
struct VineRoute: Hashable {}

/// The vine's gold, the same as the knight's branch menu on Home.
enum VineGold {
    static let light = Color(hex: 0xF6DC93)
    static let deep = Color(hex: 0xC99436)
    static let bright = Color(hex: 0xF0CF7A)
    static let ink = Color(hex: 0x2A1C08)
    static let metal = LinearGradient(colors: [light, deep, bright], startPoint: .top, endPoint: .bottom)

    /// Gold words: warm on dark rooms, a deeper gold on light ones so they still read.
    static func text(_ theme: BoardTheme) -> Color { theme.screenIsDark ? Color(hex: 0xE6C06A) : Color(hex: 0x8C6620) }

    /// The carved title: the vine's own metal on dark rooms, a deeper cut on light ones.
    static func title(_ theme: BoardTheme) -> LinearGradient {
        guard !theme.screenIsDark else { return metal }
        return LinearGradient(colors: [Color(hex: 0xC99436), Color(hex: 0x8C6620), Color(hex: 0xB7832E)],
                              startPoint: .top, endPoint: .bottom)
    }

    static func carved(_ size: CGFloat) -> Font { .custom("Cinzel-Bold", size: size) }
}

// MARK: - The card on Learn

/// The small card under Today: a gold sprig with this week's leaves, the step in bloom, and the
/// bud after it. Tap it for the whole vine.
struct VineCard: View {
    let vine: LearningVine
    let theme: BoardTheme

    var body: some View {
        NavigationLink(value: VineRoute()) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .firstTextBaseline) {
                    Text("YOUR VINE")
                        .font(VineGold.carved(13))
                        .tracking(2)
                        .foregroundStyle(VineGold.text(theme))
                    Spacer(minLength: 8)
                    Text(countLine)
                        .font(.app(.caption, weight: .medium))
                        .foregroundStyle(.secondary)
                    Image(systemName: "chevron.right")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.tertiary)
                }
                VineSprig(leaves: min(vine.leaves.count, 5), hasBloom: vine.bloom != nil, hasBud: !vine.buds.isEmpty)
                    .frame(height: 44)
                    .accessibilityHidden(true)
                if let bloom = vine.bloom {
                    (Text("In bloom: ").foregroundStyle(.primary)
                        + Text(bloom.title).foregroundStyle(VineGold.text(theme)))
                        .font(.app(.subheadline, weight: .medium))
                        .lineLimit(1)
                } else {
                    Text("A new leaf grows each day you train.")
                        .font(.app(.subheadline))
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .trainingCard(theme, cornerRadius: 20)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Your vine. \(countLine)" + (vine.bloom.map { ". In bloom: \($0.title)" } ?? ""))
        .accessibilityAddTraits(.isButton)
    }

    private var countLine: String {
        let total = vine.leaves.count + vine.earlierDays
        return total == 1 ? "1 leaf" : "\(total) leaves"
    }
}

/// The card's little vine: a gold stem running left to right, a leaf for each recent day, the
/// flower, and a closed bud.
struct VineSprig: View {
    let leaves: Int
    let hasBloom: Bool
    let hasBud: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var breathe = false

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width, h = geo.size.height
            let bloomX = w * 0.68
            ZStack {
                Canvas { gc, _ in
                    var stem = Path()
                    stem.move(to: CGPoint(x: 4, y: h * 0.68))
                    stem.addCurve(to: CGPoint(x: bloomX * 0.5, y: h * 0.52),
                                  control1: CGPoint(x: bloomX * 0.18, y: h * 0.25), control2: CGPoint(x: bloomX * 0.32, y: h * 0.8))
                    stem.addCurve(to: CGPoint(x: bloomX, y: h * 0.42),
                                  control1: CGPoint(x: bloomX * 0.68, y: h * 0.25), control2: CGPoint(x: bloomX * 0.84, y: h * 0.62))
                    gc.stroke(stem, with: .color(VineGold.ink.opacity(0.5)), style: StrokeStyle(lineWidth: 4.5, lineCap: .round))
                    gc.stroke(stem, with: .linearGradient(Gradient(colors: [VineGold.deep, VineGold.light, VineGold.bright]),
                                                          startPoint: .zero, endPoint: CGPoint(x: w, y: 0)),
                              style: StrokeStyle(lineWidth: 2.6, lineCap: .round))
                    var ahead = Path()
                    ahead.move(to: CGPoint(x: bloomX, y: h * 0.42))
                    ahead.addCurve(to: CGPoint(x: w - 6, y: h * 0.5),
                                   control1: CGPoint(x: bloomX + 30, y: h * 0.25), control2: CGPoint(x: w - 40, y: h * 0.7))
                    gc.stroke(ahead, with: .color(VineGold.deep.opacity(0.45)),
                              style: StrokeStyle(lineWidth: 1.6, lineCap: .round, dash: [2, 5]))
                    for i in 0..<leaves {
                        let t = CGFloat(i + 1) / CGFloat(leaves + 1)
                        let x = bloomX * t * 0.92
                        let y = h * (0.6 - 0.12 * t)
                        let up = i % 2 == 0
                        gc.fill(VineLeafShape.path(at: CGPoint(x: x, y: y), angle: up ? -.pi / 3.2 : .pi / 3.4, length: 17),
                                with: .linearGradient(Gradient(colors: [VineGold.light, VineGold.deep]),
                                                      startPoint: CGPoint(x: x, y: y - 10), endPoint: CGPoint(x: x, y: y + 10)))
                    }
                    if hasBud {
                        let p = CGPoint(x: w - 34, y: h * 0.52)
                        let bud = VineBudShape.path(at: p, size: 9)
                        gc.fill(bud, with: .color(Color(hex: 0x3A3220)))
                        gc.stroke(bud, with: .color(VineGold.bright.opacity(0.75)), lineWidth: 1)
                    }
                }
                if hasBloom {
                    VineFlower(size: 18, glow: breathe ? 1 : 0.7)
                        .position(x: bloomX, y: h * 0.42)
                }
            }
        }
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(.easeInOut(duration: 2.4).repeatForever(autoreverses: true)) { breathe = true }
        }
    }
}

// MARK: - The page

/// The whole vine: it grows up the page from its root. Each leaf is a day you trained, the
/// flower is what's next, the buds above it come after, and a gold bud is what Premium opens.
struct LearningVinePage: View {
    let vine: LearningVine
    let theme: BoardTheme
    let rankTitle: String?
    @State private var premium = Premium.shared
    @State private var offer: PremiumFeature?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 6) {
                Text("YOUR VINE")
                    .font(VineGold.carved(30))
                    .tracking(2.5)
                    .foregroundStyle(VineGold.title(theme))
                    .accessibilityAddTraits(.isHeader)
                Text(subtitle)
                    .font(.app(.subheadline))
                    .foregroundStyle(.secondary)
                VineStem(nodes: nodes, theme: theme)
                    .padding(.top, 10)
                if vine.earlierDays > 0 {
                    Text(vine.earlierDays == 1 ? "1 earlier day below the root" : "\(vine.earlierDays) earlier days below the root")
                        .font(.app(.caption))
                        .foregroundStyle(.tertiary)
                        .frame(maxWidth: .infinity)
                }
                PremiumGate(theme: theme, isOn: premium.opens(.lessons)) { offer = .lessons }
                    .padding(.top, 18)
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 32)
        }
        .scrollBounceBehavior(.basedOnSize)
        .background { TrainingBackdrop(theme: theme) }
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .premiumOffer($offer)
    }

    private var subtitle: String {
        let total = vine.leaves.count + vine.earlierDays
        var parts = [total == 1 ? "1 leaf grown" : "\(total) leaves grown"]
        let week = vine.daysThisWeek()
        if week > 0 { parts.append(week == 1 ? "1 day this week" : "\(week) days this week") }
        if let rankTitle { parts.append("\(rankTitle) rank") }
        return parts.joined(separator: " · ")
    }

    /// Top to bottom: the furthest bud, the nearer buds, the flower, then the leaves, newest first.
    private var nodes: [VineNode] {
        var list = vine.buds.reversed().map { VineNode(kind: $0.premium ? .premiumBud : .bud, title: $0.title, detail: $0.detail) }
        if let bloom = vine.bloom { list.append(VineNode(kind: .bloom, title: bloom.title, detail: bloom.detail)) }
        list += vine.leaves.map { VineNode(kind: .leaf, title: $0.title, detail: Self.leafDetail($0)) }
        return list
    }

    private static func leafDetail(_ leaf: LearningVine.Leaf) -> String {
        let day = LearningVine.dayLabel(leaf.date)
        return leaf.detail.isEmpty ? day : "\(day) · \(leaf.detail)"
    }
}

struct VineNode: Identifiable, Equatable {
    enum Kind { case leaf, bloom, bud, premiumBud }
    var id: String { "\(kind)-\(title)-\(detail)" }
    let kind: Kind
    let title: String
    let detail: String
}

/// The vine itself: a gold ironwork stem swaying side to side up the page, with a leaf, the
/// flower or a bud at each sway and its words on the open side. It grows in from the root.
struct VineStem: View {
    let nodes: [VineNode]
    let theme: BoardTheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var grown: CGFloat = 0
    @State private var breathe = false

    static let row: CGFloat = 82
    static let sway: CGFloat = 26

    var body: some View {
        let height = CGFloat(max(nodes.count, 1)) * Self.row + 34
        GeometryReader { geo in
            let w = geo.size.width
            let points = Self.points(count: nodes.count, width: w)
            let root = CGPoint(x: w / 2, y: height - 4)
            let bloomIndex = Self.growingTip(nodes)
            ZStack(alignment: .topLeading) {
                // The road ahead: thin and dotted, from the flower up to the last bud.
                if bloomIndex > 0, bloomIndex < points.count {
                    VineCurve(points: Array(points[0...bloomIndex].reversed()), root: nil)
                        .trim(from: 0, to: grown)
                        .stroke(VineGold.deep.opacity(0.5), style: StrokeStyle(lineWidth: 1.8, lineCap: .round, dash: [2, 7]))
                }
                // The grown stem, from the root up to the flower.
                let pastPoints = bloomIndex < points.count ? Array(points[bloomIndex...].reversed()) : Array(points.reversed())
                VineCurve(points: pastPoints, root: root)
                    .trim(from: 0, to: grown)
                    .stroke(VineGold.ink.opacity(0.55), style: StrokeStyle(lineWidth: 7, lineCap: .round))
                    .offset(y: 2)
                VineCurve(points: pastPoints, root: root)
                    .trim(from: 0, to: grown)
                    .stroke(LinearGradient(colors: [VineGold.bright, VineGold.light, VineGold.deep], startPoint: .top, endPoint: .bottom),
                            style: StrokeStyle(lineWidth: 4.2, lineCap: .round))
                VineTendrils(points: pastPoints)
                    .opacity(grown)
                ForEach(Array(nodes.enumerated()), id: \.element.id) { index, node in
                    let p = points[index]
                    let right = p.x > w / 2
                    let shown = grown >= Self.reach(index: index, count: nodes.count)
                    mark(node, at: p, right: right)
                        .scaleEffect(shown ? 1 : 0.2, anchor: right ? .leading : .trailing)
                        .opacity(shown ? 1 : 0)
                    label(node, at: p, right: right, width: w)
                        .opacity(shown ? 1 : 0)
                }
            }
            .frame(width: w, height: height)
        }
        .frame(height: height)
        .accessibilityElement(children: .contain)
        .onAppear {
            guard grown == 0 else { return }
            if reduceMotion {
                grown = 1
            } else {
                withAnimation(.easeOut(duration: 1.6)) { grown = 1 }
                withAnimation(.easeInOut(duration: 2.4).repeatForever(autoreverses: true).delay(1.2)) { breathe = true }
            }
        }
    }

    /// Where the grown stem ends: the flower, or the newest leaf when nothing is in bloom.
    static func growingTip(_ nodes: [VineNode]) -> Int {
        if let bloom = nodes.firstIndex(where: { $0.kind == .bloom }) { return bloom }
        if let leaf = nodes.firstIndex(where: { $0.kind == .leaf }) { return leaf }
        return nodes.count
    }

    /// Where each node sits, top to bottom, swaying left and right of the middle.
    static func points(count: Int, width: CGFloat) -> [CGPoint] {
        (0..<count).map { i in
            let side: CGFloat = (count - 1 - i) % 2 == 0 ? -1 : 1
            return CGPoint(x: width / 2 + side * sway, y: CGFloat(i) * row + row / 2 + 6)
        }
    }

    /// How far the stem must have grown (it grows bottom to top) before node `index` appears.
    static func reach(index: Int, count: Int) -> CGFloat {
        guard count > 0 else { return 0 }
        return CGFloat(count - index) / CGFloat(count + 1)
    }

    @ViewBuilder
    private func mark(_ node: VineNode, at p: CGPoint, right: Bool) -> some View {
        switch node.kind {
        case .leaf:
            VineLeafShape(angle: right ? -.pi / 7 : -.pi + .pi / 7, length: 32)
                .fill(LinearGradient(colors: [VineGold.light, VineGold.deep], startPoint: .top, endPoint: .bottom))
                .overlay(VineLeafShape(angle: right ? -.pi / 7 : -.pi + .pi / 7, length: 32, veinOnly: true)
                    .stroke(VineGold.ink.opacity(0.55), lineWidth: 0.8))
                .shadow(color: .black.opacity(0.35), radius: 2, y: 1)
                .frame(width: 80, height: 80)
                .position(p)
        case .bloom:
            ZStack {
                VineFlower(size: 22, glow: breathe ? 1 : 0.72)
                PieceImage(piece: Piece(.knight, color: .black, square: .a1), theme: theme, size: 15)
            }
            .frame(width: 120, height: 120)
            .position(p)
        case .bud, .premiumBud:
            let premium = node.kind == .premiumBud
            ZStack {
                VineBudShape(size: 11)
                    .fill(premium ? AnyShapeStyle(VineGold.metal) : AnyShapeStyle(Color(hex: 0x3A3220)))
                VineBudShape(size: 11)
                    .stroke(VineGold.bright.opacity(premium ? 0.9 : 0.7), lineWidth: 1.1)
                if premium {
                    Image(systemName: "crown.fill")
                        .font(.system(size: 10))
                        .foregroundStyle(VineGold.bright)
                        .offset(y: -24)
                }
            }
            .frame(width: 60, height: 60)
            .position(p)
        }
    }

    private func label(_ node: VineNode, at p: CGPoint, right: Bool, width: CGFloat) -> some View {
        let gap: CGFloat = node.kind == .bloom ? 40 : 44
        let room = max(right ? width - p.x - gap : p.x - gap, 60)
        let ahead = node.kind == .bud || node.kind == .premiumBud
        return VStack(alignment: right ? .leading : .trailing, spacing: 2) {
            Text(node.title)
                .font(.app(node.kind == .bloom ? .headline : .subheadline, weight: .semibold))
                .foregroundStyle(ahead ? AnyShapeStyle(.secondary) : AnyShapeStyle(.primary))
                .lineLimit(2)
            Text(node.detail)
                .font(.app(.caption, weight: .medium))
                .foregroundStyle(node.kind == .bloom || node.kind == .premiumBud ? AnyShapeStyle(VineGold.text(theme)) : AnyShapeStyle(.secondary))
                .lineLimit(2)
        }
        .multilineTextAlignment(right ? .leading : .trailing)
        .frame(width: room, alignment: right ? .leading : .trailing)
        .position(x: right ? p.x + gap + room / 2 : p.x - gap - room / 2, y: p.y)
        .accessibilityElement(children: .combine)
    }
}

/// A smooth stem through the points (bottom first), from the root when there is one.
struct VineCurve: Shape {
    let points: [CGPoint]
    let root: CGPoint?

    func path(in rect: CGRect) -> Path {
        var all = points
        if let root { all.insert(root, at: 0) }
        var path = Path()
        guard let first = all.first else { return path }
        path.move(to: first)
        for (a, b) in zip(all, all.dropFirst()) {
            let mid = (a.y + b.y) / 2
            path.addCurve(to: b, control1: CGPoint(x: a.x, y: mid), control2: CGPoint(x: b.x, y: mid))
        }
        return path
    }
}

/// Small curling tendrils off the stem, between the leaves, like the knight's branches.
struct VineTendrils: View {
    let points: [CGPoint]

    var body: some View {
        Canvas { gc, _ in
            for (i, (a, b)) in zip(points, points.dropFirst()).enumerated() where i % 2 == 1 {
                let p = CGPoint(x: (a.x + b.x) / 2, y: (a.y + b.y) / 2)
                let side: CGFloat = a.x < b.x ? -1 : 1
                var curl = Path()
                curl.move(to: p)
                curl.addCurve(to: CGPoint(x: p.x + side * 20, y: p.y - 14),
                              control1: CGPoint(x: p.x + side * 8, y: p.y + 2), control2: CGPoint(x: p.x + side * 22, y: p.y - 4))
                curl.addCurve(to: CGPoint(x: p.x + side * 12, y: p.y - 12),
                              control1: CGPoint(x: p.x + side * 18, y: p.y - 22), control2: CGPoint(x: p.x + side * 10, y: p.y - 18))
                gc.stroke(curl, with: .color(VineGold.ink.opacity(0.5)), style: StrokeStyle(lineWidth: 2.6, lineCap: .round))
                gc.stroke(curl, with: .color(VineGold.deep), style: StrokeStyle(lineWidth: 1.3, lineCap: .round))
            }
        }
        .allowsHitTesting(false)
    }
}

/// An almond leaf from a point on the stem, pointing along `angle`.
struct VineLeafShape: Shape {
    var angle: CGFloat
    var length: CGFloat
    var veinOnly = false

    func path(in rect: CGRect) -> Path {
        let origin = CGPoint(x: rect.midX, y: rect.midY)
        if veinOnly {
            var vein = Path()
            vein.move(to: CGPoint(x: length * 0.12, y: 0))
            vein.addLine(to: CGPoint(x: length * 0.85, y: 0))
            return vein.applying(Self.place(origin, angle))
        }
        return Self.path(at: origin, angle: angle, length: length)
    }

    static func path(at origin: CGPoint, angle: CGFloat, length: CGFloat) -> Path {
        var leaf = Path()
        leaf.move(to: .zero)
        leaf.addCurve(to: CGPoint(x: length, y: 0),
                      control1: CGPoint(x: length * 0.25, y: -length * 0.36), control2: CGPoint(x: length * 0.75, y: -length * 0.3))
        leaf.addCurve(to: .zero,
                      control1: CGPoint(x: length * 0.75, y: length * 0.3), control2: CGPoint(x: length * 0.25, y: length * 0.36))
        leaf.closeSubpath()
        return leaf.applying(place(origin, angle))
    }

    private static func place(_ origin: CGPoint, _ angle: CGFloat) -> CGAffineTransform {
        CGAffineTransform(rotationAngle: angle).concatenating(CGAffineTransform(translationX: origin.x, y: origin.y))
    }
}

/// A closed bud: a teardrop standing up from the stem.
struct VineBudShape: Shape {
    var size: CGFloat

    func path(in rect: CGRect) -> Path {
        Self.path(at: CGPoint(x: rect.midX, y: rect.midY), size: size)
    }

    static func path(at p: CGPoint, size s: CGFloat) -> Path {
        var bud = Path()
        bud.move(to: CGPoint(x: p.x, y: p.y + s * 0.8))
        bud.addCurve(to: CGPoint(x: p.x, y: p.y - s * 1.5),
                     control1: CGPoint(x: p.x - s * 1.1, y: p.y), control2: CGPoint(x: p.x - s * 0.5, y: p.y - s))
        bud.addCurve(to: CGPoint(x: p.x, y: p.y + s * 0.8),
                     control1: CGPoint(x: p.x + s * 0.5, y: p.y - s), control2: CGPoint(x: p.x + s * 1.1, y: p.y))
        bud.closeSubpath()
        return bud
    }
}

/// The step in bloom: six gold petals in a soft glow that breathes.
struct VineFlower: View {
    let size: CGFloat
    var glow: CGFloat = 1

    var body: some View {
        ZStack {
            Circle()
                .fill(RadialGradient(colors: [Color(hex: 0xFFE6A8).opacity(0.75 * glow), Color(hex: 0xFFE6A8).opacity(0)],
                                     center: .center, startRadius: 0, endRadius: size * 2.4))
                .frame(width: size * 4.8, height: size * 4.8)
                .scaleEffect(0.85 + 0.15 * glow)
            ForEach(0..<6, id: \.self) { k in
                Ellipse()
                    .fill(LinearGradient(colors: [Color(hex: 0xFFF1CC), Color(hex: 0xE8C27A)], startPoint: .leading, endPoint: .trailing))
                    .overlay(Ellipse().stroke(VineGold.deep.opacity(0.8), lineWidth: 0.7))
                    .frame(width: size * 0.95, height: size * 0.6)
                    .offset(x: size * 0.52)
                    .rotationEffect(.degrees(Double(k) * 60 - 90))
            }
            Circle()
                .fill(RadialGradient(colors: [Color(hex: 0xFFF1CC), Color(hex: 0xC99436)], center: .center, startRadius: 0, endRadius: size * 0.45))
                .frame(width: size * 0.9, height: size * 0.9)
        }
    }
}

/// What's free and what Premium opens, as a gold-edged card under the vine. With Premium on,
/// it simply says everything is open.
struct PremiumGate: View {
    let theme: BoardTheme
    let isOn: Bool
    let open: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "crown.fill")
                    .font(.system(size: 12))
                Text(isOn ? "PREMIUM IS ON" : "GOLD BUDS OPEN WITH PREMIUM")
                    .font(VineGold.carved(12.5))
                    .tracking(1.6)
            }
            .foregroundStyle(VineGold.text(theme))
            if isOn {
                Text("Every bud on your vine is open: every lesson, every drill, your full Chess DNA and deep reviews.")
                    .font(.app(.subheadline))
                    .foregroundStyle(.secondary)
            } else {
                HStack(alignment: .top, spacing: 14) {
                    column("YOURS FREE", lines: Self.freeLines, gold: false)
                    column("PREMIUM", lines: Self.premiumLines, gold: true)
                }
                Button(action: open) {
                    Text("See Premium")
                        .font(.app(.subheadline, weight: .semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(Capsule().strokeBorder(VineGold.text(theme).opacity(0.7), lineWidth: 1))
                        .foregroundStyle(VineGold.text(theme))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .trainingCard(theme, tint: VineGold.deep, cornerRadius: 20)
    }

    private func column(_ title: String, lines: [String], gold: Bool) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.app(.caption2, weight: .bold))
                .tracking(1)
                .foregroundStyle(gold ? AnyShapeStyle(VineGold.text(theme)) : AnyShapeStyle(.secondary))
            ForEach(lines, id: \.self) { line in
                Text(line)
                    .font(.app(.caption))
                    .foregroundStyle(.primary.opacity(0.85))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    static var freeLines: [String] {
        var lines: [String] = []
        if let puzzles = PremiumFeature.ratedPuzzle.free { lines.append("Rated puzzles, \(puzzles.phrase)") }
        if let drills = PremiumFeature.openingDrill.free { lines.append("Drills, \(drills.phrase) of each") }
        lines.append("The first \(TrainingLibrary.freeLessonCount) lessons")
        lines.append("Today's plan, every day")
        return lines
    }

    static let premiumLines = ["Every lesson, every drill", "Your full Chess DNA and deep reviews", "Puzzle review and cycles", "Nothing held back"]
}
