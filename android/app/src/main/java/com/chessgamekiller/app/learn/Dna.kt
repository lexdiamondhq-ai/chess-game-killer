package com.chessgamekiller.app.learn

import android.content.Context
import android.content.SharedPreferences
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import com.chessgamekiller.app.engine.ChessEngine
import com.chessgamekiller.app.engine.Engines
import com.chessgamekiller.app.engine.Eval
import com.chessgamekiller.chess.Move
import com.chessgamekiller.chess.Position
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.launch
import org.json.JSONArray
import org.json.JSONObject
import java.time.LocalDate
import kotlin.math.exp
import kotlin.math.roundToInt

/** A move Leo flagged in one of your games: the position, what you played and what was better. */
data class Slip(val fen: String, val played: String, val best: String, val kind: String, val loss: Int) {
    /** As a drill, so "Fix your mistakes" plays it on the same board. */
    fun asDrill(index: Int): Drill {
        val position = Position.fromFen(fen)
        val bestSan = position?.let { p -> Move.fromUci(best)?.let { p.san(p.normalize(it)) } } ?: best
        val playedSan = position?.let { p -> Move.fromUci(played)?.let { p.san(p.normalize(it)) } } ?: played
        val why = when (kind) {
            "hung" -> "In your game you played $playedSan and it gave a piece away. $bestSan keeps everything safe."
            "missedMate" -> "There was checkmate here. In your game you played $playedSan; $bestSan starts the mate."
            "allowedMate" -> "$playedSan let them start a checkmate. $bestSan stops it."
            "missedWin" -> "$bestSan wins material. In your game you played $playedSan."
            else -> "$bestSan was the move here. In your game you played $playedSan."
        }
        return Drill(
            id = "game-$index-${fen.hashCode()}", skill = "game", type = "move", rating = 1000, fen = fen, setup = null,
            solution = listOf(best), alts = emptyList(), mate = if (kind == "missedMate") 1 else null, squares = emptyList(),
            move = null, answer = null, reply = null, explain = why, options = emptyList(),
            prompt = "From your game: find a better move than $playedSan.", limit = null,
        )
    }
}

/** What Leo read in one game, move by move. */
data class GameGrade(
    val openingLoss: Int, val openingMoves: Int,
    val middleLoss: Int, val middleMoves: Int,
    val endLoss: Int, val endMoves: Int,
    val hung: Int, val missedMates: Int, val allowedMates: Int, val missedWins: Int,
    val checksAndCaptures: Int, val moves: Int,
    val slips: List<Slip>,
)

/** A finished game against a rival, kept for Chess DNA. */
data class GameRecord(
    val id: Long,
    val rival: String,
    val white: Boolean,
    val moves: List<String>,
    val score: Double,
    val day: Long,
    val grade: GameGrade?,
)

/** The five things Chess DNA measures, and the drills that practice each. */
enum class DnaArea(val title: String, val skills: List<String>) {
    OPENINGS("Openings", listOf("opening")),
    SAFETY("Keeping pieces safe", listOf("safety", "threats", "counting")),
    TACTICS("Tactics", listOf("forks", "pins", "skewers", "discovered", "free-pieces")),
    CHECKMATES("Checkmates", listOf("mate-in-1", "mate-in-2", "back-rank")),
    ENDGAMES("Endgames", listOf("queen-mate", "ladder-mate", "rook-mate")),
}

/** One area's reading: a 0-100 score, a word for it, and the proof in plain words. */
data class AreaReading(val area: DnaArea, val score: Int?, val proof: String) {
    val title get() = area.title
    val skills get() = area.skills
    val why: String get() = proof
    val word: String get() = when {
        score == null -> "Not enough yet"
        score >= 80 -> "Strong"
        score >= 62 -> "Steady"
        score >= 45 -> "Shaky"
        else -> "Weak spot"
    }
}

/**
 * Chess DNA on Android: after each game against a rival, Stockfish reads every one of your moves
 * on the phone (two short looks per move, while you're elsewhere), and five areas get a score.
 * It names your style after three graded games. Unlike the iPhone it isn't compared with other
 * players yet; it says what your own games show.
 */
object Dna {
    private var prefs: SharedPreferences? = null
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Default)
    private var job: Job? = null

    var games by mutableStateOf<List<GameRecord>>(emptyList()); private set
    /** A game is being read right now. */
    var grading by mutableStateOf(false); private set

    val graded: List<GameRecord> get() = games.filter { it.grade != null }
    const val gamesToName = 3

    fun load(context: Context) {
        if (prefs != null) return
        val p = context.getSharedPreferences("dna", Context.MODE_PRIVATE)
        prefs = p
        games = runCatching { readGames(JSONArray(p.getString("games", "[]") ?: "[]")) }.getOrDefault(emptyList())
    }

    fun resetForTests() { prefs = null; games = emptyList() }

    /** A finished game: kept, then graded in the background. Games under five moves aren't worth reading. */
    fun recordGame(context: Context, rival: String, white: Boolean, moves: List<String>, score: Double) {
        if (moves.size < 10) return
        val record = GameRecord(System.currentTimeMillis(), rival, white, moves, score, LocalDate.now().toEpochDay(), null)
        games = (games + record).takeLast(30)
        save()
        gradePending(context)
    }

    /** Reads every game not read yet, one at a time. Needs the real Stockfish. */
    fun gradePending(context: Context) {
        if (job?.isActive == true) return
        val engine = Engines.get(context.applicationContext)
        if (!engine.isReal) return
        job = scope.launch {
            while (true) {
                val next = games.firstOrNull { it.grade == null } ?: break
                grading = true
                val grade = runCatching { grade(engine, next) }.getOrNull()
                    ?: GameGrade(0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, emptyList())
                games = games.map { if (it.id == next.id) it.copy(grade = grade) else it }
                save()
            }
            grading = false
        }
    }

    private fun cp(e: Eval): Int = when {
        e.mate != null -> if (e.mate > 0) 1000 else -1000
        else -> (e.cp ?: 0).coerceIn(-1000, 1000)
    }

    private fun material(p: Position, white: Boolean): Int {
        var sum = 0
        for (sq in 0 until 64) {
            val c = p[sq]
            if (c == '.' || c.isUpperCase() != white) continue
            sum += when (c.lowercaseChar()) { 'q' -> 9; 'r' -> 5; 'b', 'n' -> 3; else -> 0 }
        }
        return sum
    }

    suspend fun grade(engine: ChessEngine, game: GameRecord): GameGrade {
        var p = Position.start()
        var oL = 0; var oN = 0; var mL = 0; var mN = 0; var eL = 0; var eN = 0
        var hung = 0; var missedMates = 0; var allowedMates = 0; var missedWins = 0; var sharp = 0; var mine = 0
        val slips = mutableListOf<Slip>()
        for ((ply, uci) in game.moves.withIndex()) {
            val move = Move.fromUci(uci)?.let { p.normalize(it) } ?: break
            if (!p.isLegal(move)) break
            val after = p.play(move)
            if (p.whiteToMove == game.white && p.legalMoves().size > 1) {
                mine++
                if (p[move.to] != '.' || after.inCheck) sharp++
                val before = engine.analyze(p.fen, 10, 1, 160).firstOrNull()
                val reply = if (after.legalMoves().isEmpty()) null else engine.analyze(after.fen, 10, 1, 160).firstOrNull()
                if (before != null) {
                    val best = before.moves.firstOrNull()
                    val bestCp = cp(before.eval)
                    val playedEval = when {
                        after.legalMoves().isEmpty() -> if (after.inCheck) Eval(mate = 1) else Eval(cp = 0)
                        reply != null -> reply.eval.flipped()
                        else -> before.eval
                    }
                    val playedCp = cp(playedEval)
                    val loss = (bestCp - playedCp).coerceIn(0, 1000)
                    val endgame = material(p, true) <= 13 && material(p, false) <= 13
                    when {
                        p.fullmoveNumber <= 10 -> { oL += loss.coerceAtMost(400); oN++ }
                        endgame -> { eL += loss.coerceAtMost(400); eN++ }
                        else -> { mL += loss.coerceAtMost(400); mN++ }
                    }
                    val replyMove = reply?.moves?.firstOrNull()?.let { Move.fromUci(it) }
                    val bestMove = best?.let { Move.fromUci(it) }?.let { p.normalize(it) }
                    val bestSharp = bestMove != null && (p[bestMove.to] != '.' || p.play(bestMove).inCheck)
                    val kind = when {
                        (before.eval.mate ?: 0) > 0 && (playedEval.mate ?: 0) <= 0 -> { missedMates++; "missedMate" }
                        (playedEval.mate ?: 0) < 0 && (before.eval.mate ?: 0) >= 0 -> { allowedMates++; "allowedMate" }
                        loss >= 200 && replyMove != null && after[replyMove.to] != '.' -> { hung++; "hung" }
                        loss >= 150 && bestCp >= 150 && bestSharp -> { missedWins++; "missedWin" }
                        loss >= 150 -> "mistake"
                        else -> null
                    }
                    if (kind != null && best != null && best != uci) slips += Slip(p.fen, uci, best, kind, loss)
                }
            }
            p = after
            if (ply > 160) break
        }
        return GameGrade(oL, oN, mL, mN, eL, eN, hung, missedMates, allowedMates, missedWins, sharp, mine, slips.takeLast(6))
    }

    private fun lossScore(total: Int, n: Int): Int = (100 * exp(-(total.toDouble() / n) / 90.0)).roundToInt().coerceIn(5, 100)
    private fun rateScore(count: Int, games: Int, weight: Double): Int = (100 - weight * count / games).roundToInt().coerceIn(5, 100)

    private fun plural(n: Int, one: String, many: String) = if (n == 1) "1 $one" else "$n $many"

    /** The five readings, from every graded game. */
    fun readings(): List<AreaReading> {
        val g = graded.mapNotNull { it.grade }
        val n = g.size
        if (n == 0) return DnaArea.entries.map { AreaReading(it, null, "Play a rival and Leo reads every move.") }
        val oN = g.sumOf { it.openingMoves }; val oL = g.sumOf { it.openingLoss }
        val eN = g.sumOf { it.endMoves }; val eL = g.sumOf { it.endLoss }
        val hung = g.sumOf { it.hung }
        val wins = g.sumOf { it.missedWins }
        val mates = g.sumOf { it.missedMates + it.allowedMates }
        val games = plural(n, "game", "games")
        return listOf(
            AreaReading(DnaArea.OPENINGS, if (oN >= 5) lossScore(oL, oN) else null,
                if (oN >= 5) "${(oL.toDouble() / oN / 100).let { String.format(java.util.Locale.US, "%.1f", it) }} pawns lost a move in your first ten moves." else "A few more openings to read."),
            AreaReading(DnaArea.SAFETY, rateScore(hung, n, 28.0),
                if (hung == 0) "No piece left hanging in $games." else "${plural(hung, "piece", "pieces")} left hanging in $games."),
            AreaReading(DnaArea.TACTICS, rateScore(wins, n, 22.0),
                if (wins == 0) "No winning shot missed in $games." else "${plural(wins, "winning shot", "winning shots")} missed in $games."),
            AreaReading(DnaArea.CHECKMATES, rateScore(mates, n, 35.0),
                if (mates == 0) "No mate missed or let through in $games." else "${plural(mates, "mate", "mates")} missed or let through in $games."),
            AreaReading(DnaArea.ENDGAMES, if (eN >= 6) lossScore(eL, eN) else null,
                if (eN >= 6) "${(eL.toDouble() / eN / 100).let { String.format(java.util.Locale.US, "%.1f", it) }} pawns lost a move once the queens and most pieces are gone." else "Not enough endgames yet."),
        )
    }

    /** Your style once three games are read: named after what stands out, or All-rounder. */
    fun style(): Pair<String, String>? {
        if (graded.size < gamesToName) return null
        val scored = readings().filter { it.score != null }
        val best = scored.maxByOrNull { it.score!! } ?: return null
        val worst = scored.minByOrNull { it.score!! } ?: return null
        val g = graded.mapNotNull { it.grade }
        val sharp = g.sumOf { it.checksAndCaptures }.toDouble() / g.sumOf { it.moves }.coerceAtLeast(1)
        if (best.score!! - worst.score!! < 12) return "All-rounder" to "No one style fits you: you play the position in front of you."
        return when (best.area) {
            DnaArea.TACTICS -> "Tactician" to "You see the shots: forks, pins and pieces left loose."
            DnaArea.SAFETY -> if (sharp > 0.3) "Bold and careful" to "You attack, and you rarely leave a piece hanging." else "Guardian" to "You keep your pieces safe. Rivals have to earn every point."
            DnaArea.CHECKMATES -> "Finisher" to "When there's a mate, you find it."
            DnaArea.OPENINGS -> "Book player" to "You start well: your first ten moves hold up."
            DnaArea.ENDGAMES -> "Grinder" to "You play the ending well and squeeze out results."
        }
    }

    /** Strongest areas first, with a score. */
    fun goodAt(): List<AreaReading> = readings().filter { (it.score ?: 0) >= 62 }.sortedByDescending { it.score }.take(2)

    /** Weakest areas first: what Today's plan works on once the lessons are done. */
    fun workOn(): List<AreaReading> {
        if (graded.isEmpty()) return emptyList()
        return readings().filter { it.score != null && it.score < 80 }.sortedBy { it.score }.take(2)
    }

    /** Positions from your own games for an area, newest first. */
    fun slips(area: DnaArea?): List<Slip> {
        val kinds = when (area) {
            DnaArea.SAFETY -> setOf("hung")
            DnaArea.TACTICS -> setOf("missedWin")
            DnaArea.CHECKMATES -> setOf("missedMate", "allowedMate")
            null -> null
            else -> setOf("mistake")
        }
        return graded.reversed().flatMap { it.grade!!.slips }.filter { kinds == null || it.kind in kinds }
    }

    // MARK: Storing

    private fun save() {
        val p = prefs ?: return
        val a = JSONArray()
        for (g in games) {
            val o = JSONObject().put("id", g.id).put("rival", g.rival).put("white", g.white)
                .put("moves", JSONArray(g.moves)).put("score", g.score).put("day", g.day)
            g.grade?.let { r ->
                o.put("grade", JSONObject()
                    .put("o", JSONArray(listOf(r.openingLoss, r.openingMoves, r.middleLoss, r.middleMoves, r.endLoss, r.endMoves)))
                    .put("c", JSONArray(listOf(r.hung, r.missedMates, r.allowedMates, r.missedWins, r.checksAndCaptures, r.moves)))
                    .put("s", JSONArray().apply {
                        r.slips.forEach { s -> put(JSONArray(listOf(s.fen, s.played, s.best, s.kind, s.loss))) }
                    }))
            }
            a.put(o)
        }
        p.edit().putString("games", a.toString()).apply()
    }

    private fun readGames(a: JSONArray): List<GameRecord> = (0 until a.length()).map { i ->
        val o = a.getJSONObject(i)
        val moves = o.getJSONArray("moves")
        val grade = o.optJSONObject("grade")?.let { r ->
            val x = r.getJSONArray("o"); val c = r.getJSONArray("c"); val s = r.getJSONArray("s")
            GameGrade(
                x.getInt(0), x.getInt(1), x.getInt(2), x.getInt(3), x.getInt(4), x.getInt(5),
                c.getInt(0), c.getInt(1), c.getInt(2), c.getInt(3), c.getInt(4), c.getInt(5),
                (0 until s.length()).map { j -> s.getJSONArray(j).let { Slip(it.getString(0), it.getString(1), it.getString(2), it.getString(3), it.getInt(4)) } },
            )
        }
        GameRecord(o.getLong("id"), o.getString("rival"), o.getBoolean("white"),
            (0 until moves.length()).map { moves.getString(it) }, o.optDouble("score"), o.optLong("day"), grade)
    }

}
