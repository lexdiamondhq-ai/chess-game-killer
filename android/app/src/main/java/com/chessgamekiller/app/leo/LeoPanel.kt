package com.chessgamekiller.app.leo

import android.app.Activity
import android.content.Intent
import android.speech.RecognizerIntent
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.Send
import androidx.compose.material.icons.filled.Mic
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.OutlinedTextFieldDefaults
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.chessgamekiller.app.ui.CarvedLabel
import com.chessgamekiller.app.ui.Palette
import com.chessgamekiller.app.ui.Type
import com.chessgamekiller.app.ui.card

/**
 * Talk It Through: say or type your plan, and Leo checks it.
 * [onAsk] gets the words and whether they were typed.
 */
@Composable
fun LeoPanel(
    reply: LeoReply?,
    busy: Boolean,
    modifier: Modifier = Modifier,
    prompt: String = "Tell Leo your plan before you move",
    onAsk: (said: String, typed: Boolean) -> Unit,
) {
    var text by remember { mutableStateOf("") }
    val listen = rememberLauncherForActivityResult(ActivityResultContracts.StartActivityForResult()) { result ->
        if (result.resultCode == Activity.RESULT_OK) {
            val heard = result.data?.getStringArrayListExtra(RecognizerIntent.EXTRA_RESULTS)?.firstOrNull()
            if (!heard.isNullOrBlank()) onAsk(heard, false)
        }
    }

    Column(modifier.fillMaxWidth().card(), verticalArrangement = Arrangement.spacedBy(10.dp)) {
        Row(verticalAlignment = Alignment.CenterVertically) {
            CarvedLabel("Leo")
            Spacer(Modifier.width(8.dp))
            Text(prompt, style = Type.small)
        }

        reply?.lines?.forEach { line ->
            val color = when (line.verdict) {
                "right", "best", "excellent", "good", "checkmate" -> Palette.good
                "wrong", "blunder", "mistake", "missed", "illegal" -> Palette.bad
                "partly", "inaccuracy" -> Palette.gold
                else -> Palette.inkSoft
            }
            Row(verticalAlignment = Alignment.Top) {
                Spacer(Modifier.padding(top = 7.dp).size(8.dp).clip(CircleShape).background(color))
                Spacer(Modifier.width(8.dp))
                Text(line.note, style = Type.body.copy(color = Palette.ink))
            }
        }
        reply?.answer?.let {
            Text("“$it”", style = Type.heading.copy(fontSize = 17.sp), modifier = Modifier.testTag("leo-answer"))
        }
        reply?.error?.let { Text(it, style = Type.small.copy(color = Palette.bad)) }

        Row(verticalAlignment = Alignment.CenterVertically) {
            OutlinedTextField(
                value = text,
                onValueChange = { text = it },
                placeholder = { Text("“His bishop eyes f7, so I castle”", style = Type.small) },
                singleLine = false,
                maxLines = 3,
                textStyle = Type.body,
                shape = RoundedCornerShape(16.dp),
                colors = OutlinedTextFieldDefaults.colors(
                    focusedBorderColor = Palette.gold,
                    unfocusedBorderColor = Palette.gold.copy(alpha = 0.3f),
                    cursorColor = Palette.gold,
                ),
                modifier = Modifier.weight(1f).testTag("leo-input"),
            )
            if (busy) {
                CircularProgressIndicator(color = Palette.gold, strokeWidth = 2.dp, modifier = Modifier.padding(12.dp).size(24.dp))
            } else if (text.isNotBlank()) {
                IconButton(onClick = { onAsk(text, true); text = "" }, modifier = Modifier.testTag("leo-send")) {
                    Icon(Icons.AutoMirrored.Filled.Send, contentDescription = "Send to Leo", tint = Palette.gold)
                }
            } else {
                IconButton(
                    onClick = {
                        val intent = Intent(RecognizerIntent.ACTION_RECOGNIZE_SPEECH)
                            .putExtra(RecognizerIntent.EXTRA_LANGUAGE_MODEL, RecognizerIntent.LANGUAGE_MODEL_FREE_FORM)
                            .putExtra(RecognizerIntent.EXTRA_PROMPT, "Tell Leo your plan")
                        runCatching { listen.launch(intent) }
                    },
                    modifier = Modifier.testTag("leo-mic"),
                ) {
                    Icon(Icons.Filled.Mic, contentDescription = "Speak to Leo", tint = Palette.gold)
                }
            }
        }
    }
}
