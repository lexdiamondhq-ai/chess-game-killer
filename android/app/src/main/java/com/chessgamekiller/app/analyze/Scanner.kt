package com.chessgamekiller.app.analyze

import android.content.Context
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.Matrix
import android.net.Uri
import androidx.exifinterface.media.ExifInterface
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import org.json.JSONObject
import java.io.ByteArrayOutputStream
import java.net.HttpURLConnection
import java.net.URL
import java.util.Calendar

/** What the scanner read: 64 cells (a1 first), the side to move, and whether it was sure of the turn. */
data class Reading(val cells: CharArray, val whiteToMove: Boolean, val sureOfTurn: Boolean, val confidence: String)

class ScanException(message: String) : Exception(message)

/**
 * The photo scanner, shared with the iPhone (scanner/ in this repo): send a picture of a board,
 * get the position back. Claude reads it on the server; the key never leaves the server.
 */
class Scanner(
    private val context: Context,
    private val endpoint: String = "https://chess-game-killer-scanner.chess-game-killer.workers.dev",
) {
    suspend fun read(uri: Uri): Reading = withContext(Dispatchers.IO) {
        val jpeg = prepared(uri) ?: throw ScanException("Couldn't open that picture.")
        val connection = (URL("$endpoint/read").openConnection() as HttpURLConnection).apply {
            requestMethod = "POST"
            doOutput = true
            connectTimeout = 15_000
            readTimeout = 60_000
            setRequestProperty("Content-Type", "image/jpeg")
            setRequestProperty("X-Scan-Count", nextScanCount().toString())
        }
        try {
            connection.outputStream.use { it.write(jpeg) }
            val status = connection.responseCode
            val body = (if (status in 200..299) connection.inputStream else connection.errorStream)
                ?.bufferedReader()?.readText().orEmpty()
            if (status == 429) throw ScanException("The scanner is busy. Try again in a minute.")
            if (status !in 200..299) throw ScanException("The scanner couldn't read that one. Try again.")
            parse(body)
        } catch (e: ScanException) {
            throw e
        } catch (e: Exception) {
            throw ScanException("Couldn't reach the scanner. Check your connection.")
        } finally {
            connection.disconnect()
        }
    }

    /** The picture, upright and no bigger than 1568 pixels on a side, as JPEG. */
    private fun prepared(uri: Uri): ByteArray? {
        val resolver = context.contentResolver
        val bounds = BitmapFactory.Options().apply { inJustDecodeBounds = true }
        resolver.openInputStream(uri)?.use { BitmapFactory.decodeStream(it, null, bounds) }
        if (bounds.outWidth <= 0) return null
        var sample = 1
        while (maxOf(bounds.outWidth, bounds.outHeight) / (sample * 2) >= 1568) sample *= 2
        val decoded = resolver.openInputStream(uri)?.use {
            BitmapFactory.decodeStream(it, null, BitmapFactory.Options().apply { inSampleSize = sample })
        } ?: return null
        val rotation = runCatching {
            resolver.openInputStream(uri)?.use { ExifInterface(it).rotationDegrees } ?: 0
        }.getOrDefault(0)
        var bitmap = decoded
        if (rotation != 0) {
            bitmap = Bitmap.createBitmap(decoded, 0, 0, decoded.width, decoded.height, Matrix().apply { postRotate(rotation.toFloat()) }, true)
        }
        val longest = maxOf(bitmap.width, bitmap.height)
        if (longest > 1568) {
            val scale = 1568f / longest
            bitmap = Bitmap.createScaledBitmap(bitmap, (bitmap.width * scale).toInt(), (bitmap.height * scale).toInt(), true)
        }
        return ByteArrayOutputStream().use { out ->
            bitmap.compress(Bitmap.CompressFormat.JPEG, 85, out)
            out.toByteArray()
        }
    }

    /** This month's scans so far, counting this one (the server reads the first ones with its fastest model). */
    private fun nextScanCount(): Int {
        val prefs = context.getSharedPreferences("scanner", Context.MODE_PRIVATE)
        val now = Calendar.getInstance()
        val month = now.get(Calendar.YEAR) * 100 + now.get(Calendar.MONTH) + 1
        val count = if (prefs.getInt("month", 0) == month) prefs.getInt("count", 0) + 1 else 1
        prefs.edit().putInt("month", month).putInt("count", count).apply()
        return count
    }

    companion object {
        /** Turns the server's rows (as the picture shows them) into a board, by which edge White sits on. */
        fun parse(body: String): Reading {
            val json = runCatching { JSONObject(body) }.getOrNull() ?: throw ScanException("The scanner couldn't read that one.")
            if (!json.optBoolean("found")) throw ScanException("No chess board in that picture. Try a closer, straighter shot.")
            val rowsJson = json.optJSONArray("rows") ?: throw ScanException("The scanner couldn't read that one.")
            val rows = (0 until rowsJson.length()).map { rowsJson.optString(it) }
            if (rows.size != 8 || rows.any { it.length != 8 }) throw ScanException("The scanner couldn't read that one.")
            val side = json.optString("white_side", "bottom")
            val cells = CharArray(64) { '.' }
            for (row in 0..7) for (column in 0..7) {
                val (file, rank) = when (side) {
                    "top" -> (7 - column) to row
                    "left" -> row to column
                    "right" -> (7 - row) to (7 - column)
                    else -> column to (7 - row)
                }
                cells[rank * 8 + file] = rows[row][column]
            }
            val turn = json.optString("side_to_move", "")
            return Reading(
                cells = cells,
                whiteToMove = turn != "black",
                sureOfTurn = turn == "white" || turn == "black",
                confidence = json.optString("confidence", "medium"),
            )
        }
    }
}
