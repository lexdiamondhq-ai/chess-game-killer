package com.chessgamekiller.app.learn

import java.time.LocalDate
import java.time.format.TextStyle
import java.util.Locale

/**
 * The story Learn's gilded vine tells, as on the iPhone: a leaf for each day of training (newest
 * on top), the step in bloom that comes next, and the buds after it.
 */
data class Vine(val leaves: List<Leaf>, val bloom: Bud?, val buds: List<Bud>, val earlierDays: Int) {
    data class Leaf(val day: Long, val title: String, val detail: String)
    data class Bud(val title: String, val detail: String)

    val daysThisWeek: Int get() = leaves.count { it.day > Training.today - 7 }

    companion object {
        const val SHOWN = 12

        fun make(library: Library, today: Plan?): Vine {
            val all = Training.days.entries.filter { it.value.xp > 0 || it.value.highlights.isNotEmpty() }
                .sortedByDescending { it.key }
                .map { (day, note) ->
                    val title = note.highlights.firstOrNull() ?: "Puzzles and practice"
                    val detail = when {
                        note.highlights.size > 1 -> "and ${note.highlights.size - 1} more"
                        note.xp > 0 -> "+${note.xp} XP"
                        else -> ""
                    }
                    Leaf(day, title, detail)
                }
            var bloom: Bud? = null
            if (!Training.trainedToday && today != null && (today.lesson != null || today.drills.isNotEmpty())) {
                bloom = Bud(today.title, "Today · ${today.minutes} min")
            }
            val next = Planner.nextLesson(library)
            if (bloom == null && next != null) bloom = Bud(next.title, "Next lesson")
            val buds = mutableListOf<Bud>()
            if (next != null && bloom?.title != next.title) buds += Bud(next.title, "Next lesson")
            library.nextRank(Training.xp)?.let { buds += Bud("${it.title} rank", "${(it.xp - Training.xp).coerceAtLeast(0)} XP to go") }
            if (bloom == null) bloom = buds.removeFirstOrNull()
            val shown = all.take(SHOWN)
            return Vine(shown, bloom, buds, all.size - shown.size)
        }

        /** "Today", "Yesterday", "Wed" within the week, then "Nov 2". */
        fun dayLabel(day: Long): String {
            val diff = Training.today - day
            val date = LocalDate.ofEpochDay(day)
            return when {
                diff == 0L -> "Today"
                diff == 1L -> "Yesterday"
                diff < 7 -> date.dayOfWeek.getDisplayName(TextStyle.SHORT, Locale.getDefault())
                else -> "${date.month.getDisplayName(TextStyle.SHORT, Locale.getDefault())} ${date.dayOfMonth}"
            }
        }
    }
}
