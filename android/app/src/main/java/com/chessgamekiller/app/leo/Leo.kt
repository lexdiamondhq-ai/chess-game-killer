package com.chessgamekiller.app.leo

import android.content.Context
import android.media.MediaPlayer
import android.speech.tts.TextToSpeech
import android.util.Base64
import com.chessgamekiller.app.engine.ChessEngine
import com.chessgamekiller.app.engine.EngineLine
import com.chessgamekiller.app.ui.BoardArrow
import com.chessgamekiller.chess.Position
import com.chessgamekiller.chess.squareIndex
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import org.json.JSONArray
import org.json.JSONObject
import java.io.BufferedReader
import java.io.File
import java.io.InputStreamReader
import java.net.HttpURLConnection
import java.net.URL
import java.util.Locale

/** Where the player asked Leo: in a game, or on the Analyze board. */
enum class TalkContext(val wire: String) { GAME("game"), ANALYSIS("analysis") }

/** One line Leo checked: what they said and whether it holds. */
data class CheckedLine(val said: String, val verdict: String, val note: String)

/** What Leo sends back, filled in as the stream arrives. */
data class LeoReply(
    val lines: List<CheckedLine> = emptyList(),
    val arrows: List<BoardArrow> = emptyList(),
    val squares: Set<Int> = emptySet(),
    val answer: String? = null,
    val error: String? = null,
)

/**
 * Talk It Through on Android: the same coach server as the iPhone (coach/PROTOCOL.md).
 * Stockfish scores the position on the phone; the server checks the claims and words Leo's answer.
 */
class LeoClient(
    private val context: Context,
    private val engine: ChessEngine,
    private val baseUrl: String = "https://coach.chess-game-killer.workers.dev",
) {
    private var player: MediaPlayer? = null
    private var tts: TextToSpeech? = null

    /** Stockfish's facts for the position: every legal move scored (up to 40), and the opponent's threats. */
    suspend fun facts(fen: String): JSONObject? {
        val position = Position.fromFen(fen) ?: return null
        val count = position.legalMoves().size
        if (count == 0) return null
        val moves = engine.analyze(fen, DEPTH, minOf(count, 40), 3000)
        if (moves.isEmpty()) return null
        val threats = position.nullMove()?.let { engine.analyze(it.fen, DEPTH, 6, 1500) } ?: emptyList()
        return JSONObject()
            .put("depth", DEPTH)
            .put("moves", lines(moves))
            .put("threats", lines(threats))
    }

    private fun lines(found: List<EngineLine>): JSONArray {
        val out = JSONArray()
        for (line in found) {
            val first = line.moves.firstOrNull() ?: continue
            val eval = JSONObject()
            if (line.eval.mate != null) eval.put("mate", line.eval.mate) else eval.put("cp", line.eval.cp ?: 0)
            out.put(JSONObject().put("uci", first).put("eval", eval).put("pv", JSONArray(line.moves.take(10))))
        }
        return out
    }

    /**
     * Sends what the player said and calls [update] as each part of Leo's reply comes in.
     * Plays Leo's voice when it arrives, or the phone's own voice when it can't.
     */
    suspend fun talk(
        fen: String,
        said: String,
        typed: Boolean,
        reveal: Boolean,
        talkContext: TalkContext,
        lastMove: String?,
        voice: Boolean,
        update: (LeoReply) -> Unit,
    ) = withContext(Dispatchers.IO) {
        var reply = LeoReply()
        fun emit(r: LeoReply) { reply = r; update(r) }

        val facts = facts(fen)
        val body = JSONObject()
            .put("v", 1)
            .put("fen", fen)
            .put("said", said.trim().take(800))
            .put("typed", typed)
            .put("reveal", reveal)
            .put("context", talkContext.wire)
            .put("voice", voice)
        lastMove?.let { body.put("lastMove", it) }
        facts?.let { body.put("facts", it) }

        val connection = (URL("$baseUrl/talk").openConnection() as HttpURLConnection).apply {
            requestMethod = "POST"
            doOutput = true
            connectTimeout = 15_000
            readTimeout = 45_000
            setRequestProperty("content-type", "application/json")
        }
        try {
            connection.outputStream.use { it.write(body.toString().toByteArray()) }
            val status = connection.responseCode
            if (status != 200) {
                val error = runCatching {
                    JSONObject(connection.errorStream.bufferedReader().readText()).optString("error")
                }.getOrNull()
                emit(reply.copy(error = friendlyError(error)))
                return@withContext
            }
            val reader = BufferedReader(InputStreamReader(connection.inputStream))
            while (true) {
                val text = reader.readLine() ?: break
                if (text.isBlank()) continue
                val line = runCatching { JSONObject(text) }.getOrNull() ?: continue
                when (line.optString("type")) {
                    "checked" -> emit(readChecked(line, reply))
                    "answer" -> emit(reply.copy(answer = line.optString("text")))
                    "voice" -> {
                        val audio = line.optString("audio", "")
                        if (audio.isNotEmpty()) playMp3(audio) else reply.answer?.let { speak(it) }
                    }
                    "error" -> {
                        emit(reply.copy(error = reply.error ?: "Leo lost his words. Try again."))
                        if (reply.answer == null) break
                    }
                    "done" -> break
                }
            }
        } catch (e: Exception) {
            emit(reply.copy(error = "Couldn't reach Leo. Check your connection and try again."))
        } finally {
            connection.disconnect()
        }
    }

    private fun friendlyError(code: String?): String = when (code) {
        "rate_limited" -> "Leo needs a breath. Try again in a minute."
        "daily_limit" -> "Leo has talked all he can today. He's back tomorrow."
        "bad_request" -> "Leo couldn't read this position."
        else -> "Couldn't reach Leo. Try again."
    }

    private fun readChecked(line: JSONObject, before: LeoReply): LeoReply {
        val lines = mutableListOf<CheckedLine>()
        val arrows = mutableListOf<BoardArrow>()
        val squares = mutableSetOf<Int>()
        fun collect(item: JSONObject?) {
            item ?: return
            item.optJSONArray("arrows")?.let { list ->
                for (i in 0 until list.length()) {
                    val a = list.optJSONObject(i) ?: continue
                    val from = squareIndex(a.optString("from")) ?: continue
                    val to = squareIndex(a.optString("to")) ?: continue
                    val tone = when (a.optString("tone")) {
                        "good" -> BoardArrow.Tone.GOOD
                        "bad" -> BoardArrow.Tone.BAD
                        else -> BoardArrow.Tone.INFO
                    }
                    arrows.add(BoardArrow(from, to, tone))
                }
            }
            item.optJSONArray("squares")?.let { list ->
                for (i in 0 until list.length()) squareIndex(list.optString(i))?.let { squares.add(it) }
            }
        }
        line.optJSONObject("move")?.let { move ->
            collect(move)
            val note = move.optString("note", "")
            if (note.isNotEmpty()) lines.add(CheckedLine(move.optString("said"), move.optString("grade"), note))
        }
        line.optJSONArray("claims")?.let { claims ->
            for (i in 0 until claims.length()) {
                val c = claims.optJSONObject(i) ?: continue
                collect(c)
                lines.add(CheckedLine(c.optString("said"), c.optString("verdict"), c.optString("note")))
            }
        }
        line.optJSONArray("missed")?.let { missed ->
            for (i in 0 until missed.length()) {
                val m = missed.optJSONObject(i) ?: continue
                collect(m)
                lines.add(CheckedLine("You missed", "missed", m.optString("note")))
            }
        }
        line.optString("nudge", "").takeIf { it.isNotEmpty() && it != "null" }?.let {
            lines.add(CheckedLine("Hint", "nudge", it))
        }
        return before.copy(lines = lines, arrows = arrows, squares = squares)
    }

    private fun playMp3(base64: String) {
        runCatching {
            val bytes = Base64.decode(base64, Base64.DEFAULT)
            val file = File(context.cacheDir, "leo.mp3")
            file.writeBytes(bytes)
            player?.release()
            player = MediaPlayer().apply {
                setDataSource(file.absolutePath)
                prepare()
                start()
            }
        }
    }

    /** The phone's own voice, when Leo's can't come. */
    fun speak(text: String) {
        val existing = tts
        if (existing != null) {
            existing.speak(text, TextToSpeech.QUEUE_FLUSH, null, "leo")
            return
        }
        var created: TextToSpeech? = null
        created = TextToSpeech(context) { status ->
            if (status == TextToSpeech.SUCCESS) {
                created?.setLanguage(Locale.US)
                created?.speak(text, TextToSpeech.QUEUE_FLUSH, null, "leo")
            }
        }
        tts = created
    }

    fun stop() {
        player?.release(); player = null
        tts?.stop()
    }

    fun close() {
        stop()
        tts?.shutdown(); tts = null
    }

    companion object {
        const val DEPTH = 12
    }
}
