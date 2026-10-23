# Challenge a friend: the game server's protocol

`play/` is a Cloudflare Worker with one Durable Object per game. It lets a player send a
link by text or email; the friend opens it in the app or plays right in the browser.

- Worker name: `play`, so it lives at `https://play.chess-game-killer.workers.dev`
  (the account's workers.dev subdomain is `chess-game-killer`, as for the scanner).
- Invite link: `https://play.chess-game-killer.workers.dev/c/{CODE}`
- The app's own link: `chessgamekiller://c/{CODE}` (the app also accepts `chessgamekiller://challenge/{CODE}`,
  the https link above, and a bare code typed in).
- Durable Object class `GameRoom`, binding `GAMES`, SQLite storage (works on the Workers Free plan).
  One object per game, addressed with `env.GAMES.idFromName(CODE)`.

## Codes, tokens, names

- **Code**: 6 characters from `23456789ABCDEFGHJKMNPQRSTUVWXYZ` (no 0/O, 1/I/L). Case-insensitive on input;
  always upper case on output. A new code that is already in use is drawn again.
- **Token**: 32 lowercase hex characters (128 random bits), one per seat. It is the only proof of a seat.
  REST: `Authorization: Bearer {token}`. WebSocket: `?token={token}` on the URL.
  A token never appears in a GameState.
- **Name**: trimmed, inner whitespace collapsed, control characters removed, at most 24 characters.
  Empty → `"Player"`. Names are shown to the other player, so every page escapes them.

## Time

- `clock`: `{ "initial": seconds, "increment": seconds }` or `null` for no clock.
  Allowed: initial 60…3600, increment 0…60. The app offers 3+2, 5+0, 10+0, 15+10 and no clock.
- No clock runs until both sides have made their first move (ply 2). From then on the side to move's clock runs.
- After a move at ply ≥ 2 the mover gets the increment. (The first move of each side is untimed and earns none.)
- The server decides flag falls. A move that arrives after the mover's time ran out is refused and the game ends on time.
- A fallen flag is a loss, unless the other side has no mating material: then it is a draw (`timeout_insufficient`).
- Times are milliseconds since the epoch on the server. Every GameState carries `now`, the server's time when it was
  sent, so clients can correct for their own clock: `offset = state.now - localNowWhenReceived`.

## Fair play (friend games)

- No hints, arrows, grades or analysis in the app during a friend game. (After the game it may be reviewed.)
- **Leaving forfeits a timed game.** Only when `clock != null`, the game is `active` and both sides have moved (ply ≥ 2):
  a seat is *away* from the moment its client posts `away` or its last WebSocket closes. If it is still away
  `leaveGraceMs` (20000) later, it loses with reason `left`. Posting `back`, opening a WebSocket or making a move
  ends the absence. An absence that began before both sides had moved counts from the moment they have.
  Two absences at once: whichever deadline passes first loses.
- **Screenshots are reported.** The app posts `screenshot` when the player takes one (and `recording` when screen
  recording starts). The other side gets a notice; the counts are in the GameState.
- Games with no clock have no leave rule: come and go as you like.

## GameState

Every REST reply carries `{ "game": GameState }`, and the WebSocket sends `{ "type": "state", "game": GameState }`.

```json
{
  "code": "7KQ2XM",
  "status": "waiting",
  "createdAt": 1761187200000,
  "updatedAt": 1761187200000,
  "clock": { "initial": 600, "increment": 0 },
  "creator": "white",
  "white": { "name": "Alex", "seated": true, "online": true, "away": null, "screenshots": 0, "recordings": 0 },
  "black": { "name": null, "seated": false, "online": false, "away": null, "screenshots": 0, "recordings": 0 },
  "moves": ["e2e4", "e7e5"],
  "san": ["e4", "e5"],
  "fen": "rnbqkbnr/pppp1ppp/8/4p3/4P3/8/PPPP1PPP/RNBQKBNR w KQkq - 0 2",
  "turn": "white",
  "clocks": { "white": 600000, "black": 600000, "running": null, "since": null },
  "drawOffer": null,
  "rematch": null,
  "result": null,
  "leaveGraceMs": 20000,
  "now": 1761187200123
}
```

- `status`: `"waiting"` (only the creator is seated), `"active"` (both seated, not over), `"over"`.
- `white` / `black`: `seated` once someone holds that seat; `online` while that seat has an open WebSocket and is
  not away; `away` is the time the current absence began, or `null`.
- `moves`: every move so far in UCI (`e7e8q` for a promotion). `san`: the same moves in standard notation.
- `fen`: the current position. `turn`: the side to move.
- `clocks`: `null` with no clock. Otherwise each side's remaining time in ms *as of `since`* for the running side,
  and exactly for the waiting side. `running` is the side whose clock runs (`null` before ply 2 and once over).
  Shown time for the running side = `clocks[running] - (serverNow - since)`.
- `drawOffer`: the side offering a draw, or `null`. An offer lapses when the other side moves instead of answering.
- `rematch`: `null`, or `{ "by": "white", "code": null }` once one side asks. When the other side asks too, the server
  makes the new game and sets `code`: same players and clock, colors swapped, both already seated, and **each
  player's token from this game works for their seat in the new one**. Clients just switch to the new code.
- `result`: `null` until over, then `{ "winner": "white" | "black" | null, "reason": REASON }`.

Reasons: `checkmate`, `resign`, `timeout`, `left` (forfeit by leaving), `stalemate`, `repetition` (threefold),
`fifty_moves`, `insufficient`, `agreement`, `timeout_insufficient` (draw), `aborted` (stopped before both sides moved),
`cancelled` (the creator withdrew before anyone joined), `expired` (nobody joined within 7 days, or no move for 30 days).

## REST

All JSON. Errors are `{ "error": CODE, "message": "Plain words for a person", "game": GameState? }`.
Bodies are read as JSON whatever their content type, and the token may also come as `"token"` in the body
instead of the Authorization header, so a browser can report `away` with `navigator.sendBeacon` as a tab closes.

| Method & path | Body | Reply |
| --- | --- | --- |
| `POST /api/games` | `{ "name", "side": "white"\|"black"\|"random", "clock": {…}\|null }` | `201 { "code", "url", "appUrl", "seat", "token", "game" }` |
| `GET /api/games/{code}` | – | `200 { "game" }` |
| `POST /api/games/{code}/join` | `{ "name" }` | `200 { "seat", "token", "game" }` |
| `POST /api/games/{code}/move` | `{ "uci", "ply" }` + Bearer | `200 { "game" }` |
| `POST /api/games/{code}/action` | `{ "type" }` + Bearer | `200 { "game" }` |

- `url` is the https invite link, `appUrl` the `chessgamekiller://c/{CODE}` link.
- `join`: takes the open seat. With a valid Bearer token for this game it just returns that seat (re-join is harmless);
  a token that isn't for this game is `unauthorized`. Both seats taken: `seat_taken`; game over: `game_over`.
- `move`: `ply` is the number of half-moves already played (the index this move will have). A different `ply` is
  `409 stale` with the current game, so the client can catch up. A missing promotion letter promotes to a queen.
- `action` types:
  - `resign` (before ply 2 it aborts instead), `abort` (only before ply 2), `cancel` (creator, while waiting);
    while waiting, `resign` and `abort` cancel too,
  - `offer_draw` (if the other side's offer is standing, this accepts it), `accept_draw` (`bad_request` when there's
    no offer from the other side), `decline_draw` (harmless when there's none),
  - `rematch` (after the game is over; see `rematch` above; asking again is harmless),
  - `away`, `back` (presence, see Fair play),
  - `screenshot`, `recording` (reported to the other side; counted only while the game is `active`).

Error codes: `not_found` 404, `bad_request` 400, `unauthorized` 401, `seat_taken` 409, `not_your_turn` 409,
`stale` 409, `game_over` 409, `illegal_move` 422, `rate_limited` 429, and `server_error` 500 if something breaks on
the server (try again). A move before the friend has joined is `not_your_turn`.

## WebSocket

`GET /api/games/{code}/live?token={token}` upgrades to a WebSocket. Without a token it is a spectator
(it gets the same messages but never counts for presence). A token that isn't for this game is refused (401).

Server → client:
- `{ "type": "state", "game": GameState }`: on connect and after every change.
- `{ "type": "notice", "kind": KIND, "seat": "white" | "black", "at": ms }` for moments a client may show as a toast.
  Kinds: `joined`, `screenshot`, `recording`, `away`, `back`, `draw_offer`, `draw_declined`, `rematch_offer`.
  `seat` is the side it is about; a notice goes to the other side and spectators, not to that seat itself.

Client → server: the text `ping` (the server answers `pong` without waking the game). Clients send one every 20 s.
Moves and actions always go through REST, so a reply tells the client whether they worked.

## Pages

- `GET /c/{code}`: the invite page. Its `<head>` carries Open Graph tags naming the challenger, so Messages and
  Mail show a rich preview ("Alex challenged you to chess"). The page lets the friend open the app
  (`chessgamekiller://c/{code}`) or play right there in the browser.
- `GET /`: a short page about the app; a browser player can start a challenge from it too.
- `GET /.well-known/apple-app-site-association`: served only when the `APPLE_TEAM_ID` variable is set, for universal links later.

## Limits

- Per address: 20 new games a minute (asking for a rematch counts as one), 30 joins a minute, 240 moves and
  actions a minute. Over a limit: `rate_limited` 429 with `Retry-After`.
- At most 8 WebSockets per game, and 3 per seat: a seat's 4th socket closes that seat's oldest with close code
  4001 (don't reconnect on 4001: the game is open somewhere newer). When 8 are open, a player's socket takes the
  oldest spectator's place (closed with 4002) and a new spectator is refused (429).
- A game nobody joins expires after 7 days; a game with no move for 30 days expires; finished games are deleted 30 days later.
