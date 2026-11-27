package com.chessgamekiller.app.home

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ColumnScope
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
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.Switch
import androidx.compose.material3.SwitchDefaults
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.chessgamekiller.app.Appearance
import com.chessgamekiller.app.BuildConfig
import com.chessgamekiller.app.Progress
import com.chessgamekiller.app.SideChoice
import com.chessgamekiller.app.game.Rival
import com.chessgamekiller.app.ui.ChessBoard
import com.chessgamekiller.app.ui.GoldButton
import com.chessgamekiller.app.ui.Palette
import com.chessgamekiller.app.ui.Pill
import com.chessgamekiller.app.ui.RivalFrame
import com.chessgamekiller.app.ui.ScanGlyph
import com.chessgamekiller.app.ui.SectionTitle
import com.chessgamekiller.app.ui.TabIcon
import com.chessgamekiller.app.ui.TabKind
import com.chessgamekiller.app.ui.Type
import com.chessgamekiller.app.ui.card

/** A tab's page: the room's soft light at the top, a serif title, then its groups. */
@Composable
private fun Page(title: String, tag: String, content: @Composable ColumnScope.() -> Unit) {
    Box(Modifier.fillMaxSize()) {
        // A breath of amethyst from the left and rose from the right, as on every iPhone screen.
        Box(
            Modifier.fillMaxWidth().height(260.dp).background(
                Brush.verticalGradient(
                    listOf(
                        if (Palette.dark) Color(0x332B1F4A) else Color(0x22B8A4F0),
                        Color.Transparent,
                    ),
                ),
            ),
        )
        Column(
            Modifier.fillMaxSize().verticalScroll(rememberScrollState()).statusBarsPadding().testTag(tag),
        ) {
            Text(
                title,
                style = Type.title.copy(fontSize = 34.sp),
                modifier = Modifier.padding(start = 20.dp, end = 20.dp, top = 18.dp),
            )
            content()
            Spacer(Modifier.navigationBarsPadding().height(110.dp))
        }
    }
}

// MARK: - Learn

@Composable
fun LearnPage(actions: HomeActions) {
    Page("Learn", "page-learn") {
        SectionTitle("With Coach Leo")
        Column(Modifier.padding(horizontal = 16.dp).fillMaxWidth().card(glow = Palette.teal), verticalArrangement = Arrangement.spacedBy(10.dp)) {
            Row(verticalAlignment = Alignment.CenterVertically) {
                JewelTile(Jewel.JADE) { TabIcon(TabKind.LEARN, JewelGold, Modifier.size(26.dp)) }
                Spacer(Modifier.width(12.dp))
                Column(Modifier.weight(1f)) {
                    Text("COACH LEO", style = Type.small.copy(fontSize = 10.sp, fontWeight = FontWeight.Bold, letterSpacing = 1.2.sp, color = Palette.teal))
                    Text("Talk any position through", style = Type.title.copy(fontSize = 20.sp, fontWeight = FontWeight.Normal))
                }
            }
            Text(
                "Set up a board or snap a photo of one, then ask Leo why a move works. He answers out loud and draws on the board.",
                style = Type.small.copy(fontSize = 13.sp),
            )
            GoldButton("Ask Leo", modifier = Modifier.fillMaxWidth().testTag("learn-leo")) { actions.askLeo() }
        }
        SectionTitle("Coming to Android")
        Column(Modifier.padding(horizontal = 16.dp).fillMaxWidth().card(), verticalArrangement = Arrangement.spacedBy(12.dp)) {
            Text(
                "These are on the iPhone and on their way here:",
                style = Type.small.copy(fontSize = 13.sp),
            )
            for ((name, what) in listOf(
                "The Gilded Vine" to "Lessons from Pawn to King",
                "Today's Move" to "One position a day, with a streak",
                "Puzzles" to "Tactics at your level",
                "Your Chess DNA" to "Your style, named from your games",
            )) {
                Row(verticalAlignment = Alignment.CenterVertically) {
                    Box(Modifier.size(6.dp).clip(RoundedCornerShape(50)).background(Palette.gold))
                    Spacer(Modifier.width(10.dp))
                    Column {
                        Text(name, style = Type.heading.copy(fontSize = 17.sp))
                        Text(what, style = Type.small.copy(fontSize = 12.5.sp))
                    }
                }
            }
        }
    }
}

// MARK: - Rooms

@Composable
fun RoomsPage(actions: HomeActions) {
    val context = LocalContext.current
    val games = remember { Classics.all(context) }
    Page("Rooms", "page-rooms") {
        SectionTitle("The rivals' hall", note = "${Progress.beaten.size} of ${Rival.entries.size} beaten")
        Column(Modifier.padding(horizontal = 16.dp), verticalArrangement = Arrangement.spacedBy(12.dp)) {
            for (rival in Rival.entries) {
                Row(
                    Modifier.fillMaxWidth().card(padding = 14.dp, glow = rival.hue).testTag("hall-${rival.name.lowercase()}"),
                    verticalAlignment = Alignment.CenterVertically,
                ) {
                    RivalFrame(rival, 92.dp)
                    Spacer(Modifier.width(14.dp))
                    Column(Modifier.weight(1f)) {
                        val numeral = listOf("I", "II", "III", "IV", "V")[rival.ordinal]
                        val done = if (rival.name in Progress.beaten) " · BEATEN" else ""
                        Text("$numeral · ${rival.film.uppercase()}$done", style = Type.small.copy(fontSize = 10.sp, fontWeight = FontWeight.Bold, letterSpacing = 1.1.sp, color = Palette.gold), maxLines = 1)
                        Text(rival.title, style = Type.title.copy(fontSize = 22.sp, fontWeight = FontWeight.Normal), maxLines = 1)
                        Text(rival.lore, style = Type.small.copy(fontSize = 12.5.sp), maxLines = 2)
                        Pill(rival.faceLabel, main = true, icon = "▶", modifier = Modifier.padding(top = 8.dp).testTag("face-${rival.name.lowercase()}")) { actions.play(rival) }
                    }
                }
            }
        }
        SectionTitle("Famous games", note = "${games.size} games")
        Column(Modifier.padding(horizontal = 16.dp), verticalArrangement = Arrangement.spacedBy(10.dp)) {
            for (game in games) {
                Row(
                    Modifier.fillMaxWidth().card(padding = 12.dp).clickable { actions.replay(game) },
                    verticalAlignment = Alignment.CenterVertically,
                ) {
                    Box(Modifier.size(64.dp).clip(RoundedCornerShape(5.dp))) {
                        ChessBoard(position = game.frames.last(), flipped = game.flipped, interactive = false, coordinates = false, tagged = false)
                    }
                    Spacer(Modifier.width(12.dp))
                    Column(Modifier.weight(1f)) {
                        Text(game.title, style = Type.heading.copy(fontSize = 17.sp), maxLines = 1)
                        Text(game.players, style = Type.small.copy(fontSize = 12.sp), maxLines = 1)
                        Text(game.story, style = Type.small.copy(fontSize = 12.sp, color = Palette.inkFaint), maxLines = 2)
                    }
                }
            }
        }
    }
}

// MARK: - You

@Composable
fun YouPage() {
    Page("You", "page-you") {
        Row(
            Modifier.padding(horizontal = 16.dp, vertical = 16.dp).fillMaxWidth().card(padding = 12.dp),
            horizontalArrangement = Arrangement.SpaceEvenly,
        ) {
            Stat(Progress.rating?.toString() ?: "New", "Rating")
            Stat("${Progress.games}", "Games")
            Stat("${Progress.wins}", "Wins")
            Stat("${Progress.streak}", "Streak")
        }
        SectionTitle("Appearance")
        Choices(Appearance.entries.map { it.label }, Appearance.entries.indexOf(Progress.appearance), "appearance") {
            Progress.chooseAppearance(Appearance.entries[it])
        }
        SectionTitle("Play as")
        Choices(SideChoice.entries.map { it.label }, SideChoice.entries.indexOf(Progress.side), "side") {
            Progress.chooseSide(SideChoice.entries[it])
        }
        SectionTitle("Sound")
        Column(Modifier.padding(horizontal = 16.dp).fillMaxWidth().card(padding = 4.dp)) {
            Toggle("Board sounds", "Wooden pieces on every move", Progress.soundsOn, "toggle-sounds") { Progress.chooseSounds(it) }
            Box(Modifier.padding(horizontal = 14.dp).fillMaxWidth().height(0.7.dp).background(Palette.line))
            Toggle("Home music", "\"The Long Winter\" on Today", Progress.musicOn, "toggle-music") { Progress.chooseMusic(it) }
        }
        SectionTitle("About")
        Column(Modifier.padding(horizontal = 16.dp).fillMaxWidth().card(), verticalArrangement = Arrangement.spacedBy(6.dp)) {
            Text("Beauty of Chess for Android", style = Type.heading.copy(fontSize = 17.sp))
            Text("Version ${BuildConfig.VERSION_NAME} (${BuildConfig.VERSION_CODE}) · test build", style = Type.small)
            Text("Premium is free while you test. Every rival is open.", style = Type.small)
            Text("Rivals play with Stockfish 17 (GPL v3), on your phone.", style = Type.small.copy(color = Palette.inkFaint))
        }
    }
}

@Composable
private fun Stat(value: String, label: String) {
    Column(horizontalAlignment = Alignment.CenterHorizontally) {
        Text(value, style = Type.title.copy(fontSize = 24.sp, fontWeight = FontWeight.Normal))
        Text(label.uppercase(), style = Type.small.copy(fontSize = 9.sp, fontWeight = FontWeight.Bold, letterSpacing = 1.2.sp, color = Palette.gold))
    }
}

@Composable
private fun Choices(labels: List<String>, selected: Int, tag: String, onPick: (Int) -> Unit) {
    val shape = RoundedCornerShape(50)
    Row(
        Modifier.padding(horizontal = 16.dp).fillMaxWidth().clip(shape).background(Palette.card)
            .border(0.8.dp, Palette.gold.copy(alpha = 0.4f), shape).padding(4.dp),
    ) {
        labels.forEachIndexed { i, label ->
            val on = i == selected
            Box(
                Modifier.weight(1f).height(40.dp).clip(shape)
                    .background(if (on) Brush.verticalGradient(listOf(Palette.goldTop, Palette.goldFoot)) else Brush.verticalGradient(listOf(Color.Transparent, Color.Transparent)))
                    .clickable { onPick(i) }
                    .testTag("$tag-${label.lowercase()}"),
                contentAlignment = Alignment.Center,
            ) {
                Text(label, style = Type.button.copy(fontSize = 14.sp, color = if (on) Palette.onMetal else Palette.inkSoft))
            }
        }
    }
}

@Composable
private fun Toggle(title: String, detail: String, on: Boolean, tag: String, onChange: (Boolean) -> Unit) {
    Row(
        Modifier.fillMaxWidth().clickable { onChange(!on) }.padding(horizontal = 14.dp, vertical = 12.dp).testTag(tag),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Column(Modifier.weight(1f)) {
            Text(title, style = Type.body.copy(fontWeight = FontWeight.SemiBold))
            Text(detail, style = Type.small.copy(fontSize = 12.sp))
        }
        Switch(
            checked = on, onCheckedChange = onChange,
            colors = SwitchDefaults.colors(checkedTrackColor = Palette.gold, checkedThumbColor = Color.White),
        )
    }
}
