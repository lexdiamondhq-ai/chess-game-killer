# First-time player pass, 2026-11-24

Build: main `d815d0d`, Debug, on a brand-new iPhone 17 Pro simulator (iOS 26.5) that had never run the app.
Player: picked "I play now and then".
Screenshots are in `docs/first-run-pass/`.

## Route

| Stop | Result |
|---|---|
| First-run pages 1-4 | Pass. All four pages work; the rules on page 4 match the code. |
| First game (The Hunter) | Pass. Intro card, moves, grades, Think, resign and the end card all work. |
| Home after the game | Pass, one small issue (H3). |
| Learn and the first lesson | Pass, one question (Q2). The lesson's Black board is on purpose (you defend Scholar's Mate as Black). |
| Rated puzzle | Pass. Solved, rating 1,000 to 1,024. |
| Photo scan (Choose a photo) | Pass. The test photo read exactly right (the Nov 8 failure is gone). One visual issue (H2). |
| Play a friend | Pass. A real challenge was made on the server; the browser invite page opens. One issue (F2). |
| Premium page | Pass, one copy issue (F1). Cancelling Apple's sign-in returns cleanly. |
| Real purchase | Not tested: needs a run from Xcode with the StoreKit file, or TestFlight. |
| Talk it through (typed) | Pass. Typed a plan to Leo on the live coach server and got a real answer. Voice was not tested (the simulator has no microphone). One small issue (H4). |
| Talk with no answer | Pass after the fix. With the coach server unreachable, Leo says he needs the internet, and the free talk is given back (saved count stayed 0; a real talk afterward counted 1). (`14-talk-offline.jpg`) |

## Fix now (no creative call)

- **F1. Fixed. Premium promised scans "as often as you like".** Premium has a fair-use cap of 30 scans a day (`PremiumFeature.premium`). The store listing already says "near-unlimited". Make the app say the same. (`10-premium.jpg`)
  Now: "Talk It Through every day: up to 50 talks and 30 photo scans a day", and the limit cards say the same numbers.
- **F2. Fixed. A challenge sent without a name read "Player challenged you to chess".** The name field is optional, so the friend sees "Player". The invite page should read naturally when no name was given. (`11-friend-invite-page.jpg`)
  Now: "A friend challenged you to chess", and a withdrawn one reads "A friend withdrew this challenge" (checked on a local copy of the play server; the live page changes when PR #220 merges, since merging to main deploys it).
- **F3. Needs Alex's pick. Piece shadows above the board's back edge are cut off in a hard straight line.** Seen on every light screen with the 3D board: first-run board pick, lessons, puzzles, Analyze. On the cream background it reads as a grey smudge with a flat top. (`02-clipped-shadows.jpg`, `03-clipped-shadows-welcome.jpg`)
  My guess is that the 3D view's top edge cuts off shadows that fall behind the board. I didn't verify this.

## Needs a look on Alex's iPhone

- **H2. Analyze arrows show hard black boxes behind them on the simulator** (best move Re1, next best d3). The see-through look has been on main since Nov 7, so this may be a simulator-only drawing difference. It needs one look on a real phone before anyone changes code. (`04-analyze-arrows.jpg`)

## Small

- **H3. The first "Tap the knight to analyze" tip covers the Next game card's Play and Change buttons** on Home until it is dismissed. (`07-home-tip.jpg`)
- **H4. Leo's check can read "0 of 1 right" right above "Nf3, Best move".** The count covers only the ideas in your plan, not the move, so a best move plus one wrong idea shows 0 of 1. (Typed "develop my knight to f3 and castle". `13-talk-count.jpg`)
- Analyze offers "This game: the position in your game right now" after the game is already over.
- The notification permission pops up with no lead-in the first time you create a challenge.

## Questions for Alex (creative or product calls)

- **Q1. First-run page 1 is a plain list in the system font.** It shows none of the rivals, films or marble that make the app stand out, and it is the first thing a new player sees. (`01-welcome.jpg`)
- **Q2. One rated puzzle marks today's training "DONE"** while the welcome lesson is still unwatched, and the card then reads "Welcome to training" and "You've trained today" together. (`08-learn-done.jpg`)
- **Q3. Puzzles calls Cycles "the Woodpecker method"**, the name of another author's book. Your rule is to write ideas in the app's own words. (`09-puzzles.jpg`)
- **Q4. The grade card and the eval bar show two different numbers side by side** (for example 0.0 on the card and +1.0 on the bar). The card is the score after your move, the bar is the score now. A new player may read it as a contradiction. (`05-grade-vs-bar.jpg`) I read this from the code and didn't verify it in every position.

## Not verified

- VoiceOver: the accessibility tree lists Home's buttons while the first-run pages are up, which suggests VoiceOver can wander behind them. Not checked with VoiceOver itself.
- Anything on a real iPhone.
