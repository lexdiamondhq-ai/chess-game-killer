package com.chessgamekiller.app.home

import android.media.MediaPlayer
import androidx.compose.animation.core.animateDpAsState
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.ExperimentalFoundationApi
import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxScope
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.statusBarsPadding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.pager.HorizontalPager
import androidx.compose.foundation.pager.rememberPagerState
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.shadow
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.LocalContext
import androidx.lifecycle.compose.LocalLifecycleOwner
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.text.SpanStyle
import androidx.compose.ui.text.buildAnnotatedString
import androidx.compose.ui.text.font.FontStyle
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.withStyle
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.LifecycleEventObserver
import com.chessgamekiller.app.Progress
import com.chessgamekiller.app.R
import com.chessgamekiller.app.game.Rival
import com.chessgamekiller.app.ui.ChessBoard
import com.chessgamekiller.app.ui.Fonts
import com.chessgamekiller.app.ui.KnightGlyph
import com.chessgamekiller.app.ui.Palette
import com.chessgamekiller.app.ui.Pill
import com.chessgamekiller.app.ui.RivalFrame
import com.chessgamekiller.app.ui.ScanGlyph
import com.chessgamekiller.app.ui.SectionTitle
import com.chessgamekiller.app.ui.TabIcon
import com.chessgamekiller.app.ui.TabKind
import com.chessgamekiller.app.ui.Type
import com.chessgamekiller.app.ui.card

/** What Home can open. */
class HomeActions(
    val play: (Rival) -> Unit,
    val options: (Rival) -> Unit,
    val analyze: () -> Unit,
    val scanPhoto: () -> Unit,
    val takePhoto: () -> Unit,
    val askLeo: () -> Unit,
    val replay: (ClassicGame) -> Unit,
)

/**
 * Home, as on the iPhone: Today (the board of the day on marble and the page over it), Learn,
 * Rooms and You, under one glass bar with Analyze and the gold Play knight beside it.
 */
@Composable
fun HomeScreen(tab: TabKind, onTab: (TabKind) -> Unit, actions: HomeActions) {
    Box(Modifier.fillMaxSize().background(Palette.night)) {
        when (tab) {
            TabKind.TODAY -> TodayPage(actions)
            TabKind.LEARN -> LearnPage(actions)
            TabKind.ROOMS -> RoomsPage(actions)
            TabKind.YOU -> YouPage()
        }
        BottomBar(
            tab = tab,
            onTab = onTab,
            analyze = actions.analyze,
            play = { actions.play(Progress.upNext) },
            modifier = Modifier.align(Alignment.BottomCenter),
        )
    }
}

// MARK: - Today

@Composable
private fun TodayPage(actions: HomeActions) {
    val context = LocalContext.current
    val day = remember { Classics.today(context) }
    HomeMusic()
    Box(Modifier.fillMaxSize()) {
        Column(Modifier.fillMaxSize().verticalScroll(rememberScrollState())) {
            // The board of the day on marble, under the header.
            Box(Modifier.fillMaxWidth().height(400.dp)) {
                Image(
                    painterResource(if (Palette.dark) R.drawable.marble_dark else R.drawable.marble_light),
                    contentDescription = null,
                    contentScale = ContentScale.Crop,
                    modifier = Modifier.fillMaxSize(),
                )
                DayBoard(day, Modifier.fillMaxWidth().height(330.dp).align(Alignment.BottomCenter).offset(y = 8.dp).testTag("day-board"))
            }
            TodaySheet(day, actions, Modifier.offset(y = (-26).dp))
        }
        // The header, over the top of the board: the room's light behind it.
        Header(Modifier.align(Alignment.TopCenter))
    }
}

@Composable
private fun Header(modifier: Modifier = Modifier) {
    Box(
        modifier
            .fillMaxWidth()
            .background(
                Brush.horizontalGradient(
                    if (Palette.dark) listOf(Color(0xFF2B1F4A), Color(0xFF1A1218), Color(0xFF3A1A22))
                    else listOf(Color(0xFFE9E1F6), Color(0xFFF4ECEE), Color(0xFFF8E2E4)),
                ),
            ),
    ) {
        Row(
            Modifier.fillMaxWidth().statusBarsPadding().padding(start = 20.dp, end = 12.dp, top = 6.dp, bottom = 10.dp),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            Text(
                buildAnnotatedString {
                    append("Beauty ")
                    withStyle(SpanStyle(fontStyle = FontStyle.Italic, color = Palette.gold)) { append("of") }
                    append(" Chess")
                },
                style = Type.title.copy(fontSize = 24.sp, fontWeight = FontWeight.Medium),
                maxLines = 1,
                modifier = Modifier.weight(1f).testTag("home-title"),
            )
            HeaderNumber(Progress.rating?.toString() ?: "New", "Rating")
            Hairline()
            HeaderNumber("${Progress.wins}", "Wins")
            Hairline()
            HeaderNumber("${Progress.streak}", "Streak")
        }
        Box(
            Modifier.align(Alignment.BottomCenter).padding(horizontal = 20.dp).fillMaxWidth().height(1.dp)
                .background(Brush.horizontalGradient(listOf(Palette.gold.copy(alpha = 0f), Palette.gold.copy(alpha = 0.8f), Palette.gold.copy(alpha = 0f)))),
        )
    }
}

@Composable
private fun HeaderNumber(value: String, label: String) {
    Column(Modifier.width(52.dp), horizontalAlignment = Alignment.CenterHorizontally) {
        Text(value, style = Type.title.copy(fontSize = 18.sp, fontWeight = FontWeight.Normal), maxLines = 1)
        Text(label.uppercase(), style = Type.small.copy(fontSize = 8.sp, fontWeight = FontWeight.Bold, letterSpacing = 1.2.sp, color = Palette.gold))
    }
}

@Composable
private fun Hairline() {
    Box(
        Modifier.size(1.dp, 26.dp)
            .background(Brush.verticalGradient(listOf(Palette.gold.copy(alpha = 0f), Palette.gold.copy(alpha = 0.55f), Palette.gold.copy(alpha = 0f)))),
    )
}

/** The page that sits over the board: Next game, then For today. */
@Composable
private fun TodaySheet(day: ClassicGame?, actions: HomeActions, modifier: Modifier = Modifier) {
    val shape = RoundedCornerShape(topStart = 34.dp, topEnd = 34.dp)
    Column(
        modifier
            .fillMaxWidth()
            .shadow(if (Palette.dark) 0.dp else 20.dp, shape)
            .clip(shape)
            .background(Palette.sheet)
            .border(1.25.dp, Brush.verticalGradient(listOf(Palette.gold.copy(alpha = 0.9f), Palette.gold.copy(alpha = 0f)), endY = 160f), shape),
    ) {
        Box(
            Modifier.align(Alignment.CenterHorizontally).padding(top = 10.dp).size(38.dp, 4.dp)
                .clip(CircleShape).background(Palette.inkFaint),
        )
        SectionTitle("Next game")
        RivalPager(actions)
        SectionTitle("For today")
        if (day != null) {
            GameOfTheDay(day, Modifier.padding(horizontal = 16.dp)) { actions.replay(day) }
            Spacer(Modifier.height(10.dp))
        }
        Row(Modifier.padding(horizontal = 16.dp), horizontalArrangement = Arrangement.spacedBy(10.dp)) {
            Tile(
                eyebrow = "Coach Leo", title = "Talk it through", detail = "Ask about any position",
                accent = Palette.teal, stone = Jewel.JADE, modifier = Modifier.weight(1f).testTag("tile-leo"),
                icon = { TabIcon(TabKind.LEARN, JewelGold, Modifier.size(26.dp)) },
                onClick = actions.askLeo,
            )
            Tile(
                eyebrow = "Analyze", title = "Snap a board", detail = "A photo to the best move",
                accent = Palette.violet, stone = Jewel.AMETHYST, modifier = Modifier.weight(1f).testTag("home-scan"),
                icon = { ScanGlyph(JewelGold, Modifier.size(26.dp)) },
                onClick = actions.scanPhoto,
            )
        }
        Spacer(Modifier.navigationBarsPadding().height(120.dp))
    }
}

@OptIn(ExperimentalFoundationApi::class)
@Composable
private fun RivalPager(actions: HomeActions) {
    val next = Progress.upNext
    val pager = rememberPagerState(initialPage = next.ordinal) { Rival.entries.size }
    Column {
        HorizontalPager(
            state = pager,
            pageSpacing = 16.dp,
            contentPadding = androidx.compose.foundation.layout.PaddingValues(horizontal = 16.dp),
            modifier = Modifier.testTag("rival-pager"),
        ) { page ->
            val rival = Rival.entries[page]
            val status = when {
                rival == next -> "Up next"
                rival.name in Progress.beaten -> "${rival.place} · Beaten"
                else -> rival.place
            }
            NextRivalCard(rival, status, actions)
        }
        Row(
            Modifier.fillMaxWidth().padding(top = 12.dp),
            horizontalArrangement = Arrangement.spacedBy(6.dp, Alignment.CenterHorizontally),
        ) {
            Rival.entries.forEachIndexed { i, _ ->
                val on = i == pager.currentPage
                val w by animateDpAsState(if (on) 16.dp else 5.dp, label = "dash")
                Box(Modifier.size(w, 5.dp).clip(CircleShape).background(if (on) Palette.gold else Palette.gold.copy(alpha = 0.3f)))
            }
        }
    }
}

@Composable
private fun NextRivalCard(rival: Rival, status: String, actions: HomeActions) {
    val side = when (Progress.side) {
        com.chessgamekiller.app.SideChoice.WHITE -> "You're White"
        com.chessgamekiller.app.SideChoice.BLACK -> "You're Black"
        com.chessgamekiller.app.SideChoice.RANDOM -> "Either side"
    }
    Row(
        Modifier.fillMaxWidth().card(padding = 14.dp, glow = Palette.gold).testTag("rival-${rival.name.lowercase()}"),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        RivalFrame(rival, 112.dp)
        Spacer(Modifier.width(14.dp))
        Column(Modifier.weight(1f)) {
            Text(status.uppercase(), style = Type.small.copy(fontSize = 10.sp, fontWeight = FontWeight.Bold, letterSpacing = 1.2.sp, color = Palette.gold), maxLines = 1)
            Text(rival.title, style = Type.title.copy(fontSize = 26.sp, fontWeight = FontWeight.Normal), maxLines = 1)
            Text("${rival.eloPlain} · No clock · $side", style = Type.small.copy(fontSize = 12.5.sp), maxLines = 2)
            Row(Modifier.padding(top = 10.dp), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                Pill("Play", main = true, icon = "▶", modifier = Modifier.testTag("play-${rival.name.lowercase()}")) { actions.play(rival) }
                Pill("Options", icon = "☰", modifier = Modifier.testTag("options-${rival.name.lowercase()}")) { actions.options(rival) }
            }
        }
    }
}

@Composable
private fun GameOfTheDay(day: ClassicGame, modifier: Modifier = Modifier, onClick: () -> Unit) {
    val last = day.frames.last()
    Row(
        modifier.fillMaxWidth().card(padding = 14.dp, glow = Palette.gold).clickable(onClick = onClick).testTag("game-of-the-day"),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Box(Modifier.size(104.dp).clip(RoundedCornerShape(6.dp))) {
            ChessBoard(position = last, flipped = day.flipped, interactive = false, coordinates = false, tagged = false)
        }
        Spacer(Modifier.width(14.dp))
        Column(Modifier.weight(1f)) {
            Text("GAME OF THE DAY", style = Type.small.copy(fontSize = 10.sp, fontWeight = FontWeight.Bold, letterSpacing = 1.2.sp, color = Palette.gold))
            Text(day.title, style = Type.title.copy(fontSize = 21.sp, fontWeight = FontWeight.Normal), maxLines = 2)
            Text(day.players, style = Type.small.copy(fontSize = 12.5.sp), maxLines = 1)
            Text(day.story, style = Type.small.copy(fontSize = 12.5.sp, color = Palette.inkFaint), maxLines = 2, modifier = Modifier.padding(top = 2.dp))
            Pill("Replay", main = true, icon = "▶", modifier = Modifier.padding(top = 8.dp)) { onClick() }
        }
    }
}

val JewelGold = Color(0xFFE8C27A)

enum class Jewel(val colors: List<Color>) {
    JADE(listOf(Color(0xFF1F7A5C), Color(0xFF0C3B2E))),
    AMETHYST(listOf(Color(0xFF6A47C9), Color(0xFF2D1A66))),
    RUBY(listOf(Color(0xFFB3263E), Color(0xFF5A0F1F))),
    SAPPHIRE(listOf(Color(0xFF2B5BC0), Color(0xFF102A63))),
    AMBER(listOf(Color(0xFFC98A2E), Color(0xFF6B3F0E))),
}

/** A door's own stone: a fine gold drawing on a deep jewel tile. */
@Composable
fun JewelTile(stone: Jewel, size: Dp = 44.dp, content: @Composable BoxScope.() -> Unit) {
    val shape = RoundedCornerShape(size * 0.3f)
    Box(
        Modifier.size(size)
            .shadow(6.dp, shape, ambientColor = stone.colors[1], spotColor = stone.colors[1])
            .clip(shape)
            .background(Brush.linearGradient(stone.colors))
            .background(Brush.radialGradient(listOf(Color.White.copy(alpha = 0.24f), Color.Transparent), center = Offset(size.value * 0.9f, size.value * 0.6f), radius = size.value * 2f))
            .padding(size * 0.06f)
            .border(0.7.dp, JewelGold.copy(alpha = 0.7f), RoundedCornerShape(size * 0.24f)),
        contentAlignment = Alignment.Center,
        content = content,
    )
}

@Composable
private fun Tile(
    eyebrow: String, title: String, detail: String, accent: Color, stone: Jewel,
    modifier: Modifier = Modifier, icon: @Composable () -> Unit, onClick: () -> Unit,
) {
    Column(modifier.card(padding = 14.dp, glow = accent).clickable(onClick = onClick)) {
        JewelTile(stone) { icon() }
        Spacer(Modifier.height(12.dp))
        Text(eyebrow.uppercase(), style = Type.small.copy(fontSize = 10.sp, fontWeight = FontWeight.Bold, letterSpacing = 1.2.sp, color = accent), maxLines = 1)
        Text(title, style = Type.title.copy(fontSize = 19.sp, fontWeight = FontWeight.Normal), maxLines = 1)
        Text(detail, style = Type.small.copy(fontSize = 12.sp), maxLines = 2)
    }
}

/** "The Long Winter", softly, while Today is open and Home music is on (You > Sound). */
@Composable
private fun HomeMusic() {
    val context = LocalContext.current
    val lifecycle = LocalLifecycleOwner.current.lifecycle
    val on = Progress.musicOn
    DisposableEffect(on) {
        if (!on) return@DisposableEffect onDispose { }
        val player = runCatching { MediaPlayer.create(context, R.raw.music_home) }.getOrNull()
        player?.isLooping = true
        player?.setVolume(0.35f, 0.35f)
        if (lifecycle.currentState.isAtLeast(Lifecycle.State.STARTED)) player?.start()
        val observer = LifecycleEventObserver { _, event ->
            when (event) {
                Lifecycle.Event.ON_START -> player?.start()
                Lifecycle.Event.ON_STOP -> player?.pause()
                else -> {}
            }
        }
        lifecycle.addObserver(observer)
        onDispose {
            lifecycle.removeObserver(observer)
            player?.release()
        }
    }
}

// MARK: - The bottom bar

@Composable
private fun BottomBar(tab: TabKind, onTab: (TabKind) -> Unit, analyze: () -> Unit, play: () -> Unit, modifier: Modifier = Modifier) {
    val bar = RoundedCornerShape(50)
    Row(
        modifier.fillMaxWidth().navigationBarsPadding().padding(horizontal = 12.dp, vertical = 10.dp),
        horizontalArrangement = Arrangement.spacedBy(8.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Row(
            Modifier.weight(1f).height(64.dp)
                .shadow(16.dp, bar, ambientColor = Color.Black.copy(alpha = 0.4f), spotColor = Color.Black.copy(alpha = 0.4f))
                .clip(bar)
                .background(Palette.bar)
                .border(0.8.dp, Brush.verticalGradient(listOf(Palette.gold.copy(alpha = 0.55f), Palette.gold.copy(alpha = 0.15f))), bar)
                .padding(horizontal = 4.dp),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            for ((kind, title) in listOf(TabKind.TODAY to "Today", TabKind.LEARN to "Learn", TabKind.ROOMS to "Rooms", TabKind.YOU to "You")) {
                val on = kind == tab
                Column(
                    Modifier.weight(1f).height(54.dp).clip(bar)
                        .background(if (on) Palette.glassHi else Color.Transparent)
                        .then(if (on) Modifier.border(0.8.dp, Palette.gold.copy(alpha = 0.6f), bar) else Modifier)
                        .clickable { onTab(kind) }
                        .testTag("tab-${title.lowercase()}"),
                    horizontalAlignment = Alignment.CenterHorizontally,
                    verticalArrangement = Arrangement.Center,
                ) {
                    TabIcon(kind, if (on) Palette.tabGold else Palette.ink.copy(alpha = 0.82f), Modifier.size(26.dp))
                    Text(title, style = Type.small.copy(fontSize = 11.sp, fontWeight = FontWeight.SemiBold, color = if (on) Palette.ink else Palette.inkSoft), maxLines = 1)
                }
            }
        }
        // Analyze: a little board inside camera corners.
        Column(
            Modifier.size(58.dp)
                .shadow(12.dp, CircleShape, ambientColor = Color.Black.copy(alpha = 0.4f), spotColor = Color.Black.copy(alpha = 0.4f))
                .clip(CircleShape)
                .background(Palette.bar)
                .border(1.dp, Brush.verticalGradient(listOf(Palette.gold.copy(alpha = 0.8f), Palette.gold.copy(alpha = 0.25f))), CircleShape)
                .clickable(onClick = analyze)
                .testTag("bar-analyze"),
            horizontalAlignment = Alignment.CenterHorizontally,
            verticalArrangement = Arrangement.Center,
        ) {
            val tint = if (Palette.dark) Color(0xFFE8C27A) else Color(0xFF8A5F1E)
            ScanGlyph(tint, Modifier.size(26.dp, 25.dp))
            Text("Analyze", style = Type.small.copy(fontSize = 9.5.sp, fontWeight = FontWeight.SemiBold, color = tint))
        }
        // The gold Play coin: the Gilded knight over the word Play.
        Column(
            Modifier.size(58.dp)
                .shadow(14.dp, CircleShape, ambientColor = Color(0xFFE8C27A), spotColor = Color(0xFFA66F25))
                .clip(CircleShape)
                .background(Brush.radialGradient(0f to Color(0xFFFFF1CC), 0.45f to Color(0xFFE8C27A), 1f to Color(0xFFA66F25), center = Offset(55f, 45f), radius = 190f))
                .border(1.dp, Color.White.copy(alpha = 0.35f), CircleShape)
                .clickable(onClick = play)
                .testTag("bar-play"),
            horizontalAlignment = Alignment.CenterHorizontally,
            verticalArrangement = Arrangement.Center,
        ) {
            KnightGlyph(Modifier.size(23.dp, 28.dp))
            Text("Play", style = Type.small.copy(fontSize = 10.sp, fontWeight = FontWeight.SemiBold, color = Color(0xFF2A1C08)))
        }
    }
}
