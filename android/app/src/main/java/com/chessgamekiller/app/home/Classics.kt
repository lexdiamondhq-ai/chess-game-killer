package com.chessgamekiller.app.home

import android.content.Context
import com.chessgamekiller.chess.Move
import com.chessgamekiller.chess.Position
import org.json.JSONObject
import java.time.LocalDate

/** A famous game, as in the iPhone's Famous Games room (classic-games.json). */
data class ClassicGame(
    val id: String,
    val white: String,
    val black: String,
    val event: String,
    val year: Int,
    val result: String,
    val blurb: String,
    val moves: List<String>,
) {
    /** "The Opera Game", or the players. */
    val title: String get() {
        val colon = blurb.indexOf(':')
        return if (colon in 1..34) blurb.substring(0, colon) else "${surname(white)} v ${surname(black)}"
    }

    /** What happens in it: the blurb after its name. */
    val story: String get() {
        val colon = blurb.indexOf(':')
        if (colon !in 1..34) return blurb
        val rest = blurb.substring(colon + 1).trim()
        return rest.replaceFirstChar { it.uppercase() }
    }

    /** "Morphy v Duke Karl & Count Isouard · 1858". */
    val players: String get() = "${surname(white)} v ${surname(black)}" + if (year > 0) " · $year" else ""

    /** The winner plays toward you. */
    val flipped: Boolean get() = result == "0-1"

    /** Every position from the start, then one after each move. */
    val frames: List<Position> by lazy {
        val out = mutableListOf(Position.start())
        for (uci in moves) {
            val move = Move.fromUci(uci) ?: break
            val last = out.last()
            if (!last.isLegal(move)) break
            out += last.play(last.normalize(move))
        }
        out
    }

    private fun surname(name: String): String =
        if (name.contains('&') || name.contains(',')) name else name.trim().split(' ').last()
}

object Classics {
    @Volatile private var cache: List<ClassicGame>? = null

    fun all(context: Context): List<ClassicGame> = cache ?: synchronized(this) {
        cache ?: load(context).also { cache = it }
    }

    /** Today's game: the same all day, a new one at midnight. */
    fun today(context: Context): ClassicGame? {
        val games = all(context).filter { it.moves.size > 7 }
        if (games.isEmpty()) return null
        return games[(LocalDate.now().toEpochDay() % games.size).toInt()]
    }

    private fun load(context: Context): List<ClassicGame> = runCatching {
        val text = context.assets.open("classic-games.json").bufferedReader().use { it.readText() }
        val list = JSONObject(text).getJSONArray("games")
        (0 until list.length()).map { i ->
            val g = list.getJSONObject(i)
            val moves = g.getJSONArray("moves")
            ClassicGame(
                id = g.getString("id"),
                white = g.getString("white"),
                black = g.getString("black"),
                event = g.optString("event"),
                year = g.optInt("year"),
                result = g.optString("result"),
                blurb = g.optString("blurb"),
                moves = (0 until moves.length()).map { moves.getString(it) },
            )
        }
    }.getOrDefault(emptyList())
}
