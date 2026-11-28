package com.chessgamekiller.app.ui

import androidx.compose.foundation.Canvas
import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.drawBehind
import androidx.compose.ui.geometry.CornerRadius
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Rect
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.BlendMode
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.ColorFilter
import androidx.compose.ui.graphics.CompositingStrategy
import androidx.compose.ui.graphics.ImageBitmap
import androidx.compose.ui.graphics.Path
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.graphics.StrokeJoin
import androidx.compose.ui.graphics.drawscope.DrawScope
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.graphics.drawscope.translate
import androidx.compose.ui.graphics.drawscope.scale
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.res.imageResource
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.IntOffset
import androidx.compose.ui.unit.IntSize
import androidx.compose.ui.unit.dp
import com.chessgamekiller.app.game.Rival
import kotlin.math.min
import kotlin.math.roundToInt

private fun DrawScope.grid(w: Float, h: Float, ox: Float = 0f, oy: Float = 0f, block: DrawScope.() -> Unit) {
    val k = min(size.width / w, size.height / h)
    translate((size.width - w * k) / 2 - ox * k, (size.height - h * k) / 2 - oy * k) {
        scale(k, k, pivot = Offset.Zero) { block() }
    }
}

private fun poly(points: FloatArray): Path = Path().apply {
    moveTo(points[0], points[1])
    var i = 2
    while (i < points.size) { lineTo(points[i], points[i + 1]); i += 2 }
    close()
}

/** The Gilded knight: solid ink with a pale gold mane, eye and steps, as on the iPhone's Play coin. */
@Composable
fun KnightGlyph(modifier: Modifier = Modifier, ink: Color = Color(0xFF2A1C08), detail: Color = Color(0xFFF6DB9C)) {
    Canvas(modifier) {
        grid(78f, 96f, 4f, 6f) {
            drawPath(poly(KnightShape.rim), ink)
            val gold = Path()
            KnightShape.details.forEach { gold.addPath(poly(it)) }
            gold.addOval(Rect(73.9f, 59.9f, 77.1f, 63.1f))
            drawPath(gold, detail)
            for ((y, from, to) in listOf(Triple(94.5f, 10.2f, 69.8f), Triple(92.1f, 15.2f, 64.8f), Triple(89.3f, 14.1f, 65.8f), Triple(86.9f, 16.7f, 63.2f))) {
                drawLine(detail, Offset(from, y), Offset(to, y), strokeWidth = 0.9f)
            }
        }
    }
}

/** Analyze's mark: a little chessboard inside four camera corners, so it reads "scan a board". */
@Composable
fun ScanGlyph(color: Color, modifier: Modifier = Modifier) {
    Canvas(modifier) {
        grid(34f, 32f) {
            val corners = Path().apply {
                moveTo(2f, 9f); lineTo(2f, 3f); lineTo(9f, 3f)
                moveTo(25f, 3f); lineTo(32f, 3f); lineTo(32f, 9f)
                moveTo(32f, 23f); lineTo(32f, 29f); lineTo(25f, 29f)
                moveTo(9f, 29f); lineTo(2f, 29f); lineTo(2f, 23f)
            }
            drawPath(corners, color, style = Stroke(2.2f, cap = StrokeCap.Round, join = StrokeJoin.Round))
            for (row in 0 until 4) for (col in 0 until 4) if ((row + col) % 2 == 0) {
                drawRect(color, Offset(9f + col * 4, 8f + row * 4), Size(4f, 4f))
            }
            drawRect(color, Offset(9f, 8f), Size(16f, 16f), style = Stroke(0.9f))
        }
    }
}

enum class TabKind { TODAY, LEARN, ROOMS, YOU }

/** The bottom bar's icons, drawn as on the iPhone: a pawn at sunrise, a bishop, a castle gate and a crowned shield. */
@Composable
fun TabIcon(kind: TabKind, color: Color, modifier: Modifier = Modifier) {
    Canvas(modifier.graphicsLayer(compositingStrategy = CompositingStrategy.Offscreen)) {
        grid(26f, 26f) {
            val line = Stroke(1.9f, cap = StrokeCap.Round, join = StrokeJoin.Round)
            when (kind) {
                TabKind.TODAY -> {
                    drawOval(color, Offset(9.5f, 3.5f), Size(7f, 7f))
                    drawPath(Path().apply {
                        moveTo(10f, 12f); lineTo(16f, 12f); lineTo(17.5f, 20f); lineTo(8.5f, 20f); close()
                        addRect(Rect(7f, 21f, 19f, 23.5f))
                    }, color)
                    val rays = Path().apply {
                        moveTo(3f, 7f); lineTo(6f, 7f); moveTo(20f, 7f); lineTo(23f, 7f); moveTo(13f, 1f); lineTo(13f, 2.5f)
                    }
                    drawPath(rays, color, style = Stroke(1.3f, cap = StrokeCap.Round))
                }
                TabKind.LEARN -> {
                    drawPath(Path().apply {
                        moveTo(13f, 2f)
                        cubicTo(16f, 5f, 18f, 8f, 18f, 11f)
                        cubicTo(18f, 13f, 16.5f, 14.5f, 15.5f, 15f)
                        lineTo(17f, 20f); lineTo(9f, 20f); lineTo(10.5f, 15f)
                        cubicTo(9.5f, 14.5f, 8f, 13f, 8f, 11f)
                        cubicTo(8f, 8f, 10f, 5f, 13f, 2f)
                        close()
                        addRect(Rect(7f, 21f, 19f, 23.5f))
                    }, color)
                    drawLine(Color.Black, Offset(14.5f, 6f), Offset(11.5f, 10f), strokeWidth = 1.4f, cap = StrokeCap.Round, blendMode = BlendMode.Clear)
                }
                TabKind.YOU -> {
                    drawPath(Path().apply {
                        moveTo(5f, 7f); lineTo(21f, 7f); lineTo(21f, 13f)
                        cubicTo(21f, 18f, 17f, 21f, 13f, 23f)
                        cubicTo(9f, 21f, 5f, 18f, 5f, 13f)
                        close()
                        moveTo(9f, 11f); lineTo(11f, 9f); lineTo(13f, 11f); lineTo(15f, 9f); lineTo(17f, 11f); lineTo(17f, 13f); lineTo(9f, 13f); close()
                    }, color, style = line)
                }
                TabKind.ROOMS -> {
                    drawPath(Path().apply {
                        moveTo(4f, 23f)
                        listOf(4f to 9f, 7f to 9f, 7f to 6f, 10f to 6f, 10f to 9f, 16f to 9f, 16f to 6f, 19f to 6f, 19f to 9f, 22f to 9f, 22f to 23f)
                            .forEach { (x, y) -> lineTo(x, y) }
                        close()
                        moveTo(10f, 23f); lineTo(10f, 17f)
                        arcTo(Rect(10f, 14f, 16f, 20f), 180f, 180f, false)
                        lineTo(16f, 23f)
                    }, color, style = line)
                    drawPath(Path().apply { moveTo(12f, 17f); lineTo(12f, 23f); moveTo(14f, 17f); lineTo(14f, 23f) }, color.copy(alpha = color.alpha * 0.7f), style = line)
                }
            }
        }
    }
}

/**
 * A rival's own picture, the still from its welcome film, cut square on its face and set in a
 * gold frame, as on the iPhone's Next game card.
 */
@Composable
fun RivalFrame(rival: Rival, side: Dp, modifier: Modifier = Modifier, dimmed: Boolean = false) {
    val image: ImageBitmap = ImageBitmap.imageResource(rival.still)
    val pad = side * 0.055f
    Box(
        modifier
            .size(side)
            .drawBehind {
                drawRoundRect(
                    Brush.linearGradient(
                        0f to Color(0xFFF3D99A), 0.45f to Color(0xFF9C6B2C), 0.7f to Color(0xFFE8C27A), 1f to Color(0xFF7A521F),
                        start = Offset.Zero, end = Offset(size.width, size.height),
                    ),
                    cornerRadius = CornerRadius(5.dp.toPx()),
                )
            }
            .padding(pad),
    ) {
        Canvas(Modifier.size(side - pad * 2).clip(RoundedCornerShape(3.dp))) {
            val w = image.width
            val top = (image.height * rival.faceTop).roundToInt()
            drawImage(
                image,
                srcOffset = IntOffset(0, top),
                srcSize = IntSize(w, w.coerceAtMost(image.height - top)),
                dstSize = IntSize(size.width.roundToInt(), size.height.roundToInt()),
                colorFilter = if (dimmed) ColorFilter.colorMatrix(androidx.compose.ui.graphics.ColorMatrix().apply { setToSaturation(0.15f) }) else null,
                alpha = if (dimmed) 0.75f else 1f,
            )
        }
    }
}
