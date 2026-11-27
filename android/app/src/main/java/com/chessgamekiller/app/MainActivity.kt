package com.chessgamekiller.app

import android.app.Application
import android.graphics.Color as AndroidColor
import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.SystemBarStyle
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import androidx.compose.foundation.isSystemInDarkTheme
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.unit.dp
import com.chessgamekiller.app.analyze.AnalyzeScreen
import com.chessgamekiller.app.analyze.AnalyzeStart
import com.chessgamekiller.app.game.GameScreen
import com.chessgamekiller.app.game.Rival
import com.chessgamekiller.app.home.HomeActions
import com.chessgamekiller.app.home.HomeScreen
import com.chessgamekiller.app.home.ReplayScreen
import com.chessgamekiller.app.ui.BeautyTheme
import com.chessgamekiller.app.ui.GoldButton
import com.chessgamekiller.app.ui.Palette
import com.chessgamekiller.app.ui.QuietButton
import com.chessgamekiller.app.ui.TabKind
import com.chessgamekiller.app.ui.Type

class BeautyApp : Application()

class MainActivity : ComponentActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        Progress.load(this)
        enableEdgeToEdge()
        setContent {
            val dark = when (Progress.appearance) {
                Appearance.SYSTEM -> isSystemInDarkTheme()
                Appearance.LIGHT -> false
                Appearance.DARK -> true
            }
            if (Palette.dark != dark) Palette.dark = dark
            // The clock and battery in ink that reads on the page.
            LaunchedEffect(dark) {
                val style = if (dark) SystemBarStyle.dark(AndroidColor.TRANSPARENT)
                else SystemBarStyle.light(AndroidColor.TRANSPARENT, AndroidColor.TRANSPARENT)
                enableEdgeToEdge(statusBarStyle = style, navigationBarStyle = style)
            }
            BeautyTheme { App() }
        }
    }
}

/** Which screen is up. Kept as plain strings so it survives the app being put away. */
@Composable
fun App() {
    var screen by rememberSaveable { mutableStateOf("home") }
    var tab by rememberSaveable { mutableStateOf(TabKind.TODAY) }
    var rivalName by rememberSaveable { mutableStateOf(Rival.CUB.name) }
    var playWhite by rememberSaveable { mutableStateOf(true) }
    var analyzeFen by rememberSaveable { mutableStateOf<String?>(null) }
    var analyzeStart by rememberSaveable { mutableStateOf(AnalyzeStart.POSITION) }
    var analyzeFrom by rememberSaveable { mutableStateOf("home") }
    var replayId by rememberSaveable { mutableStateOf("") }
    var optionsFor by rememberSaveable { mutableStateOf<String?>(null) }
    var choosingAnalyze by rememberSaveable { mutableStateOf(false) }

    fun play(rival: Rival) {
        rivalName = rival.name
        playWhite = when (Progress.side) {
            SideChoice.WHITE -> true
            SideChoice.BLACK -> false
            SideChoice.RANDOM -> Math.random() < 0.5
        }
        screen = "game"
    }

    fun analyze(start: AnalyzeStart, fen: String? = null, from: String = "home") {
        analyzeFen = fen; analyzeStart = start; analyzeFrom = from; screen = "analyze"
    }

    // One place for the game in the tree, so its state lives on while Analyze sits over it.
    Box {
        if (screen == "game" || (screen == "analyze" && analyzeFrom == "game")) {
            GameScreen(
                rival = Rival.valueOf(rivalName),
                playWhite = playWhite,
                onExit = { screen = "home" },
                onAnalyze = { fen -> analyze(AnalyzeStart.POSITION, fen, "game") },
            )
        }
        if (screen == "replay" || (screen == "analyze" && analyzeFrom == "replay")) {
            ReplayScreen(
                gameId = replayId,
                onExit = { screen = "home" },
                onAnalyze = { fen -> analyze(AnalyzeStart.POSITION, fen, "replay") },
            )
        }
        if (screen == "analyze") {
            AnalyzeScreen(
                start = analyzeStart,
                startFen = analyzeFen,
                onExit = { screen = analyzeFrom },
            )
        }
        if (screen == "home") {
            HomeScreen(
                tab = tab,
                onTab = { tab = it },
                actions = HomeActions(
                    play = ::play,
                    options = { optionsFor = it.name },
                    analyze = { choosingAnalyze = true },
                    scanPhoto = { analyze(AnalyzeStart.PICK_PHOTO) },
                    takePhoto = { analyze(AnalyzeStart.TAKE_PHOTO) },
                    askLeo = { analyze(AnalyzeStart.POSITION) },
                    replay = { replayId = it.id; screen = "replay" },
                ),
            )
        }
    }

    // A rival's Options: which side you take.
    optionsFor?.let { name ->
        val rival = Rival.valueOf(name)
        AlertDialog(
            onDismissRequest = { optionsFor = null },
            containerColor = Palette.card,
            title = { Text(rival.title, style = Type.heading) },
            text = {
                Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
                    Text("Play as", style = Type.small)
                    Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                        for (choice in SideChoice.entries) {
                            val on = Progress.side == choice
                            if (on) GoldButton(choice.label, modifier = Modifier.weight(1f).testTag("option-${choice.name.lowercase()}")) { Progress.chooseSide(choice) }
                            else QuietButton(choice.label, modifier = Modifier.weight(1f).testTag("option-${choice.name.lowercase()}")) { Progress.chooseSide(choice) }
                        }
                    }
                    Text("No clock. ${rival.blurb}", style = Type.small)
                }
            },
            confirmButton = { GoldButton(rival.faceLabel, modifier = Modifier.testTag("option-play")) { optionsFor = null; play(rival) } },
            dismissButton = { QuietButton("Close") { optionsFor = null } },
        )
    }

    // Analyze from the bar: a photo, the camera, or a board to set up.
    if (choosingAnalyze) {
        AlertDialog(
            onDismissRequest = { choosingAnalyze = false },
            containerColor = Palette.card,
            title = { Text("Analyze", style = Type.heading) },
            text = {
                Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
                    Text("Snap any board: a real one or a screenshot. Stockfish shows the best moves, and Leo talks it over.", style = Type.small)
                    GoldButton("Scan a photo", modifier = Modifier.fillMaxWidth().testTag("analyze-photo")) { choosingAnalyze = false; analyze(AnalyzeStart.PICK_PHOTO) }
                    QuietButton("Take a photo", modifier = Modifier.fillMaxWidth().testTag("analyze-camera")) { choosingAnalyze = false; analyze(AnalyzeStart.TAKE_PHOTO) }
                    QuietButton("Set up a board", modifier = Modifier.fillMaxWidth().testTag("home-board")) { choosingAnalyze = false; analyze(AnalyzeStart.POSITION) }
                }
            },
            confirmButton = {},
        )
    }
}
