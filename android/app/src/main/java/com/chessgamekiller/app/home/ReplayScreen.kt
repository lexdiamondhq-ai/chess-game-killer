package com.chessgamekiller.app.home

import androidx.activity.compose.BackHandler
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.statusBarsPadding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.chessgamekiller.app.Sounds
import com.chessgamekiller.app.ui.BoardArrow
import com.chessgamekiller.app.ui.ChessBoard
import com.chessgamekiller.app.ui.GoldButton
import com.chessgamekiller.app.ui.Palette
import com.chessgamekiller.app.ui.Pill
import com.chessgamekiller.app.ui.Type
import com.chessgamekiller.chess.Move
import kotlinx.coroutines.delay

/** A famous game to step through, move by move, or to play itself; Analyze takes any position on. */
@Composable
fun ReplayScreen(gameId: String, onExit: () -> Unit, onAnalyze: (String) -> Unit) {
    val context = LocalContext.current
    val game = remember(gameId) { Classics.all(context).firstOrNull { it.id == gameId } }
    BackHandler { onExit() }
    if (game == null) { LaunchedEffect(Unit) { onExit() }; return }
    val sounds = remember { Sounds(context) }
    val frames = game.frames
    // Starts on the finish, as Home's card does: the last seven moves.
    var ply by rememberSaveable(gameId) { mutableIntStateOf((frames.size - 1 - 7).coerceAtLeast(0)) }
    var playing by remember { mutableStateOf(false) }

    fun go(to: Int) {
        val next = to.coerceIn(0, frames.size - 1)
        if (next == ply + 1) {
            val before = frames[ply]
            game.moves.getOrNull(ply)?.let { Move.fromUci(it) }?.let { sounds.playMove(before.san(before.normalize(it))) }
        }
        ply = next
    }

    LaunchedEffect(playing) {
        while (playing) {
            delay(1300)
            if (ply >= frames.size - 1) { playing = false } else go(ply + 1)
        }
    }

    val last = game.moves.getOrNull(ply - 1)?.let { Move.fromUci(it) }
    Column(
        Modifier.fillMaxSize().background(Palette.night).statusBarsPadding().navigationBarsPadding()
            .verticalScroll(rememberScrollState()).testTag("replay"),
    ) {
        Row(Modifier.fillMaxWidth().padding(horizontal = 6.dp, vertical = 4.dp), verticalAlignment = Alignment.CenterVertically) {
            IconButton(onClick = onExit, modifier = Modifier.testTag("replay-back")) {
                Icon(Icons.AutoMirrored.Filled.ArrowBack, contentDescription = "Back", tint = Palette.ink)
            }
            Column(Modifier.weight(1f)) {
                Text("FAMOUS GAME", style = Type.small.copy(fontSize = 10.sp, fontWeight = FontWeight.Bold, letterSpacing = 1.2.sp, color = Palette.gold))
                Text(game.title, style = Type.title.copy(fontSize = 22.sp, fontWeight = FontWeight.Normal), maxLines = 1)
            }
        }
        Text(game.players, style = Type.small, modifier = Modifier.padding(horizontal = 20.dp))
        Spacer(Modifier.height(10.dp))
        ChessBoard(
            position = frames[ply],
            flipped = game.flipped,
            lastMove = last,
            interactive = false,
            modifier = Modifier.padding(horizontal = 6.dp),
        )
        Text(
            if (ply == 0) "The start" else "Move ${(ply + 1) / 2}${if (ply % 2 == 1) "" else "..."} of ${(frames.size) / 2}",
            style = Type.small, modifier = Modifier.padding(horizontal = 20.dp, vertical = 10.dp),
        )
        Row(Modifier.fillMaxWidth().padding(horizontal = 16.dp), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            Pill("⏮") { playing = false; go(0) }
            Pill("◀", modifier = Modifier.testTag("replay-prev")) { playing = false; go(ply - 1) }
            Pill(if (playing) "Pause" else "Play", main = true, modifier = Modifier.testTag("replay-play")) { playing = !playing }
            Pill("▶", modifier = Modifier.testTag("replay-next")) { playing = false; go(ply + 1) }
            Pill("⏭") { playing = false; go(frames.size - 1) }
        }
        Text(game.story, style = Type.body, modifier = Modifier.padding(20.dp))
        GoldButton("Analyze this position", modifier = Modifier.fillMaxWidth().padding(horizontal = 16.dp).testTag("replay-analyze")) {
            onAnalyze(frames[ply].fen)
        }
        Spacer(Modifier.height(24.dp))
    }
}
