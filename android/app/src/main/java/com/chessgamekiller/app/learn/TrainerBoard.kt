package com.chessgamekiller.app.learn

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.chessgamekiller.app.Sounds
import com.chessgamekiller.app.engine.ChessEngine
import com.chessgamekiller.app.ui.BoardArrow
import com.chessgamekiller.app.ui.ChessBoard
import com.chessgamekiller.app.ui.GoldButton
import com.chessgamekiller.app.ui.Palette
import com.chessgamekiller.app.ui.QuietButton
import com.chessgamekiller.app.ui.Type
import com.chessgamekiller.chess.Move
import com.chessgamekiller.chess.Position
import com.chessgamekiller.chess.squareIndex
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch

/** The lessons' named colors on the board. */
fun trainingColor(name: String?): Color = when (name) {
    "red" -> Color(0xFFE0605A)
    "green" -> Color(0xFF6FC46A)
    "yellow", "orange" -> Color(0xFFE9B949)
    "violet", "pink" -> Color(0xFFA78BFA)
    "teal" -> Color(0xFF2FC9AE)
    else -> Color(0xFF7FA8FF)
}

fun arrowTone(name: String?): BoardArrow.Tone = when (name) {
    "red" -> BoardArrow.Tone.BAD
    "green" -> BoardArrow.Tone.GOOD
    "yellow", "orange" -> BoardArrow.Tone.BEST
    else -> BoardArrow.Tone.INFO
}

private fun uciArrow(uci: String?, tone: BoardArrow.Tone): BoardArrow? {
    val m = uci?.let { Move.fromUci(it) } ?: return null
    return BoardArrow(m.from, m.to, tone)
}

private fun pieceWord(c: Char) = when (c.lowercaseChar()) {
    'k' -> "king"; 'q' -> "queen"; 'r' -> "rook"; 'b' -> "bishop"; 'n' -> "knight"; else -> "pawn"
}

/**
 * One drill on the board, played like the iPhone's DrillRunner: the opponent's setup move first,
 * then the learner's turn. Move puzzles check each move (and any mate when mate counts), tap
 * puzzles want the squares in danger, yes-or-no puzzles show the move and then why, choices
 * explain each answer, and playouts are played to mate against Stockfish.
 */
class DrillState(
    val drill: Drill,
    private val scope: CoroutineScope,
    private val engine: ChessEngine?,
    private val lines: CoachLines?,
    promptTemplate: String?,
    private val sounds: Sounds?,
    private val success: String? = null,
    private val hintText: String? = null,
    private val wrongText: String? = null,
    private val feedback: Map<String, String> = emptyMap(),
    private val onFinished: (Outcome) -> Unit = {},
) {
    private val start = Position.fromFen(drill.fen) ?: Position.start()
    /** The position the learner faces, after the setup move. */
    private val faced: Position = drill.setup?.let { u -> Move.fromUci(u)?.let { m -> start.normalize(m) }?.takeIf { start.isLegal(it) }?.let { start.play(it) } } ?: start

    var position by mutableStateOf(start); private set
    var lastMove by mutableStateOf<Move?>(null); private set
    var arrows by mutableStateOf<List<BoardArrow>>(emptyList()); private set
    var marks by mutableStateOf<Map<Int, Color>>(emptyMap()); private set
    var message by mutableStateOf<String?>(null); private set
    /** True green, false red, null the coach's own words. */
    var good by mutableStateOf<Boolean?>(null); private set
    var busy by mutableStateOf(true); private set
    var done by mutableStateOf(false); private set
    var outcome by mutableStateOf<Outcome?>(null); private set
    /** Choice answers already tried. */
    var tried by mutableStateOf<Set<Int>>(emptySet()); private set

    val kind: String get() = drill.type
    val learnerWhite: Boolean = faced.whiteToMove
    private var mistakes = 0
    private var hints = 0
    private var index = 0
    private val found = mutableSetOf<String>()
    private var playoutMoves = 0

    val prompt: String = run {
        var text = drill.prompt ?: promptTemplate ?: "Find the best move."
        if ("{move}" in text) {
            val san = drill.move?.let { Move.fromUci(it) }?.let { m -> faced.normalize(m).takeIf { faced.isLegal(it) }?.let { faced.san(it) } } ?: drill.move ?: ""
            text = text.replace("{move}", san)
        }
        text.replace("{limit}", "${drill.limit ?: 10}")
    }

    private fun pick(list: List<String>?, fallback: String) = list?.randomOrNull() ?: fallback

    fun begin() {
        scope.launch {
            if (drill.setup != null && faced !== start) {
                delay(450)
                playUci(drill.setup)
            }
            if (kind == "safe") uciArrow(drill.move, BoardArrow.Tone.INFO)?.let { arrows = listOf(it) }
            busy = false
        }
    }

    private fun playUci(uci: String): Boolean {
        val m = Move.fromUci(uci)?.let { position.normalize(it) } ?: return false
        if (!position.isLegal(m)) return false
        val san = position.san(m)
        position = position.play(m)
        lastMove = m
        sounds?.playMove(san)
        return true
    }

    val canMove: Boolean get() = !busy && !done && (kind == "move" || kind == "playout") && position.whiteToMove == learnerWhite

    private fun finish(result: Outcome, text: String?, green: Boolean) {
        done = true
        busy = false
        outcome = result
        good = green
        message = text
        onFinished(result)
    }

    private fun succeed(extra: String? = null) {
        val clean = mistakes == 0 && hints == 0
        val opener = if (clean) pick(lines?.correct, "Yes! That's it.") else pick(lines?.correctAfterHint, "There it is.")
        val result = when { mistakes > 0 -> Outcome.AFTER_MISTAKE; hints > 0 -> Outcome.WITH_HINT; else -> Outcome.FIRST_TRY }
        finish(result, listOfNotNull(opener, extra ?: success ?: drill.explain).joinToString(" "), true)
    }

    // MARK: Moves

    fun onMove(m: Move) {
        if (!canMove) return
        val move = position.normalize(m)
        if (!position.isLegal(move)) return
        if (kind == "playout") { playout(move); return }
        val uci = move.uci
        val expected = drill.solution.getOrNull(index)
        val others = drill.alts.getOrNull(index / 2) ?: emptyList()
        val after = position.play(move)
        val mated = after.inCheck && after.legalMoves().isEmpty()
        marks = emptyMap()
        when {
            (drill.mate != null && mated) || (uci == expected && index + 1 >= drill.solution.size) -> {
                playUci(uci); index = drill.solution.size; arrows = emptyList(); succeed()
            }
            uci == expected -> {
                playUci(uci)
                index += 1
                good = true
                message = pick(lines?.keepGoing, "Good. Keep going.")
                busy = true
                scope.launch {
                    delay(550)
                    drill.solution.getOrNull(index)?.let { playUci(it) }
                    index += 1
                    busy = false
                    if (index >= drill.solution.size) succeed()
                }
            }
            uci in others -> { playUci(uci); succeed("That works too!") }
            else -> wrongMove(uci)
        }
    }

    private fun wrongMove(uci: String) {
        mistakes += 1
        good = false
        message = feedback[uci] ?: wrongText ?: pick(lines?.wrong, "Not quite. Have another look.")
        val before = position
        val beforeLast = lastMove
        playUci(uci)
        busy = true
        scope.launch {
            delay(700)
            position = before
            lastMove = beforeLast
            busy = false
            if (mistakes >= 3) reveal()
        }
    }

    private fun playout(move: Move) {
        playUci(move.uci)
        playoutMoves += 1
        val p = position
        when {
            p.inCheck && p.legalMoves().isEmpty() -> succeed("Checkmate in $playoutMoves.")
            p.legalMoves().isEmpty() -> playoutAgain("Stalemate! Their king had no move but wasn't in check. Leave it a square.")
            playoutMoves >= (drill.limit ?: 10) -> playoutAgain("Out of moves. Shrink the box first, then bring your king.")
            else -> {
                busy = true
                scope.launch {
                    delay(250)
                    val fen = position.fen
                    val reply = runCatching { engine?.chooseMove(fen, 20, null, 250) }.getOrNull()
                        ?: position.legalMoves().randomOrNull()?.uci
                    if (reply != null && position.fen == fen) playUci(reply)
                    busy = false
                }
            }
        }
    }

    private fun playoutAgain(why: String) {
        mistakes += 1
        good = false
        message = "$why Try again."
        busy = true
        scope.launch {
            delay(1200)
            position = faced
            lastMove = null
            playoutMoves = 0
            busy = false
            if (mistakes >= 3) finish(Outcome.MISSED, "Keep at it: this one comes with practice. It'll be back.", false)
        }
    }

    // MARK: Tap, yes-or-no, choice

    fun onTap(square: Int) {
        if (busy || done || kind != "tap") return
        val name = com.chessgamekiller.chess.squareName(square)
        if (name in drill.squares) {
            if (!found.add(name)) return
            marks = marks + (square to trainingColor("green"))
            if (found.containsAll(drill.squares)) {
                uciArrow(drill.setup, BoardArrow.Tone.BAD)?.let { arrows = listOf(it) }
                succeed()
            }
        } else {
            mistakes += 1
            good = false
            val piece = position[square]
            message = if (piece != '.' && piece.isUpperCase() == learnerWhite) "That one's safe. Look at what their pieces can reach now."
            else "Tap your piece that's in danger."
            marks = marks + (square to trainingColor("red"))
            scope.launch {
                delay(650)
                marks = marks - square
                if (mistakes >= 3 && !done) reveal()
            }
        }
    }

    fun answer(yes: Boolean) {
        if (busy || done || kind != "safe") return
        val right = yes == drill.answer
        if (!right) mistakes += 1
        busy = true
        val text = (if (right) pick(lines?.correct, "Yes!") + " " else "Not quite. ") + (drill.explain ?: "")
        message = text
        good = right
        scope.launch {
            delay(300)
            drill.move?.let { playUci(it) }
            arrows = emptyList()
            drill.reply?.let { reply ->
                delay(650)
                uciArrow(reply, BoardArrow.Tone.BAD)?.let { arrows = listOf(it) }
                playUci(reply)
            }
            finish(if (!right) Outcome.MISSED else if (hints > 0) Outcome.WITH_HINT else Outcome.FIRST_TRY, text, right)
        }
    }

    fun choose(i: Int) {
        if (busy || done || kind != "choice") return
        val option = drill.options.getOrNull(i) ?: return
        tried = tried + i
        uciArrow(option.move, if (option.correct) BoardArrow.Tone.GOOD else BoardArrow.Tone.BAD)?.let { arrows = listOf(it) }
        if (option.correct) {
            succeed(option.why)
        } else {
            mistakes += 1
            good = false
            message = option.why ?: wrongText ?: pick(lines?.wrong, "Not that one.")
        }
    }

    // MARK: Help

    fun hint() {
        if (busy || done) return
        hints += 1
        good = null
        when (kind) {
            "move" -> {
                val next = drill.solution.getOrNull(index)?.let { Move.fromUci(it) }
                if (next == null) {
                    message = hintText ?: "Look at every check first."
                } else if (hints == 1) {
                    marks = mapOf(next.from to trainingColor("yellow"))
                    message = hintText ?: "Try your ${pieceWord(position[next.from])} on ${com.chessgamekiller.chess.squareName(next.from)}."
                } else {
                    arrows = listOf(BoardArrow(next.from, next.to, BoardArrow.Tone.GOOD))
                    message = "There: play it."
                }
            }
            "tap" -> {
                uciArrow(drill.setup, BoardArrow.Tone.BAD)?.let { arrows = listOf(it) }
                message = hintText ?: "Follow their last move: what does it attack now?"
            }
            "safe" -> {
                val to = drill.move?.let { Move.fromUci(it) }?.to
                if (to != null) marks = mapOf(to to trainingColor("yellow"))
                message = hintText ?: "Count on that square: what of theirs can capture there, and what of yours defends it?"
            }
            "playout" -> message = "Shrink the box: take squares away from their king, and bring your king closer. Don't check for the sake of it."
            else -> message = hintText ?: "Take the center, bring out a piece, keep your king safe."
        }
    }

    /** Shows the answer: the rest of the line, or the squares. Counts as missed. */
    fun reveal() {
        if (done || (busy && kind != "move")) return
        when (kind) {
            "tap" -> {
                marks = drill.squares.mapNotNull { squareIndex(it) }.associateWith { trainingColor("green") }
                finish(Outcome.MISSED, "Here: " + (drill.explain ?: drill.squares.joinToString(", ")), false)
            }
            "choice" -> {
                val right = drill.options.indexOfFirst { it.correct }
                uciArrow(drill.options.getOrNull(right)?.move, BoardArrow.Tone.GOOD)?.let { arrows = listOf(it) }
                finish(Outcome.MISSED, "It's \"${drill.options.getOrNull(right)?.text}\". ${drill.options.getOrNull(right)?.why ?: ""}", false)
            }
            "safe" -> answer(drill.answer != true)
            "playout" -> finish(Outcome.MISSED, "Keep at it: this one comes with practice. It'll be back.", false)
            else -> scope.launch {
                busy = true
                val rest = drill.solution.drop(index)
                for ((i, uci) in rest.withIndex()) {
                    if (i % 2 == 0) uciArrow(uci, BoardArrow.Tone.GOOD)?.let { arrows = listOf(it) }
                    delay(650)
                    playUci(uci)
                }
                finish(Outcome.MISSED, "Here's how it goes. " + (success ?: drill.explain ?: ""), false)
            }
        }
    }
}

/** The prompt, the board, the coach's words and the buttons for one drill. [footer] shows once it's done. */
@Composable
fun DrillPanel(
    state: DrillState,
    modifier: Modifier = Modifier,
    flipped: Boolean = !state.learnerWhite,
    yesLabel: String = "Yes",
    noLabel: String = "No",
    footer: @Composable () -> Unit = {},
) {
    Column(modifier.fillMaxWidth(), verticalArrangement = Arrangement.spacedBy(10.dp)) {
        Text(state.prompt, style = Type.heading.copy(fontSize = 19.sp), modifier = Modifier.padding(horizontal = 18.dp).testTag("drill-prompt"))
        ChessBoard(
            position = state.position,
            flipped = flipped,
            lastMove = state.lastMove,
            arrows = state.arrows,
            marks = state.marks,
            interactive = state.canMove,
            onMove = { state.onMove(it) },
            onSquareTap = if (state.kind == "tap") ({ sq -> state.onTap(sq) }) else null,
            modifier = Modifier.padding(horizontal = 6.dp),
        )
        Text(
            state.message ?: "",
            style = Type.body.copy(
                fontWeight = FontWeight.Medium,
                color = when (state.good) { true -> Palette.good; false -> Palette.bad; null -> Palette.ink },
            ),
            modifier = Modifier.padding(horizontal = 18.dp).heightIn(min = 44.dp).testTag("drill-message"),
        )
        if (!state.done) {
            when (state.kind) {
                "safe" -> Row(Modifier.fillMaxWidth().padding(horizontal = 16.dp), horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                    GoldButton(yesLabel, modifier = Modifier.weight(1f).testTag("safe-yes"), enabled = !state.busy) { state.answer(true) }
                    GoldButton(noLabel, modifier = Modifier.weight(1f).testTag("safe-no"), enabled = !state.busy) { state.answer(false) }
                }
                "choice" -> Column(Modifier.fillMaxWidth().padding(horizontal = 16.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
                    state.drill.options.forEachIndexed { i, option ->
                        QuietButton(option.text, enabled = i !in state.tried, modifier = Modifier.fillMaxWidth().testTag("choice-$i")) { state.choose(i) }
                    }
                }
            }
            Row(Modifier.fillMaxWidth().padding(horizontal = 16.dp), horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                QuietButton("Hint", modifier = Modifier.weight(1f).testTag("drill-hint"), enabled = !state.busy) { state.hint() }
                QuietButton("Show me", modifier = Modifier.weight(1f).testTag("drill-show"), enabled = !state.busy) { state.reveal() }
            }
        } else {
            footer()
        }
    }
}
