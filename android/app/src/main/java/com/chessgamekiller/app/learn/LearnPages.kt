package com.chessgamekiller.app.learn

import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.matchParentSize
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.Path
import androidx.compose.ui.graphics.PathEffect
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.graphics.drawscope.DrawScope
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.graphics.drawscope.rotate
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.chessgamekiller.app.Progress
import com.chessgamekiller.app.home.Jewel
import com.chessgamekiller.app.home.JewelGold
import com.chessgamekiller.app.home.JewelTile
import com.chessgamekiller.app.ui.ChessBoard
import com.chessgamekiller.app.ui.Fonts
import com.chessgamekiller.app.ui.GoldButton
import com.chessgamekiller.app.ui.KnightGlyph
import com.chessgamekiller.app.ui.Palette
import com.chessgamekiller.app.ui.Pill
import com.chessgamekiller.app.ui.SectionTitle
import com.chessgamekiller.app.ui.TabIcon
import com.chessgamekiller.app.ui.TabKind
import com.chessgamekiller.app.ui.Type
import com.chessgamekiller.app.ui.card
import com.chessgamekiller.chess.Move
import com.chessgamekiller.chess.Position
import kotlin.math.PI
import kotlin.math.sin

/** Coach Leo's small portrait: the gold knight on a jade stone. */
@Composable
fun CoachBadge(modifier: Modifier = Modifier) {
    JewelTile(Jewel.JADE, 34.dp) { KnightGlyph(Modifier.size(22.dp), ink = JewelGold, detail = Color(0xFF0C3B2E)) }
}

@Composable
private fun Eyebrow(text: String, color: Color = Palette.gold) {
    Text(text.uppercase(), style = Type.small.copy(fontSize = 10.5.sp, fontWeight = FontWeight.Bold, letterSpacing = 1.3.sp, color = color), maxLines = 1)
}

/** The first position a plan shows, from the side that plays it. */
private fun previewFen(plan: Plan): String? =
    plan.lesson?.steps?.firstOrNull { it.fen != null }?.fen ?: plan.drills.firstOrNull()?.let { d ->
        val p = Position.fromFen(d.fen) ?: return@let d.fen
        d.setup?.let { u -> Move.fromUci(u)?.let { p.normalize(it) }?.takeIf { p.isLegal(it) }?.let { p.play(it).fen } } ?: d.fen
    }

@Composable
fun BoardThumb(fen: String, modifier: Modifier = Modifier) {
    val p = remember(fen) { Position.fromFen(fen) } ?: return
    Box(modifier.clip(RoundedCornerShape(6.dp))) {
        ChessBoard(position = p, flipped = !p.whiteToMove, interactive = false, coordinates = false, tagged = false)
    }
}

/**
 * The Learn tab, as on the iPhone: Leo's line and the streak, Today's session, Today's Move, the
 * gilded vine, then the doors (Puzzles, Lessons, Chess DNA, Ask Leo).
 */
@Composable
fun LearnTab(open: (String) -> Unit, askLeo: () -> Unit) {
    val context = LocalContext.current
    val library = remember { Library.get(context) }
    // Read the state the plan depends on, so the card changes after a lesson or a session.
    val key = Training.xp + Training.lessonsDone.size + Dna.graded.size
    val plan = remember(key) { Planner.today(library) }
    val vine = remember(key) { Vine.make(library, plan) }
    val greeting = remember { library.course.lines.greeting.randomOrNull() ?: "Ready when you are." }
    LaunchedEffect(Unit) { Dna.gradePending(context) }

    Column(Modifier.padding(horizontal = 16.dp), verticalArrangement = Arrangement.spacedBy(14.dp)) {
        Row(Modifier.padding(top = 10.dp), verticalAlignment = Alignment.CenterVertically) {
            CoachBadge()
            Spacer(Modifier.width(12.dp))
            Text(greeting, style = Type.small.copy(fontSize = 13.5.sp), modifier = Modifier.weight(1f))
            Spacer(Modifier.width(8.dp))
            Text(
                "🔥 ${Progress.streak} ${if (Progress.streak == 1) "day" else "days"}",
                style = Type.small.copy(fontWeight = FontWeight.SemiBold, color = Palette.ink),
                modifier = Modifier.clip(RoundedCornerShape(50)).border(1.dp, Palette.gold.copy(alpha = 0.5f), RoundedCornerShape(50))
                    .padding(horizontal = 10.dp, vertical = 5.dp),
            )
        }
        TodayCard(plan, open)
        DailyCard(library, open)
        VineCard(vine, Modifier.clickable { open("vine") }.testTag("learn-vine"))
        Doors(library, open, askLeo)
    }
}

@Composable
private fun TodayCard(plan: Plan, open: (String) -> Unit) {
    val done = Training.trainedToday
    Column(Modifier.fillMaxWidth().card(padding = 18.dp, glow = Palette.gold).testTag("learn-today"), verticalArrangement = Arrangement.spacedBy(12.dp)) {
        Row {
            Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(5.dp)) {
                Eyebrow(if (done) "Today · done" else "Today · ${plan.minutes} min")
                Text(if (done) "Nice work today" else plan.title, style = Type.title.copy(fontSize = 23.sp), maxLines = 2)
                Text(
                    if (done) "You've trained today and your streak is safe. Another round is always welcome." else plan.reason,
                    style = Type.small.copy(fontSize = 13.5.sp),
                )
            }
            previewFen(plan)?.let { fen ->
                Spacer(Modifier.width(12.dp))
                BoardThumb(fen, Modifier.size(88.dp))
            }
        }
        Row(horizontalArrangement = Arrangement.spacedBy(6.dp)) {
            if (plan.lesson != null) Chip("▶ Lesson")
            if (plan.drills.isNotEmpty()) Chip(if (plan.drills.size == 1) "1 puzzle" else "${plan.drills.size} puzzles")
            val own = plan.drills.count { it.skill == "game" }
            if (own > 0) Chip("$own from your games")
        }
        GoldButton(if (done) "Train more" else "Start", modifier = Modifier.fillMaxWidth().testTag("learn-start")) { open("today") }
    }
}

@Composable
private fun Chip(text: String) {
    Text(
        text, style = Type.small.copy(fontSize = 11.5.sp, fontWeight = FontWeight.SemiBold, color = Palette.gold),
        modifier = Modifier.clip(RoundedCornerShape(50)).background(Palette.gold.copy(alpha = 0.12f)).padding(horizontal = 9.dp, vertical = 4.dp),
    )
}

@Composable
private fun DailyCard(library: Library, open: (String) -> Unit) {
    val puzzle = remember { library.dailyPuzzle() } ?: return
    val result = Training.daily[Training.today]
    Row(
        Modifier.fillMaxWidth().card(padding = 16.dp, glow = Palette.rose).clickable { open("daily") }.testTag("learn-daily"),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(4.dp)) {
            Eyebrow("Today's Move · No. ${puzzle.number}", Palette.rose)
            Text(puzzle.headline, style = Type.heading.copy(fontSize = 19.sp), maxLines = 2)
            Text(
                when (result) {
                    null -> "${puzzle.difficulty}. One move a day, the same for everyone."
                    Outcome.FIRST_TRY -> "Found first try. Next one tomorrow."
                    Outcome.MISSED -> "Missed today. Next one tomorrow."
                    else -> "Found. Next one tomorrow."
                },
                style = Type.small.copy(fontSize = 12.5.sp),
            )
            if (result == null) Pill("Play", main = true, icon = "▶", modifier = Modifier.padding(top = 6.dp)) { open("daily") }
        }
        Spacer(Modifier.width(12.dp))
        BoardThumb(puzzle.shownFen, Modifier.size(84.dp))
    }
}

// MARK: - The vine

private val vineGold = Color(0xFFE2BC6A)

private fun DrawScope.leaf(at: Offset, angle: Float, size: Float, color: Color = vineGold) {
    rotate(angle, at) {
        drawOval(color, topLeft = Offset(at.x, at.y - size * 0.32f), size = Size(size, size * 0.64f))
        drawLine(Color(0x66000000), Offset(at.x + size * 0.1f, at.y), Offset(at.x + size * 0.9f, at.y), strokeWidth = 1f)
    }
}

private fun DrawScope.flower(at: Offset, r: Float) {
    drawCircle(Brush.radialGradient(listOf(Color(0x88F6DEA3), Color.Transparent), center = at, radius = r * 3.2f), r * 3.2f, at)
    for (i in 0 until 6) {
        val a = i * 60f
        rotate(a, at) { drawOval(Color(0xFFF6DEA3), topLeft = Offset(at.x - r * 0.42f, at.y - r * 1.15f), size = Size(r * 0.84f, r * 1.1f)) }
    }
    drawCircle(Color(0xFFB98A3A), r * 0.42f, at)
}

private fun DrawScope.bud(at: Offset, r: Float, color: Color = vineGold) {
    val p = Path().apply {
        moveTo(at.x, at.y - r * 1.4f)
        cubicTo(at.x + r, at.y - r * 0.4f, at.x + r * 0.8f, at.y + r, at.x, at.y + r)
        cubicTo(at.x - r * 0.8f, at.y + r, at.x - r, at.y - r * 0.4f, at.x, at.y - r * 1.4f)
    }
    drawPath(p, color, style = Stroke(width = 2.2f))
}

/** Learn's card: a sprig of the vine, its leaves, the flower in bloom and a bud. */
@Composable
fun VineCard(vine: Vine, modifier: Modifier = Modifier) {
    Column(modifier.fillMaxWidth().card(padding = 16.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
        Row(verticalAlignment = Alignment.CenterVertically) {
            Text("YOUR VINE", style = Type.label, modifier = Modifier.weight(1f))
            Text("${vine.leaves.size + vine.earlierDays} ${if (vine.leaves.size + vine.earlierDays == 1) "leaf" else "leaves"} ›", style = Type.small)
        }
        Canvas(Modifier.fillMaxWidth().height(56.dp)) {
            val mid = size.height / 2
            val bloomX = size.width * 0.72f
            val path = Path()
            var x = 0f
            path.moveTo(0f, mid)
            while (x <= bloomX) { path.lineTo(x, mid + sin(x / size.width * 4 * PI).toFloat() * 8f); x += 4f }
            drawPath(path, vineGold, style = Stroke(width = 3.5f, cap = StrokeCap.Round))
            val n = vine.leaves.size.coerceAtMost(5)
            for (i in 0 until n) {
                val lx = bloomX * (0.12f + 0.16f * i)
                val ly = mid + sin(lx / size.width * 4 * PI).toFloat() * 8f
                leaf(Offset(lx, ly), if (i % 2 == 0) -40f else 40f, 26f)
            }
            drawLine(vineGold.copy(alpha = 0.6f), Offset(bloomX, mid), Offset(size.width * 0.94f, mid), strokeWidth = 2f,
                pathEffect = PathEffect.dashPathEffect(floatArrayOf(6f, 8f)))
            bud(Offset(size.width * 0.95f, mid), 9f)
            flower(Offset(bloomX, mid + sin(bloomX / size.width * 4 * PI).toFloat() * 8f), 13f)
        }
        Text(
            buildString {
                append("In bloom: ")
                append(vine.bloom?.title ?: "Your first lesson")
            },
            style = Type.small.copy(fontSize = 13.5.sp, color = Palette.ink),
        )
    }
}

/** A point on the vine page: 0 a bud, 1 the flower in bloom, 2 a leaf. */
private data class Node(val title: String, val detail: String, val kind: Int)

/** The vine's own page: buds at the top, the flower in bloom, then a leaf for each day trained. */
@Composable
fun VinePage(library: Library, onBack: () -> Unit) {
    val plan = remember { Planner.today(library) }
    val vine = remember { Vine.make(library, plan) }
    val rank = library.rank(Training.xp)
    val nodes = vine.buds.reversed().map { Node(it.title, it.detail, 0) } +
        listOfNotNull(vine.bloom?.let { Node(it.title, it.detail, 1) }) +
        vine.leaves.map { Node(it.title, Vine.dayLabel(it.day) + if (it.detail.isNotEmpty()) " · ${it.detail}" else "", 2) }
    val bloomAt = nodes.indexOfFirst { it.kind == 1 }.let { if (it < 0) nodes.indexOfFirst { n -> n.kind == 2 } else it }
    val rowH = 92.dp
    Column(Modifier.fillMaxSize().verticalScroll(rememberScrollState()).navigationBarsPadding().testTag("vine-page")) {
        LearnTopBar("Learn", "", onBack)
        Text("YOUR VINE", style = Type.label.copy(fontSize = 30.sp, letterSpacing = 3.sp), modifier = Modifier.padding(horizontal = 22.dp))
        val total = vine.leaves.size + vine.earlierDays
        Text(
            "$total ${if (total == 1) "leaf" else "leaves"} grown · ${vine.daysThisWeek} ${if (vine.daysThisWeek == 1) "day" else "days"} this week · ${rank.title} rank",
            style = Type.small, modifier = Modifier.padding(horizontal = 22.dp, vertical = 6.dp),
        )
        Box(Modifier.fillMaxWidth().padding(top = 18.dp)) {
            Canvas(Modifier.matchParentSize()) {
                val h = rowH.toPx()
                val cx = size.width / 2
                val amp = size.width * 0.13f
                fun xAt(y: Float) = cx + amp * sin(PI * y / h - PI / 2).toFloat()
                val split = if (bloomAt >= 0) h * (bloomAt + 0.5f) else 0f
                // Buds: a dotted line. Bloom and leaves: the gold stem.
                val dotted = Path(); val solid = Path()
                var y = h * 0.5f
                dotted.moveTo(xAt(y), y); var movedSolid = false
                while (y <= size.height - h * 0.2f) {
                    if (y <= split) dotted.lineTo(xAt(y), y)
                    else { if (!movedSolid) { solid.moveTo(xAt(split), split); movedSolid = true }; solid.lineTo(xAt(y), y) }
                    y += 3f
                }
                drawPath(dotted, vineGold.copy(alpha = 0.55f), style = Stroke(2f, pathEffect = PathEffect.dashPathEffect(floatArrayOf(4f, 7f))))
                drawPath(solid, vineGold, style = Stroke(5f, cap = StrokeCap.Round))
                nodes.forEachIndexed { i, node ->
                    val ny = h * (i + 0.5f)
                    val nx = xAt(ny)
                    when (node.kind) {
                        0 -> bud(Offset(nx, ny), 11f)
                        1 -> flower(Offset(nx, ny), 18f)
                        else -> leaf(Offset(nx, ny), if (nx > cx) -25f else 205f, 44f)
                    }
                }
            }
            Column {
                nodes.forEachIndexed { i, node ->
                    val nodeRight = sin(PI * (i + 0.5) - PI / 2) > 0
                    Row(Modifier.fillMaxWidth().height(rowH), verticalAlignment = Alignment.CenterVertically) {
                        val label: @Composable (TextAlign) -> Unit = { align ->
                            Column(Modifier.padding(horizontal = 20.dp)) {
                                Text(node.title, style = Type.heading.copy(fontSize = 16.sp, fontWeight = FontWeight.SemiBold, textAlign = align,
                                    color = if (node.kind == 0) Palette.inkSoft else Palette.ink), modifier = Modifier.fillMaxWidth(), maxLines = 2)
                                Text(node.detail, style = Type.small.copy(fontSize = 11.5.sp, textAlign = align,
                                    color = if (node.kind == 1) Palette.gold else Palette.inkFaint), modifier = Modifier.fillMaxWidth(), maxLines = 1)
                            }
                        }
                        if (nodeRight) { Box(Modifier.weight(1f)) { label(TextAlign.End) }; Spacer(Modifier.weight(1f)) }
                        else { Spacer(Modifier.weight(1f)); Box(Modifier.weight(1f)) { label(TextAlign.Start) } }
                    }
                }
            }
        }
        if (vine.earlierDays > 0) Text("and ${vine.earlierDays} earlier days", style = Type.small, modifier = Modifier.align(Alignment.CenterHorizontally).padding(8.dp))
        Column(Modifier.padding(16.dp).fillMaxWidth().card(padding = 16.dp, glow = Palette.gold), verticalArrangement = Arrangement.spacedBy(6.dp)) {
            Text("♛  PREMIUM IS ON", style = Type.label)
            Text("Every bud on your vine is open while you test: every lesson, every drill and Chess DNA.", style = Type.small.copy(fontSize = 13.sp))
        }
        Spacer(Modifier.height(24.dp))
    }
}

// MARK: - Doors

@Composable
private fun Doors(library: Library, open: (String) -> Unit, askLeo: () -> Unit) {
    val style = Dna.style()?.first
    Column(verticalArrangement = Arrangement.spacedBy(12.dp)) {
        Row(horizontalArrangement = Arrangement.spacedBy(12.dp)) {
            Door("Puzzles", "Rating ${Training.puzzleRating}", Jewel.SAPPHIRE, "♞", Modifier.weight(1f).testTag("door-puzzles")) { open("puzzles") }
            Door("Lessons", "${Training.lessonsDone.keys.count { library.lesson(it) != null }} of ${library.lessons.size} watched", Jewel.AMBER, "♗",
                Modifier.weight(1f).testTag("door-lessons")) { open("lessons") }
        }
        Row(horizontalArrangement = Arrangement.spacedBy(12.dp)) {
            Door("Chess DNA", style ?: if (Dna.games.isEmpty()) "Play a game first" else "Your style and what to fix", Jewel.AMETHYST, "✦",
                Modifier.weight(1f).testTag("door-dna")) { open("dna") }
            Door("Ask Leo", "Talk any position through", Jewel.JADE, null, Modifier.weight(1f).testTag("learn-leo"), onClick = askLeo)
        }
    }
}

@Composable
private fun Door(title: String, status: String, stone: Jewel, glyph: String?, modifier: Modifier, onClick: () -> Unit) {
    Column(modifier.card(padding = 14.dp).clickable(onClick = onClick)) {
        JewelTile(stone, 40.dp) {
            if (glyph != null) Text(glyph, fontSize = 21.sp, color = JewelGold) else TabIcon(TabKind.LEARN, JewelGold, Modifier.size(22.dp))
        }
        Spacer(Modifier.height(12.dp))
        Text(title, style = Type.heading.copy(fontSize = 18.sp), maxLines = 1)
        Text(status, style = Type.small.copy(fontSize = 12.sp), maxLines = 1)
    }
}

// MARK: - Lessons

@Composable
fun LessonsPage(library: Library, onBack: () -> Unit, open: (String) -> Unit) {
    Column(Modifier.fillMaxSize().verticalScroll(rememberScrollState()).navigationBarsPadding().testTag("lessons-page")) {
        LearnTopBar("Learn", "Lessons", onBack, trailing = "${Training.lessonsDone.size} of ${library.lessons.size}")
        for (unit in library.course.units) {
            SectionTitle(unit.title, note = null)
            Text(unit.subtitle, style = Type.small, modifier = Modifier.padding(start = 20.dp, end = 20.dp, bottom = 10.dp).padding(top = 0.dp))
            Column(Modifier.padding(horizontal = 16.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
                for (id in unit.lessons) {
                    val lesson = library.lesson(id) ?: continue
                    val done = id in Training.lessonsDone
                    Row(
                        Modifier.fillMaxWidth().card(padding = 14.dp, radius = 18.dp).clickable { open(lesson.id) }.testTag("lesson-${lesson.id}"),
                        verticalAlignment = Alignment.CenterVertically,
                    ) {
                        Box(
                            Modifier.size(30.dp).clip(RoundedCornerShape(50))
                                .background(if (done) Palette.gold else Color.Transparent)
                                .border(1.dp, Palette.gold.copy(alpha = 0.7f), RoundedCornerShape(50)),
                            contentAlignment = Alignment.Center,
                        ) { Text(if (done) "✓" else "▶", fontSize = 13.sp, color = if (done) Palette.onMetal else Palette.gold) }
                        Spacer(Modifier.width(12.dp))
                        Column(Modifier.weight(1f)) {
                            Text(lesson.title, style = Type.heading.copy(fontSize = 17.sp))
                            Text(lesson.subtitle, style = Type.small.copy(fontSize = 12.sp), maxLines = 1)
                        }
                    }
                }
            }
        }
        Spacer(Modifier.height(24.dp))
    }
}

// MARK: - Puzzles

@Composable
fun PuzzlesPage(library: Library, onBack: () -> Unit, open: (String) -> Unit) {
    Column(Modifier.fillMaxSize().verticalScroll(rememberScrollState()).navigationBarsPadding().testTag("puzzles-page")) {
        LearnTopBar("Learn", "Puzzles", onBack)
        Column(Modifier.padding(16.dp).fillMaxWidth().card(padding = 18.dp, glow = Palette.info), verticalArrangement = Arrangement.spacedBy(8.dp)) {
            Eyebrow("Puzzle rating")
            Text("${Training.puzzleRating}", style = Type.title.copy(fontSize = 44.sp, fontFamily = Fonts.display))
            val seen = Training.skills.values.sumOf { it.seen }
            val clean = Training.skills.values.sumOf { it.clean }
            Text(if (seen == 0) "Ten puzzles find your level." else "$clean of $seen solved first try.", style = Type.small)
            GoldButton("Start puzzles", modifier = Modifier.fillMaxWidth().padding(top = 4.dp).testTag("puzzles-start")) { open("mixed") }
        }
        SectionTitle("By skill", note = "${library.drills.size} puzzles")
        Column(Modifier.padding(horizontal = 16.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
            for (skill in library.course.skills) {
                val stat = Training.skills[skill.id]
                Row(Modifier.fillMaxWidth().card(padding = 14.dp, radius = 18.dp), verticalAlignment = Alignment.CenterVertically) {
                    Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(4.dp)) {
                        Text(skill.title, style = Type.heading.copy(fontSize = 17.sp))
                        Text(if (stat == null || stat.seen == 0) skill.blurb else "${(stat.accuracy * 100).toInt()}% first try · ${stat.seen} played",
                            style = Type.small.copy(fontSize = 12.sp), maxLines = 2)
                    }
                    Spacer(Modifier.width(10.dp))
                    Pill("Practice", modifier = Modifier.testTag("practice-${skill.id}")) { open("practice:${skill.id}|${skill.title}") }
                }
            }
        }
        Spacer(Modifier.height(24.dp))
    }
}

// MARK: - Chess DNA

@Composable
private fun Bar(score: Int?) {
    Box(Modifier.fillMaxWidth().height(6.dp).clip(RoundedCornerShape(50)).background(Palette.line)) {
        if (score != null) Box(
            Modifier.fillMaxWidth(score / 100f).height(6.dp).clip(RoundedCornerShape(50))
                .background(Brush.horizontalGradient(listOf(Palette.goldFoot, Palette.goldTop))),
        )
    }
}

@Composable
fun DnaPage(onBack: () -> Unit, open: (String) -> Unit, onPlay: () -> Unit) {
    val context = LocalContext.current
    LaunchedEffect(Unit) { Dna.gradePending(context) }
    val readings = Dna.readings()
    val style = Dna.style()
    val graded = Dna.graded.size
    Column(Modifier.fillMaxSize().verticalScroll(rememberScrollState()).navigationBarsPadding().testTag("dna-page")) {
        LearnTopBar("Learn", "Chess DNA", onBack)
        Text("Coach Leo reads every move of your games against the rivals and finds where the points go.",
            style = Type.small.copy(fontSize = 14.sp), modifier = Modifier.padding(horizontal = 20.dp, vertical = 6.dp))
        Column(Modifier.padding(16.dp).fillMaxWidth().card(padding = 18.dp, glow = Palette.violet), verticalArrangement = Arrangement.spacedBy(12.dp)) {
            Row {
                Eyebrow("Your Chess DNA")
                Spacer(Modifier.weight(1f))
                Text("$graded ${if (graded == 1) "game" else "games"} · ${Training.skills.values.sumOf { it.seen }} puzzles", style = Type.small.copy(fontSize = 12.sp))
            }
            Row(verticalAlignment = Alignment.CenterVertically) {
                JewelTile(Jewel.AMETHYST, 48.dp) { Text("✦", fontSize = 22.sp, color = JewelGold) }
                Spacer(Modifier.width(14.dp))
                Column(Modifier.weight(1f)) {
                    Text(style?.first ?: "Not named yet", style = Type.title.copy(fontSize = 22.sp))
                    Text(
                        style?.second ?: when {
                            Dna.games.isEmpty() -> "Play a rival. After the game, Leo reads every move you made."
                            else -> "${(Dna.gamesToName - graded).coerceAtLeast(1)} more ${if (Dna.gamesToName - graded == 1) "game" else "games"} and Leo names your style."
                        },
                        style = Type.small.copy(fontSize = 13.sp),
                    )
                }
            }
            if (Dna.grading) Text("Leo is reading your last game…", style = Type.small.copy(color = Palette.gold), modifier = Modifier.testTag("dna-grading"))
            for (r in readings) {
                Column(verticalArrangement = Arrangement.spacedBy(5.dp)) {
                    Row {
                        Text(r.title, style = Type.body.copy(fontWeight = FontWeight.SemiBold), modifier = Modifier.weight(1f))
                        Text(r.word, style = Type.small.copy(fontSize = 12.sp, color = if (r.score == null) Palette.inkFaint else Palette.gold, fontWeight = FontWeight.SemiBold))
                    }
                    Bar(r.score)
                }
            }
            if (Dna.games.isEmpty()) GoldButton("Play a rival", modifier = Modifier.fillMaxWidth().testTag("dna-play")) { onPlay() }
        }
        val good = Dna.goodAt()
        if (good.isNotEmpty()) {
            SectionTitle("You are good at", note = "from your last $graded ${if (graded == 1) "game" else "games"}")
            AreaList(good, "Sharpen") { open("practice:${it.skills.joinToString(",")}|${it.title}") }
        }
        val work = Dna.workOn()
        if (work.isNotEmpty()) {
            SectionTitle("Work on these")
            AreaList(work, "Practice") { open("fix:${it.area.name}") }
        }
        if (Dna.slips(null).isNotEmpty()) {
            Column(Modifier.padding(16.dp).fillMaxWidth().card(padding = 16.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
                Text("Fix your mistakes", style = Type.heading)
                Text("${Dna.slips(null).size} positions from your own games where there was a better move.", style = Type.small)
                Pill("Fix them", main = true, modifier = Modifier.testTag("dna-fix")) { open("fix:ALL") }
            }
        }
        Spacer(Modifier.height(24.dp))
    }
}

@Composable
private fun AreaList(list: List<AreaReading>, action: String, onClick: (AreaReading) -> Unit) {
    Column(Modifier.padding(horizontal = 16.dp).fillMaxWidth().card(padding = 6.dp)) {
        for (r in list) {
            Row(Modifier.fillMaxWidth().clickable { onClick(r) }.padding(12.dp), verticalAlignment = Alignment.CenterVertically) {
                Column(Modifier.weight(1f)) {
                    Text(r.title, style = Type.heading.copy(fontSize = 17.sp))
                    Text(r.proof, style = Type.small.copy(fontSize = 12.sp))
                }
                Text("$action ›", style = Type.small.copy(color = Palette.gold, fontWeight = FontWeight.SemiBold))
            }
        }
    }
}
