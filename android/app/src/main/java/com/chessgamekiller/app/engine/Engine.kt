package com.chessgamekiller.app.engine

import android.content.Context
import android.util.Log
import com.chessgamekiller.chess.Move
import com.chessgamekiller.chess.Position
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import kotlinx.coroutines.withContext
import java.io.BufferedReader
import java.io.File
import java.io.InputStreamReader
import java.io.OutputStreamWriter

/** A score from the side to move's view: centipawns, or mate in n (negative: it gets mated). */
data class Eval(val cp: Int? = null, val mate: Int? = null) {
    /** For bars and sorting: mates count as a huge number. */
    val sortValue: Int get() = when {
        mate != null -> if (mate > 0) 100_000 - mate else -100_000 - mate
        else -> cp ?: 0
    }

    fun flipped() = Eval(cp?.let { -it }, mate?.let { -it })

    /** "+0.4", "-1.2", "M3", "-M2". */
    fun label(): String = when {
        mate != null -> if (mate > 0) "M$mate" else "-M${-mate}"
        else -> {
            val v = (cp ?: 0) / 100.0
            (if (v > 0) "+" else "") + String.format(java.util.Locale.US, "%.1f", v)
        }
    }
}

/** One line from the engine: the moves (engine notation) and its score, from the side to move's view. */
data class EngineLine(val moves: List<String>, val eval: Eval, val depth: Int)

interface ChessEngine {
    /** Up to [lines] best lines for the side to move, best first. */
    suspend fun analyze(fen: String, depth: Int, lines: Int, maxTimeMs: Int): List<EngineLine>

    /** A move at a given strength: Stockfish's skill (0 weakest, 20 full), an optional depth cap, and a time cap. */
    suspend fun chooseMove(fen: String, skill: Int, depth: Int?, thinkTimeMs: Int): String?

    val isReal: Boolean
}

object Engines {
    @Volatile private var shared: ChessEngine? = null

    fun get(context: Context): ChessEngine {
        shared?.let { return it }
        synchronized(this) {
            shared?.let { return it }
            val binary = File(context.applicationInfo.nativeLibraryDir, "libstockfish.so")
            val engine: ChessEngine = if (binary.exists()) Stockfish(binary) else SimpleEngine()
            shared = engine
            return engine
        }
    }

    /** For tests: swap in an engine. */
    fun install(engine: ChessEngine) { shared = engine }
}

/**
 * Stockfish 17 running as its own program, spoken to in UCI, one search at a time.
 * The program ships inside the app as lib/<abi>/libstockfish.so (see .github/workflows/android.yml).
 */
class Stockfish(private val binary: File) : ChessEngine {
    override val isReal = true
    private val lock = Mutex()
    private var process: Process? = null
    private var input: OutputStreamWriter? = null
    private var output: BufferedReader? = null

    private fun ensureStarted() {
        if (process?.isAlive == true) return
        val p = ProcessBuilder(binary.absolutePath).redirectErrorStream(true).start()
        process = p
        input = OutputStreamWriter(p.outputStream)
        output = BufferedReader(InputStreamReader(p.inputStream))
        send("uci")
        readUntil { it == "uciok" }
        val threads = (Runtime.getRuntime().availableProcessors() - 1).coerceIn(1, 4)
        send("setoption name Threads value $threads")
        send("setoption name Hash value 64")
        send("isready")
        readUntil { it == "readyok" }
    }

    private fun send(line: String) {
        input?.apply { write(line + "\n"); flush() }
    }

    private fun readUntil(stop: (String) -> Boolean): List<String> {
        val seen = mutableListOf<String>()
        val reader = output ?: return seen
        while (true) {
            val line = reader.readLine() ?: break
            seen.add(line)
            if (stop(line)) break
        }
        return seen
    }

    private suspend fun <T> session(block: () -> T): T? = withContext(Dispatchers.IO) {
        lock.withLock {
            try {
                ensureStarted()
                block()
            } catch (e: Exception) {
                Log.w("Stockfish", "engine failed", e)
                process?.destroy(); process = null
                null
            }
        }
    }

    override suspend fun analyze(fen: String, depth: Int, lines: Int, maxTimeMs: Int): List<EngineLine> =
        session {
            send("setoption name Skill Level value 20")
            send("setoption name MultiPV value ${lines.coerceAtLeast(1)}")
            send("ucinewgame")
            send("position fen $fen")
            send("go depth $depth movetime $maxTimeMs")
            val found = HashMap<Int, EngineLine>()
            for (line in readUntil { it.startsWith("bestmove") }) {
                parseInfo(line)?.let { (index, parsed) ->
                    val old = found[index]
                    if (old == null || parsed.depth >= old.depth) found[index] = parsed
                }
            }
            found.toSortedMap().values.toList()
        } ?: emptyList()

    override suspend fun chooseMove(fen: String, skill: Int, depth: Int?, thinkTimeMs: Int): String? = session {
        send("setoption name Skill Level value ${skill.coerceIn(0, 20)}")
        send("setoption name MultiPV value 1")
        send("position fen $fen")
        send(if (depth != null) "go depth $depth movetime $thinkTimeMs" else "go movetime $thinkTimeMs")
        readUntil { it.startsWith("bestmove") }.lastOrNull()
            ?.split(' ')?.getOrNull(1)?.takeIf { it != "(none)" }
    }

    companion object {
        /** Reads "info depth 12 ... multipv 2 score cp 31 ... pv e1g1 d7d6". */
        fun parseInfo(line: String): Pair<Int, EngineLine>? {
            if (!line.startsWith("info ") || " pv " !in line || " score " !in line) return null
            if (" lowerbound" in line || " upperbound" in line) return null
            val parts = line.split(' ')
            var depth = 0; var multipv = 1; var eval: Eval? = null
            var i = 0
            while (i < parts.size) {
                when (parts[i]) {
                    "depth" -> depth = parts.getOrNull(i + 1)?.toIntOrNull() ?: 0
                    "multipv" -> multipv = parts.getOrNull(i + 1)?.toIntOrNull() ?: 1
                    "score" -> {
                        val kind = parts.getOrNull(i + 1)
                        val value = parts.getOrNull(i + 2)?.toIntOrNull()
                        eval = if (kind == "mate") Eval(mate = value) else Eval(cp = value)
                    }
                    "pv" -> {
                        val moves = parts.drop(i + 1)
                        return multipv to EngineLine(moves, eval ?: return null, depth)
                    }
                }
                i++
            }
            return null
        }
    }
}

/**
 * Stand-in when Stockfish isn't in the build (the emulator in tests): plays a capture if it
 * can, else any move. Only so the screens work without the engine; real phones use Stockfish.
 */
class SimpleEngine : ChessEngine {
    override val isReal = false

    private fun value(c: Char) = when (c.lowercaseChar()) {
        'q' -> 900; 'r' -> 500; 'b', 'n' -> 300; 'p' -> 100; else -> 0
    }

    override suspend fun analyze(fen: String, depth: Int, lines: Int, maxTimeMs: Int): List<EngineLine> {
        val p = Position.fromFen(fen) ?: return emptyList()
        return p.legalMoves()
            .map { m -> EngineLine(listOf(m.uci), Eval(cp = value(p[m.to])), 1) }
            .sortedByDescending { it.eval.cp }
            .take(lines)
    }

    override suspend fun chooseMove(fen: String, skill: Int, depth: Int?, thinkTimeMs: Int): String? {
        val p = Position.fromFen(fen) ?: return null
        val moves = p.legalMoves()
        return (moves.maxByOrNull { value(p[it.to]) }?.takeIf { value(p[it.to]) > 0 } ?: moves.randomOrNull())?.uci
    }
}

/** A move in engine notation as standard notation, when it is legal. */
fun Position.sanOf(uci: String): String? = Move.fromUci(uci)?.takeIf { isLegal(it) }?.let { san(it) }
