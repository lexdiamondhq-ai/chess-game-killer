package com.chessgamekiller.app.game

import androidx.compose.ui.graphics.Color
import com.chessgamekiller.app.R

/**
 * The five rivals, as on the iPhone (Views/Rivals.swift and MatchController.Level): the same
 * names, pictures and Stockfish settings, after Lichess's calibrated levels.
 */
enum class Rival(
    val title: String,
    val shortName: String,
    val elo: String,
    val blurb: String,
    val skill: Int,
    val depth: Int?,
    val thinkTimeMs: Int,
    val portrait: Int,
    val coin: Int,
    val hue: Color,
) {
    CUB("The Cub", "Cub", "~1000",
        "Real players finding their feet. They leave pieces hanging, like people do.",
        3, 5, 50, R.drawable.rival_1000s, R.drawable.rival_1000s_coin, Color(0xFFEBD3A0)),
    HUNTER("The Hunter", "Hunter", "~1200",
        "Weekend players. They know an opening or two, then wander.",
        6, 5, 100, R.drawable.rival_1200s, R.drawable.rival_1200s_coin, Color(0xFFE6C483)),
    BERSERKER("The Berserker", "Berserker", "~1600",
        "Club players. Solid openings, then the slips real people make.",
        10, 5, 200, R.drawable.rival_1600s, R.drawable.rival_1600s_coin, Color(0xFFDDB46A)),
    LIONHEART("The Lionheart", "Lionheart", "~2000",
        "Strong players. Sharp, patient, and they rarely hand you a piece.",
        14, 5, 300, R.drawable.rival_2000s, R.drawable.rival_2000s_coin, Color(0xFFD6A24A)),
    ASHEN_KING("The Ashen King", "Ashen King", "2500+",
        "Grandmaster strength. Full Stockfish, no mercy.",
        20, null, 600, R.drawable.rival_masters, R.drawable.rival_masters_coin, Color(0xFFF2DCA8)),
}
