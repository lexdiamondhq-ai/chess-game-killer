package com.chessgamekiller.app

import android.graphics.Bitmap
import androidx.compose.ui.graphics.asAndroidBitmap
import androidx.compose.ui.test.assertIsDisplayed
import androidx.compose.ui.test.captureToImage
import androidx.compose.ui.test.hasTestTag
import androidx.compose.ui.test.hasText
import androidx.compose.ui.test.junit4.createAndroidComposeRule
import androidx.compose.ui.test.onNodeWithTag
import androidx.compose.ui.test.isRoot
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
        // With a dialog up there are two windows: take the top one.
        val roots = rule.onAllNodes(isRoot())
        val count = roots.fetchSemanticsNodes().size
        val bitmap = roots[count - 1].captureToImage().asAndroidBitmap()
        val context = InstrumentationRegistry.getInstrumentation().targetContext
        val dir = File(context.getExternalFilesDir(null), "screens").apply { mkdirs() }
        File(dir, "$name.png").outputStream().use { bitmap.compress(Bitmap.CompressFormat.PNG, 100, it) }
    }

    private fun tap(tag: String) = rule.onNodeWithTag(tag, useUnmergedTree = true).performClick()

    @Test fun homeLooksLikeTheIPhone() {
        rule.onNodeWithTag("home-title").assertIsDisplayed()
        rule.onNodeWithTag("day-board").assertIsDisplayed()
        rule.onNodeWithTag("bar-play").assertIsDisplayed()
        rule.onNodeWithTag("rival-cub").assertIsDisplayed()
        Thread.sleep(2500) // the board of the day plays its first move
        snap("01-home-today")
        rule.onNodeWithTag("game-of-the-day").performScrollTo()
        snap("02-home-for-today")
        tap("tab-rooms")
        rule.onNodeWithTag("page-rooms").assertIsDisplayed()
        snap("03-rooms")
        tap("tab-learn")
        rule.onNodeWithTag("learn-leo").assertIsDisplayed()
        snap("04-learn")
        tap("tab-you")
        snap("05-you")
        // The same screens by night.
        rule.onNodeWithTag("appearance-dark").performScrollTo().performClick()
        snap("06-you-dark")
        tap("tab-today")
        rule.onNodeWithTag("home-title").assertIsDisplayed()
        snap("07-home-today-dark")
        rule.onNodeWithTag("game-of-the-day").performScrollTo()
        snap("08-home-for-today-dark")
        tap("tab-rooms")
        snap("09-rooms-dark")
        tap("tab-you")
        rule.onNodeWithTag("appearance-automatic").performScrollTo().performClick()
        tap("tab-today")
    }

    @Test fun playAMoveAndTheCubAnswers() {
        tap("play-cub")
        rule.onNodeWithTag("board").assertIsDisplayed()
        tap("square-e2")
        snap("10-game-selected")
        tap("square-e4")
        // The Cub replies, and it is the player's move again with 1. e4 on the list.
        rule.waitForIdle()
        rule.waitUntil(15_000) {
            rule.onAllNodes(hasTestTag("game-status") and hasText("Your move")).fetchSemanticsNodes().isNotEmpty()
        }
        rule.onNode(hasTestTag("move-list") and hasText("1. e4 ", substring = true)).assertIsDisplayed()
        snap("11-game-after-reply")
        tap("take-back")
        rule.waitUntil(5_000) {
            rule.onAllNodes(hasTestTag("move-list") and hasText("You have White", substring = true)).fetchSemanticsNodes().isNotEmpty()
        }
    }

    @Test fun theGoldKnightPlaysTheRivalUpNext() {
        tap("bar-play")
        rule.onNodeWithTag("board").assertIsDisplayed()
        rule.onNodeWithTag("game-status").assertIsDisplayed()
        tap("game-back")
        rule.onNodeWithTag("home-title").assertIsDisplayed()
    }

    @Test fun resignEndsTheGame() {
        tap("play-cub")
        tap("square-d2"); tap("square-d4")
        rule.waitForIdle()
        rule.waitUntil(15_000) {
            rule.onAllNodes(hasTestTag("game-status") and hasText("Your move")).fetchSemanticsNodes().isNotEmpty()
        }
        tap("resign")
        tap("resign-confirm")
        rule.onNodeWithTag("end-play-again").assertIsDisplayed()
        snap("12-game-resigned")
        tap("end-play-again")
        rule.onNodeWithTag("game-status").assertIsDisplayed()
    }

    @Test fun optionsPicksASideAndPlays() {
        tap("options-cub")
        rule.onNodeWithTag("option-white").assertIsDisplayed()
        snap("13-options")
        tap("option-play")
        rule.onNodeWithTag("board").assertIsDisplayed()
    }

    @Test fun analyzeTheStartAndEditPieces() {
        tap("bar-analyze")
        snap("14-analyze-choice")
        tap("home-board")
        rule.waitUntil(15_000) {
            rule.onAllNodes(hasTestTag("engine-line-0"), useUnmergedTree = true).fetchSemanticsNodes().isNotEmpty()
        }
        snap("15-analyze")
        tap("rotate")
        tap("side-to-move")
        tap("edit-pieces")
        tap("brush-erase")
        tap("square-d8") // take Black's queen off
        tap("edit-pieces") // Done
        rule.onNodeWithTag("eval-bar", useUnmergedTree = true).assertIsDisplayed()
        tap("square-e2"); tap("square-e4")
        rule.onNodeWithTag("analyze-undo").performScrollTo().performClick()
    }

    @Test fun replayTheGameOfTheDay() {
        // Past it, so the card sits clear of the bottom bar.
        rule.onNodeWithTag("tile-leo").performScrollTo()
        tap("game-of-the-day")
        rule.onNodeWithTag("replay").assertIsDisplayed()
        tap("replay-next")
        snap("16-replay")
        tap("replay-back")
        rule.onNodeWithTag("home-title").assertIsDisplayed()
    }

    @Test fun leoIsInTheGame() {
        tap("tab-rooms")
        rule.onNodeWithTag("face-hunter").performScrollTo().performClick()
        rule.onNodeWithTag("leo-input").performScrollTo().assertIsDisplayed()
        rule.onNodeWithTag("leo-mic").assertIsDisplayed()
        snap("17-game-leo")
    }
}
