import Accelerate
import Foundation

/// Maia: networks trained on millions of Lichess games to play the move a person of a given
/// rating would play here (https://github.com/CSSLab/maia-chess, GPLv3). They run on the phone
/// with no search: one pass through a small network gives how likely a player of that rating is
/// to choose each legal move. The crowd rivals play from them once their opening book runs out,
/// so a 1200 keeps making a 1200's moves, not a weakened engine's.
///
/// The files in `ChessGameKiller/Maia` are made by `scripts/maia/convert_maia.py`, which also
/// describes their layout; `scripts/maia/reference.py` works out the numbers `MaiaTests` checks.
enum Maia {
    /// The ratings there is a network for.
    static let ratings = [1100, 1200, 1600, 1900]

    /// The network closest to a rating.
    static func rating(nearest rating: Int) -> Int {
        ratings.min { abs($0 - rating) < abs($1 - rating) } ?? 1600
    }
}

// MARK: - The network

/// One Maia network: 6 residual blocks of 64 filters with squeeze-excitation, then a
/// convolutional policy head of 80 planes over the 64 squares. Batch norms are folded in.
final class MaiaNetwork: @unchecked Sendable {
    struct Conv {
        let weights: [Float]  // [out][in][3][3]
        let scale: [Float]
        let shift: [Float]
        let inputs: Int
        let outputs: Int
    }

    struct Block {
        let conv1: Conv
        let conv2: Conv
        let seW1: [Float]  // [se][filters]
        let seB1: [Float]
        let seW2: [Float]  // [2 * filters][se]
        let seB2: [Float]
    }

    static let inputPlanes = 112
    let filters: Int
    let seChannels: Int
    let policyPlanes: Int
    private let input: Conv
    private let blocks: [Block]
    private let policy1: Conv
    private let policy: Conv

    /// The bundled network for a rating, or nil when it isn't in the app.
    convenience init?(rating: Int, bundle: Bundle = .main) {
        guard let url = bundle.url(forResource: "maia-\(rating)", withExtension: "bin"),
              let data = try? Data(contentsOf: url, options: .mappedIfSafe) else { return nil }
        self.init(data: data)
    }

    /// Reads a network file; nil when it isn't one.
    init?(data: Data) {
        var reader = Reader(data: data)
        guard reader.magic() == "MAIA", reader.uint32() == 1,
              let blockCount = reader.uint32(), let filters = reader.uint32(),
              let se = reader.uint32(), let planes = reader.uint32(),
              (1...40).contains(blockCount), (1...512).contains(filters), (1...512).contains(se), planes == 80
        else { return nil }
        self.filters = filters
        self.seChannels = se
        self.policyPlanes = planes

        func conv(_ inputs: Int, _ outputs: Int, bias: Bool = false) -> Conv? {
            guard let weights = reader.halves(outputs * inputs * 9) else { return nil }
            if bias {
                guard let shift = reader.floats(outputs) else { return nil }
                return Conv(weights: weights, scale: [Float](repeating: 1, count: outputs), shift: shift,
                            inputs: inputs, outputs: outputs)
            }
            guard let scale = reader.floats(outputs), let shift = reader.floats(outputs) else { return nil }
            return Conv(weights: weights, scale: scale, shift: shift, inputs: inputs, outputs: outputs)
        }

        guard let input = conv(Self.inputPlanes, filters) else { return nil }
        var blocks: [Block] = []
        for _ in 0..<blockCount {
            guard let conv1 = conv(filters, filters), let conv2 = conv(filters, filters),
                  let w1 = reader.halves(se * filters), let b1 = reader.floats(se),
                  let w2 = reader.halves(2 * filters * se), let b2 = reader.floats(2 * filters)
            else { return nil }
            blocks.append(Block(conv1: conv1, conv2: conv2, seW1: w1, seB1: b1, seW2: w2, seB2: b2))
        }
        guard let policy1 = conv(filters, filters), let policy = conv(filters, planes, bias: true),
              reader.atEnd else { return nil }
        self.input = input
        self.blocks = blocks
        self.policy1 = policy1
        self.policy = policy
    }

    /// The policy head's raw scores, `policyPlanes * 64` of them (plane * 64 + square), for
    /// `MaiaInput`'s 112 planes.
    func policyLogits(planes: [Float]) -> [Float] {
        precondition(planes.count == Self.inputPlanes * 64)
        var x = Self.apply(input, to: planes, relu: true)
        for block in blocks {
            var y = Self.apply(block.conv1, to: x, relu: true)
            y = Self.apply(block.conv2, to: y, relu: false)
            squeezeExcite(&y, block)
            for i in 0..<y.count { x[i] = max(0, y[i] + x[i]) }
        }
        x = Self.apply(policy1, to: x, relu: true)
        return Self.apply(policy, to: x, relu: false)
    }

    private func squeezeExcite(_ y: inout [Float], _ block: Block) {
        let f = filters
        var pooled = [Float](repeating: 0, count: f)
        for c in 0..<f {
            var sum: Float = 0
            for s in 0..<64 { sum += y[c * 64 + s] }
            pooled[c] = sum / 64
        }
        var hidden = [Float](repeating: 0, count: seChannels)
        vDSP_mmul(block.seW1, 1, pooled, 1, &hidden, 1, vDSP_Length(seChannels), 1, vDSP_Length(f))
        for i in 0..<seChannels { hidden[i] = max(0, hidden[i] + block.seB1[i]) }
        var gates = [Float](repeating: 0, count: 2 * f)
        vDSP_mmul(block.seW2, 1, hidden, 1, &gates, 1, vDSP_Length(2 * f), 1, vDSP_Length(seChannels))
        for c in 0..<f {
            let gate = 1 / (1 + exp(-(gates[c] + block.seB2[c])))
            let add = gates[f + c] + block.seB2[f + c]
            for s in 0..<64 { y[c * 64 + s] = y[c * 64 + s] * gate + add }
        }
    }

    /// A 3x3 convolution over the board (zero beyond the edges), then scale, shift and maybe ReLU.
    /// Planes are [channel][rank * 8 + file].
    private static func apply(_ conv: Conv, to x: [Float], relu: Bool) -> [Float] {
        let k = conv.inputs * 9
        // Each column holds the 3x3 neighbourhood of one square, for every input plane.
        var columns = [Float](repeating: 0, count: k * 64)
        columns.withUnsafeMutableBufferPointer { cols in
            x.withUnsafeBufferPointer { src in
                for c in 0..<conv.inputs {
                    for ky in 0..<3 {
                        for kx in 0..<3 {
                            let row = (c * 9 + ky * 3 + kx) * 64
                            for rank in 0..<8 {
                                let r = rank + ky - 1
                                guard (0..<8).contains(r) else { continue }
                                for file in 0..<8 {
                                    let f = file + kx - 1
                                    guard (0..<8).contains(f) else { continue }
                                    cols[row + rank * 8 + file] = src[c * 64 + r * 8 + f]
                                }
                            }
                        }
                    }
                }
            }
        }
        var out = [Float](repeating: 0, count: conv.outputs * 64)
        vDSP_mmul(conv.weights, 1, columns, 1, &out, 1, vDSP_Length(conv.outputs), 64, vDSP_Length(k))
        for o in 0..<conv.outputs {
            let scale = conv.scale[o], shift = conv.shift[o]
            for s in 0..<64 {
                let v = out[o * 64 + s] * scale + shift
                out[o * 64 + s] = relu ? max(0, v) : v
            }
        }
        return out
    }

    /// Reads the file's little-endian fields in order.
    private struct Reader {
        let data: Data
        var offset = 0

        var atEnd: Bool { offset == data.count }

        mutating func bytes(_ count: Int) -> Data? {
            guard count >= 0, offset + count <= data.count else { return nil }
            defer { offset += count }
            let start = data.startIndex + offset
            return data[start..<start + count]
        }

        mutating func magic() -> String? {
            bytes(4).flatMap { String(data: $0, encoding: .ascii) }
        }

        mutating func uint32() -> Int? {
            guard let raw = bytes(4) else { return nil }
            return raw.enumerated().reduce(0) { $0 | Int($1.element) << (8 * $1.offset) }
        }

        mutating func floats(_ count: Int) -> [Float]? {
            guard let raw = bytes(count * 4) else { return nil }
            var out = [Float](repeating: 0, count: count)
            _ = out.withUnsafeMutableBytes { raw.copyBytes(to: $0) }  // iPhones are little-endian, like the file
            return out
        }

        /// Float16 values, widened to Float.
        mutating func halves(_ count: Int) -> [Float]? {
            guard let raw = bytes(count * 2) else { return nil }
            var half = [UInt16](repeating: 0, count: count)
            _ = half.withUnsafeMutableBytes { raw.copyBytes(to: $0) }
            var out = [Float](repeating: 0, count: count)
            half.withUnsafeMutableBufferPointer { h in
                out.withUnsafeMutableBufferPointer { o in
                    var source = vImage_Buffer(data: UnsafeMutableRawPointer(h.baseAddress), height: 1, width: vImagePixelCount(count),
                                               rowBytes: count * 2)
                    var dest = vImage_Buffer(data: UnsafeMutableRawPointer(o.baseAddress), height: 1, width: vImagePixelCount(count),
                                             rowBytes: count * 4)
                    _ = vImageConvert_Planar16FtoPlanarF(&source, &dest, vImage_Flags(kvImageNoFlags))
                }
            }
            return out
        }
    }
}

// MARK: - What the network sees

/// A position read from FEN, enough for Maia: the pieces, who moves, the castling rights and the
/// fifty-move count.
struct MaiaBoard: Equatable {
    /// rank * 8 + file, a1 = 0; letters as in FEN ("P" white pawn, "n" black knight).
    var squares: [Character?]
    var whiteToMove: Bool
    var castling: Set<Character>
    var halfmoves: Int

    init?(fen: String) {
        let fields = fen.split(separator: " ")
        guard fields.count >= 2 else { return nil }
        var squares = [Character?](repeating: nil, count: 64)
        let ranks = fields[0].split(separator: "/", omittingEmptySubsequences: false)
        guard ranks.count == 8 else { return nil }
        for (row, text) in ranks.enumerated() {
            let rank = 7 - row
            var file = 0
            for char in text {
                if let empty = char.wholeNumberValue {
                    file += empty
                } else {
                    guard "PNBRQKpnbrqk".contains(char), file < 8 else { return nil }
                    squares[rank * 8 + file] = char
                    file += 1
                }
            }
            guard file == 8 else { return nil }
        }
        self.squares = squares
        whiteToMove = fields[1] == "w"
        castling = fields.count > 2 ? Set(fields[2].filter { "KQkq".contains($0) }) : []
        halfmoves = fields.count > 4 ? Int(fields[4]) ?? 0 : 0
    }

    /// What makes two positions the same one, for repetitions.
    var key: String {
        squares.map { $0.map(String.init) ?? "." }.joined() + (whiteToMove ? "w" : "b") + String(castling.sorted())
    }

    static let startSquares = MaiaBoard(fen: "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1")!.squares
}

/// lc0's classical 112 input planes, as Maia was trained on them.
enum MaiaInput {
    /// The planes for the last of `fens` (the game so far, oldest first), from the side to move's
    /// point of view: 8 positions of 13 planes (its pieces, the other side's, a repetition), then
    /// castling rights, the side to move, the fifty-move count and a plane of ones. A game that
    /// began from the standard position has nothing before it; one that began from a set-up
    /// position repeats it (lc0's fen_only).
    static func planes(fens: [String]) -> [Float]? {
        let boards = fens.compactMap(MaiaBoard.init(fen:))
        guard let current = boards.last, boards.count == fens.count else { return nil }
        var out = [Float](repeating: 0, count: MaiaNetwork.inputPlanes * 64)
        let white = current.whiteToMove
        let first = boards[0]
        let fromStart = first.squares == MaiaBoard.startSquares && first.whiteToMove

        var seen: [String: Int] = [:]
        var repeated = [Bool](repeating: false, count: boards.count)
        for (i, board) in boards.enumerated() {
            repeated[i] = seen[board.key, default: 0] > 0
            seen[board.key, default: 0] += 1
        }

        for i in 0..<8 {
            let index = boards.count - 1 - i
            if index < 0 && fromStart { break }
            let board = boards[max(0, index)]
            let base = i * 13
            for square in 0..<64 {
                guard let piece = board.squares[square], let kind = pieceOrder[piece] else { continue }
                let plane = base + (piece.isUppercase == white ? 0 : 6) + kind
                let rank = square / 8, file = square % 8
                let seenRank = white ? rank : 7 - rank
                out[plane * 64 + seenRank * 8 + file] = 1
            }
            if index >= 0 && repeated[index] { fill(&out, base + 12, 1) }
        }
        let (ourKing, ourQueen, theirKing, theirQueen): (Character, Character, Character, Character) =
            white ? ("K", "Q", "k", "q") : ("k", "q", "K", "Q")
        if current.castling.contains(ourQueen) { fill(&out, 104, 1) }
        if current.castling.contains(ourKing) { fill(&out, 105, 1) }
        if current.castling.contains(theirQueen) { fill(&out, 106, 1) }
        if current.castling.contains(theirKing) { fill(&out, 107, 1) }
        if !white { fill(&out, 108, 1) }
        fill(&out, 109, Float(current.halfmoves))
        fill(&out, 111, 1)
        return out
    }

    /// Pawn, knight, bishop, rook, queen, king: the order of each side's six planes.
    private static let pieceOrder: [Character: Int] = [
        "P": 0, "N": 1, "B": 2, "R": 3, "Q": 4, "K": 5, "p": 0, "n": 1, "b": 2, "r": 3, "q": 4, "k": 5,
    ]

    private static func fill(_ planes: inout [Float], _ plane: Int, _ value: Float) {
        for s in 0..<64 { planes[plane * 64 + s] = value }
    }
}

// MARK: - Moves

/// Maia's chances for each legal move.
enum MaiaMoves {
    private static let queenDirections = [(0, 1), (1, 1), (1, 0), (1, -1), (0, -1), (-1, -1), (-1, 0), (-1, 1)]
    private static let knightDirections = [(1, 2), (2, 1), (2, -1), (1, -2), (-1, -2), (-2, -1), (-2, 1), (-1, 2)]

    /// Where the policy head scores a move (engine notation) on `board`: plane * 64 + the
    /// from-square, from the mover's side. Castling is the king taking its own rook, and a knight
    /// promotion is the plain pawn move, as lc0 has it. Nil for something that isn't a move.
    static func policyIndex(of uci: String, on board: MaiaBoard) -> Int? {
        let chars = Array(uci)
        guard chars.count >= 4,
              let fromFile = file(chars[0]), let fromRank = rank(chars[1]),
              let toFile0 = file(chars[2]), let toRank0 = rank(chars[3]),
              let piece = board.squares[fromRank * 8 + fromFile] else { return nil }
        var toFile = toFile0
        let toRank = toRank0
        if "Kk".contains(piece), fromFile == 4, abs(toFile - fromFile) == 2, toRank == fromRank {
            toFile = toFile > fromFile ? 7 : 0
        }
        let white = board.whiteToMove
        let fr = white ? fromRank : 7 - fromRank
        let tr = white ? toRank : 7 - toRank
        let df = toFile - fromFile, dr = tr - fr
        let promotion = chars.count >= 5 ? Character(chars[4].lowercased()) : nil
        let plane: Int
        if let promotion, let kind = ["r", "b", "q"].firstIndex(of: promotion), abs(df) <= 1, dr == 1 {
            plane = 64 + (df + 1) * 3 + kind
        } else if let knight = knightDirections.firstIndex(where: { $0 == (df, dr) }) {
            plane = 56 + knight
        } else {
            let steps = max(abs(df), abs(dr))
            guard steps >= 1, steps <= 7, df == 0 || dr == 0 || abs(df) == abs(dr),
                  let direction = queenDirections.firstIndex(where: { $0 == (df.signum(), dr.signum()) }) else { return nil }
            plane = direction * 7 + steps - 1
        }
        return plane * 64 + fr * 8 + fromFile
    }

    /// Each legal move (engine notation, as ChessKit gives them) with Maia's chance of it, most
    /// likely first. A pawn reaching the last rank is offered as each promotion.
    static func probabilities(fens: [String], legal: [String], network: MaiaNetwork) -> [(move: String, chance: Double)] {
        guard let fen = fens.last, let board = MaiaBoard(fen: fen),
              let planes = MaiaInput.planes(fens: fens) else { return [] }
        let logits = network.policyLogits(planes: planes)
        var scored: [(String, Float)] = []
        for move in expandPromotions(legal, on: board) {
            guard let index = policyIndex(of: move, on: board), index < logits.count else { continue }
            scored.append((move, logits[index]))
        }
        guard let top = scored.map({ $0.1 }).max() else { return [] }
        let weights = scored.map { Double(exp($0.1 - top)) }
        let total = weights.reduce(0, +)
        var out: [(move: String, chance: Double)] = []
        for (pair, weight) in zip(scored, weights) { out.append((move: pair.0, chance: weight / total)) }
        return out.sorted { $0.chance > $1.chance }
    }

    /// The move a player of this rating makes: drawn by its chance among the moves people really
    /// consider (at least 5%, or the favourite), so the same position doesn't always go the same way.
    /// `pick` is in 0..<1.
    static func choose(from moves: [(move: String, chance: Double)], pick: Double) -> String? {
        guard let best = moves.first else { return nil }
        let considered = moves.filter { $0.chance >= 0.05 || $0.move == best.move }
        let total = considered.reduce(0) { $0 + $1.chance }
        var left = min(max(pick, 0), 0.999_999) * total
        for move in considered {
            left -= move.chance
            if left < 0 { return move.move }
        }
        return considered.last?.move
    }

    private static func expandPromotions(_ moves: [String], on board: MaiaBoard) -> [String] {
        var out: [String] = []
        var seen = Set<String>()
        for move in moves {
            let chars = Array(move)
            if chars.count == 4, let f = file(chars[0]), let r = rank(chars[1]), let tr = rank(chars[3]),
               let piece = board.squares[r * 8 + f], "Pp".contains(piece), tr == 0 || tr == 7 {
                for letter in ["q", "r", "b", "n"] where seen.insert(move + letter).inserted { out.append(move + letter) }
            } else if seen.insert(move).inserted {
                out.append(move)
            }
        }
        return out
    }

    private static func file(_ c: Character) -> Int? {
        guard let a = c.asciiValue, (97...104).contains(a) else { return nil }
        return Int(a) - 97
    }

    private static func rank(_ c: Character) -> Int? {
        guard let n = c.wholeNumberValue, (1...8).contains(n) else { return nil }
        return n - 1
    }
}

// MARK: - The player

/// Plays a person's move at a rating. A protocol so tests can use a fake.
protocol HumanMovePicking: AnyObject, Sendable {
    /// A move (engine notation) for the last of `fens`, the game so far, oldest first; nil when
    /// there's no network for it or no legal move. `pick` in 0..<1 chooses among the likely moves.
    func move(fens: [String], legal: [String], rating: Int, pick: Double) async -> String?
}

/// Maia on the phone. Networks load on first use and stay loaded (about 2 MB each).
actor MaiaPlayer: HumanMovePicking {
    static let shared = MaiaPlayer()

    private var networks: [Int: MaiaNetwork] = [:]
    private var missing: Set<Int> = []

    func network(rating: Int) -> MaiaNetwork? {
        let rating = Maia.rating(nearest: rating)
        if let loaded = networks[rating] { return loaded }
        guard !missing.contains(rating) else { return nil }
        guard let made = MaiaNetwork(rating: rating) else {
            missing.insert(rating)
            NSLog("Maia: no network for %d", rating)
            return nil
        }
        networks[rating] = made
        return made
    }

    func move(fens: [String], legal: [String], rating: Int, pick: Double) async -> String? {
        guard let network = network(rating: rating) else { return nil }
        let moves = MaiaMoves.probabilities(fens: fens, legal: legal, network: network)
        return MaiaMoves.choose(from: moves, pick: pick)
    }
}
