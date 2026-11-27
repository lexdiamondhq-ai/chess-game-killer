package com.chessgamekiller.app

import android.content.Context
import android.content.SharedPreferences
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import com.chessgamekiller.app.game.Rival
import java.time.LocalDate
import kotlin.math.pow
import kotlin.math.roundToInt

/** Light, dark, or as the phone is. */
enum class Appearance(val label: String) { SYSTEM("Automatic"), LIGHT("Light"), DARK("Dark") }

/** Which side you take against a rival. */
enum class SideChoice(val label: String) { WHITE("White"), BLACK("Black"), RANDOM("Either") }

/**
 * What the app remembers on this phone: your settings, your rating, the rivals you've beaten and
 * your streak. Home's numbers (Rating, Wins, Streak) read from here.
 */
object Progress {
    private lateinit var prefs: SharedPreferences

    var appearance by mutableStateOf(Appearance.SYSTEM)
        private set
    var soundsOn by mutableStateOf(true)
        private set
    var musicOn by mutableStateOf(true)
        private set
    var side by mutableStateOf(SideChoice.WHITE)
        private set
    /** Nil until your first finished game: Home shows "New". */
    var rating by mutableStateOf<Int?>(null); private set
    var games by mutableIntStateOf(0)
        private set
    var wins by mutableIntStateOf(0)
        private set
    var streak by mutableIntStateOf(0)
        private set
    var beaten by mutableStateOf<Set<String>>(emptySet()); private set

    fun load(context: Context) {
        if (::prefs.isInitialized) return
        prefs = context.getSharedPreferences("progress", Context.MODE_PRIVATE)
        appearance = runCatching { Appearance.valueOf(prefs.getString("appearance", null)!!) }.getOrDefault(Appearance.SYSTEM)
        soundsOn = prefs.getBoolean("sounds", true)
        musicOn = prefs.getBoolean("music", true)
        side = runCatching { SideChoice.valueOf(prefs.getString("side", null)!!) }.getOrDefault(SideChoice.WHITE)
        rating = prefs.getInt("rating", 0).takeIf { it > 0 }
        games = prefs.getInt("games", 0)
        wins = prefs.getInt("wins", 0)
        beaten = prefs.getStringSet("beaten", emptySet())!!.toSet()
        streak = liveStreak()
    }

    fun setAppearance(value: Appearance) { appearance = value; prefs.edit().putString("appearance", value.name).apply() }
    fun setSounds(on: Boolean) { soundsOn = on; prefs.edit().putBoolean("sounds", on).apply() }
    fun setMusic(on: Boolean) { musicOn = on; prefs.edit().putBoolean("music", on).apply() }
    fun setSide(value: SideChoice) { side = value; prefs.edit().putString("side", value.name).apply() }

    /** The rival up next: the first one not yet beaten, else the Ashen King. */
    val upNext: Rival get() = Rival.entries.firstOrNull { it.name !in beaten } ?: Rival.ASHEN_KING

    /**
     * A finished game: [score] is 1 for a win, 0.5 for a draw, 0 for a loss. The rating moves
     * like Elo against the rival's strength, starting from 1200.
     */
    fun record(rival: Rival, score: Double) {
        val now = rating ?: 1200
        val expected = 1.0 / (1.0 + 10.0.pow((rival.strength - now) / 400.0))
        val k = if (games < 10) 40 else 24
        rating = (now + k * (score - expected)).roundToInt().coerceIn(100, 3200)
        games += 1
        if (score >= 1.0) { wins += 1; beaten = beaten + rival.name }
        val today = LocalDate.now().toEpochDay()
        val last = prefs.getLong("lastDay", -1)
        val run = prefs.getInt("run", 0)
        val newRun = when (today - last) { 0L -> run.coerceAtLeast(1); 1L -> run + 1; else -> 1 }
        prefs.edit()
            .putInt("rating", rating!!).putInt("games", games).putInt("wins", wins)
            .putStringSet("beaten", beaten).putLong("lastDay", today).putInt("run", newRun)
            .apply()
        streak = newRun
    }

    /** The run of days in a row with a game, or 0 once a day has been missed. */
    private fun liveStreak(): Int {
        val last = prefs.getLong("lastDay", -1)
        if (last < 0) return 0
        return if (LocalDate.now().toEpochDay() - last <= 1) prefs.getInt("run", 0) else 0
    }
}
