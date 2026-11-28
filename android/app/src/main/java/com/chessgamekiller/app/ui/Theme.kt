package com.chessgamekiller.app.ui

import androidx.compose.foundation.background
import androidx.compose.foundation.border
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

/** The iPhone app's palette: espresso dark, warm ivory ink, and one gold for the thing to do. */
object Palette {
    val night = Color(0xFF0E0B08)
    val card = Color(0xFF1A1410)
    val cardHigh = Color(0xFF241B14)
    val ink = Color(0xFFF2E8D5)
    val inkSoft = Color(0xFFBFB29C)
    val inkFaint = Color(0xFF8A7E6B)
    val gold = Color(0xFFE2B577)
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
    val title = TextStyle(fontFamily = Fonts.display, fontWeight = FontWeight.Medium, fontSize = 30.sp, color = Palette.ink)
    val heading = TextStyle(fontFamily = Fonts.display, fontWeight = FontWeight.Medium, fontSize = 21.sp, color = Palette.ink)
    val body = TextStyle(fontFamily = Fonts.geist, fontWeight = FontWeight.Normal, fontSize = 15.sp, lineHeight = 21.sp, color = Palette.ink)
    val small = TextStyle(fontFamily = Fonts.geist, fontWeight = FontWeight.Medium, fontSize = 13.sp, color = Palette.inkSoft)
    val button = TextStyle(fontFamily = Fonts.geist, fontWeight = FontWeight.SemiBold, fontSize = 16.sp)
    val label = TextStyle(fontFamily = Fonts.carved, fontWeight = FontWeight.Bold, fontSize = 12.sp, letterSpacing = 2.sp, color = Palette.gold)
}

@Composable
fun BeautyTheme(content: @Composable () -> Unit) {
    MaterialTheme(
        colorScheme = darkColorScheme(
            primary = Palette.gold,
            onPrimary = Palette.onMetal,
            background = Palette.night,
            surface = Palette.card,
            onSurface = Palette.ink,
            onBackground = Palette.ink,
        ),
        content = content,
    )
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

/** A dark card with a hairline gold rim. */
fun Modifier.card(): Modifier = this
    .clip(RoundedCornerShape(20.dp))
    .background(Brush.verticalGradient(listOf(Palette.cardHigh, Palette.card)))
    .border(0.7.dp, Palette.gold.copy(alpha = 0.35f), RoundedCornerShape(20.dp))
    .padding(16.dp)
