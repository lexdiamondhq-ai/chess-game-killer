package com.chessgamekiller.app.home

import androidx.compose.foundation.Image
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
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.statusBarsPadding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.chessgamekiller.app.R
import com.chessgamekiller.app.game.Rival
import com.chessgamekiller.app.ui.CarvedLabel
import com.chessgamekiller.app.ui.Fonts
import com.chessgamekiller.app.ui.GoldButton
import com.chessgamekiller.app.ui.Palette
import com.chessgamekiller.app.ui.QuietButton
import com.chessgamekiller.app.ui.Type
import com.chessgamekiller.app.ui.card

enum class SideChoice(val label: String) { WHITE("White"), BLACK("Black"), RANDOM("Either") }

/** Home on Android's first build: the rivals, Analyze, and Leo (inside both). */
@Composable
fun HomeScreen(
    side: SideChoice,
    onSide: (SideChoice) -> Unit,
    onPlay: (Rival) -> Unit,
    onScanPhoto: () -> Unit,
    onTakePhoto: () -> Unit,
    onAnalyzeBoard: () -> Unit,
) {
    Box(Modifier.fillMaxSize().background(Palette.night)) {
        // The dark marble behind Home, fading into the night below.
        Image(
            painterResource(R.drawable.marble_dark),
            contentDescription = null,
            contentScale = ContentScale.Crop,
            modifier = Modifier.fillMaxWidth().height(420.dp).alpha(0.55f),
        )
        Box(
            Modifier.fillMaxWidth().height(420.dp)
                .background(Brush.verticalGradient(listOf(Color.Transparent, Palette.night))),
        )
        Column(
            Modifier
                .fillMaxSize()
                .statusBarsPadding()
                .navigationBarsPadding()
                .verticalScroll(rememberScrollState())
                .padding(horizontal = 16.dp),
        ) {
            Spacer(Modifier.height(28.dp))
            Text(
                "BEAUTY OF CHESS",
                fontFamily = Fonts.carved,
                fontSize = 26.sp,
                letterSpacing = 3.sp,
                color = Palette.goldTop,
                textAlign = TextAlign.Center,
                modifier = Modifier.fillMaxWidth().testTag("home-title"),
            )
            Text(
                "Every piece remembers",
                style = Type.small.copy(color = Palette.inkSoft),
                textAlign = TextAlign.Center,
                modifier = Modifier.fillMaxWidth().padding(top = 4.dp),
            )
            Spacer(Modifier.height(28.dp))

            CarvedLabel("Analyze")
            Spacer(Modifier.height(8.dp))
            Column(Modifier.fillMaxWidth().card(), verticalArrangement = Arrangement.spacedBy(10.dp)) {
                Text("Snap any board", style = Type.heading)
                Text("A photo of a real board or a screenshot. Stockfish shows the best moves, and Leo talks it over.", style = Type.small)
                GoldButton("Scan a photo", modifier = Modifier.fillMaxWidth().testTag("home-scan")) { onScanPhoto() }
                Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    QuietButton("Take a photo", modifier = Modifier.weight(1f).testTag("home-camera")) { onTakePhoto() }
                    QuietButton("Open the board", modifier = Modifier.weight(1f).testTag("home-board")) { onAnalyzeBoard() }
                }
            }

            Spacer(Modifier.height(26.dp))
            Row(verticalAlignment = Alignment.CenterVertically) {
                CarvedLabel("Your rivals", Modifier.weight(1f))
                Text("Play as", style = Type.small)
                Spacer(Modifier.width(6.dp))
                for (choice in SideChoice.entries) {
                    val on = choice == side
                    Text(
                        choice.label,
                        style = Type.small.copy(color = if (on) Palette.onMetal else Palette.inkSoft),
                        modifier = Modifier
                            .padding(start = 4.dp)
                            .clip(RoundedCornerShape(50))
                            .background(if (on) Palette.gold else Color.Transparent)
                            .border(1.dp, Palette.gold.copy(alpha = if (on) 1f else 0.3f), RoundedCornerShape(50))
                            .clickable { onSide(choice) }
                            .padding(horizontal = 10.dp, vertical = 5.dp)
                            .testTag("side-${choice.name.lowercase()}"),
                    )
                }
            }
            Spacer(Modifier.height(8.dp))
            for (rival in Rival.entries) {
                RivalCard(rival) { onPlay(rival) }
                Spacer(Modifier.height(12.dp))
            }

            Text(
                "Premium is free while you test. Every rival is open.",
                style = Type.small.copy(color = Palette.inkFaint),
                textAlign = TextAlign.Center,
                modifier = Modifier.fillMaxWidth().padding(vertical = 16.dp),
            )
        }
    }
}

@Composable
private fun RivalCard(rival: Rival, onPlay: () -> Unit) {
    Row(
        Modifier.fillMaxWidth().card().testTag("rival-${rival.name.lowercase()}"),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Image(
            painterResource(rival.portrait),
            contentDescription = null,
            contentScale = ContentScale.Fit,
            modifier = Modifier.size(80.dp),
        )
        Spacer(Modifier.width(14.dp))
        Column(Modifier.weight(1f)) {
            Row(verticalAlignment = Alignment.Bottom) {
                Text(rival.title, style = Type.heading, modifier = Modifier.weight(1f, fill = false))
                Spacer(Modifier.width(8.dp))
                Text(rival.elo, style = Type.small.copy(color = rival.hue))
            }
            Text(rival.blurb, style = Type.small, maxLines = 2)
            Spacer(Modifier.height(8.dp))
            GoldButton("Face ${rival.title.removePrefix("The ").let { "the $it" }}", modifier = Modifier.testTag("play-${rival.name.lowercase()}")) { onPlay() }
        }
    }
}
