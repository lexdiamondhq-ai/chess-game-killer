package com.chessgamekiller.app.home

import androidx.compose.animation.core.Animatable
import androidx.compose.animation.core.FastOutSlowInEasing
import androidx.compose.animation.core.LinearEasing
import androidx.compose.animation.core.RepeatMode
import androidx.compose.animation.core.infiniteRepeatable
import androidx.compose.animation.core.rememberInfiniteTransition
import androidx.compose.animation.core.tween
import androidx.compose.animation.core.animateFloat
import androidx.compose.foundation.Canvas
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.ImageBitmap
import androidx.compose.ui.graphics.Path
import androidx.compose.ui.graphics.drawscope.DrawScope
import androidx.compose.ui.res.imageResource
import androidx.compose.ui.unit.IntOffset
import androidx.compose.ui.unit.IntSize
import com.chessgamekiller.app.ui.pieceDrawable
import com.chessgamekiller.chess.Move
import com.chessgamekiller.chess.Position
import com.chessgamekiller.chess.fileOf
import com.chessgamekiller.chess.rankOf
import kotlinx.coroutines.delay
import kotlin.math.cos
import kotlin.math.roundToInt
import kotlin.math.sin

/**
 * Home's board of the day: a wooden board seen from above at an angle, turning slowly, playing
 * the famous game of the day move by move, as the iPhone's clay board does. The pieces stand
 * up on it, nearer ones larger, drawn back to front.
 */
@Composable
fun DayBoard(game: ClassicGame?, modifier: Modifier = Modifier, still: Boolean = false) {
    val frames = remember(game?.id) { game?.frames ?: listOf(Position.start()) }
    var index by remember(game?.id) { mutableIntStateOf(0) }
    val slide = remember { Animatable(1f) }
    var moving by remember { mutableIntStateOf(-1) }

    LaunchedEffect(game?.id, still) {
        if (still || frames.size < 2) return@LaunchedEffect
        while (true) {
            delay(if (index == frames.size - 1) 4500 else 2200)
            if (index == frames.size - 1) { index = 0; moving = -1; continue }
            moving = index
            index += 1
            slide.snapTo(0f)
            slide.animateTo(1f, tween(520, easing = FastOutSlowInEasing))
        }
    }

    val turn = rememberInfiniteTransition(label = "turn")
    val sway by turn.animateFloat(
        initialValue = -1f, targetValue = 1f,
        animationSpec = infiniteRepeatable(tween(14000, easing = LinearEasing), RepeatMode.Reverse), label = "sway",
    )

    val images = PieceImages.load()
    val flipped = game?.flipped == true

    Canvas(modifier) {
        val position = frames[index.coerceIn(0, frames.lastIndex)]
        // The move under way slides its piece from where it stood.
        val move: Move? = if (moving >= 0 && moving + 1 == index) diff(frames[moving], position) else null
        drawBoard(position, move, slide.value, images, yawDeg = 28f + 9f * sway * if (still) 0f else 1f, flipped = flipped)
    }
}

/** The piece pictures, loaded once. */
private object PieceImages {
    @Composable
    fun load(): Map<Char, ImageBitmap> = "KQRBNPkqrbnp".associateWith { ImageBitmap.imageResource(pieceDrawable(it)) }
}

/** Which piece moved between two positions (from, to), for the slide. */
private fun diff(before: Position, after: Position): Move? {
    var from = -1; var to = -1
    for (sq in 0..63) {
        val a = before[sq]; val b = after[sq]
        if (a == b) continue
        if (b == '.') { if (from < 0 || a.lowercaseChar() == 'k') from = sq }
        else to = if (to < 0 || b.lowercaseChar() == 'k') sq else to
    }
    return if (from >= 0 && to >= 0) Move(from, to) else null
}

private class Projector(val w: Float, val h: Float, yawDeg: Float) {
    private val yaw = Math.toRadians(yawDeg.toDouble())
    private val cy = cos(yaw).toFloat(); private val sy = sin(yaw).toFloat()
    private val pitch = Math.toRadians(50.0)
    private val cp = cos(pitch).toFloat(); private val sp = sin(pitch).toFloat()
    private val distance = 17f
    private val focal = w * 1.15f
    private val centerY = h * 0.52f

    /** A point on the board's plane (x, z from -4 to 4, z toward you), lifted [y] above it. */
    fun at(x: Float, z: Float, y: Float = 0f): Triple<Float, Float, Float> {
        val xr = x * cy - z * sy
        val zr = x * sy + z * cy
        val depth = distance - zr * cp + y * sp
        val sx = w / 2 + focal * xr / depth
        val syy = centerY + focal * (zr * sp - y * cp) / depth
        return Triple(sx, syy, focal / depth)
    }
}

private fun DrawScope.drawBoard(
    position: Position, move: Move?, t: Float, images: Map<Char, ImageBitmap>, yawDeg: Float, flipped: Boolean,
) {
    val p = Projector(size.width, size.height, yawDeg + if (flipped) 180f else 0f)
    fun quad(x0: Float, z0: Float, x1: Float, z1: Float, y: Float = 0f): Path {
        val a = p.at(x0, z0, y); val b = p.at(x1, z0, y); val c = p.at(x1, z1, y); val d = p.at(x0, z1, y)
        return Path().apply { moveTo(a.first, a.second); lineTo(b.first, b.second); lineTo(c.first, c.second); lineTo(d.first, d.second); close() }
    }

    // A soft shadow under the board, then its dark frame with a little thickness.
    val rim = 4.42f
    drawPath(quad(-rim - 0.3f, -rim - 0.3f, rim + 0.3f, rim + 0.6f, -0.35f), Color.Black.copy(alpha = 0.18f))
    for (step in 0..6) drawPath(quad(-rim, -rim, rim, rim, -0.05f * step), Color(0xFF15100C))
    drawPath(quad(-rim, -rim, rim, rim), Brush.linearGradient(listOf(Color(0xFF2A211B), Color(0xFF0F0B08)), start = Offset(0f, 0f), end = Offset(size.width, size.height)))

    // The squares: a1 at the near left (x -4, z +4).
    for (sq in 0..63) {
        val f = fileOf(sq); val r = rankOf(sq)
        val x0 = -4f + f; val z0 = 4f - r - 1f
        val light = (f + r) % 2 == 1
        drawPath(quad(x0, z0, x0 + 1, z0 + 1), if (light) Color(0xFFE7D7B6) else Color(0xFF6B3F27))
    }

    // The pieces, back to front.
    data class Stand(val piece: Char, val x: Float, val z: Float)
    val stands = mutableListOf<Stand>()
    for (sq in 0..63) {
        val c = position[sq]
        if (c == '.') continue
        var x = -4f + fileOf(sq) + 0.5f
        var z = 4f - rankOf(sq) - 0.5f
        if (move != null && sq == move.to && t < 1f) {
            val fx = -4f + fileOf(move.from) + 0.5f
            val fz = 4f - rankOf(move.from) - 0.5f
            x = fx + (x - fx) * t; z = fz + (z - fz) * t
        }
        stands += Stand(c, x, z)
    }
    stands.sortBy { p.at(it.x, it.z).second }
    for (s in stands) {
        val image = images[s.piece] ?: continue
        val (bx, by, scale) = p.at(s.x, s.z)
        val height = scale * 1.12f
        val width = height * image.width / image.height
        // A small shadow at its foot.
        drawOval(Color.Black.copy(alpha = 0.22f), Offset(bx - width * 0.3f, by - height * 0.06f), androidx.compose.ui.geometry.Size(width * 0.6f, height * 0.12f))
        drawImage(
            image,
            dstOffset = IntOffset((bx - width / 2).roundToInt(), (by - height * 0.91f).roundToInt()),
            dstSize = IntSize(width.roundToInt(), height.roundToInt()),
        )
    }
}
