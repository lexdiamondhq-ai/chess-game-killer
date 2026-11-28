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
    /** The rival's bronze coin: its face on the iPhone's cards. */
    val portrait: Int,
    val hue: Color,
    /** The still from its welcome film, 9:16. */
    val still: Int,
    /** The film's name and one line on how it plays, as in the rivals' hall. */
    val film: String,
    val lore: String,
    /** Its strength, for your rating. */
    val strength: Int,
    /** Where a square crop starts down the still, so it sits on the rider's face. */
    val faceTop: Float = 0.07f,
) {
    CUB("The Cub", "Cub", "~1000",
        "Real players finding their feet. They leave pieces hanging, like people do.",
        3, 5, 50, R.drawable.rival_1000s_coin, Color(0xFFEBD3A0),
        R.drawable.rival_1000s_card, "Out of the birches", "Wears the fox. Still learning the hunt.", 1000),
    HUNTER("The Hunter", "Hunter", "~1200",
        "Weekend players. They know an opening or two, then wander.",
        6, 5, 100, R.drawable.rival_1200s_coin, Color(0xFFE6C483),
        R.drawable.rival_1200s_card, "Out of the snow", "Wears the wolf. Knows the trail, then loses the scent.", 1200),
    BERSERKER("The Berserker", "Berserker", "~1600",
        "Club players. Solid openings, then the slips real people make.",
        10, 5, 200, R.drawable.rival_1600s_coin, Color(0xFFDDB46A),
        R.drawable.rival_1600s_card, "Through the storm", "Wears the bear. Charges in, then slips when it counts.", 1600),
    LIONHEART("The Lionheart", "Lionheart", "~2000",
        "Strong players. Sharp, patient, and they rarely hand you a piece.",
        14, 5, 300, R.drawable.rival_2000s_coin, Color(0xFFD6A24A),
        R.drawable.rival_2000s_card, "Down from the throne", "Wears the lion. Rules by the hammer, and never yields a square.", 2000),
    ASHEN_KING("The Ashen King", "Ashen King", "2500+",
        "Grandmaster strength. Full Stockfish, no mercy.",
        20, null, 600, R.drawable.rival_masters_coin, Color(0xFFF2DCA8),
        R.drawable.rival_masters_card, "The storm throne", "Crowned in bone and ash. Plays the masters' moves, then the machine's.", 2500, 0.2f),
    ;

    /** "1200", without the "~". */
    val eloPlain: String get() = elo.removePrefix("~")
    /** "Face the Hunter". */
    val faceLabel: String get() = "Face the " + title.removePrefix("The ")
    /** "Rival 2 of 5". */
    val place: String get() = "Rival ${ordinal + 1} of ${entries.size}"
}
