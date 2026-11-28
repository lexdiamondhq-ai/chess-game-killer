package com.chessgamekiller.app

import com.chessgamekiller.app.learn.Library
import com.chessgamekiller.app.learn.Narrator
import com.chessgamekiller.app.learn.Planner
import com.chessgamekiller.app.learn.Training
import com.chessgamekiller.chess.Move
import com.chessgamekiller.chess.Position
import com.chessgamekiller.chess.squareIndex
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertTrue
import org.junit.Test
import java.io.File

/** Every lesson, drill and daily puzzle the Learn tab ships, played through the rules. */
class TrainingContentTest {
    private val assets = File("src/main/assets")
    private val library by lazy { Library.load { File(assets, it).readText() } }

    private fun play(p: Position, uci: String, where: String): Position {
        val m = Move.fromUci(uci)?.let { p.normalize(it) }
        assertNotNull("bad move $uci in $where", m)
        assertTrue("illegal $uci in $where (${p.fen})", p.isLegal(m!!))
        return p.play(m)
    }

    @Test fun theCourseHasFifteenLessonsInOrder() {
        assertEquals(15, library.lessons.size)
        assertEquals("welcome", library.lessons.first().id)
        assertEquals(6, library.course.ranks.size)
    }

    @Test fun everyLessonPlaysThrough() {
        for (lesson in library.lessons) {
            var p = Position.start()
            for ((i, step) in lesson.steps.withIndex()) {
                val where = "${lesson.id} step $i"
                step.fen?.let { p = Position.fromFen(it) ?: error("bad fen in $where") }
                for (u in step.moves) p = play(p, u, where)
                step.task?.let { t ->
                    for (u in t.solution) p = play(p, u, where)
                    for (s in t.squares) assertNotNull(where, squareIndex(s))
                    if (t.type == "choice") assertTrue("no right answer in $where", t.options.any { it.correct })
                }
            }
        }
    }

    @Test fun everyDrillIsPlayable() {
        assertTrue(library.drills.size > 1400)
        for (d in library.drills) {
            var p = Position.fromFen(d.fen) ?: error("bad fen in ${d.id}")
            d.setup?.let { p = play(p, it, d.id) }
            when (d.type) {
                "move" -> { var q = p; for (u in d.solution) q = play(q, u, d.id); assertTrue(d.id, d.solution.isNotEmpty()) }
                "safe" -> { val after = play(p, d.move!!, d.id); d.reply?.let { play(after, it, d.id) }; assertNotNull(d.id, d.answer) }
                "tap" -> { assertTrue(d.id, d.squares.isNotEmpty()); d.squares.forEach { assertNotNull(d.id, squareIndex(it)) } }
                "choice" -> { assertTrue(d.id, d.options.any { it.correct }); d.options.mapNotNull { it.move }.forEach { play(p, it, d.id) } }
                "playout" -> assertNotNull(d.id, d.limit)
                else -> error("unknown type ${d.type} in ${d.id}")
            }
            assertNotNull("skill ${d.skill} of ${d.id}", library.skill(d.skill))
        }
    }

    @Test fun everyDailyPuzzlePlays() {
        assertTrue(library.daily.size > 300)
        for (d in library.daily) {
            var p = Position.fromFen(d.fen) ?: error("bad fen in daily ${d.number}")
            for (u in d.moves) p = play(p, u, "daily ${d.number}")
        }
        assertNotNull(library.dailyPuzzle())
    }

    @Test fun leosVoiceIsFoundByTheLine() {
        val line = library.lessons.first().steps.first().say!!
        assertTrue(File(assets, "narration/${Narrator.fileName(line)}.mp3").exists())
    }

    @Test fun todayStartsWithTheFirstLessonThenPicksDrillsNearTheLevel() {
        Training.resetForTests()
        val plan = Planner.today(library)
        assertEquals("welcome", plan.lesson?.id)
        val mixed = Planner.mixed(library)
        assertEquals(10, mixed.drills.size)
        assertTrue(mixed.drills.all { it.rating < 1200 })
    }
}
