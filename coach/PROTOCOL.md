# Talk It Through: the coach server's protocol

Before you move, you tell Leo your plan, out loud or typed: "his bishop eyes h7, so h6, and my knight
is safe." Leo checks every claim and answers in his voice: "Right about the bishop. But your knight
isn't safe: your d-pawn is pinned."

**Claude only turns what the player said into claims, and words the answer. The rules (chess.js) and
Stockfish decide what is true.** Leo never invents chess.

- `coach/` is a Cloudflare Worker named `coach`: `https://coach.chess-game-killer.workers.dev`.
- The iPhone runs Stockfish while the player talks and sends the engine's numbers with the request,
  so the server never runs an engine and one request does everything.
- Deployed from main by `.github/workflows/coach.yml` with the repository secrets `ANTHROPIC_API_KEY`,
  `ELEVENLABS_API_KEY` and `CLOUDFLARE_API_TOKEN` (the same ones the scanner and the sounds use).

```
iPhone                                    coach worker                         services
hold the orb ─ speech → text (on device)
             ─ Stockfish: every legal move, and the opponent's best moves if it were their turn
release ──── POST /talk ───────────────→ check the request, rate limit, daily budget
                                          Claude: what they said → typed claims ─→ Anthropic
                                          chess.js + the engine numbers → verdicts
         ←── line: checked ─────────────
                                          Claude: verdicts → Leo's answer       ─→ Anthropic
         ←── line: answer ──────────────
                                          Leo's voice (Liam)                  ─→ ElevenLabs
         ←── line: voice ───────────────
         ←── line: done ────────────────
```

## Words

- **P**: the position in the request. The player is the side to move in P.
- **M**: the move the player says they will play, when they name one and it is legal.
- **P′**: P after M (the opponent to move).
- **N**: the *null-move* position: P with the other side to move (en passant cleared). It answers "what
  would the opponent do if it were their turn?", which is what a threat is. There is no N when the player
  is in check.
- **Eval** `{"cp": 35}` or `{"mate": 3}`. Centipawns, or mate in n (positive: the side whose view it is
  mates; zero or negative: it gets mated). Every eval names whose view it is.

## POST /talk

`content-type: application/json`, at most 32 KB.

```json
{
  "v": 1,
  "fen": "r1bqk2r/pppp1ppp/2n2n2/2b1p3/2B1P3/3P1N2/PPP2PPP/RNBQK2R w KQkq - 1 5",
  "said": "his bishop eyes f2 so I'll castle, and my knight on f3 is safe",
  "typed": false,
  "reveal": false,
  "context": "game",
  "lastMove": "f8c5",
  "voice": true,
  "facts": {
    "depth": 12,
    "moves": [
      { "uci": "e1g1", "eval": { "cp": 31 }, "pv": ["e1g1", "d7d6", "c2c3"] },
      { "uci": "c2c3", "eval": { "cp": 28 }, "pv": ["c2c3", "d7d6", "e1g1"] }
    ],
    "threats": [
      { "uci": "c5f2", "eval": { "cp": -120 }, "pv": ["c5f2", "e1f2", "f6g4"] }
    ]
  }
}
```

| Field | |
|---|---|
| `v` | Always 1. |
| `fen` | Required. The position. The player is the side to move. |
| `said` | Required. What the player said or typed, 1 to 800 characters after trimming. |
| `typed` | Optional, default false. False means speech to text, so words may be misheard ("night" for knight, "age six" for h6). |
| `reveal` | Optional, default false. May Leo name the best move? True in games when hints are on; false in training, where Leo nudges instead ("Look at your knight."). |
| `context` | Optional: `"game"` (default), `"session"` (Leo's daily session) or `"analysis"`. |
| `lastMove` | Optional. The opponent's last move in engine notation (`f8c5`), for "he just…" claims. |
| `voice` | Optional, default true. False skips the voice line (muted coach). |
| `facts` | Optional but expected. Without it, engine-dependent claims come back `unclear`. |
| `coach` | Optional: `"vera"` for Coach Vera (her persona, Sarah's voice). Anything else, or left out, is Leo (Liam's voice). |
| `facts.depth` | The search depth used. |
| `facts.moves` | The player's legal moves, scored by Stockfish in P (MultiPV), **from the player's view**, best first. Ideally every legal move (the app asks for up to 40 lines). `pv` is the line from that move, at most 10 moves, engine notation. |
| `facts.threats` | Stockfish's best moves for the opponent in N (MultiPV 6), **from the opponent's view**, best first. Empty or missing when the player is in check. |

The server drops facts it can't use (moves that aren't legal, malformed evals) rather than refusing the
request. A `pv` is trusted only as far as its moves are legal.

### Errors before the stream starts

A plain JSON body and an HTTP status:

| Status | Body |
|---|---|
| 400 | `{"error": "bad_request", "detail": "…"}` (bad JSON, bad FEN, game over, `said` empty or too long) |
| 404 / 405 | `{"error": "not_found"}` / `{"error": "method_not_allowed"}` |
| 413 | `{"error": "too_large"}` |
| 415 | `{"error": "unsupported_type"}` |
| 429 | `{"error": "rate_limited"}` (12 a minute per address) or `{"error": "daily_limit"}` (the day's talks across everyone are used up) |
| 503 | `{"error": "not_configured"}` (no Anthropic key) |

### The stream

Otherwise `200` with `content-type: application/x-ndjson`: one JSON object per line, in this order.

1. `checked`: always first.
2. `answer`: Leo's words.
3. `voice`: only when `voice` is true.
4. `done`.

An `{"type": "error", "error": "upstream" | "timeout" | "internal"}` line can replace the lines still to
come; the stream then ends. A client that loses the connection after `checked` keeps what it has.

#### `checked`

```json
{
  "type": "checked",
  "understood": true,
  "player": "white",
  "move": {
    "said": "I'll castle",
    "san": "O-O", "uci": "e1g1",
    "grade": "best",
    "note": "O-O is the best move.",
    "reply": { "san": "d6", "uci": "d7d6" },
    "squares": ["e1", "g1"],
    "arrows": [{ "from": "e1", "to": "g1", "tone": "good" }]
  },
  "claims": [
    {
      "id": "c1",
      "said": "his bishop eyes f2",
      "kind": "attacks",
      "verdict": "right",
      "note": "The bishop on c5 hits f2.",
      "squares": ["c5", "f2"],
      "arrows": [{ "from": "c5", "to": "f2", "tone": "info" }]
    },
    {
      "id": "c2",
      "said": "my knight on f3 is safe",
      "kind": "safe",
      "verdict": "right",
      "note": "Nothing can take the knight on f3 and win it.",
      "squares": ["f3"],
      "arrows": []
    }
  ],
  "missed": [],
  "habits": { "threats": "good", "forcing": "none", "safety": "good" },
  "eval": { "cp": 31 },
  "best": null,
  "nudge": null
}
```

| Field | |
|---|---|
| `understood` | False when nothing they said was about the position: then `move` is null and `claims` is empty. |
| `player` | `"white"` or `"black"`. |
| `move` | The move they said they would play, or null. `san`/`uci` are null when it isn't legal, or when it fits two moves ("Nd7" with both knights able to go there). `grade`: `checkmate`, `best`, `excellent`, `good`, `inaccuracy`, `mistake`, `blunder` (the app's thresholds, see below), `illegal`, or `unknown` (legal but not in the facts, or fitting two moves). `reply`: the opponent's best answer from the engine, or null. |
| `claims` | At most 6, in the order said. `kind` is one of the kinds below. `verdict`: `right`, `wrong`, `partly`, `unclear`. `note` is one line for the screen; it may use move notation. |
| `missed` | At most 2 things that mattered and weren't said: `{ "kind": "threat" \| "hanging" \| "mate" \| "free", "note", "squares", "arrows" }`. `mate` is the opponent's mate threat, or a mate the player has. |
| `habits` | Leo's Traffic Light. Each is `good`, `missed` or `none` (nothing to judge). `threats`: did they name the opponent's real threat (red)? `forcing`: when the best move is a check, capture or attack that wins something, did they look at it (yellow)? `safety`: is the move they chose safe, not dropping material (green)? |
| `eval` | P with best play, from the player's view (from the facts), or null. |
| `best` | The engine's move, `{ "san", "uci" }`, only when `reveal` is true; otherwise null. |
| `nudge` | When `reveal` is false and their move isn't the best: a hint that names the piece, not the square ("Look at your knight."). Otherwise null. |
| `squares`, `arrows` | What to light on the board for that line. `tone`: `good` (green), `bad` (red), `info` (the coach's accent). |

**Grades** use the app's scale (`MoveReview.grade`): the loss in winning chances
`2 / (1 + exp(-0.00368208 · cp)) − 1` (cp clamped to ±1000, mates count as ±1) between the best move's eval
and M's, both from `facts.moves`: below 0.04 `excellent`, 0.10 `good`, 0.20 `inaccuracy`, 0.30 `mistake`,
else `blunder`. M equal to the first line is `best`; M that mates on the board is `checkmate`.

#### `answer`

```json
{ "type": "answer", "text": "Right about the bishop eyeing f2, and castling is the best move here.", "source": "leo" }
```

`text` is what Leo says: at most 320 characters, in plain spoken words (no move notation: "bishop takes h7,
check", not "Bxh7+"), so it reads well and speaks well. `source` is `"leo"` (Claude worded it) or
`"template"` (the server's own wording, used when Claude is slow, fails, or names a square the checked facts
don't contain).

#### `voice`

```json
{ "type": "voice", "format": "mp3", "audio": "<base64>" }
```

or `{ "type": "voice", "unavailable": "budget" | "upstream" | "not_configured" }`, when the app should speak
the answer with the device's voice instead.

#### `done`

`{ "type": "done" }`

## Claim kinds

What the server can check, and how. "Their position" is P′ when the claim is about after M, else P.
For something the opponent could do in P, the server looks in N.

| Kind | Example | Right when |
|---|---|---|
| `threat` | "he threatens Bxf2+", "he wants to take my knight" | The move (or a capture of the named piece) is legal for the opponent in N (or P′) and is one of the engine's threats there gaining a pawn or more over the eval and winning material along its line, or wins material by exchange, or mates. (The material test keeps a quiet move from counting just because the player has a strong move of their own, which lifts P's eval.) `partly`: real, but a bigger threat exists (named in the note). `wrong`: not legal, or it loses material. |
| `attacks` | "his bishop eyes h7" | The piece attacks the square. `partly`: same line but blocked (names the blocker). |
| `defends` | "my knight defends e5" | The piece covers the square. `partly`: it covers it but is pinned and can't take back. |
| `safe` | "my knight is safe", "after h6 my king is safe", "he has no threats" | The other side can't win the piece by capturing it (exchange count with legal moves, so pinned defenders don't count); for the king, no mate or decisive check against it in the facts. With no piece and no square ("nothing of mine is hanging", "he isn't threatening anything"): no piece of `side` can be won and the other side has no real threat. |
| `hanging` | "his rook on a8 is free" | It can be won by capturing. `partly`: it can be taken, but taking it loses to the engine's reply (named). |
| `pinned` | "my d-pawn is pinned" | Pinned to the king, or to a queen or rook behind it. |
| `check` | "Bb5 is check" | The move is legal and gives check. |
| `mate` | "Qxf7 is mate", "I have mate in two", "he threatens mate" | The move mates on the board, or the facts show the mate. `partly`: strong, but the defence isn't forced (names the escape). |
| `wins` | "Nxe5 wins a pawn" | Following the engine's line from that move, the material comes out at least that far ahead. `partly`: it wins less. |
| `line` | "if he takes, I take back with the bishop" | Every move is legal in turn, and the opponent's reply is the engine's. `partly`: legal, but the opponent has a better reply (named). |
| `eval` | "I'm winning", "it's about equal" | The facts' eval falls in the same band: winning ≥ +3, better +1…+3, slightly better +0.4…+1, equal within ±0.4 (and the mirror bands). `partly`: the next band. |
| `material` | "I'm up a pawn", "we're even" | The material count (1, 3, 3, 5, 9) agrees. `partly`: the right side is ahead, by another amount. |
| `plan` | "push the h-pawn", "trade queens" | A concrete first move is graded like M (good or better is right). Vague plans are `unclear`. |

## Server internals

For the people working on `coach/src`: these are the seams between the files.

```
src/index.js    routes, validation, rate limit, the budget, the NDJSON stream; exports TalkBudget
src/claims.js   Claude call 1. parseClaims(client, env, input) → parsed
src/verify.js   verifyTalk({ fen, facts, parsed, reveal, said }) → { checked, spoken }   (no network; said is
                optional, for spoken.said, which is otherwise rebuilt from parsed)
src/words.js    move notation → spoken words; piece and square names
src/answer.js   Claude call 2. wordAnswer(client, env, { checked, spoken }) → { text, source }
                templateAnswer(checked, spoken) → string; guardAnswer(text, spoken) → string | null
src/voice.js    speak(env, text, fetchImpl) → Uint8Array | null   (ElevenLabs)
src/vendor/chess.js   chess.js 1.4.0, the same file as play/public/vendor/chess.js
```

`parsed`, what Claude heard (claims.js normalizes Claude's JSON to exactly this):

```json
{
  "about": true,
  "move": { "said": "I'll castle", "san": "O-O" },
  "claims": [
    {
      "said": "his bishop eyes f2",
      "kind": "attacks",
      "side": "opponent",
      "piece": "B",
      "square": "c5",
      "target": "f2",
      "moves": [],
      "afterMove": false,
      "negated": false,
      "eval": "",
      "gain": ""
    }
  ]
}
```

| Field | |
|---|---|
| `move` | Null, or the player's chosen move: their words and SAN as Claude read it (verify.js resolves it against the legal moves and may correct it). |
| `side` | Whose piece, move or advantage the claim is about: `"me"` (the player) or `"opponent"`. |
| `piece` | `""` or `K Q R B N P`: the piece the claim is about. |
| `square` | `""` or where that piece stands now. |
| `target` | `""` or the square it attacks, defends or threatens. |
| `moves` | A move or a line in SAN, starting from the claim's position, sides alternating. |
| `afterMove` | The claim is about P′. |
| `negated` | The player said it is not so ("his queen doesn't defend f7", "my knight isn't pinned"). The claim is written without the not; verify.js judges it that way and turns the verdict around (right and wrong swap; partly and unclear stay). The note says what is true either way. Denying a real threat counts as missing it; "my king isn't safe", said rightly, counts as spotting it. "He has no threats" stays a `safe` claim, not a negated `threat`. |
| `eval` | `""` or `winning`, `better`, `slightly_better`, `equal`, `slightly_worse`, `worse`, `losing`, from `side`'s view. |
| `gain` | `""` or `pawn`, `two_pawns`, `exchange`, `piece`, `rook`, `queen`, `mate`, `even`: what a `wins` move gains, or how far `side` is ahead for `material`. |

`spoken`, the checked facts in plain words for Claude call 2 and for `templateAnswer`. Every square Leo may
name appears in one of these strings; `guardAnswer` rejects an answer naming any other square or using
move notation.

```json
{
  "player": "white",
  "said": "his bishop eyes f2 so I'll castle, and my knight on f3 is safe",
  "right": ["The bishop on c5 does hit f2."],
  "wrong": [],
  "partly": [],
  "unclear": [],
  "move": "Castling is the best move here.",
  "missed": [],
  "habit": "You named his threat before choosing your move.",
  "nudge": null
}
```

## Limits

- 12 talks a minute per address (`TALK_LIMITER`).
- `DAILY_TALKS` (400) across everyone per UTC day, and `DAILY_VOICE_CHARS` (40,000) of Leo's voice, counted
  in the `TalkBudget` Durable Object. Past the voice budget, `voice` says `unavailable: "budget"` and the
  app uses the device's voice.
- Claude calls time out after `CLAUDE_TIMEOUT_MS` (12 s); the answer falls back to the template.

The per-player allowances in the Premium plan (3 a week free, 30 a day Premium) aren't built yet: they wait
for the subscription.
