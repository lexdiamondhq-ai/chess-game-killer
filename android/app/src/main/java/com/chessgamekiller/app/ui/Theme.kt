package com.chessgamekiller.app.ui

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.defaultMinSize
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.darkColorScheme
import androidx.compose.material3.lightColorScheme
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.shadow
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.Font
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.chessgamekiller.app.R

/**
 * The iPhone app's palette (HomeAuroraPalette and Design.swift): warm espresso by night, cream by
 * day, warm ivory ink, and one gold for the thing to do. It follows the phone's light or dark
 * setting, or the one picked in You > Appearance.
 */
object Palette {
    /** Dark or light: set once per frame from the phone and the Appearance setting. */
    var dark by mutableStateOf(true)

    private fun pick(night: Long, day: Long) = Color(if (dark) night else day)

    /** The page. */
    val night get() = pick(0xFF100B08, 0xFFF6F3EE)
    val bgLow get() = pick(0xFF140F0C, 0xFFEFEAE2)
    /** A card's body: a shade off the page. */
    val card get() = pick(0xFF221B16, 0xFFFFFFFF)
    val cardHigh get() = pick(0xFF2A221C, 0xFFFFFFFF)
    /** The page that slides up over Home's board. */
    val sheet get() = if (dark) Color(0xF7110C09) else Color(0xFAF8F5F0)
    val ink get() = pick(0xFFF2EEE6, 0xFF1C1813)
    val inkSoft get() = ink.copy(alpha = if (dark) 0.74f else 0.72f)
    val inkFaint get() = ink.copy(alpha = if (dark) 0.5f else 0.52f)
    val line get() = if (dark) Color.White.copy(alpha = 0.12f) else Color(0x1F1C1813)
    val glassHi get() = if (dark) Color.White.copy(alpha = 0.12f) else Color.White
    val bar get() = if (dark) Color(0xD914161E) else Color(0xEBFFFFFF)
    /** The warm gold of Home: full by night, deeper by day so it reads on cream. */
    val gold get() = pick(0xFFF0C76E, 0xFFAE761C)
    val rose get() = pick(0xFFFF6688, 0xFFD9335E)
    val violet get() = pick(0xFF9B7CFF, 0xFF603CEA)
    val teal get() = pick(0xFF2FE2C2, 0xFF089F84)
    val tabGold get() = pick(0xFFE8C27A, 0xFFB7832E)
    val goldTop = Color(0xFFF6DEA3)
    val goldFoot = Color(0xFFC99B4E)
    val goldRim = Color(0xFF9C6B2C)
    val onMetal = Color(0xFF2A1E0F)
    val good = Color(0xFF7FC37A)
    val bad = Color(0xFFE0605A)
    val info = Color(0xFF8FB4FF)

    // The board: the iPhone's default wood.
    val lightSquare = Color(0xFFCDBC9C)
    val darkSquare = Color(0xFF553420)
    val labelOnLight = Color(0xCC2A2722)
    val labelOnDark = Color(0xD9E8DFCC)
    val selected = Color(0x4D5E8FFF)
    val lastMove = Color(0x61D9A92B)
    val hintDot = Color(0x66221A10)
    val check = Color(0xFFD92D3F)
}

object Fonts {
    /** Cinzel: the carved capitals for labels. */
    val carved = FontFamily(Font(R.font.cinzel_bold, FontWeight.Bold))
    /** Geist: buttons, labels, numbers and running text. */
    val geist = FontFamily(
        Font(R.font.geist_regular, FontWeight.Normal),
        Font(R.font.geist_medium, FontWeight.Medium),
        Font(R.font.geist_semibold, FontWeight.SemiBold),
        Font(R.font.geist_bold, FontWeight.Bold),
    )
    /** The display serif for names and headings. */
    val display = FontFamily.Serif
}

object Type {
    val title get() = TextStyle(fontFamily = Fonts.display, fontWeight = FontWeight.Medium, fontSize = 30.sp, color = Palette.ink)
    val heading get() = TextStyle(fontFamily = Fonts.display, fontWeight = FontWeight.Medium, fontSize = 21.sp, color = Palette.ink)
    val body get() = TextStyle(fontFamily = Fonts.geist, fontWeight = FontWeight.Normal, fontSize = 15.sp, lineHeight = 21.sp, color = Palette.ink)
    val small get() = TextStyle(fontFamily = Fonts.geist, fontWeight = FontWeight.Medium, fontSize = 13.sp, color = Palette.inkSoft)
    val button get() = TextStyle(fontFamily = Fonts.geist, fontWeight = FontWeight.SemiBold, fontSize = 16.sp)
    val label get() = TextStyle(fontFamily = Fonts.carved, fontWeight = FontWeight.Bold, fontSize = 12.sp, letterSpacing = 2.sp, color = Palette.gold)
}

@Composable
fun BeautyTheme(content: @Composable () -> Unit) {
    val scheme = if (Palette.dark) darkColorScheme(
        primary = Palette.gold, onPrimary = Palette.onMetal, background = Palette.night,
        surface = Palette.card, onSurface = Palette.ink, onBackground = Palette.ink,
    ) else lightColorScheme(
        primary = Palette.gold, onPrimary = Palette.onMetal, background = Palette.night,
        surface = Palette.card, onSurface = Palette.ink, onBackground = Palette.ink,
    )
    MaterialTheme(colorScheme = scheme, content = content)
}

/** A carved gold label over a group: "YOUR RIVALS". */
@Composable
fun CarvedLabel(text: String, modifier: Modifier = Modifier) {
    Text(text.uppercase(), style = Type.label, modifier = modifier)
}

/** The gold main button: the one thing to do on a screen. */
@Composable
fun GoldButton(text: String, modifier: Modifier = Modifier, enabled: Boolean = true, onClick: () -> Unit) {
    val shape = RoundedCornerShape(50)
    Box(
        modifier
            .shadow(if (enabled) 10.dp else 0.dp, shape, ambientColor = Palette.goldFoot, spotColor = Palette.goldFoot)
            .clip(shape)
            .background(Brush.verticalGradient(listOf(Palette.goldTop, Palette.goldFoot)), shape)
            .border(1.dp, Brush.verticalGradient(listOf(Color.White.copy(alpha = 0.6f), Palette.goldRim)), shape),
    ) {
        TextButton(
            onClick = onClick,
            enabled = enabled,
            contentPadding = PaddingValues(horizontal = 26.dp, vertical = 12.dp),
            colors = ButtonDefaults.textButtonColors(contentColor = Palette.onMetal, disabledContentColor = Palette.onMetal.copy(alpha = 0.5f)),
            modifier = Modifier.defaultMinSize(minHeight = 48.dp).align(Alignment.Center),
        ) { Text(text, style = Type.button) }
    }
}

/** A quiet outlined button for everything that isn't the main thing. */
@Composable
fun QuietButton(text: String, modifier: Modifier = Modifier, enabled: Boolean = true, onClick: () -> Unit) {
    val shape = RoundedCornerShape(50)
    TextButton(
        onClick = onClick,
        enabled = enabled,
        modifier = modifier.border(1.dp, Palette.gold.copy(alpha = if (enabled) 0.55f else 0.2f), shape).defaultMinSize(minHeight = 44.dp),
        shape = shape,
        contentPadding = PaddingValues(horizontal = 16.dp, vertical = 8.dp),
        colors = ButtonDefaults.textButtonColors(contentColor = Palette.ink, disabledContentColor = Palette.inkFaint),
    ) { Text(text, style = Type.button.copy(fontSize = 14.sp)) }
}

/** A Home card: its body a shade off the page, a gilded hairline edge, a soft lift by day. */
fun Modifier.card(padding: androidx.compose.ui.unit.Dp = 16.dp, radius: androidx.compose.ui.unit.Dp = 24.dp, glow: Color? = null): Modifier {
    val shape = RoundedCornerShape(radius)
    return this
        .shadow(if (Palette.dark) 0.dp else 6.dp, shape, ambientColor = Color(0x22000000), spotColor = Color(0x22000000))
        .clip(shape)
        .background(Palette.card)
        .then(if (glow != null) Modifier.background(Brush.radialGradient(listOf(glow.copy(alpha = if (Palette.dark) 0.16f else 0.11f), Color.Transparent), center = androidx.compose.ui.geometry.Offset.Zero, radius = 700f)) else Modifier)
        .border(0.8.dp, Brush.verticalGradient(listOf(Palette.gold.copy(alpha = 0.75f), Palette.gold.copy(alpha = 0.22f))), shape)
        .padding(padding)
}

/** A Home section's heading: "Next game" in the serif, a short gold rule under it, a note at the right. */
@Composable
fun SectionTitle(text: String, modifier: Modifier = Modifier, note: String? = null) {
    androidx.compose.foundation.layout.Column(modifier.padding(start = 20.dp, end = 20.dp, top = 26.dp, bottom = 14.dp)) {
        androidx.compose.foundation.layout.Row(verticalAlignment = Alignment.Bottom) {
            Text(text, style = Type.title.copy(fontSize = 27.sp, fontWeight = FontWeight.Normal), modifier = Modifier.weight(1f))
            if (note != null) Text(note, style = Type.small.copy(fontSize = 14.sp))
        }
        Box(
            Modifier.padding(top = 6.dp).size(androidx.compose.ui.unit.DpSize(56.dp, 1.5.dp))
                .background(Brush.horizontalGradient(listOf(Palette.gold, Palette.gold.copy(alpha = 0f)))),
        )
    }
}

/** A small capsule on a card: solid gold for the card's one action, a gold outline for the rest. */
@Composable
fun Pill(text: String, modifier: Modifier = Modifier, main: Boolean = false, icon: String? = null, onClick: () -> Unit) {
    val shape = RoundedCornerShape(50)
    val base = modifier
        .defaultMinSize(minHeight = 34.dp)
        .clip(shape)
        .then(
            if (main) Modifier.background(Brush.verticalGradient(listOf(Palette.goldTop, Palette.goldFoot)), shape)
                .border(0.75.dp, Color.White.copy(alpha = 0.35f), shape)
            else Modifier.border(1.dp, Palette.gold.copy(alpha = 0.7f), shape),
        )
        .clickable(onClick = onClick)
        .padding(horizontal = if (main) 16.dp else 14.dp, vertical = 7.dp)
    androidx.compose.foundation.layout.Row(base, verticalAlignment = Alignment.CenterVertically) {
        if (icon != null) Text(icon + " ", style = Type.button.copy(fontSize = 12.sp, color = if (main) Palette.onMetal else Palette.gold))
        Text(text, style = Type.button.copy(fontSize = 14.sp, fontWeight = FontWeight.Bold, color = if (main) Palette.onMetal else Palette.gold))
    }
}
