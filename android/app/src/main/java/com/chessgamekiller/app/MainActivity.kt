package com.chessgamekiller.app

import android.app.Application
import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import androidx.compose.foundation.layout.Box
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import com.chessgamekiller.app.analyze.AnalyzeScreen
import com.chessgamekiller.app.analyze.AnalyzeStart
import com.chessgamekiller.app.game.GameScreen
import com.chessgamekiller.app.game.Rival
import com.chessgamekiller.app.home.HomeScreen
import com.chessgamekiller.app.home.SideChoice
import com.chessgamekiller.app.ui.BeautyTheme

class BeautyApp : Application()

class MainActivity : ComponentActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        enableEdgeToEdge()
        setContent { BeautyTheme { App() } }
    }
}

/** Which screen is up. Kept as plain strings so it survives the app being put away. */
@Composable
fun App() {
    var screen by rememberSaveable { mutableStateOf("home") }
    var rivalName by rememberSaveable { mutableStateOf(Rival.CUB.name) }
    var playWhite by rememberSaveable { mutableStateOf(true) }
    var side by rememberSaveable { mutableStateOf(SideChoice.WHITE) }
    var analyzeFen by rememberSaveable { mutableStateOf<String?>(null) }
    var analyzeStart by rememberSaveable { mutableStateOf(AnalyzeStart.POSITION) }
    var analyzeFrom by rememberSaveable { mutableStateOf("home") }


    // One place for the game in the tree, so its state lives on while Analyze sits over it.
    Box {
        if (screen == "game" || (screen == "analyze" && analyzeFrom == "game")) {
            GameScreen(
                rival = Rival.valueOf(rivalName),
                playWhite = playWhite,
                onExit = { screen = "home" },
                onAnalyze = { fen ->
                    analyzeFen = fen; analyzeStart = AnalyzeStart.POSITION; analyzeFrom = "game"; screen = "analyze"
                },
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
                side = side,
                onSide = { side = it },
                onPlay = { rival ->
                    rivalName = rival.name
                    playWhite = when (side) {
                        SideChoice.WHITE -> true
                        SideChoice.BLACK -> false
                        SideChoice.RANDOM -> Math.random() < 0.5
                    }
                    screen = "game"
                },
                onScanPhoto = { analyzeFen = null; analyzeStart = AnalyzeStart.PICK_PHOTO; analyzeFrom = "home"; screen = "analyze" },
                onTakePhoto = { analyzeFen = null; analyzeStart = AnalyzeStart.TAKE_PHOTO; analyzeFrom = "home"; screen = "analyze" },
                onAnalyzeBoard = { analyzeFen = null; analyzeStart = AnalyzeStart.POSITION; analyzeFrom = "home"; screen = "analyze" },
            )
        }
    }
}
