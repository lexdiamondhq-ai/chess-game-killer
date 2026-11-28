package com.chessgamekiller.app

import android.content.Context
import android.media.AudioAttributes
import android.media.SoundPool

/** The iPhone's board sounds: a soft tock on a move, a capture, castling, check, and the game's end. */
class Sounds(context: Context) {
    private val pool = SoundPool.Builder()
        .setMaxStreams(3)
        .setAudioAttributes(
            AudioAttributes.Builder()
                .setUsage(AudioAttributes.USAGE_GAME)
                .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION)
                .build(),
        )
        .build()

    private val move = pool.load(context, R.raw.move_soft, 1)
    private val capture = pool.load(context, R.raw.capture_soft, 1)
    private val castle = pool.load(context, R.raw.castle, 1)
    private val check = pool.load(context, R.raw.check, 1)
    private val win = pool.load(context, R.raw.win, 1)
    private val defeat = pool.load(context, R.raw.defeat, 1)

    fun playMove(san: String) {
        val id = when {
            san.endsWith("+") || san.endsWith("#") -> check
            san.startsWith("O-O") -> castle
            "x" in san -> capture
            else -> move
        }
        pool.play(id, 1f, 1f, 1, 0, 1f)
    }

    fun playEnd(won: Boolean?) {
        pool.play(if (won == true) win else defeat, 0.9f, 0.9f, 1, 0, 1f)
    }
}
