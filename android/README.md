# Beauty of Chess for Android

The first Android build, for Google Play testing: the five rivals, Analyze with the photo
scanner, and Leo (Talk It Through). It uses the same servers as the iPhone app
(`coach/`, `scanner/`), so nothing on the server side changes.

- `chess/`: the rules of chess in plain Kotlin (moves, check, notation, draws), with tests.
- `app/`: the Android app in Jetpack Compose. Package name `com.chessgamekiller.app`, the same as
  the iPhone bundle ID.
- Stockfish 17 comes from the official Android release and is added by
  `.github/workflows/android.yml` as `app/src/main/jniLibs/<abi>/libstockfish.so`. Without it
  (the emulator) the app falls back to a tiny stand-in engine so the screens still work.

Builds run on GitHub (the Android workflow): it runs the tests, builds a debug APK and a release
AAB for Google Play, and runs tap tests on an emulator with a picture of each step.

Not in this first build yet: Premium payments (Google Play Billing; Premium is free for testers),
phone alerts (Firebase instead of Apple's push), friend games, Learn, Rooms, the 3D board and the
rival films.
