package com.chessgamekiller.app.learn

import android.content.Context
import android.media.MediaPlayer
import com.chessgamekiller.app.Progress
import java.security.MessageDigest

/**
 * Coach Leo's recorded voice for the lessons: the same files as the iPhone, named "nar-" and the
 * first 12 hex digits of the line's SHA-1. A line without a recording is just shown.
 */
class Narrator(private val context: Context) {
    private var player: MediaPlayer? = null

    companion object {
        fun fileName(text: String): String {
            val digest = MessageDigest.getInstance("SHA-1").digest(text.toByteArray(Charsets.UTF_8))
            return "nar-" + digest.joinToString("") { "%02x".format(it) }.take(12)
        }
    }

    /** Says a line out loud, stopping whatever was playing. Quiet when sounds are off in You. */
    fun say(text: String?, onDone: () -> Unit = {}) {
        stop()
        if (text.isNullOrBlank() || !Progress.soundsOn) { onDone(); return }
        val ok = runCatching {
            val fd = context.assets.openFd("narration/${fileName(text.trim())}.mp3")
            val p = MediaPlayer()
            p.setDataSource(fd.fileDescriptor, fd.startOffset, fd.length)
            fd.close()
            p.setOnCompletionListener { onDone() }
            p.prepare()
            p.start()
            player = p
        }.isSuccess
        if (!ok) onDone()
    }

    fun stop() {
        player?.let { runCatching { it.stop() }; it.release() }
        player = null
    }
}
