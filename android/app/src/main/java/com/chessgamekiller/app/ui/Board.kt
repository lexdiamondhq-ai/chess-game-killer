package com.chessgamekiller.app.ui

import androidx.compose.foundation.Canvas
import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.aspectRatio
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.Path
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.chessgamekiller.app.R
import com.chessgamekiller.chess.Move
import com.chessgamekiller.chess.Position
import com.chessgamekiller.chess.fileOf
import com.chessgamekiller.chess.rankOf
import com.chessgamekiller.chess.squareName
import kotlin.math.atan2
import kotlin.math.cos
import kotlin.math.sin

/** An arrow drawn on the board: good (green), bad (red), info (the coach's blue) or best (gold). */
data class BoardArrow(val from: Int, val to: Int, val tone: Tone = Tone.INFO) {
    enum class Tone { GOOD, BAD, INFO, BEST }
}

fun pieceDrawable(c: Char): Int = when (c) {
    'K' -> R.drawable.piece_wk; 'Q' -> R.drawable.piece_wq; 'R' -> R.drawable.piece_wr
    'B' -> R.drawable.piece_wb; 'N' -> R.drawable.piece_wn; 'P' -> R.drawable.piece_wp
    'k' -> R.drawable.piece_bk; 'q' -> R.drawable.piece_bq; 'r' -> R.drawable.piece_br
    'b' -> R.drawable.piece_bb; 'n' -> R.drawable.piece_bn; else -> R.drawable.piece_bp
}

private fun pieceName(c: Char): String {
    val color = if (c.isUpperCase()) "White" else "Black"
    val kind = when (c.lowercaseChar()) {
        'k' -> "king"; 'q' -> "queen"; 'r' -> "rook"; 'b' -> "bishop"; 'n' -> "knight"; else -> "pawn"
    }
    return "$color $kind"
}

/**
 * The board. Tap a piece, then tap where it goes. With [onSquareTap] set it only reports taps
 * (the piece editor). Every square carries a test tag like "square-e2" for the tap tests.
 */
@Composable
fun ChessBoard(
    position: Position,
    modifier: Modifier = Modifier,
    flipped: Boolean = false,
    lastMove: Move? = null,
    arrows: List<BoardArrow> = emptyList(),
    interactive: Boolean = true,
    highlights: Set<Int> = emptySet(),
    /** Squares tinted by a lesson or drill: green found, red wrong, yellow a hint. */
    marks: Map<Int, Color> = emptyMap(),
    /** Small words on squares, from a lesson ("3", "x"). */
    labels: Map<Int, String> = emptyMap(),
    onMove: (Move) -> Unit = {},
    onSquareTap: ((Int) -> Unit)? = null,
    /** Letters and numbers on the edge squares; off on a small board. */
    coordinates: Boolean = true,
    /** Square tags for the tap tests; off on a small board so they stay unique. */
    tagged: Boolean = true,
) {
    var selected by remember { mutableStateOf<Int?>(null) }
    var promotion by remember { mutableStateOf<Pair<Int, Int>?>(null) }
    LaunchedEffect(position.fen) { selected = null }

    val legal = remember(position.fen) { position.legalMoves() }
    val targets = selected?.let { s -> legal.filter { it.from == s }.map { it.to }.toSet() } ?: emptySet()
    val checkSquare = if (position.inCheck) position.kingSquare(position.whiteToMove) else -1

    fun tap(square: Int) {
        if (onSquareTap != null) { onSquareTap(square); return }
        if (!interactive) return
        val piece = position[square]
        val mine = piece != '.' && piece.isUpperCase() == position.whiteToMove
        val from = selected
        when {
            from != null && square in targets -> {
                if (position.needsPromotion(from, square)) promotion = from to square
                else onMove(Move(from, square))
                selected = null
            }
            mine -> selected = if (selected == square) null else square
            else -> selected = null
        }
    }

    BoxWithConstraints(
        modifier
            .fillMaxWidth()
            .aspectRatio(1f)
            .clip(RoundedCornerShape(6.dp))
            .border(1.dp, Palette.gold.copy(alpha = 0.45f), RoundedCornerShape(6.dp))
            .then(if (tagged) Modifier.testTag("board") else Modifier),
    ) {
        val cell = maxWidth / 8
        Column(Modifier.fillMaxSize()) {
            for (row in 0..7) {
                Row(Modifier.fillMaxWidth().weight(1f)) {
                    for (col in 0..7) {
                        val file = if (flipped) 7 - col else col
                        val rank = if (flipped) row else 7 - row
                        val sq = rank * 8 + file
                        val light = (file + rank) % 2 == 1
                        val piece = position[sq]
                        val base = if (light) Palette.lightSquare else Palette.darkSquare
                        Box(
                            Modifier
                                .weight(1f)
                                .fillMaxSize()
                                .background(base)
                                .background(
                                    when {
                                        sq == selected -> Palette.selected
                                        sq in marks -> marks.getValue(sq).copy(alpha = 0.5f)
                                        sq in highlights -> Palette.info.copy(alpha = 0.35f)
                                        lastMove != null && (sq == lastMove.from || sq == lastMove.to) -> Palette.lastMove
                                        else -> Color.Transparent
                                    },
                                )
                                .then(if (tagged) Modifier.testTag("square-${squareName(sq)}") else Modifier)
                                .semantics {
                                    contentDescription = squareName(sq) + if (piece != '.') ", " + pieceName(piece) else ""
                                }
                                .clickable(
                                    interactionSource = remember { MutableInteractionSource() },
                                    indication = null,
                                ) { tap(sq) },
                            contentAlignment = Alignment.Center,
                        ) {
                            if (sq == checkSquare) {
                                Box(Modifier.fillMaxSize().background(
                                    androidx.compose.ui.graphics.Brush.radialGradient(
                                        listOf(Palette.check.copy(alpha = 0.85f), Color.Transparent),
                                    ),
                                ))
                            }
                            if (piece != '.') {
                                Image(
                                    painterResource(pieceDrawable(piece)),
                                    contentDescription = null,
                                    modifier = Modifier.fillMaxSize().padding(cell * 0.06f),
                                )
                            }
                            labels[sq]?.let { word ->
                                Box(
                                    Modifier.align(Alignment.Center).clip(RoundedCornerShape(50))
                                        .background(Color(0xCC1A140F)).padding(horizontal = 5.dp, vertical = 1.dp),
                                ) { Text(word, fontSize = 11.sp, fontWeight = FontWeight.Bold, color = Palette.goldTop) }
                            }
                            if (sq in targets) {
                                if (piece == '.') Box(Modifier.size(cell * 0.3f).clip(CircleShape).background(Palette.hintDot))
                                else Box(Modifier.fillMaxSize().padding(2.dp).border(3.dp, Palette.hintDot, CircleShape))
                            }
                            // Coordinates on the edge squares.
                            if (coordinates && col == 0) Text(
                                "${'1' + rank}",
                                fontSize = 9.sp, fontWeight = FontWeight.SemiBold,
                                color = if (light) Palette.labelOnLight else Palette.labelOnDark,
                                modifier = Modifier.align(Alignment.TopStart).padding(start = 2.dp, top = 1.dp),
                            )
                            if (coordinates && row == 7) Text(
                                "${'a' + file}",
                                fontSize = 9.sp, fontWeight = FontWeight.SemiBold,
                                color = if (light) Palette.labelOnLight else Palette.labelOnDark,
                                modifier = Modifier.align(Alignment.BottomEnd).padding(end = 3.dp, bottom = 1.dp),
                            )
                        }
                    }
                }
            }
        }
        if (arrows.isNotEmpty()) {
            Canvas(Modifier.fillMaxSize()) {
                val s = size.width / 8
                fun center(sq: Int): Offset {
                    val col = if (flipped) 7 - fileOf(sq) else fileOf(sq)
                    val row = if (flipped) rankOf(sq) else 7 - rankOf(sq)
                    return Offset(col * s + s / 2, row * s + s / 2)
                }
                for (a in arrows) {
                    val color = when (a.tone) {
                        BoardArrow.Tone.GOOD -> Palette.good
                        BoardArrow.Tone.BAD -> Palette.bad
                        BoardArrow.Tone.INFO -> Palette.info
                        BoardArrow.Tone.BEST -> Palette.gold
                    }.copy(alpha = 0.85f)
                    val start = center(a.from)
                    val end = center(a.to)
                    val angle = atan2(end.y - start.y, end.x - start.x)
                    val head = s * 0.42f
                    // Start at the piece's edge, not its middle, so the piece stays visible.
                    val lift = Offset(cos(angle) * s * 0.3f, sin(angle) * s * 0.3f)
                    val shaftEnd = Offset(end.x - cos(angle) * head * 0.8f, end.y - sin(angle) * head * 0.8f)
                    drawLine(color, start + lift, shaftEnd, strokeWidth = s * 0.16f, cap = StrokeCap.Round)
                    val path = Path().apply {
                        moveTo(end.x, end.y)
                        lineTo(end.x - cos(angle - 0.5f) * head, end.y - sin(angle - 0.5f) * head)
                        lineTo(end.x - cos(angle + 0.5f) * head, end.y - sin(angle + 0.5f) * head)
                        close()
                    }
                    drawPath(path, color)
                }
            }
        }
    }

    promotion?.let { (from, to) ->
        val white = position.whiteToMove
        AlertDialog(
            onDismissRequest = { promotion = null },
            containerColor = Palette.card,
            title = { Text("Promote to", style = Type.heading) },
            text = {
                Row(horizontalArrangement = Arrangement.SpaceEvenly, modifier = Modifier.fillMaxWidth()) {
                    for (p in "qrbn") {
                        val c = if (white) p.uppercaseChar() else p
                        Image(
                            painterResource(pieceDrawable(c)),
                            contentDescription = pieceName(c),
                            modifier = Modifier
                                .size(56.dp)
                                .testTag("promote-$p")
                                .clickable { promotion = null; onMove(Move(from, to, p)) },
                        )
                    }
                }
            },
            confirmButton = {},
        )
    }
}
