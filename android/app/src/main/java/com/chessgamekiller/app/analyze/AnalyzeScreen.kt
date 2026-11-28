package com.chessgamekiller.app.analyze

import android.net.Uri
import androidx.activity.compose.BackHandler
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.PickVisualMediaRequest
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.gestures.detectTapGestures
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
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
import androidx.compose.material.icons.filled.Delete
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateListOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.compose.ui.graphics.Color
import androidx.compose.foundation.layout.aspectRatio
import androidx.core.content.FileProvider
import com.chessgamekiller.app.engine.EngineLine
import com.chessgamekiller.app.engine.Engines
import com.chessgamekiller.app.leo.LeoClient
import com.chessgamekiller.app.leo.LeoPanel
import com.chessgamekiller.app.leo.LeoReply
import com.chessgamekiller.app.leo.TalkContext
import com.chessgamekiller.app.ui.BoardArrow
import com.chessgamekiller.app.ui.CarvedLabel
import com.chessgamekiller.app.ui.ChessBoard
import com.chessgamekiller.app.ui.GoldButton
import com.chessgamekiller.app.ui.Palette
import com.chessgamekiller.app.ui.QuietButton
import com.chessgamekiller.app.ui.Type
import com.chessgamekiller.app.ui.card
import com.chessgamekiller.app.ui.pieceDrawable
import com.chessgamekiller.chess.Move
import com.chessgamekiller.chess.Position
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import java.io.File
import kotlin.math.exp

/** How Analyze opens: straight to the photo picker, the camera, or a position (from a game or the start). */
enum class AnalyzeStart { PICK_PHOTO, TAKE_PHOTO, POSITION }

/**
 * Analyze: a photo or any position, Stockfish's best lines, and Leo to talk it over.
 * Edit pieces and Rotate fix what the scanner misread, as on the iPhone.
 */
@Composable
fun AnalyzeScreen(start: AnalyzeStart, startFen: String?, onExit: () -> Unit) {
    val context = LocalContext.current
    val engine = remember { Engines.get(context) }
    val scanner = remember { Scanner(context) }
    val leo = remember { LeoClient(context, engine) }
    DisposableEffect(Unit) { onDispose { leo.close() } }
    val scope = rememberCoroutineScope()

    val initial = remember { (startFen?.let { Position.fromFen(it) } ?: Position.start()) }
    var cells by remember { mutableStateOf(initial.board()) }
    var whiteToMove by remember { mutableStateOf(initial.whiteToMove) }
    var castlingFen by remember { mutableStateOf(initial.fen) }
    var flipped by remember { mutableStateOf(false) }
    var editing by remember { mutableStateOf(false) }
    var brush by remember { mutableStateOf<Char?>(null) }
    val explored = remember { mutableStateListOf<Position>() }
    var lastMove by remember { mutableStateOf<Move?>(null) }

    var scanning by remember { mutableStateOf(false) }
    var scanNote by remember { mutableStateOf<String?>(null) }
    var lines by remember { mutableStateOf<List<EngineLine>>(emptyList()) }
    var thinking by remember { mutableStateOf(false) }
    var leoReply by remember { mutableStateOf<LeoReply?>(null) }
    var leoBusy by remember { mutableStateOf(false) }

    // The position on the board: the base (from the photo or edits) or the moves tried on it.
    val base: Position? = remember(cells.concatToString(), whiteToMove, castlingFen) {
        // Keep the given position's castling and en passant when the board is unchanged.
        Position.fromFen(castlingFen)?.takeIf { it.board().contentEquals(cells) && it.whiteToMove == whiteToMove }
            ?: Position.fromCells(cells, whiteToMove)
    }
    val position: Position? = explored.lastOrNull() ?: base

    fun applyReading(reading: Reading) {
        cells = reading.cells
        whiteToMove = reading.whiteToMove
        castlingFen = ""
        explored.clear(); lastMove = null; leoReply = null
        flipped = false
        val valid = Position.fromCells(reading.cells, reading.whiteToMove) != null
        scanNote = when {
            !valid -> "Some pieces look off. Tap Edit pieces to fix them."
            !reading.sureOfTurn -> "Check whose move it is below."
            reading.confidence == "low" -> "The photo was hard to read. Check the pieces."
            else -> null
        }
        if (!valid) editing = true
    }

    fun scan(uri: Uri) {
        scanning = true; scanNote = null
        scope.launch {
            try {
                applyReading(scanner.read(uri))
            } catch (e: ScanException) {
                scanNote = e.message
            }
            scanning = false
        }
    }

    val pick = rememberLauncherForActivityResult(ActivityResultContracts.PickVisualMedia()) { uri ->
        if (uri != null) scan(uri)
    }
    var photoUri by remember { mutableStateOf<Uri?>(null) }
    val shoot = rememberLauncherForActivityResult(ActivityResultContracts.TakePicture()) { ok ->
        val uri = photoUri
        if (ok && uri != null) scan(uri)
    }
    fun takePhoto() {
        val dir = File(context.cacheDir, "photos").apply { mkdirs() }
        val file = File(dir, "board-${System.currentTimeMillis()}.jpg")
        val uri = FileProvider.getUriForFile(context, "${context.packageName}.photos", file)
        photoUri = uri
        runCatching { shoot.launch(uri) }
    }
    fun pickPhoto() = runCatching { pick.launch(PickVisualMediaRequest(ActivityResultContracts.PickVisualMedia.ImageOnly)) }

    LaunchedEffect(Unit) {
        when (start) {
            AnalyzeStart.PICK_PHOTO -> pickPhoto()
            AnalyzeStart.TAKE_PHOTO -> takePhoto()
            AnalyzeStart.POSITION -> Unit
        }
    }

    // Stockfish on every new position, after a beat so quick taps don't pile up.
    val fen = if (editing) null else position?.fen
    LaunchedEffect(fen) {
        lines = emptyList()
        if (fen == null) return@LaunchedEffect
        val p = Position.fromFen(fen) ?: return@LaunchedEffect
        if (p.legalMoves().isEmpty()) return@LaunchedEffect
        delay(150)
        thinking = true
        lines = engine.analyze(fen, 18, 3, 2500)
        thinking = false
    }

    BackHandler {
        if (explored.isNotEmpty()) { explored.removeAt(explored.size - 1); lastMove = null } else onExit()
    }

    val best = lines.firstOrNull()
    val whiteShare: Float = run {
        val e = best?.eval ?: return@run 0.5f
        val pov = if (position?.whiteToMove != false) e else e.flipped()
        if (pov.mate != null) (if (pov.mate > 0) 1f else 0f)
        else (1f / (1f + exp(-0.00368208f * (pov.cp ?: 0)))).toFloat()
    }

    // Solid and touch-tight: a game may sit underneath.
    Box(
        Modifier
            .fillMaxSize()
            .background(Palette.night)
            // Eats taps that miss every control, without folding the screen into one button for tests and TalkBack.
            .pointerInput(Unit) { detectTapGestures { } },
    ) {
        Column(
            Modifier.fillMaxSize().statusBarsPadding().navigationBarsPadding().verticalScroll(rememberScrollState()),
        ) {
            Row(Modifier.fillMaxWidth().padding(horizontal = 8.dp, vertical = 6.dp), verticalAlignment = Alignment.CenterVertically) {
                IconButton(onClick = onExit, modifier = Modifier.testTag("analyze-back")) {
                    Icon(Icons.AutoMirrored.Filled.ArrowBack, contentDescription = "Back", tint = Palette.ink)
                }
                Text("Analyze", style = Type.title.copy(fontSize = 26.sp), modifier = Modifier.weight(1f))
                if (scanning) CircularProgressIndicator(color = Palette.gold, strokeWidth = 2.dp, modifier = Modifier.size(22.dp).padding(end = 4.dp))
            }

            if (!editing) {
                // Who is better: White's share of the bar, from the left.
                Box(
                    Modifier.fillMaxWidth().padding(horizontal = 6.dp, vertical = 4.dp).height(6.dp)
                        .clip(RoundedCornerShape(3.dp)).background(Color(0xFF151210)).testTag("eval-bar"),
                ) {
                    Box(Modifier.fillMaxHeight().fillMaxWidth(whiteShare.coerceIn(0.02f, 0.98f)).background(Palette.ink))
                }
            }
            Row(Modifier.fillMaxWidth().padding(horizontal = 6.dp)) {
                Box(Modifier.weight(1f)) {
                    val shown = if (editing || position == null) Position.fromCells(cells, whiteToMove) else position
                    if (shown != null) {
                        ChessBoard(
                            position = shown,
                            flipped = flipped,
                            lastMove = lastMove,
                            arrows = leoReply?.arrows?.takeIf { it.isNotEmpty() }
                                ?: best?.moves?.firstOrNull()?.let { Move.fromUci(it) }?.let { listOf(BoardArrow(it.from, it.to, BoardArrow.Tone.BEST)) }
                                ?: emptyList(),
                            highlights = leoReply?.squares ?: emptySet(),
                            interactive = !editing,
                            onMove = { m ->
                                val now = position ?: return@ChessBoard
                                if (now.isLegal(m)) {
                                    explored.add(now.play(m)); lastMove = now.normalize(m); leoReply = null
                                }
                            },
                            onSquareTap = if (editing) ({ sq -> cells = cells.copyOf().also { it[sq] = brush ?: '.' }; castlingFen = "" }) else null,
                        )
                    } else {
                        EditorBoard(cells, flipped) { sq -> cells = cells.copyOf().also { it[sq] = brush ?: '.' }; castlingFen = "" }
                    }
                }
            }

            scanNote?.let {
                Text(it, style = Type.small.copy(color = Palette.gold), modifier = Modifier.padding(horizontal = 16.dp, vertical = 8.dp).testTag("scan-note"))
            }

            if (editing) {
                PiecePalette(brush) { brush = it }
            }

            Row(
                Modifier.fillMaxWidth().padding(horizontal = 12.dp, vertical = 8.dp),
                horizontalArrangement = Arrangement.spacedBy(8.dp),
            ) {
                QuietButton(if (editing) "Done" else "Edit pieces", modifier = Modifier.weight(1f).testTag("edit-pieces")) {
                    if (editing) {
                        if (Position.fromCells(cells, whiteToMove) == null) {
                            scanNote = "Each side needs one king, and the side not to move can't be in check."
                        } else { editing = false; scanNote = null; explored.clear(); lastMove = null }
                    } else { editing = true; explored.clear(); lastMove = null; leoReply = null }
                }
                QuietButton("Rotate", modifier = Modifier.weight(1f).testTag("rotate")) { flipped = !flipped }
                QuietButton(if (whiteToMove) "White to move" else "Black to move", modifier = Modifier.weight(1.3f).testTag("side-to-move")) {
                    whiteToMove = !whiteToMove; castlingFen = ""; explored.clear(); lastMove = null; leoReply = null
                }
            }
            Row(
                Modifier.fillMaxWidth().padding(horizontal = 12.dp),
                horizontalArrangement = Arrangement.spacedBy(8.dp),
            ) {
                QuietButton("Photo", modifier = Modifier.weight(1f).testTag("analyze-photo")) { pickPhoto() }
                QuietButton("Camera", modifier = Modifier.weight(1f).testTag("analyze-camera")) { takePhoto() }
                QuietButton("Undo move", enabled = explored.isNotEmpty(), modifier = Modifier.weight(1f).testTag("analyze-undo")) {
                    explored.removeAt(explored.size - 1); lastMove = null; leoReply = null
                }
            }

            if (!editing && position != null) {
                Column(Modifier.padding(12.dp).fillMaxWidth().card(), verticalArrangement = Arrangement.spacedBy(6.dp)) {
                    Row(verticalAlignment = Alignment.CenterVertically) {
                        CarvedLabel("Stockfish")
                        Spacer(Modifier.width(8.dp))
                        if (thinking) Text("thinking…", style = Type.small)
                    }
                    if (position.legalMoves().isEmpty()) {
                        Text(if (position.inCheck) "Checkmate." else "Stalemate.", style = Type.body)
                    }
                    lines.forEachIndexed { i, line ->
                        val pov = if (position.whiteToMove) line.eval else line.eval.flipped()
                        Row(Modifier.testTag("engine-line-$i")) {
                            Text(pov.label(), style = Type.button.copy(color = if (i == 0) Palette.gold else Palette.inkSoft, fontSize = 14.sp), modifier = Modifier.width(56.dp))
                            Text(lineSan(position, line), style = Type.body, maxLines = 1)
                        }
                    }
                }
                LeoPanel(
                    reply = leoReply,
                    busy = leoBusy,
                    prompt = "Ask Leo about this position",
                    modifier = Modifier.padding(horizontal = 12.dp),
                    onAsk = { said, typed ->
                        if (leoBusy) return@LeoPanel
                        leoBusy = true
                        leoReply = LeoReply()
                        val here = position.fen
                        scope.launch {
                            leo.talk(here, said, typed, reveal = true, talkContext = TalkContext.ANALYSIS,
                                lastMove = lastMove?.uci, voice = true) { leoReply = it }
                            leoBusy = false
                        }
                    },
                )
            }
            if (!editing && position == null) {
                GoldButton("Fix the pieces", modifier = Modifier.padding(16.dp).fillMaxWidth()) { editing = true }
            }
            Spacer(Modifier.height(24.dp))
        }
    }
}

/** "e4 e5 Nf3 Nc6": a line's first moves in standard notation. */
private fun lineSan(start: Position, line: EngineLine): String {
    var p = start
    val words = mutableListOf<String>()
    for (uci in line.moves.take(8)) {
        val m = Move.fromUci(uci) ?: break
        if (!p.isLegal(m)) break
        words.add(p.san(m))
        p = p.play(m)
    }
    return words.joinToString(" ")
}

/** The pieces to place while editing, and the eraser. */
@Composable
private fun PiecePalette(brush: Char?, onPick: (Char?) -> Unit) {
    Column(Modifier.padding(horizontal = 12.dp, vertical = 4.dp)) {
        for (row in listOf("KQRBNP", "kqrbnp")) {
            Row(horizontalArrangement = Arrangement.spacedBy(4.dp)) {
                for (c in row) {
                    Box(
                        Modifier
                            .size(44.dp)
                            .clip(RoundedCornerShape(10.dp))
                            .background(if (brush == c) Palette.gold.copy(alpha = 0.35f) else Palette.card)
                            .border(1.dp, if (brush == c) Palette.gold else Palette.gold.copy(alpha = 0.2f), RoundedCornerShape(10.dp))
                            .clickable { onPick(c) }
                            .testTag("brush-$c"),
                        contentAlignment = Alignment.Center,
                    ) {
                        Image(painterResource(pieceDrawable(c)), contentDescription = null, modifier = Modifier.size(36.dp))
                    }
                }
                if (row.first() == 'K') {
                    Box(
                        Modifier
                            .size(44.dp)
                            .clip(RoundedCornerShape(10.dp))
                            .background(if (brush == null) Palette.gold.copy(alpha = 0.35f) else Palette.card)
                            .clickable { onPick(null) }
                            .testTag("brush-erase"),
                        contentAlignment = Alignment.Center,
                    ) { Icon(Icons.Filled.Delete, contentDescription = "Erase", tint = Palette.ink) }
                }
            }
            Spacer(Modifier.height(4.dp))
        }
        Text("Pick a piece, then tap squares to place it.", style = Type.small)
    }
}

/** A board that can't be played yet (a king missing): only taps for editing. */
@Composable
private fun EditorBoard(cells: CharArray, flipped: Boolean, onTap: (Int) -> Unit) {
    Column(Modifier.fillMaxWidth().clip(RoundedCornerShape(6.dp))) {
        for (row in 0..7) {
            Row(Modifier.fillMaxWidth()) {
                for (col in 0..7) {
                    val file = if (flipped) 7 - col else col
                    val rank = if (flipped) row else 7 - row
                    val sq = rank * 8 + file
                    Box(
                        Modifier
                            .weight(1f)
                            .aspectSquare()
                            .background(if ((file + rank) % 2 == 1) Palette.lightSquare else Palette.darkSquare)
                            .clickable { onTap(sq) }
                            .testTag("square-${'a' + file}${'1' + rank}"),
                    ) {
                        val c = cells[sq]
                        if (c != '.') Image(painterResource(pieceDrawable(c)), contentDescription = null, modifier = Modifier.fillMaxSize())
                    }
                }
            }
        }
    }
}

private fun Modifier.aspectSquare() = this.then(Modifier.aspectRatio(1f))
