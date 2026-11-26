# First-time player pass (Nov 24-27, 2026)

Goal: when Apple clears the release, a brand-new player's first day in Beauty of Chess has nothing broken, nothing confusing and nothing that looks off.
Alex agreed to this on 2026-11-24 instead of download work, because the release is waiting on Apple.

Branch: `claude/first-time-player`, worktree `.worktrees/first-run`, from main `d815d0d`.
The main folder and Alex's phone builds are not touched.

## Steps

1. Build latest main for a fresh simulator that has never run the app.
   Proof: the app launches on the new simulator straight into the first-run pages.
2. Play it as a new player and log every issue in `docs/first-run-pass.md` (screen, what is wrong, screenshot).
   The route: first-run pages, first rival game to the end, a puzzle, a lesson, Coach Leo (Think and Talk it through), a photo scan, Analyze, a friend challenge link, Premium sign-up with Apple's test purchases (`Support/Premium.storekit`), Settings.
   Proof: the log lists each route stop as passed or with its issues, with a screenshot for each issue.
3. Fix the issues, smallest change that works, grouped into small pull requests.
   Proof: each PR shows before and after screenshots of the same screen, and the unit tests pass.
4. Bring PR #71 "No dead ends" up to date with main (a failed scan or talk gives the free try back).
   Proof: it merges cleanly, the tests pass, and a scan with the network off gives the try back on the simulator.
5. Run the full test suite and report to Alex.
   Proof: `xcodebuild test` output read in full; anything not checked on a real iPhone is named.

## Rules

- No creative changes (new looks, art, characters) without Alex's pick.
- Nothing merged without Alex's OK on the screenshots.
- No App Store Connect changes.
- Not verified on a real iPhone unless Alex installs the build; say so in every report.

## Status

- 2026-11-24: plan written, step 1 started.
- 2026-11-24: steps 1 and 2 done; the log is `docs/first-run-pass.md`.
  Step 3: F1 (Premium caps wording) and F2 ("A friend challenged you") fixed. F3 (cut-off shadows) needs Alex to pick a look; H2 (Analyze arrows) needs a look on Alex's iPhone.
  Step 4: main already counts a photo scan only when it is read, so only the talk half of #71 was left; a talk with no answer now gives the free talk back. The rest of #71 (lobby card, offer screen, Rewind) changes screens and still waits for Alex.
- 2026-11-24: checked the talk give-back in the app: with the coach server unreachable the free talk came back (count 0), and a real talk on the live server counted 1.
  The invite fix moved to its own PR #220 (with "A friend withdrew this challenge"); PR #219 keeps the Premium wording, the talk give-back, and this log.
  Step 4's scan half was read from the code (a scan counts only when the photo is read); a scan with the network off was not run on the simulator.
  Next: Alex picks the Premium wording and a shadow look, and checks the Analyze arrows on the iPhone.
