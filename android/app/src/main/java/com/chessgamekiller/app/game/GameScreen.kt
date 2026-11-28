package com.chessgamekiller.app.game

import androidx.activity.compose.BackHandler
import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.statusBarsPadding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material3.AlertDialog
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
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.chessgamekiller.app.Progress
import com.chessgamekiller.app.Sounds
import com.chessgamekiller.app.ui.KnightGlyph
import com.chessgamekiller.app.ui.RivalFrame
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontWeight
import com.chessgamekiller.app.engine.Engines
import com.chessgamekiller.app.leo.LeoClient
import com.chessgamekiller.app.leo.LeoPanel
import com.chessgamekiller.app.leo.LeoReply
import com.chessgamekiller.app.leo.TalkContext
import com.chessgamekiller.app.ui.ChessBoard
import com.chessgamekiller.app.ui.GoldButton
import com.chessgamekiller.app.ui.Palette
import com.chessgamekiller.app.ui.QuietButton
import com.chessgamekiller.app.ui.Type
import com.chessgamekiller.chess.Game
import com.chessgamekiller.chess.GameStatus
import com.chessgamekiller.chess.Move
import kotlinx.coroutines.Job
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch

/** A game against one rival: you, the board, the rival's moves from Stockfish, and Leo to talk it through. */
@Composable
fun GameScreen(rival: Rival, playWhite: Boolean, onExit: () -> Unit, onAnalyze: (String) -> Unit) {
    val context = LocalContext.current
    val engine = remember { Engines.get(context) }
    val sounds = remember { Sounds(context) }
    val leo = remember { LeoClient(context, engine) }
    DisposableEffect(Unit) { onDispose { leo.close() } }
    val scope = rememberCoroutineScope()

    var game by remember { mutableStateOf(Game()) }
    var version by remember { mutableIntStateOf(0) }
    var thinking by remember { mutableStateOf(false) }
    var resigned by remember { mutableStateOf(false) }
    var showEnd by remember { mutableStateOf(false) }
    var confirmResign by remember { mutableStateOf(false) }
    var leoReply by remember { mutableStateOf<LeoReply?>(null) }
    var leoBusy by remember { mutableStateOf(false) }
    var rivalJob by remember { mutableStateOf<Job?>(null) }
    /** The result is counted once per game, for your rating and the rivals you've beaten. */
    var recorded by remember { mutableStateOf(false) }

    // Read version so the screen redraws after every move.
    @Suppress("UNUSED_VARIABLE") val tick = version
    val position = game.position
    val playerToMove = position.whiteToMove == playWhite
    val over = game.isOver || resigned

    fun finished() {
        if (game.isOver) {
            val won = game.whiteWon?.let { it == playWhite }
            sounds.playEnd(won)
            showEnd = true
            if (!recorded) {
                recorded = true
                val score = when (won) { true -> 1.0; false -> 0.0; null -> 0.5 }
                Progress.record(rival, score)
                // Chess DNA: Leo reads the game's moves in the background.
                com.chessgamekiller.app.learn.Dna.recordGame(context, rival.name, playWhite, game.moves.map { it.move.uci }, score)
            }
        }
    }

    fun rivalMove() {
        if (game.isOver || resigned) return
        thinking = true
        rivalJob = scope.launch {
            val started = System.currentTimeMillis()
            val fen = game.position.fen
            val uci = engine.chooseMove(fen, rival.skill, rival.depth, rival.thinkTimeMs)
                ?: engine.chooseMove(fen, rival.skill, rival.depth, rival.thinkTimeMs * 2)
            // A short pause so a reply doesn't land the instant you let go.
            val waited = System.currentTimeMillis() - started
            if (waited < 450) delay(450 - waited)
            if (uci != null && game.position.fen == fen) {
                game.playUci(uci)?.let { sounds.playMove(it.san) }
                version++
            }
            thinking = false
            finished()
        }
    }

    fun play(move: Move) {
        if (!playerToMove || thinking || over) return
        val played = runCatching { game.play(move) }.getOrNull() ?: return
        sounds.playMove(played.san)
        leoReply = null
        version++
        finished()
        rivalMove()
    }

    fun takeBack() {
        rivalJob?.cancel(); thinking = false
        // Back to the player's own turn: one or two moves.
        if (game.moves.isEmpty()) return
        game.undo()
        if (game.position.whiteToMove != playWhite && game.moves.isNotEmpty()) game.undo()
        if (game.position.whiteToMove != playWhite) rivalMove()
        leoReply = null
        version++
    }

    fun newGame() {
        rivalJob?.cancel(); thinking = false
        game = Game(); resigned = false; showEnd = false; leoReply = null; recorded = false
        version++
        if (!playWhite) rivalMove()
    }

    LaunchedEffect(Unit) { if (!playWhite) rivalMove() }
    BackHandler { rivalJob?.cancel(); onExit() }

    Box(Modifier.fillMaxSize().background(Palette.night)) {
        Column(
            Modifier
                .fillMaxSize()
                .statusBarsPadding()
                .navigationBarsPadding()
                .verticalScroll(rememberScrollState()),
        ) {
            // The rival across the board.
            Row(
                Modifier.fillMaxWidth().padding(horizontal = 8.dp, vertical = 6.dp),
                verticalAlignment = Alignment.CenterVertically,
            ) {
                IconButton(onClick = { rivalJob?.cancel(); onExit() }, modifier = Modifier.testTag("game-back")) {
                    Icon(Icons.AutoMirrored.Filled.ArrowBack, contentDescription = "Back", tint = Palette.ink)
                }
                RivalFrame(rival, 50.dp)
                Spacer(Modifier.width(12.dp))
                Column(Modifier.weight(1f)) {
                    Text(rival.title, style = Type.title.copy(fontSize = 22.sp, fontWeight = FontWeight.Normal))
                    Text(
                        when {
                            thinking -> "Thinking…"
                            over -> statusText(game.status, resigned, playWhite, game.whiteWon)
                            playerToMove -> "Your move"
                            else -> rival.elo
                        },
                        style = Type.small.copy(color = if (playerToMove && !over) Palette.gold else Palette.inkSoft),
                        modifier = Modifier.testTag("game-status"),
                    )
                }
            }

            ChessBoard(
                position = position,
                flipped = !playWhite,
                lastMove = game.lastMove,
                arrows = leoReply?.arrows ?: emptyList(),
                highlights = leoReply?.squares ?: emptySet(),
                interactive = playerToMove && !thinking && !over,
                onMove = ::play,
                modifier = Modifier.padding(horizontal = 6.dp),
            )

            // You, across the board from the rival.
            Row(
                Modifier.fillMaxWidth().padding(horizontal = 16.dp, vertical = 10.dp),
                verticalAlignment = Alignment.CenterVertically,
            ) {
                Box(
                    Modifier.size(36.dp).clip(CircleShape)
                        .background(Brush.radialGradient(listOf(Palette.goldTop, Palette.goldFoot)))
                        .border(1.dp, Color.White.copy(alpha = 0.35f), CircleShape),
                    contentAlignment = Alignment.Center,
                ) { KnightGlyph(Modifier.size(18.dp, 22.dp)) }
                Spacer(Modifier.width(10.dp))
                Column(Modifier.weight(1f)) {
                    Text("You", style = Type.heading.copy(fontSize = 18.sp))
                    Text(
                        (if (playWhite) "White" else "Black") + " · " + (Progress.rating?.let { "Rating $it" } ?: "New"),
                        style = Type.small.copy(fontSize = 12.sp),
                    )
                }
            }

            // The moves so far.
            Text(
                game.pgnMoves().ifEmpty { if (playWhite) "You have White. Tap a piece, then its square." else "You have Black." },
                style = Type.small,
                maxLines = 1,
                modifier = Modifier
                    .fillMaxWidth()
                    .horizontalScroll(rememberScrollState(), reverseScrolling = true)
                    .padding(horizontal = 16.dp, vertical = 10.dp)
                    .testTag("move-list"),
            )

            Row(
                Modifier.fillMaxWidth().padding(horizontal = 16.dp),
                horizontalArrangement = Arrangement.spacedBy(8.dp),
            ) {
                QuietButton("Take back", enabled = game.moves.isNotEmpty() && !over, modifier = Modifier.weight(1f).testTag("take-back")) { takeBack() }
                QuietButton("Analyze", modifier = Modifier.weight(1f).testTag("game-analyze")) { onAnalyze(game.position.fen) }
                QuietButton("Resign", enabled = !over && game.moves.isNotEmpty(), modifier = Modifier.weight(1f).testTag("resign")) { confirmResign = true }
            }

            Spacer(Modifier.height(12.dp))
            if (!over) {
                LeoPanel(
                    reply = leoReply,
                    busy = leoBusy,
                    modifier = Modifier.padding(horizontal = 12.dp),
                    onAsk = { said, typed ->
                        if (leoBusy) return@LeoPanel
                        leoBusy = true
                        leoReply = LeoReply()
                        val fen = game.position.fen
                        scope.launch {
                            leo.talk(
                                fen = fen, said = said, typed = typed, reveal = true,
                                talkContext = TalkContext.GAME,
                                lastMove = game.lastMove?.uci, voice = true,
                            ) { leoReply = it }
                            leoBusy = false
                        }
                    },
                )
            } else {
                GoldButton("Play again", modifier = Modifier.fillMaxWidth().padding(horizontal = 16.dp).testTag("play-again")) { newGame() }
            }
            Spacer(Modifier.height(24.dp))
        }
    }

    if (confirmResign) {
        AlertDialog(
            onDismissRequest = { confirmResign = false },
            containerColor = Palette.card,
            title = { Text("Resign this game?", style = Type.heading) },
            text = { Text("${rival.title} takes the win.", style = Type.body) },
            confirmButton = {
                QuietButton("Resign", modifier = Modifier.testTag("resign-confirm")) {
                    confirmResign = false
                    rivalJob?.cancel(); thinking = false
                    resigned = true; showEnd = true
                    sounds.playEnd(false)
                    if (!recorded) {
                        recorded = true
                        Progress.record(rival, 0.0)
                        com.chessgamekiller.app.learn.Dna.recordGame(context, rival.name, playWhite, game.moves.map { it.move.uci }, 0.0)
                    }
                }
            },
            dismissButton = { QuietButton("Keep playing") { confirmResign = false } },
        )
    }

    if (showEnd) {
        val text = statusText(game.status, resigned, playWhite, game.whiteWon)
        AlertDialog(
            onDismissRequest = { showEnd = false },
            containerColor = Palette.card,
            title = { Text(text, style = Type.title.copy(fontSize = 24.sp)) },
            text = { Text(game.pgnMoves().takeLast(120), style = Type.small) },
            confirmButton = { GoldButton("Play again", modifier = Modifier.testTag("end-play-again")) { newGame() } },
            dismissButton = { QuietButton("Look at the board") { showEnd = false } },
        )
    }
}

fun statusText(status: GameStatus, resigned: Boolean, playWhite: Boolean, whiteWon: Boolean?): String = when {
    resigned -> "You resigned"
    status == GameStatus.CHECKMATE -> if (whiteWon == playWhite) "You won by checkmate" else "Checkmate. You lost"
    status == GameStatus.STALEMATE -> "Draw by stalemate"
    status == GameStatus.REPETITION -> "Draw by repetition"
    status == GameStatus.FIFTY_MOVES -> "Draw by the 50-move rule"
    status == GameStatus.INSUFFICIENT_MATERIAL -> "Draw: nobody can mate"
    else -> ""
}
