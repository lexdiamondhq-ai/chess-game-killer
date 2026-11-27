package com.chessgamekiller.app.learn

import androidx.activity.compose.BackHandler
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ColumnScope
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.statusBarsPadding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.chessgamekiller.app.Sounds
import com.chessgamekiller.app.engine.Engines
import com.chessgamekiller.app.game.Rival
import com.chessgamekiller.app.ui.BoardArrow
import com.chessgamekiller.app.ui.ChessBoard
import com.chessgamekiller.app.ui.GoldButton
import com.chessgamekiller.app.ui.Palette
import com.chessgamekiller.app.ui.QuietButton
import com.chessgamekiller.app.ui.Type
import com.chessgamekiller.app.ui.card
import com.chessgamekiller.chess.Move
import com.chessgamekiller.chess.Position
import com.chessgamekiller.chess.squareIndex
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch

/**
 * Everything Learn opens, one page over another: lessons, sessions, Today's Move, the vine,
 * Puzzles and Chess DNA. Routes are plain words, so the stack survives the app being put away.
 */
@Composable
fun LearnHost(start: String, onExit: () -> Unit, onPlay: (Rival) -> Unit, onAskLeo: () -> Unit) {
    var stack by rememberSaveable(start) { mutableStateOf(arrayListOf(start)) }
    fun push(route: String) { stack = ArrayList(stack + route) }
    fun replace(route: String) { stack = ArrayList(stack.dropLast(1) + route) }
    fun pop() { if (stack.size <= 1) onExit() else stack = ArrayList(stack.dropLast(1)) }
    val context = LocalContext.current
    val library = remember { Library.get(context) }
    val route = stack.last()
    BackHandler { pop() }
    Box(Modifier.fillMaxSize().background(Palette.night)) {
        when {
            route == "lessons" -> LessonsPage(library, onBack = ::pop, open = { push("lesson:$it") })
            route.startsWith("lesson:") -> library.lesson(route.removePrefix("lesson:"))?.let { lesson ->
                LessonScreen(lesson, library, onExit = ::pop, onPractice = { replace("practice:${library.skillsFor(lesson).joinToString(",")}|${lesson.title}") })
            } ?: LaunchedEffect(route) { pop() }
            route == "puzzles" -> PuzzlesPage(library, onBack = ::pop, open = ::push)
            route == "dna" -> DnaPage(onBack = ::pop, open = ::push, onPlay = { onPlay(com.chessgamekiller.app.Progress.upNext) })
            route == "vine" -> VinePage(library, onBack = ::pop)
            route == "daily" -> DailyScreen(library, onExit = ::pop)
            else -> {
                val plan = remember(route) { planFor(route, library) }
                SessionScreen(plan, library, onExit = ::pop)
            }
        }
    }
}

/** today · mixed · practice:<skills>|<title> · fix:<AREA or ALL> */
fun planFor(route: String, library: Library): Plan = when {
    route == "today" -> Planner.today(library)
    route == "mixed" -> Planner.mixed(library)
    route.startsWith("practice:") -> {
        val (skills, title) = route.removePrefix("practice:").split('|').let { it[0] to (it.getOrNull(1) ?: "Practice") }
        Planner.practice(library, skills.split(','), title)
    }
    route.startsWith("fix:") -> {
        val area = DnaArea.entries.firstOrNull { it.name == route.removePrefix("fix:") }
        val own = Dna.slips(area).take(5).mapIndexed { i, s -> s.asDrill(i) }
        if (area == null) Plan("Fix your mistakes", "From your games", null, own.ifEmpty { Planner.mixed(library).drills })
        else Planner.practice(library, area.skills, area.title, own)
    }
    else -> Planner.today(library)
}

/** The top of a Learn page: back, a small carved eyebrow and the title. */
@Composable
fun LearnTopBar(eyebrow: String, title: String, onBack: () -> Unit, trailing: String? = null) {
    Row(Modifier.fillMaxWidth().statusBarsPadding().padding(horizontal = 6.dp, vertical = 4.dp), verticalAlignment = Alignment.CenterVertically) {
        IconButton(onClick = onBack, modifier = Modifier.testTag("learn-back")) {
            Icon(Icons.AutoMirrored.Filled.ArrowBack, contentDescription = "Back", tint = Palette.ink)
        }
        Column(Modifier.weight(1f)) {
            Text(eyebrow.uppercase(), style = Type.small.copy(fontSize = 10.sp, fontWeight = FontWeight.Bold, letterSpacing = 1.2.sp, color = Palette.gold), maxLines = 1)
            Text(title, style = Type.title.copy(fontSize = 22.sp, fontWeight = FontWeight.Normal), maxLines = 1)
        }
        if (trailing != null) Text(trailing, style = Type.small, modifier = Modifier.padding(end = 14.dp))
    }
}

@Composable
private fun ScrollPage(content: @Composable ColumnScope.() -> Unit) {
    Column(Modifier.fillMaxSize().verticalScroll(rememberScrollState()).navigationBarsPadding(), content = content)
}

// MARK: - A lesson

/**
 * A narrated lesson, played like the iPhone's: Leo talks (his recorded voice), pieces move,
 * arrows appear, and every so often it's the learner's turn on the same board as the drills.
 */
@Composable
fun LessonScreen(lesson: Lesson, library: Library, onExit: () -> Unit, onPractice: () -> Unit, inSession: Boolean = false, onDone: () -> Unit = {}) {
    val context = LocalContext.current
    val scope = rememberCoroutineScope()
    val narrator = remember { Narrator(context) }
    val sounds = remember { Sounds(context) }
    DisposableEffect(Unit) { onDispose { narrator.stop() } }

    var stepIndex by rememberSaveable(lesson.id) { mutableIntStateOf(0) }
    var finished by rememberSaveable(lesson.id) { mutableStateOf(false) }
    var position by remember { mutableStateOf(Position.start()) }
    var lastMove by remember { mutableStateOf<Move?>(null) }
    var animating by remember { mutableStateOf(false) }
    var task by remember { mutableStateOf<DrillState?>(null) }
    var ready by remember { mutableStateOf(false) }
    val step = lesson.steps.getOrNull(stepIndex)

    // Rebuilds where the lesson stands after the steps before this one, so coming back lands right.
    fun replayTo(index: Int) {
        var p = Position.start()
        for (s in lesson.steps.take(index)) {
            s.fen?.let { f -> Position.fromFen(f)?.let { p = it } }
            for (u in s.moves) Move.fromUci(u)?.let { m -> p.normalize(m).takeIf { p.isLegal(it) }?.let { p = p.play(it) } }
            s.task?.solution?.let { sol ->
                for (u in sol) Move.fromUci(u)?.let { m -> p.normalize(m).takeIf { p.isLegal(it) }?.let { p = p.play(it) } }
            }
        }
        position = p
    }

    LaunchedEffect(stepIndex, finished) {
        if (finished || step == null) return@LaunchedEffect
        // Opening on a step: rebuild the board. Going on: keep the board the last task left.
        if (!ready) { replayTo(stepIndex); ready = true } else task?.let { position = it.position; lastMove = it.lastMove }
        task = null
        step.fen?.let { f -> Position.fromFen(f)?.let { position = it; lastMove = null } }
        narrator.say(step.say)
        if (step.moves.isNotEmpty()) {
            animating = true
            for (u in step.moves) {
                delay(850)
                val m = Move.fromUci(u)?.let { position.normalize(it) } ?: continue
                if (!position.isLegal(m)) continue
                sounds.playMove(position.san(m))
                position = position.play(m)
                lastMove = m
            }
            animating = false
        }
        step.task?.let { t ->
            val drill = Drill(
                id = "${lesson.id}-$stepIndex", skill = lesson.skill, type = t.type, rating = 600, fen = position.fen, setup = null,
                solution = t.solution, alts = t.accept, mate = if (t.mate) 1 else null, squares = t.squares,
                move = null, answer = null, reply = null, explain = null, options = t.options, prompt = t.prompt, limit = null,
            )
            task = DrillState(drill, scope, Engines.get(context), library.course.lines, t.prompt, sounds,
                success = t.success, hintText = t.hint, wrongText = t.wrong, feedback = t.feedback,
                onFinished = { narrator.say(t.success) }).also { it.begin() }
        }
    }

    Column(Modifier.fillMaxSize().testTag("lesson")) {
        LearnTopBar("Lesson", lesson.title, onExit, trailing = if (finished) null else "${stepIndex + 1} of ${lesson.steps.size}")
        // A thin gold line that fills as the lesson goes.
        Box(Modifier.fillMaxWidth().padding(horizontal = 18.dp).height(3.dp).clip(RoundedCornerShape(50)).background(Palette.line)) {
            Box(Modifier.fillMaxWidth(if (finished) 1f else (stepIndex + 1f) / lesson.steps.size).height(3.dp).background(Palette.gold))
        }
        Column(Modifier.weight(1f).verticalScroll(rememberScrollState()).padding(top = 12.dp)) {
            if (finished) {
                LessonDone(lesson, library, onPractice, onExit, inSession, onDone)
            } else {
                val t = task
                if (t != null) {
                    DrillPanel(t, flipped = lesson.blackBottom)
                    // A task's lesson words stay under it.
                    step?.say?.let { Text(it, style = Type.small, modifier = Modifier.padding(horizontal = 18.dp, vertical = 6.dp)) }
                } else {
                    ChessBoard(
                        position = position,
                        flipped = lesson.blackBottom,
                        lastMove = lastMove,
                        interactive = false,
                        arrows = step?.arrows?.mapNotNull { a ->
                            val f = squareIndex(a.from); val to = squareIndex(a.to)
                            if (f != null && to != null) BoardArrow(f, to, arrowTone(a.color)) else null
                        } ?: emptyList(),
                        marks = step?.marks?.mapNotNull { m -> squareIndex(m.square)?.let { it to trainingColor(m.color) } }?.toMap() ?: emptyMap(),
                        labels = step?.labels?.mapNotNull { l -> squareIndex(l.square)?.let { it to l.text } }?.toMap() ?: emptyMap(),
                        modifier = Modifier.padding(horizontal = 6.dp),
                    )
                    Row(Modifier.padding(horizontal = 18.dp, vertical = 14.dp), verticalAlignment = Alignment.Top) {
                        CoachBadge(Modifier.size(34.dp))
                        Spacer(Modifier.width(12.dp))
                        Text(step?.say ?: "", style = Type.body, modifier = Modifier.weight(1f).heightIn(min = 60.dp).testTag("lesson-say"))
                    }
                }
            }
        }
        if (!finished) {
            val canGo = !animating && (task == null || task?.done == true)
            GoldButton(
                if (stepIndex + 1 >= lesson.steps.size) "Finish" else "Continue",
                enabled = canGo,
                modifier = Modifier.fillMaxWidth().padding(16.dp).navigationBarsPadding().testTag("lesson-continue"),
            ) {
                narrator.stop()
                if (stepIndex + 1 >= lesson.steps.size) {
                    Training.finishLesson(lesson)
                    finished = true
                } else stepIndex += 1
            }
        }
    }
}

@Composable
private fun LessonDone(lesson: Lesson, library: Library, onPractice: () -> Unit, onExit: () -> Unit, inSession: Boolean, onDone: () -> Unit) {
    val line = remember { library.course.lines.lessonDone.randomOrNull() ?: "Lesson done." }
    Column(Modifier.padding(16.dp).fillMaxWidth().card(padding = 20.dp, glow = Palette.gold), verticalArrangement = Arrangement.spacedBy(12.dp)) {
        Text("LESSON DONE", style = Type.label)
        Text(lesson.title, style = Type.title.copy(fontSize = 26.sp))
        Text(line, style = Type.body)
        RankLine(library)
        if (inSession) {
            GoldButton("Practice it", modifier = Modifier.fillMaxWidth().testTag("lesson-next")) { onDone() }
        } else {
            GoldButton("Practice it now", modifier = Modifier.fillMaxWidth().testTag("lesson-practice")) { onPractice() }
            QuietButton("Back to Learn", modifier = Modifier.fillMaxWidth()) { onExit() }
        }
    }
}

@Composable
fun RankLine(library: Library) {
    val rank = library.rank(Training.xp)
    val next = library.nextRank(Training.xp)
    Text(
        "${rank.title} rank · ${Training.xp} XP" + (next?.let { " · ${it.xp - Training.xp} to ${it.title}" } ?: ""),
        style = Type.small.copy(color = Palette.gold, fontWeight = FontWeight.SemiBold),
    )
}

// MARK: - A session

/** A lesson if the plan has one, then its drills one by one, then what it came to. */
@Composable
fun SessionScreen(plan: Plan, library: Library, onExit: () -> Unit) {
    val context = LocalContext.current
    val scope = rememberCoroutineScope()
    val sounds = remember { Sounds(context) }
    var inLesson by rememberSaveable { mutableStateOf(plan.lesson != null) }
    var index by rememberSaveable { mutableIntStateOf(0) }
    var clean by rememberSaveable { mutableIntStateOf(0) }
    var earned by rememberSaveable { mutableIntStateOf(0) }
    var closed by rememberSaveable { mutableStateOf(false) }

    if (inLesson && plan.lesson != null) {
        LessonScreen(plan.lesson, library, onExit = onExit, onPractice = {}, inSession = true, onDone = { inLesson = false })
        return
    }
    val drill = plan.drills.getOrNull(index)
    if (drill == null && !closed && plan.drills.isNotEmpty()) {
        LaunchedEffect(Unit) { Training.finishSession(plan.title); earned += 30; closed = true }
    }
    Column(Modifier.fillMaxSize().testTag("session")) {
        LearnTopBar(plan.reason.takeIf { it.length < 24 } ?: "Today", plan.title, onExit,
            trailing = if (drill != null) "${index + 1} of ${plan.drills.size}" else null)
        // A dot for each drill.
        Row(Modifier.fillMaxWidth().padding(horizontal = 18.dp, vertical = 4.dp), horizontalArrangement = Arrangement.spacedBy(4.dp)) {
            plan.drills.indices.forEach { i ->
                Box(Modifier.weight(1f).height(3.dp).clip(RoundedCornerShape(50)).background(if (i < index) Palette.gold else Palette.line))
            }
        }
        Column(Modifier.weight(1f).verticalScroll(rememberScrollState()).navigationBarsPadding().padding(top = 8.dp)) {
            if (drill != null) {
                val skill = library.skill(drill.skill)
                val state = remember(drill.id, index) {
                    DrillState(drill, scope, Engines.get(context), library.course.lines, skill?.prompt, sounds, onFinished = { outcome ->
                        Training.recordDrill(drill, outcome)
                        earned += outcome.xp
                        if (outcome == Outcome.FIRST_TRY) clean += 1
                    }).also { it.begin() }
                }
                if (skill != null) {
                    Text(skill.title.uppercase(), style = Type.small.copy(fontSize = 10.sp, fontWeight = FontWeight.Bold, letterSpacing = 1.2.sp, color = Palette.gold),
                        modifier = Modifier.padding(horizontal = 18.dp, vertical = 2.dp))
                }
                DrillPanel(state, yesLabel = skill?.yes ?: "Yes", noLabel = skill?.no ?: "No") {
                    GoldButton(if (index + 1 >= plan.drills.size) "Finish" else "Next", modifier = Modifier.fillMaxWidth().padding(horizontal = 16.dp).testTag("drill-next")) {
                        index += 1
                    }
                }
            } else {
                val line = remember { library.course.lines.sessionDone.randomOrNull() ?: "That's a session." }
                Column(Modifier.padding(16.dp).fillMaxWidth().card(padding = 20.dp, glow = Palette.gold).testTag("session-done"), verticalArrangement = Arrangement.spacedBy(12.dp)) {
                    Text("SESSION DONE", style = Type.label)
                    Text(if (plan.drills.isEmpty()) "Nothing to practice yet" else "$clean of ${plan.drills.size} first try", style = Type.title.copy(fontSize = 26.sp))
                    Text(line, style = Type.body)
                    Text("+$earned XP", style = Type.heading.copy(color = Palette.gold))
                    RankLine(library)
                    Text("Puzzle rating ${Training.puzzleRating}", style = Type.small)
                    GoldButton("Done", modifier = Modifier.fillMaxWidth().testTag("session-close")) { onExit() }
                }
            }
        }
    }
}

// MARK: - Today's Move

/** One puzzle a day, the same as on the iPhone. Played once; after that it shows the answer until tomorrow. */
@Composable
fun DailyScreen(library: Library, onExit: () -> Unit) {
    val puzzle = remember { library.dailyPuzzle() }
    Column(Modifier.fillMaxSize().testTag("daily")) {
        LearnTopBar("Today's Move" + (puzzle?.let { " · No. ${it.number} · ${it.difficulty}" } ?: ""), puzzle?.headline ?: "Today's Move", onExit)
        if (puzzle == null) {
            Text("Today's Move is missing from this build.", style = Type.body, modifier = Modifier.padding(20.dp))
        } else DailyBoard(puzzle, library, onExit)
    }
}

@Composable
private fun ColumnScope.DailyBoard(puzzle: DailyPuzzle, library: Library, onExit: () -> Unit) {
    val context = LocalContext.current
    val scope = rememberCoroutineScope()
    val sounds = remember { Sounds(context) }
    run {
        val playedBefore = remember { Training.playedDailyToday }
        val state = remember {
            DrillState(puzzle.asDrill(), scope, Engines.get(context), library.course.lines, puzzle.headline, sounds,
                success = "That's today's move.", onFinished = { Training.recordDaily(it) }).also { s ->
                if (playedBefore) { s.begin(); scope.launch { delay(700); s.reveal() } } else s.begin()
            }
        }
        Column(Modifier.weight(1f).verticalScroll(rememberScrollState()).navigationBarsPadding().padding(top = 8.dp)) {
            DrillPanel(state) {
                Column(Modifier.padding(horizontal = 16.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
                    val result = Training.daily[Training.today]
                    Text(
                        when (result) {
                            Outcome.FIRST_TRY -> "Found first try."
                            Outcome.WITH_HINT, Outcome.AFTER_MISTAKE -> "Found, with a little help."
                            Outcome.MISSED -> "Missed today. It happens to everyone."
                            null -> ""
                        } + " Played today. Next one tomorrow.",
                        style = Type.small.copy(color = Palette.gold, fontWeight = FontWeight.SemiBold),
                        modifier = Modifier.testTag("daily-locked"),
                    )
                    QuietButton("Back to Learn", modifier = Modifier.fillMaxWidth()) { onExit() }
                }
            }
        }
    }
}
