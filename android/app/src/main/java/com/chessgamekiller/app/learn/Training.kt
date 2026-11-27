package com.chessgamekiller.app.learn

import android.content.Context
import android.content.SharedPreferences
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableDoubleStateOf
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import com.chessgamekiller.app.Progress
import org.json.JSONArray
import org.json.JSONObject
import java.time.LocalDate
import kotlin.math.abs
import kotlin.math.pow
import kotlin.math.roundToInt

/** How a drill went. Effort always earns something. */
enum class Outcome(val score: Double, val xp: Int) {
    FIRST_TRY(1.0, 10), WITH_HINT(0.6, 6), AFTER_MISTAKE(0.35, 5), MISSED(0.0, 2);

    val solved: Boolean get() = this != MISSED
}

/** Everything the training ships with, read once. */
class Library(
    val course: Course,
    /** In course order. */
    val lessons: List<Lesson>,
    val drills: List<Drill>,
    val daily: List<DailyPuzzle>,
) {
    fun lesson(id: String) = lessons.firstOrNull { it.id == id }
    fun skill(id: String) = course.skills.firstOrNull { it.id == id }

    /** The skills a lesson's practice works on: its unit's skills that it teaches, else its own. */
    fun skillsFor(lesson: Lesson): List<String> {
        val bySkill = course.skills.filter { it.lesson == lesson.id }.map { it.id }
        return bySkill.ifEmpty { listOf(lesson.skill).filter { s -> course.skills.any { it.id == s } } }
    }

    /** The rank for some XP, and the one after it. */
    fun rank(xp: Int): RankDef = course.ranks.lastOrNull { xp >= it.xp } ?: course.ranks.first()
    fun nextRank(xp: Int): RankDef? = course.ranks.firstOrNull { it.xp > xp }

    /** Today's Move: the same puzzle for everyone on a date, counted from October 1, 2026. */
    fun dailyPuzzle(day: Long = LocalDate.now().toEpochDay()): DailyPuzzle? {
        if (daily.isEmpty()) return null
        val number = (day - LocalDate.of(2026, 10, 1).toEpochDay() + 1).coerceAtLeast(1)
        return daily[((number - 1) % daily.size).toInt()]
    }

    companion object {
        @Volatile private var shared: Library? = null

        fun get(context: Context): Library = shared ?: synchronized(this) {
            shared ?: load { name -> context.assets.open(name).bufferedReader().use { it.readText() } }.also { shared = it }
        }

        /** Reads the files by name, so the tests can read them from the source folder. */
        fun load(read: (String) -> String): Library {
            val course = ContentParser.course(read("training/course.json"))
            val ids = course.units.flatMap { it.lessons }.distinct()
            val lessons = ids.mapNotNull { id -> runCatching { ContentParser.lesson(read("training/lesson-$id.json")) }.getOrNull() }
            val drills = ContentParser.drills(read("training/drills.json"))
            val daily = runCatching { ContentParser.daily(read("daily-moves.csv")) }.getOrDefault(emptyList())
            return Library(course, lessons, drills, daily)
        }
    }
}

/** One day on the vine: the XP earned and what was done. */
data class DayNote(val xp: Int, val highlights: List<String>)

/** A skill's record: drills seen and solved first try. */
data class SkillStat(val seen: Int, val clean: Int) {
    val accuracy: Double get() = if (seen == 0) 0.0 else clean.toDouble() / seen
}

/**
 * What Learn remembers on this phone: XP and rank, the puzzle rating, lessons watched, a diary of
 * days for the vine, each skill's record, and Today's Move results. Like the iPhone's TrainingProgress.
 */
object Training {
    private var prefs: SharedPreferences? = null

    var xp by mutableIntStateOf(0); private set
    var rating by mutableDoubleStateOf(600.0); private set
    var attempts by mutableIntStateOf(0); private set
    /** Lesson id to the day it was finished. */
    var lessonsDone by mutableStateOf<Map<String, Long>>(emptyMap()); private set
    var days by mutableStateOf<Map<Long, DayNote>>(emptyMap()); private set
    var skills by mutableStateOf<Map<String, SkillStat>>(emptyMap()); private set
    /** Day to Today's Move outcome. */
    var daily by mutableStateOf<Map<Long, Outcome>>(emptyMap()); private set
    /** Drills seen lately, so a session brings new ones. */
    private var recent: List<String> = emptyList()

    val today: Long get() = LocalDate.now().toEpochDay()
    val puzzleRating: Int get() = rating.roundToInt()
    val trainedToday: Boolean get() = (days[today]?.xp ?: 0) > 0
    val playedDailyToday: Boolean get() = daily.containsKey(today)

    fun load(context: Context) {
        if (prefs != null) return
        val p = context.getSharedPreferences("training", Context.MODE_PRIVATE)
        prefs = p
        runCatching { read(JSONObject(p.getString("state", "{}") ?: "{}")) }
    }

    /** For the tests: start clean, without a phone. */
    fun resetForTests() {
        prefs = null
        xp = 0; rating = 600.0; attempts = 0; lessonsDone = emptyMap(); days = emptyMap(); skills = emptyMap()
        daily = emptyMap(); recent = emptyList()
    }

    private fun read(o: JSONObject) {
        xp = o.optInt("xp")
        rating = o.optDouble("rating", 600.0)
        attempts = o.optInt("attempts")
        lessonsDone = o.optJSONObject("lessons")?.let { l -> l.keys().asSequence().associateWith { l.getLong(it) } } ?: emptyMap()
        days = o.optJSONObject("days")?.let { d ->
            d.keys().asSequence().associate { key ->
                val n = d.getJSONObject(key)
                val h = n.optJSONArray("h") ?: JSONArray()
                key.toLong() to DayNote(n.optInt("xp"), (0 until h.length()).map { h.getString(it) })
            }
        } ?: emptyMap()
        skills = o.optJSONObject("skills")?.let { s ->
            s.keys().asSequence().associate { key -> val a = s.getJSONArray(key); key to SkillStat(a.getInt(0), a.getInt(1)) }
        } ?: emptyMap()
        daily = o.optJSONObject("daily")?.let { d ->
            d.keys().asSequence().mapNotNull { key -> runCatching { key.toLong() to Outcome.valueOf(d.getString(key)) }.getOrNull() }.toMap()
        } ?: emptyMap()
        recent = o.optJSONArray("recent")?.let { a -> (0 until a.length()).map { a.getString(it) } } ?: emptyList()
    }

    private fun save() {
        val p = prefs ?: return
        val o = JSONObject()
        o.put("xp", xp); o.put("rating", rating); o.put("attempts", attempts)
        o.put("lessons", JSONObject().apply { lessonsDone.forEach { (k, v) -> put(k, v) } })
        o.put("days", JSONObject().apply {
            days.forEach { (k, v) -> put(k.toString(), JSONObject().put("xp", v.xp).put("h", JSONArray(v.highlights))) }
        })
        o.put("skills", JSONObject().apply { skills.forEach { (k, v) -> put(k, JSONArray(listOf(v.seen, v.clean))) } })
        o.put("daily", JSONObject().apply { daily.forEach { (k, v) -> put(k.toString(), v.name) } })
        o.put("recent", JSONArray(recent.takeLast(400)))
        p.edit().putString("state", o.toString()).apply()
    }

    private fun note(xpEarned: Int, highlight: String? = null) {
        val old = days[today] ?: DayNote(0, emptyList())
        val list = if (highlight != null && highlight !in old.highlights) old.highlights + highlight else old.highlights
        days = days + (today to DayNote(old.xp + xpEarned, list))
        xp += xpEarned
        Progress.markActiveDay()
    }

    /** Chance of solving a drill of [difficulty] at [rating] (Elo). */
    fun expected(rating: Double, difficulty: Double) = 1.0 / (1.0 + 10.0.pow((difficulty - rating) / 400.0))

    /** Fast at first, then settles, so a few drills find the right level. */
    private fun kFactor(n: Int) = when { n < 8 -> 56.0; n < 25 -> 36.0; else -> 22.0 }

    fun recordDrill(drill: Drill, outcome: Outcome) {
        if (drill.skill != "daily" && drill.skill != "game") {
            rating = (rating + kFactor(attempts) * (outcome.score - expected(rating, drill.rating.toDouble())))
                .coerceIn(200.0, 2400.0)
            attempts += 1
            val s = skills[drill.skill] ?: SkillStat(0, 0)
            skills = skills + (drill.skill to SkillStat(s.seen + 1, s.clean + if (outcome == Outcome.FIRST_TRY) 1 else 0))
            recent = (recent - drill.id) + drill.id
        }
        note(outcome.xp)
        save()
    }

    fun finishLesson(lesson: Lesson) {
        val first = lesson.id !in lessonsDone
        lessonsDone = lessonsDone + (lesson.id to (lessonsDone[lesson.id] ?: today))
        note(if (first) 40 else 10, lesson.title)
        save()
    }

    fun finishSession(title: String) {
        note(30, title)
        save()
    }

    fun recordDaily(outcome: Outcome) {
        if (playedDailyToday) return
        daily = daily + (today to outcome)
        note(outcome.xp + 10, "Today's Move")
        save()
    }

    fun recentlySeen(id: String) = id in recent

    /** Erase training progress (You > Start training over). */
    fun reset() {
        xp = 0; rating = 600.0; attempts = 0; lessonsDone = emptyMap(); days = emptyMap(); skills = emptyMap()
        daily = emptyMap(); recent = emptyList()
        save()
    }
}

/** A short session: maybe a lesson, then drills. What Today's card shows is exactly what Start plays. */
data class Plan(
    val title: String,
    val reason: String,
    val lesson: Lesson?,
    val drills: List<Drill>,
) {
    val minutes: Int get() = ((if (lesson != null) 3.0 else 0.0) + drills.size * 0.6).roundToInt().coerceAtLeast(2)
}

object Planner {
    /** Drills of some skills near the player's level, new ones first, in a fixed order for the day. */
    fun pick(library: Library, skills: Collection<String>, count: Int, seed: Long = Training.today, maxPlayouts: Int = 1): List<Drill> {
        val pool = library.drills.filter { it.skill in skills }
        if (pool.isEmpty()) return emptyList()
        val level = Training.rating
        val random = java.util.Random(seed * 31 + skills.hashCode())
        // The nearest to the player's level, a little spread, unseen ones ahead of seen ones.
        val ranked = pool.sortedBy { d ->
            val distance = abs(d.rating - level) + random.nextInt(140)
            distance + if (Training.recentlySeen(d.id)) 2_000 else 0
        }
        val out = mutableListOf<Drill>()
        var playouts = 0
        for (d in ranked) {
            if (d.type == "playout") { if (playouts >= maxPlayouts) continue; playouts++ }
            out += d
            if (out.size >= count) break
        }
        return out.sortedBy { it.rating }
    }

    /** The next lesson not yet watched, in course order. */
    fun nextLesson(library: Library): Lesson? = library.lessons.firstOrNull { it.id !in Training.lessonsDone }

    /** Today: the course while there's course left, then the weakest skill from games and drills. */
    fun today(library: Library): Plan {
        nextLesson(library)?.let { lesson ->
            val skills = library.skillsFor(lesson)
            val first = lesson.id == library.lessons.firstOrNull()?.id
            return Plan(
                title = if (first) "Welcome to training" else lesson.title,
                reason = if (first) "Meet Coach Leo and the one habit that wins more games than any opening."
                else "New lesson: ${lesson.title}, then practice at your level.",
                lesson = lesson,
                drills = pick(library, skills, 5),
            )
        }
        // Past the course: what the games say first, then the shakiest skill, then a rotation.
        Dna.workOn().firstOrNull()?.let { area ->
            return Plan(area.title, "Your games say: ${area.why.replaceFirstChar { it.lowercase() }} Today's puzzles work on it.", null,
                pick(library, area.skills, 8))
        }
        val shaky = Training.skills.filter { it.value.seen >= 3 }.minByOrNull { it.value.accuracy }?.key
        val skill = library.skill(shaky ?: "") ?: library.course.skills[(Training.today % library.course.skills.size).toInt()]
        return Plan(skill.title, skill.blurb, null, pick(library, listOf(skill.id), 8))
    }

    fun practice(library: Library, skills: List<String>, title: String, own: List<Drill> = emptyList()): Plan =
        Plan(title, "Practice", null, own.take(5) + pick(library, skills, 8 - own.take(5).size, seed = System.currentTimeMillis()))

    /** Rated puzzles across every skill, at the player's level. */
    fun mixed(library: Library): Plan =
        Plan("Puzzles", "At your level", null, pick(library, library.course.skills.map { it.id }, 10, seed = System.currentTimeMillis(), maxPlayouts = 0))
}
