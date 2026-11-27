package com.chessgamekiller.app

import android.graphics.Bitmap
import androidx.compose.ui.graphics.asAndroidBitmap
import androidx.compose.ui.test.assertIsDisplayed
import androidx.compose.ui.test.captureToImage
import androidx.compose.ui.test.hasTestTag
import androidx.compose.ui.test.hasText
import androidx.compose.ui.test.junit4.createAndroidComposeRule
import androidx.compose.ui.test.onNodeWithTag
import androidx.compose.ui.test.onRoot
import androidx.compose.ui.test.performClick
import androidx.compose.ui.test.performScrollTo
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import java.io.File

/**
 * Real taps on the real screens: each test taps what a player taps and checks what happens next.
 * Pictures of each step land in the app's files/screens folder for the pull request.
 */
@RunWith(AndroidJUnit4::class)
class TapTests {
    @get:Rule val rule = createAndroidComposeRule<MainActivity>()

    private fun snap(name: String) {
        rule.waitForIdle()
        val bitmap = rule.onRoot().captureToImage().asAndroidBitmap()
        val context = InstrumentationRegistry.getInstrumentation().targetContext
        val dir = File(context.getExternalFilesDir(null), "screens").apply { mkdirs() }
        File(dir, "$name.png").outputStream().use { bitmap.compress(Bitmap.CompressFormat.PNG, 100, it) }
    }

    private fun tap(tag: String) = rule.onNodeWithTag(tag, useUnmergedTree = true).performClick()

    @Test fun homeShowsRivalsAndAnalyze() {
        rule.onNodeWithTag("home-title").assertIsDisplayed()
        rule.onNodeWithTag("home-scan").assertIsDisplayed()
        snap("01-home")
        rule.onNodeWithTag("rival-ashen_king").performScrollTo().assertIsDisplayed()
        snap("02-home-rivals")
    }

    @Test fun playAMoveAndTheCubAnswers() {
        rule.onNodeWithTag("play-cub").performScrollTo().performClick()
        rule.onNodeWithTag("board").assertIsDisplayed()
        tap("square-e2")
        snap("03-game-selected")
        tap("square-e4")
        // The Cub replies, and it is the player's move again with 1. e4 on the list.
        rule.waitForIdle()
        rule.waitUntil(15_000) {
            rule.onAllNodes(hasTestTag("game-status") and hasText("Your move")).fetchSemanticsNodes().isNotEmpty()
        }
        rule.onNode(hasTestTag("move-list") and hasText("1. e4 ", substring = true)).assertIsDisplayed()
        snap("04-game-after-reply")
        tap("take-back")
        rule.waitUntil(5_000) {
            rule.onAllNodes(hasTestTag("move-list") and hasText("You have White", substring = true)).fetchSemanticsNodes().isNotEmpty()
        }
    }

    @Test fun resignEndsTheGame() {
        rule.onNodeWithTag("play-cub").performScrollTo().performClick()
        tap("square-d2"); tap("square-d4")
        rule.waitForIdle()
        rule.waitUntil(15_000) {
            rule.onAllNodes(hasTestTag("game-status") and hasText("Your move")).fetchSemanticsNodes().isNotEmpty()
        }
        tap("resign")
        tap("resign-confirm")
        rule.onNodeWithTag("end-play-again").assertIsDisplayed()
        snap("05-game-resigned")
        tap("end-play-again")
        rule.onNodeWithTag("game-status").assertIsDisplayed()
    }

    @Test fun analyzeTheStartAndEditPieces() {
        rule.onNodeWithTag("home-board").performScrollTo().performClick()
        rule.waitUntil(15_000) {
            rule.onAllNodes(hasTestTag("engine-line-0"), useUnmergedTree = true).fetchSemanticsNodes().isNotEmpty()
        }
        snap("06-analyze")
        tap("rotate")
        tap("side-to-move")
        tap("edit-pieces")
        tap("brush-erase")
        tap("square-d8") // take Black's queen off
        snap("07-analyze-editing")
        tap("edit-pieces") // Done
        rule.onNodeWithTag("eval-bar").assertIsDisplayed()
        tap("square-e2"); tap("square-e4")
        rule.onNodeWithTag("analyze-undo").performScrollTo().performClick()
    }

    @Test fun leoIsInTheGame() {
        rule.onNodeWithTag("play-hunter").performScrollTo().performClick()
        rule.onNodeWithTag("leo-input").performScrollTo().assertIsDisplayed()
        rule.onNodeWithTag("leo-mic").assertIsDisplayed()
        snap("08-game-leo")
    }
}
