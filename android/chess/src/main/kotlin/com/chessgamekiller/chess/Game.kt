package com.chessgamekiller.chess

/** How a game stands. */
enum class GameStatus { ONGOING, CHECKMATE, STALEMATE, FIFTY_MOVES, REPETITION, INSUFFICIENT_MATERIAL }

/** One move played, with its notation and the position it left. */
data class PlayedMove(val move: Move, val san: String, val after: Position)

/** A game from a starting position: the moves so far, and whether it is over. */
class Game(val start: Position = Position.start()) {
    private val played = mutableListOf<PlayedMove>()

    val moves: List<PlayedMove> get() = played
    val position: Position get() = played.lastOrNull()?.after ?: start
    val lastMove: Move? get() = played.lastOrNull()?.move

    fun play(move: Move): PlayedMove {
        val before = position
        val m = before.normalize(move)
        val san = before.san(m)
        val entry = PlayedMove(m, san, before.play(m))
        played.add(entry)
        return entry
    }

    fun playUci(uci: String): PlayedMove? {
        val m = Move.fromUci(uci) ?: return null
        if (!position.isLegal(m)) return null
        return play(m)
    }

    /** Takes back the last move. */
    fun undo(): PlayedMove? = if (played.isEmpty()) null else played.removeAt(played.size - 1)

    val status: GameStatus
        get() {
            val p = position
            if (p.legalMoves().isEmpty()) return if (p.inCheck) GameStatus.CHECKMATE else GameStatus.STALEMATE
            if (p.insufficientMaterial) return GameStatus.INSUFFICIENT_MATERIAL
            if (p.halfmoveClock >= 100) return GameStatus.FIFTY_MOVES
            val key = p.repetitionKey
            val seen = (listOf(start) + played.map { it.after }).count { it.repetitionKey == key }
            if (seen >= 3) return GameStatus.REPETITION
            return GameStatus.ONGOING
        }

    val isOver: Boolean get() = status != GameStatus.ONGOING

    /** The winner when the board decides it: true White, false Black, null a draw or still playing. */
    val whiteWon: Boolean?
        get() = if (status == GameStatus.CHECKMATE) !position.whiteToMove else null

    /** The moves as "1. e4 e5 2. Nf3". */
    fun pgnMoves(): String = buildString {
        var number = start.fullmoveNumber
        var white = start.whiteToMove
        for ((i, m) in played.withIndex()) {
            if (white) append("$number. ") else if (i == 0) append("$number... ")
            append(m.san).append(' ')
            if (!white) number++
            white = !white
        }
    }.trim()
}
