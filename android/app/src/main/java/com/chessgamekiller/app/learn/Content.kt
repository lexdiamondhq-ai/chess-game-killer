package com.chessgamekiller.app.learn

import org.json.JSONArray
import org.json.JSONObject

// The iPhone's training, read from the same files (assets/training, copied from
// ChessGameKiller/Training/Content): the course, fifteen narrated lessons and 1,446 drills.
// Everything here is plain data, so the unit tests read the real files.

data class Skill(
    val id: String,
    val title: String,
    val blurb: String,
    val lesson: String,
    /** What a drill of this skill asks, like "Find the fork." */
    val prompt: String,
    val yes: String?,
    val no: String?,
)

data class CourseUnit(val id: String, val title: String, val subtitle: String, val lessons: List<String>, val skills: List<String>)

/** Pawn, Knight, Bishop, Rook, Queen, King: a learner is promoted by XP. */
data class RankDef(val id: String, val title: String, val piece: String, val xp: Int)

data class CoachLines(
    val greeting: List<String>,
    val correct: List<String>,
    val correctAfterHint: List<String>,
    val keepGoing: List<String>,
    val wrong: List<String>,
    val sessionDone: List<String>,
    val lessonDone: List<String>,
    val promotion: List<String>,
)

data class Course(val units: List<CourseUnit>, val skills: List<Skill>, val ranks: List<RankDef>, val lines: CoachLines)

/** Named colors from the lessons: red, yellow, green, blue... */
data class Arrow(val from: String, val to: String, val color: String?)
data class Mark(val square: String, val color: String?)
data class SquareLabel(val square: String, val text: String)

data class Choice(val text: String, val move: String?, val correct: Boolean, val why: String?)

/** A lesson's turn for the learner: play a move, tap squares, or pick an answer. */
data class LessonTask(
    val type: String,
    val prompt: String,
    /** The learner's moves and the replies, alternating, learner first. */
    val solution: List<String>,
    /** Other moves that also solve it, one list per learner move. */
    val accept: List<List<String>>,
    /** Any checkmate solves the last step. */
    val mate: Boolean,
    val squares: List<String>,
    val options: List<Choice>,
    val hint: String?,
    val success: String,
    val wrong: String?,
    val feedback: Map<String, String>,
)

data class LessonStep(
    /** A new position; steps without one carry on from the last. */
    val fen: String?,
    val say: String?,
    /** Moves to animate, in engine notation. */
    val moves: List<String>,
    val arrows: List<Arrow>,
    val marks: List<Mark>,
    val labels: List<SquareLabel>,
    val task: LessonTask?,
)

data class Lesson(val id: String, val title: String, val subtitle: String, val skill: String, val blackBottom: Boolean, val steps: List<LessonStep>)

/** One practice item. Most come from real games and were checked with Stockfish. */
data class Drill(
    val id: String,
    val skill: String,
    /** move, tap, safe, choice or playout. */
    val type: String,
    /** About 400 is easy, 1600 is hard. */
    val rating: Int,
    val fen: String,
    /** The opponent's move that sets it up, shown first. */
    val setup: String?,
    val solution: List<String>,
    val alts: List<List<String>>,
    val mate: Int?,
    val squares: List<String>,
    val move: String?,
    val answer: Boolean?,
    /** The reply that shows why a move was unsafe. */
    val reply: String?,
    val explain: String?,
    val options: List<Choice>,
    val prompt: String?,
    /** For playout: moves allowed to finish. */
    val limit: Int?,
)

/** Today's Move: one puzzle a day, the same for everyone, as on the iPhone (daily-moves.csv). */
data class DailyPuzzle(
    val number: Int,
    val id: String,
    /** The position before the opponent's move. */
    val fen: String,
    /** The opponent's move first, then the answer and replies. */
    val moves: List<String>,
    val rating: Int,
    val themes: List<String>,
    val shownFen: String,
) {
    val solverIsWhite: Boolean get() = shownFen.split(' ').getOrNull(1) != "b"

    val mateIn: Int? get() = (1..5).firstOrNull { "mateIn$it" in themes }

    /** "White to play and mate in two." */
    val headline: String get() {
        val side = if (solverIsWhite) "White" else "Black"
        val mate = mateIn ?: return "$side to play and win."
        val words = listOf("zero", "one", "two", "three", "four", "five")
        return if (mate == 1) "$side to play and mate." else "$side to play and mate in ${words[mate]}."
    }

    val difficulty: String get() = when {
        rating < 1400 -> "Easy"
        rating < 1600 -> "Medium"
        rating < 1800 -> "Tricky"
        rating < 2000 -> "Hard"
        else -> "Hardest"
    }

    /** As a drill, so the same board plays it. */
    fun asDrill(): Drill = Drill(
        id = "daily-$number", skill = "daily", type = "move", rating = rating, fen = fen,
        setup = moves.first(), solution = moves.drop(1), alts = emptyList(), mate = mateIn, squares = emptyList(),
        move = null, answer = null, reply = null, explain = null, options = emptyList(), prompt = headline, limit = null,
    )
}

object ContentParser {
    private fun JSONArray?.strings(): List<String> =
        if (this == null) emptyList() else (0 until length()).map { getString(it) }

    private fun JSONObject.str(key: String): String? = if (has(key) && !isNull(key)) getString(key) else null

    private fun choices(a: JSONArray?): List<Choice> = if (a == null) emptyList() else (0 until a.length()).map {
        val o = a.getJSONObject(it)
        Choice(o.getString("text"), o.str("move"), o.optBoolean("correct"), o.str("why"))
    }

    private fun lists(a: JSONArray?): List<List<String>> =
        if (a == null) emptyList() else (0 until a.length()).map { a.optJSONArray(it).strings() }

    fun course(text: String): Course {
        val o = JSONObject(text)
        val units = o.getJSONArray("units").let { a ->
            (0 until a.length()).map {
                val u = a.getJSONObject(it)
                CourseUnit(u.getString("id"), u.getString("title"), u.getString("subtitle"),
                    u.getJSONArray("lessons").strings(), u.optJSONArray("skills").strings())
            }
        }
        val skills = o.getJSONArray("skills").let { a ->
            (0 until a.length()).map {
                val s = a.getJSONObject(it)
                Skill(s.getString("id"), s.getString("title"), s.getString("blurb"), s.getString("lesson"),
                    s.getString("prompt"), s.str("yes"), s.str("no"))
            }
        }
        val ranks = o.getJSONArray("ranks").let { a ->
            (0 until a.length()).map {
                val r = a.getJSONObject(it)
                RankDef(r.getString("id"), r.getString("title"), r.getString("piece"), r.getInt("xp"))
            }
        }
        val l = o.getJSONObject("lines")
        val lines = CoachLines(
            l.getJSONArray("greeting").strings(), l.getJSONArray("correct").strings(),
            l.getJSONArray("correctAfterHint").strings(), l.getJSONArray("keepGoing").strings(),
            l.getJSONArray("wrong").strings(), l.getJSONArray("sessionDone").strings(),
            l.getJSONArray("lessonDone").strings(), l.getJSONArray("promotion").strings(),
        )
        return Course(units, skills, ranks, lines)
    }

    fun lesson(text: String): Lesson {
        val o = JSONObject(text)
        val steps = o.getJSONArray("steps").let { a ->
            (0 until a.length()).map { i ->
                val s = a.getJSONObject(i)
                val task = s.optJSONObject("task")?.let { t ->
                    val fb = t.optJSONObject("feedback")
                    LessonTask(
                        type = t.getString("type"), prompt = t.getString("prompt"),
                        solution = t.optJSONArray("solution").strings(), accept = lists(t.optJSONArray("accept")),
                        mate = t.optBoolean("mate"), squares = t.optJSONArray("squares").strings(),
                        options = choices(t.optJSONArray("options")), hint = t.str("hint"),
                        success = t.getString("success"), wrong = t.str("wrong"),
                        feedback = fb?.keys()?.asSequence()?.associateWith { fb.getString(it) } ?: emptyMap(),
                    )
                }
                LessonStep(
                    fen = s.str("fen"), say = s.str("say"), moves = s.optJSONArray("moves").strings(),
                    arrows = s.optJSONArray("arrows")?.let { arr ->
                        (0 until arr.length()).map { arr.getJSONObject(it).let { x -> Arrow(x.getString("from"), x.getString("to"), x.str("color")) } }
                    } ?: emptyList(),
                    marks = s.optJSONArray("marks")?.let { arr ->
                        (0 until arr.length()).map { arr.getJSONObject(it).let { x -> Mark(x.getString("square"), x.str("color")) } }
                    } ?: emptyList(),
                    labels = s.optJSONArray("labels")?.let { arr ->
                        (0 until arr.length()).map { arr.getJSONObject(it).let { x -> SquareLabel(x.getString("square"), x.getString("text")) } }
                    } ?: emptyList(),
                    task = task,
                )
            }
        }
        return Lesson(o.getString("id"), o.getString("title"), o.optString("subtitle"), o.optString("skill"),
            o.optString("orientation") == "black", steps)
    }

    fun drills(text: String): List<Drill> {
        val a = JSONObject(text).getJSONArray("drills")
        return (0 until a.length()).map { i ->
            val d = a.getJSONObject(i)
            Drill(
                id = d.getString("id"), skill = d.getString("skill"), type = d.getString("type"),
                rating = d.optInt("rating", 800), fen = d.getString("fen"), setup = d.str("setup"),
                solution = d.optJSONArray("solution").strings(), alts = lists(d.optJSONArray("alts")),
                mate = if (d.has("mate")) d.getInt("mate") else null, squares = d.optJSONArray("squares").strings(),
                move = d.str("move"), answer = if (d.has("answer")) d.getBoolean("answer") else null,
                reply = d.str("reply"), explain = d.str("explain"), options = choices(d.optJSONArray("options")),
                prompt = d.str("prompt"), limit = if (d.has("limit")) d.getInt("limit") else null,
            )
        }
    }

    /** day,id,fen,moves,rating,themes,shown. A line that can't be read is skipped. */
    fun daily(text: String): List<DailyPuzzle> = text.lineSequence().drop(1).mapNotNull { line ->
        val f = line.split(',')
        if (f.size < 7) return@mapNotNull null
        val number = f[0].toIntOrNull() ?: return@mapNotNull null
        val rating = f[4].toIntOrNull() ?: return@mapNotNull null
        val moves = f[3].split(' ').filter { it.isNotBlank() }
        if (moves.size < 2 || moves.size % 2 != 0) return@mapNotNull null
        DailyPuzzle(number, f[1], f[2], moves, rating, f[5].split(' ').filter { it.isNotBlank() }, f[6].trim())
    }.toList()
}
