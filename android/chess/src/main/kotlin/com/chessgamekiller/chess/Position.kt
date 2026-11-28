package com.chessgamekiller.chess

/**
 * The rules of chess, small and self-contained, so the Android app needs no chess library.
 *
 * Squares are 0..63: a1 = 0, b1 = 1, ... h1 = 7, a2 = 8, ... h8 = 63.
 * A board cell holds a FEN letter ('P' white pawn, 'k' black king) or '.' when empty.
 */
data class Move(val from: Int, val to: Int, val promotion: Char? = null) {
    val uci: String get() = squareName(from) + squareName(to) + (promotion?.lowercaseChar()?.toString() ?: "")

    override fun toString(): String = uci

    companion object {
        fun fromUci(text: String): Move? {
            if (text.length !in 4..5) return null
            val from = squareIndex(text.substring(0, 2)) ?: return null
            val to = squareIndex(text.substring(2, 4)) ?: return null
            val promo = if (text.length == 5) text[4].lowercaseChar() else null
            if (promo != null && promo !in "qrbn") return null
            return Move(from, to, promo)
        }
    }
}

fun fileOf(square: Int) = square and 7
fun rankOf(square: Int) = square shr 3
fun squareName(square: Int): String = "${'a' + fileOf(square)}${'1' + rankOf(square)}"
fun squareIndex(name: String): Int? {
    if (name.length != 2) return null
    val f = name[0] - 'a'
    val r = name[1] - '1'
    if (f !in 0..7 || r !in 0..7) return null
    return r * 8 + f
}

fun isWhitePiece(c: Char) = c in 'A'..'Z'
fun isBlackPiece(c: Char) = c in 'a'..'z'

class Position private constructor(
    private val cells: CharArray,
    /** True when White is to move. */
    val whiteToMove: Boolean,
    /** Castling rights as FEN letters, any of "KQkq", or "" for none. */
    val castling: String,
    /** The en passant target square, or -1. */
    val epSquare: Int,
    val halfmoveClock: Int,
    val fullmoveNumber: Int,
) {
    operator fun get(square: Int): Char = cells[square]

    fun board(): CharArray = cells.copyOf()

    // MARK: FEN

    val fen: String
        get() = buildString {
            for (r in 7 downTo 0) {
                var empty = 0
                for (f in 0..7) {
                    val c = cells[r * 8 + f]
                    if (c == '.') empty++ else {
                        if (empty > 0) { append(empty); empty = 0 }
                        append(c)
                    }
                }
                if (empty > 0) append(empty)
                if (r > 0) append('/')
            }
            append(if (whiteToMove) " w " else " b ")
            append(castling.ifEmpty { "-" })
            append(' ')
            append(if (epSquare >= 0) squareName(epSquare) else "-")
            append(' ').append(halfmoveClock).append(' ').append(fullmoveNumber)
        }

    /** The board, the side to move, castling and en passant: what makes two positions "the same" for repetition. */
    val repetitionKey: String get() = fen.split(' ').take(4).joinToString(" ")

    // MARK: Attacks

    /** Is [square] attacked by a piece of the given color? */
    fun isAttacked(square: Int, byWhite: Boolean): Boolean {
        val f = fileOf(square)
        val r = rankOf(square)
        // Pawns
        val pawn = if (byWhite) 'P' else 'p'
        val pr = if (byWhite) r - 1 else r + 1
        if (pr in 0..7) {
            if (f > 0 && cells[pr * 8 + f - 1] == pawn) return true
            if (f < 7 && cells[pr * 8 + f + 1] == pawn) return true
        }
        val knight = if (byWhite) 'N' else 'n'
        for ((df, dr) in KNIGHT) {
            val nf = f + df; val nr = r + dr
            if (nf in 0..7 && nr in 0..7 && cells[nr * 8 + nf] == knight) return true
        }
        val king = if (byWhite) 'K' else 'k'
        for ((df, dr) in KING) {
            val nf = f + df; val nr = r + dr
            if (nf in 0..7 && nr in 0..7 && cells[nr * 8 + nf] == king) return true
        }
        val rook = if (byWhite) 'R' else 'r'
        val bishop = if (byWhite) 'B' else 'b'
        val queen = if (byWhite) 'Q' else 'q'
        for ((df, dr) in ROOK_DIRS) {
            var nf = f + df; var nr = r + dr
            while (nf in 0..7 && nr in 0..7) {
                val c = cells[nr * 8 + nf]
                if (c != '.') { if (c == rook || c == queen) return true; break }
                nf += df; nr += dr
            }
        }
        for ((df, dr) in BISHOP_DIRS) {
            var nf = f + df; var nr = r + dr
            while (nf in 0..7 && nr in 0..7) {
                val c = cells[nr * 8 + nf]
                if (c != '.') { if (c == bishop || c == queen) return true; break }
                nf += df; nr += dr
            }
        }
        return false
    }

    fun kingSquare(white: Boolean): Int = cells.indexOf(if (white) 'K' else 'k')

    val inCheck: Boolean
        get() {
            val k = kingSquare(whiteToMove)
            return k >= 0 && isAttacked(k, !whiteToMove)
        }

    // MARK: Moves

    private fun own(c: Char) = if (whiteToMove) isWhitePiece(c) else isBlackPiece(c)
    private fun enemy(c: Char) = if (whiteToMove) isBlackPiece(c) else isWhitePiece(c)

    private fun pseudoMoves(): List<Move> {
        val out = ArrayList<Move>(48)
        for (sq in 0 until 64) {
            val c = cells[sq]
            if (c == '.' || !own(c)) continue
            val f = fileOf(sq); val r = rankOf(sq)
            when (c.lowercaseChar()) {
                'p' -> {
                    val dir = if (whiteToMove) 1 else -1
                    val startRank = if (whiteToMove) 1 else 6
                    val lastRank = if (whiteToMove) 7 else 0
                    val one = r + dir
                    if (one in 0..7) {
                        val t = one * 8 + f
                        if (cells[t] == '.') {
                            addPawn(out, sq, t, one == lastRank)
                            if (r == startRank) {
                                val t2 = (r + 2 * dir) * 8 + f
                                if (cells[t2] == '.') out.add(Move(sq, t2))
                            }
                        }
                        for (df in intArrayOf(-1, 1)) {
                            val nf = f + df
                            if (nf !in 0..7) continue
                            val t = one * 8 + nf
                            if (enemy(cells[t])) addPawn(out, sq, t, one == lastRank)
                            else if (t == epSquare) out.add(Move(sq, t))
                        }
                    }
                }
                'n' -> for ((df, dr) in KNIGHT) step(out, sq, f + df, r + dr)
                'k' -> {
                    for ((df, dr) in KING) step(out, sq, f + df, r + dr)
                    castlingMoves(out, sq)
                }
                'r' -> slide(out, sq, ROOK_DIRS)
                'b' -> slide(out, sq, BISHOP_DIRS)
                'q' -> { slide(out, sq, ROOK_DIRS); slide(out, sq, BISHOP_DIRS) }
            }
        }
        return out
    }

    private fun addPawn(out: MutableList<Move>, from: Int, to: Int, promotes: Boolean) {
        if (promotes) for (p in "qrbn") out.add(Move(from, to, p)) else out.add(Move(from, to))
    }

    private fun step(out: MutableList<Move>, from: Int, nf: Int, nr: Int) {
        if (nf !in 0..7 || nr !in 0..7) return
        val t = nr * 8 + nf
        if (!own(cells[t])) out.add(Move(from, t))
    }

    private fun slide(out: MutableList<Move>, from: Int, dirs: Array<IntArray>) {
        val f = fileOf(from); val r = rankOf(from)
        for ((df, dr) in dirs) {
            var nf = f + df; var nr = r + dr
            while (nf in 0..7 && nr in 0..7) {
                val t = nr * 8 + nf
                val c = cells[t]
                if (c == '.') out.add(Move(from, t)) else {
                    if (enemy(c)) out.add(Move(from, t))
                    break
                }
                nf += df; nr += dr
            }
        }
    }

    private fun castlingMoves(out: MutableList<Move>, kingSq: Int) {
        val white = whiteToMove
        val home = if (white) 4 else 60
        if (kingSq != home) return
        val them = !white
        if (isAttacked(home, them)) return
        val kingSide = if (white) 'K' else 'k'
        val queenSide = if (white) 'Q' else 'q'
        val rook = if (white) 'R' else 'r'
        if (kingSide in castling && cells[home + 3] == rook &&
            cells[home + 1] == '.' && cells[home + 2] == '.' &&
            !isAttacked(home + 1, them) && !isAttacked(home + 2, them)
        ) out.add(Move(home, home + 2))
        if (queenSide in castling && cells[home - 4] == rook &&
            cells[home - 1] == '.' && cells[home - 2] == '.' && cells[home - 3] == '.' &&
            !isAttacked(home - 1, them) && !isAttacked(home - 2, them)
        ) out.add(Move(home, home - 2))
    }

    private var legalCache: List<Move>? = null

    /** Every legal move, in a stable order. */
    fun legalMoves(): List<Move> {
        legalCache?.let { return it }
        val mover = whiteToMove
        val moves = pseudoMoves().filter { m ->
            val next = applyUnchecked(m)
            val k = next.kingSquare(mover)
            k >= 0 && !next.isAttacked(k, !mover)
        }
        legalCache = moves
        return moves
    }

    fun isLegal(move: Move): Boolean = legalMoves().contains(normalize(move))

    /** A move as the player meant it: a pawn reaching the last rank without a piece named becomes a queen. */
    fun normalize(move: Move): Move {
        val c = cells[move.from]
        if (c.lowercaseChar() == 'p' && (rankOf(move.to) == 7 || rankOf(move.to) == 0) && move.promotion == null) {
            return move.copy(promotion = 'q')
        }
        return move
    }

    fun needsPromotion(from: Int, to: Int): Boolean {
        val c = cells[from]
        return c.lowercaseChar() == 'p' && (rankOf(to) == 7 || rankOf(to) == 0) &&
            legalMoves().any { it.from == from && it.to == to }
    }

    /** The position after a legal move. Throws if the move isn't legal. */
    fun play(move: Move): Position {
        val m = normalize(move)
        require(isLegal(m)) { "Illegal move ${m.uci} in $fen" }
        return applyUnchecked(m)
    }

    private fun applyUnchecked(m: Move): Position {
        val b = cells.copyOf()
        val piece = b[m.from]
        val captured = b[m.to]
        val lower = piece.lowercaseChar()
        var ep = -1
        b[m.from] = '.'
        // En passant capture
        if (lower == 'p' && m.to == epSquare && captured == '.' && fileOf(m.from) != fileOf(m.to)) {
            val capSq = if (whiteToMove) m.to - 8 else m.to + 8
            b[capSq] = '.'
        }
        // Castling: move the rook too
        if (lower == 'k' && kotlin.math.abs(m.to - m.from) == 2) {
            if (m.to > m.from) { b[m.from + 1] = b[m.from + 3]; b[m.from + 3] = '.' }
            else { b[m.from - 1] = b[m.from - 4]; b[m.from - 4] = '.' }
        }
        b[m.to] = if (m.promotion != null) {
            if (whiteToMove) m.promotion.uppercaseChar() else m.promotion.lowercaseChar()
        } else piece
        if (lower == 'p' && kotlin.math.abs(m.to - m.from) == 16) ep = (m.from + m.to) / 2

        var rights = castling
        fun drop(c: Char) { rights = rights.replace(c.toString(), "") }
        if (piece == 'K') { drop('K'); drop('Q') }
        if (piece == 'k') { drop('k'); drop('q') }
        for (sq in intArrayOf(m.from, m.to)) when (sq) {
            0 -> drop('Q'); 7 -> drop('K'); 56 -> drop('q'); 63 -> drop('k')
        }
        val half = if (lower == 'p' || captured != '.') 0 else halfmoveClock + 1
        val full = if (whiteToMove) fullmoveNumber else fullmoveNumber + 1
        return Position(b, !whiteToMove, rights, ep, half, full)
    }

    /** The same board with the other side to move and no en passant: "what would they do if it were their turn?" */
    fun nullMove(): Position? {
        if (inCheck) return null
        return Position(cells.copyOf(), !whiteToMove, castling, -1, halfmoveClock, fullmoveNumber)
    }

    // MARK: Notation

    /** Standard notation for a legal move: "Nf3", "exd5", "O-O", "e8=Q+". */
    fun san(move: Move): String {
        val m = normalize(move)
        val piece = cells[m.from]
        val lower = piece.lowercaseChar()
        val capture = cells[m.to] != '.' || (lower == 'p' && m.to == epSquare && fileOf(m.from) != fileOf(m.to))
        val text = StringBuilder()
        if (lower == 'k' && kotlin.math.abs(m.to - m.from) == 2) {
            text.append(if (m.to > m.from) "O-O" else "O-O-O")
        } else if (lower == 'p') {
            if (capture) text.append('a' + fileOf(m.from)).append('x')
            text.append(squareName(m.to))
            if (m.promotion != null) text.append('=').append(m.promotion.uppercaseChar())
        } else {
            text.append(lower.uppercaseChar())
            val rivals = legalMoves().filter { it.to == m.to && it.from != m.from && cells[it.from] == piece }
            if (rivals.isNotEmpty()) {
                val sameFile = rivals.any { fileOf(it.from) == fileOf(m.from) }
                val sameRank = rivals.any { rankOf(it.from) == rankOf(m.from) }
                if (!sameFile) text.append('a' + fileOf(m.from))
                else if (!sameRank) text.append('1' + rankOf(m.from))
                else text.append(squareName(m.from))
            }
            if (capture) text.append('x')
            text.append(squareName(m.to))
        }
        val next = applyUnchecked(m)
        if (next.inCheck) text.append(if (next.legalMoves().isEmpty()) '#' else '+')
        return text.toString()
    }

    /** Reads a move in standard notation, forgiving about check marks. */
    fun parseSan(text: String): Move? {
        val clean = text.trim().trimEnd('+', '#', '!', '?')
        return legalMoves().firstOrNull { san(it).trimEnd('+', '#') == clean }
    }

    /** Material that can never give mate: K v K, K+minor v K, K+B v K+B with bishops on one color. */
    val insufficientMaterial: Boolean
        get() {
            val pieces = cells.withIndex().filter { it.value != '.' && it.value.lowercaseChar() != 'k' }
            if (pieces.isEmpty()) return true
            if (pieces.any { it.value.lowercaseChar() in "pqr" }) return false
            if (pieces.size == 1) return true
            if (pieces.all { it.value.lowercaseChar() == 'b' }) {
                val colors = pieces.map { (fileOf(it.index) + rankOf(it.index)) % 2 }.toSet()
                return colors.size == 1
            }
            return false
        }

    companion object {
        const val START_FEN = "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1"

        val KNIGHT = arrayOf(
            intArrayOf(1, 2), intArrayOf(2, 1), intArrayOf(2, -1), intArrayOf(1, -2),
            intArrayOf(-1, -2), intArrayOf(-2, -1), intArrayOf(-2, 1), intArrayOf(-1, 2),
        )
        val KING = arrayOf(
            intArrayOf(1, 0), intArrayOf(1, 1), intArrayOf(0, 1), intArrayOf(-1, 1),
            intArrayOf(-1, 0), intArrayOf(-1, -1), intArrayOf(0, -1), intArrayOf(1, -1),
        )
        val ROOK_DIRS = arrayOf(intArrayOf(1, 0), intArrayOf(-1, 0), intArrayOf(0, 1), intArrayOf(0, -1))
        val BISHOP_DIRS = arrayOf(intArrayOf(1, 1), intArrayOf(1, -1), intArrayOf(-1, 1), intArrayOf(-1, -1))

        fun start(): Position = fromFen(START_FEN)!!

        /** Reads a FEN. Returns null when it isn't a playable position (bad text, a king missing or two). */
        fun fromFen(fen: String): Position? {
            val parts = fen.trim().split(Regex("\\s+"))
            if (parts.isEmpty()) return null
            val rows = parts[0].split('/')
            if (rows.size != 8) return null
            val cells = CharArray(64) { '.' }
            for ((i, row) in rows.withIndex()) {
                val r = 7 - i
                var f = 0
                for (c in row) {
                    if (c.isDigit()) f += c - '0'
                    else {
                        if (c !in "PNBRQKpnbrqk" || f > 7) return null
                        cells[r * 8 + f] = c
                        f++
                    }
                }
                if (f != 8) return null
            }
            if (cells.count { it == 'K' } != 1 || cells.count { it == 'k' } != 1) return null
            val white = parts.getOrElse(1) { "w" } != "b"
            var castling = parts.getOrElse(2) { "-" }.filter { it in "KQkq" }
            // Drop rights the board can't have.
            if (cells[4] != 'K') castling = castling.replace("K", "").replace("Q", "")
            if (cells[60] != 'k') castling = castling.replace("k", "").replace("q", "")
            if (cells[7] != 'R') castling = castling.replace("K", "")
            if (cells[0] != 'R') castling = castling.replace("Q", "")
            if (cells[63] != 'r') castling = castling.replace("k", "")
            if (cells[56] != 'r') castling = castling.replace("q", "")
            val ep = parts.getOrElse(3) { "-" }.let { if (it == "-") -1 else squareIndex(it) ?: -1 }
            val half = parts.getOrElse(4) { "0" }.toIntOrNull() ?: 0
            val full = parts.getOrElse(5) { "1" }.toIntOrNull()?.coerceAtLeast(1) ?: 1
            val position = Position(cells, white, castling, ep, half, full)
            // The side not to move can't be in check.
            val theirKing = position.kingSquare(!white)
            if (position.isAttacked(theirKing, white)) return null
            return position
        }

        /** Builds a position from 64 cells (a1 first) and the side to move, guessing castling rights from the board. */
        fun fromCells(cells: CharArray, whiteToMove: Boolean): Position? {
            val sb = StringBuilder()
            for (r in 7 downTo 0) {
                var empty = 0
                for (f in 0..7) {
                    val c = cells[r * 8 + f]
                    if (c == '.') empty++ else { if (empty > 0) { sb.append(empty); empty = 0 }; sb.append(c) }
                }
                if (empty > 0) sb.append(empty)
                if (r > 0) sb.append('/')
            }
            var rights = ""
            if (cells[4] == 'K' && cells[7] == 'R') rights += "K"
            if (cells[4] == 'K' && cells[0] == 'R') rights += "Q"
            if (cells[60] == 'k' && cells[63] == 'r') rights += "k"
            if (cells[60] == 'k' && cells[56] == 'r') rights += "q"
            return fromFen("$sb ${if (whiteToMove) "w" else "b"} ${rights.ifEmpty { "-" }} - 0 1")
        }
    }
}
