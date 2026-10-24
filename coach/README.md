# Talk It Through: Coach Leo's server

Before a move, the player tells Coach Leo what they see and what they'll play, out loud or typed. This server
checks every claim against the rules and Stockfish's numbers (worked out on the iPhone and sent along), then has
Claude word Leo's answer, and ElevenLabs reads it in George's voice, the voice of the recorded lessons.
Claude never decides what's true: it turns the words into claims, and words the verdict the rules reached.

The workflow deploys it to **https://coach.chess-game-killer.workers.dev**. [PROTOCOL.md](PROTOCOL.md) is the contract with the app:
the request, the stream, the claim kinds, the grades and the limits.

## How it fits together

- `src/index.js`: the entry point. It checks each request (path, method, size, JSON, position, rate limit, daily
  budget), streams the answer and holds `TalkBudget`, the Durable Object that counts the day's talks and voice.
- `src/claims.js`: Claude call 1. The player's words, the position and its legal moves go in; typed claims come out
  as structured output (`CLAIMS_SCHEMA`), read charitably (speech-to-text slips like "night" for knight included).
- `src/verify.js`, `src/board.js`, `src/words.js`: the rules (chess.js) and the engine's numbers decide which claims
  are right, grade the move, and find what was missed. No AI in here.
- `src/answer.js`: Claude call 2. The checked facts go in; Leo's spoken answer comes out. A guard turns down
  wording with move notation or a square the facts don't name, and the server's own template answers instead.
- `src/voice.js`: George on ElevenLabs, with the lessons' model and settings (`scripts/training/make_narration.py`).
- `src/vendor/chess.js`: [chess.js](https://github.com/jhlywa/chess.js) 1.4.0 (BSD-2-Clause), the same copy as `play/`.

A talk streams `checked`, `answer`, `voice` and `done`, one JSON line each, so the app can light up the board
while Leo's words are still on their way. When something fails, the talk still ends well where it can:

| What fails | What the player gets |
|---|---|
| Claude call 1 (hearing the claims) | An `error` line (`upstream` or `timeout`) instead of the rest. |
| Claude call 2 (Leo's words), or the guard turns them down | The template answer (`source: "template"`). |
| ElevenLabs, its daily budget, or no key | `voice` says `unavailable`, and the app speaks with the device's voice. |
| A bug of ours | An `error` line with `internal`. |

Each talk logs one line of codes and timings (`{"talk":"done","claims":2,"parse_ms":…}`), never the player's words
or a key.

## Run it

Needs Node 22 or later.

```sh
cd coach
npm ci
npm test              # unit tests, no network
npm run check         # bundles it for Workers (dry run)
npm run dev           # http://localhost:8787, with the keys in coach/.dev.vars
```

`.dev.vars` holds `ANTHROPIC_API_KEY=…` and, for the voice, `ELEVENLABS_API_KEY=…` (it's in `.gitignore`).
Then talk to it:

```sh
curl -N localhost:8787/talk -H 'content-type: application/json' -d '{"v":1,
  "fen":"r1bqk2r/pppp1ppp/2n2n2/2b1p3/2B1P3/3P1N2/PPP2PPP/RNBQK2R w KQkq - 1 5",
  "said":"his bishop eyes f2 so I will castle", "voice":false}'
```

The live check runs the real pipeline in Node against the real APIs for every case in
`test/fixtures/talks.json`, and prints a table of what Claude heard, the verdicts, Leo's words, timings and tokens:

```sh
ANTHROPIC_API_KEY=… node test/live.mjs                      # ELEVENLABS_API_KEY=… adds one reading by George
ANTHROPIC_API_KEY=… node test/live.mjs --only castle --audio leo.mp3
```

It fails only on what's broken (a crash, claims that don't match the schema, a cut-off reply, a request Anthropic
turns down), not on wording. `test/make_facts.mjs` fills in Stockfish's numbers for the fixtures.
`npm run smoke -- <url>` runs the post-deploy check against any server: one talk, every line in order.

## Deploying

`.github/workflows/coach.yml` runs the tests and the bundle on every pull request that touches `coach/`, plus the
live check when the `ANTHROPIC_API_KEY` secret is set. On pushes to `main` it also deploys with wrangler and has one
talk with the live server (`test/smoke.mjs`). It needs `ANTHROPIC_API_KEY` and `CLOUDFLARE_API_TOKEN`;
`ELEVENLABS_API_KEY` is optional (no voice without it); the account ID is looked up from the token.

Settings (`[vars]` in `wrangler.toml`): `MODEL` (`claude-opus-5-5`), `PARSE_EFFORT` and `ANSWER_EFFORT` (`low`),
`CLAUDE_TIMEOUT_MS` (12000, for each Claude call), `DAILY_TALKS` (400) and `DAILY_VOICE_CHARS` (40000) across
everyone per UTC day, `VOICE_ID` (George, Leo's voice), `VERA_VOICE_ID` (Sarah, Vera's voice; requests with `coach: "vera"`) and `VOICE_MODEL` (`eleven_multilingual_v2`). Each address can start 12
talks a minute.

## What a talk costs

Two Claude Opus 5.5 calls at low effort, with the server-side fallback on, so a request Opus's safety classifiers
turn down is answered by another model rather than refused. The first call's instructions (about 1,700 tokens) are cached; the rest is the position, the words and the verdict,
around 1,500 tokens in all, plus a few hundred tokens out each, thinking included. That comes to about one or two
cents a talk at list prices, so `DAILY_TALKS` caps Claude at roughly $8 a day. The live check prints the measured
figure. The voice is 100 to 320 characters of ElevenLabs a talk; `DAILY_VOICE_CHARS` caps it at 40,000 a day.
