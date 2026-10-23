import ChessKit
import CoreGraphics
import UIKit

/// Turns a tap on a flat board into the square the player meant.
///
/// The 3D sprites stand taller than their squares: a piece's head is drawn over the square
/// behind it, and that is where a tap on the head lands. So:
/// 1. With a piece picked up, a tap near one of its move dots plays that move, even where
///    the dot shows through a piece's head.
/// 2. Otherwise a tap on the picture of a piece standing in front (one or two rows nearer
///    the player) picks that piece.
/// 3. Otherwise it is the square under the finger.
@MainActor
enum BoardTapResolver {
    /// How near a move dot's center a tap plays that move, in squares.
    static let dotReach: CGFloat = 0.22

    /// The square for a tap at `point`, in points from the top left of the 8x8 squares.
    /// `piece` tells what stands on a square. `isSolid` tells whether a piece's picture, standing
    /// on its square, is solid at a point given from that square's center in squares (down is
    /// positive); nil on boards whose pieces stay inside their squares.
    static func square(
        at point: CGPoint,
        squareSize size: CGFloat,
        flipped: Bool,
        selected: Square?,
        targets: Set<Square>,
        piece: (Square) -> Piece?,
        isSolid: ((Piece, CGPoint) -> Bool)?
    ) -> Square? {
        guard size > 0 else { return nil }
        let column = Int((point.x / size).rounded(.down))
        let row = Int((point.y / size).rounded(.down))
        guard (0..<8).contains(column), (0..<8).contains(row) else { return nil }

        if selected != nil {
            var nearest: (square: Square, distance: CGFloat)?
            for target in targets {
                let dot = center(of: target, squareSize: size, flipped: flipped)
                let distance = hypot(point.x - dot.x, point.y - dot.y)
                if distance <= dotReach * size, distance < (nearest?.distance ?? .infinity) {
                    nearest = (target, distance)
                }
            }
            if let nearest { return nearest.square }
        }

        if let isSolid {
            // The nearer row first: it is drawn over the one behind it.
            for ahead in [2, 1] where row + ahead < 8 {
                let front = squareAt(column: column, row: row + ahead, flipped: flipped)
                guard let standing = piece(front) else { continue }
                if isSolid(standing, offset(of: point, from: front, squareSize: size, flipped: flipped,
                                            lifted: front == selected)) {
                    return front
                }
            }
        }
        return squareAt(column: column, row: row, flipped: flipped)
    }

    /// A square's center, in points from the top left of the squares.
    static func center(of square: Square, squareSize size: CGFloat, flipped: Bool) -> CGPoint {
        let column = flipped ? 7 - square.fileIndex : square.fileIndex
        let row = flipped ? square.rankIndex : 7 - square.rankIndex
        return CGPoint(x: (CGFloat(column) + 0.5) * size, y: (CGFloat(row) + 0.5) * size)
    }

    /// Where `point` is from the center of `square`, in squares, as the piece standing there
    /// is drawn: a picked-up piece is drawn a little larger, about its square's center.
    static func offset(of point: CGPoint, from square: Square, squareSize size: CGFloat, flipped: Bool,
                       lifted: Bool) -> CGPoint {
        let middle = center(of: square, squareSize: size, flipped: flipped)
        let scale = size * (lifted ? PieceImage.liftedScale : 1)
        return CGPoint(x: (point.x - middle.x) / scale, y: (point.y - middle.y) / scale)
    }

    private static func squareAt(column: Int, row: Int, flipped: Bool) -> Square {
        flipped ? Square(file: 7 - column, rank: row) : Square(file: column, rank: 7 - row)
    }
}

/// A small copy of a picture's alpha channel: where a piece's picture is solid.
struct AlphaMask {
    let width: Int
    let height: Int
    /// Row by row from the top: 0 is clear, 255 solid.
    let alpha: [UInt8]
    /// How far down the picture its first solid row is, as a fraction of its height:
    /// the top of the piece. Nil for a picture with nothing solid in it.
    let top: CGFloat?

    init(width: Int, height: Int, alpha: [UInt8]) {
        self.width = width
        self.height = height
        self.alpha = alpha
        top = Self.firstSolidRow(width: width, height: height, alpha: alpha).map { CGFloat($0) / CGFloat(max(height, 1)) }
    }

    /// The picture's alpha at `scale` of its size: an eighth is plenty for a fingertip.
    init?(image: CGImage, scale: CGFloat = 1.0 / 8) {
        let width = max(Int((CGFloat(image.width) * scale).rounded()), 1)
        let height = max(Int((CGFloat(image.height) * scale).rounded()), 1)
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        let drawn: Bool = pixels.withUnsafeMutableBytes { buffer in
            guard let context = CGContext(
                data: buffer.baseAddress, width: width, height: height, bitsPerComponent: 8,
                bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ) else { return false }
            context.interpolationQuality = .medium
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        guard drawn else { return nil }
        // The bitmap's first row is the top of the picture.
        self.init(width: width, height: height, alpha: stride(from: 3, to: pixels.count, by: 4).map { pixels[$0] })
    }

    /// The alpha at a point given as a fraction of the picture's width and height from its
    /// top left; 0 off the picture.
    func value(atUnit point: CGPoint) -> UInt8 {
        let x = Int((point.x * CGFloat(width)).rounded(.down))
        let y = Int((point.y * CGFloat(height)).rounded(.down))
        guard (0..<width).contains(x), (0..<height).contains(y), alpha.count == width * height else { return 0 }
        return alpha[y * width + x]
    }

    /// Solid enough that a finger there is on the piece, not on its soft shadow.
    func isSolid(atUnit point: CGPoint) -> Bool {
        value(atUnit: point) > 127
    }

    private static func firstSolidRow(width: Int, height: Int, alpha: [UInt8]) -> Int? {
        guard alpha.count == width * height else { return nil }
        return (0..<height).first { y in (0..<width).contains { alpha[y * width + $0] > 127 } }
    }
}

/// The sprites' alpha masks, made the first time each picture is needed.
@MainActor
final class SpriteMasks {
    static let shared = SpriteMasks()

    private var masks: [String: AlphaMask] = [:]
    private var missing: Set<String> = []

    /// The mask of a picture in the asset catalog, or nil if there is no such picture.
    func mask(named name: String) -> AlphaMask? {
        if let mask = masks[name] { return mask }
        guard !missing.contains(name) else { return nil }
        guard let image = UIImage(named: name)?.cgImage, let mask = AlphaMask(image: image) else {
            missing.insert(name)
            return nil
        }
        masks[name] = mask
        return mask
    }

    /// Whether a piece's picture in `theme`, standing on its square as the board draws it, is
    /// solid at `offset` from the square's center, in squares.
    func isSolid(_ piece: Piece, in theme: BoardTheme, at offset: CGPoint) -> Bool {
        let name = theme.imageName(for: piece)
        guard let mask = mask(named: name) else { return false }
        let rect = PieceImage.boardRect(of: name, squareSize: 1)
        return mask.isSolid(atUnit: CGPoint(x: (offset.x - rect.minX) / rect.width,
                                            y: (offset.y - rect.minY) / rect.height))
    }
}
