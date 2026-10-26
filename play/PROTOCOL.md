# Challenge a friend and play online: the game server's protocol

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
- **Leaving lets the other side claim the win.** Only when `clock != null`, the game is `active` and both sides have
  moved (ply ≥ 2): a seat is *away* from the moment its client posts `away` or its last WebSocket closes. Once it has
  been away `leaveGraceMs` (60000), the other side may post `claim_win` and win with reason `left`, or keep waiting.
  Leaving never ends a game by itself: the absent side's clock keeps running, so an unclaimed game still ends on time.
  Each seat's `claimableAt` says when a claim becomes possible (`null` while it is here or the rule doesn't apply).
  Posting `back`, opening a WebSocket or making a move ends the absence. An absence that began before both sides had
  moved counts from the moment they have.
- **Screenshots are reported.** The app posts `screenshot` when the player takes one (and `recording` when screen
  recording starts). The other side gets a notice; the counts are in the GameState.
- Games with no clock have no leave rule: come and go as you like.
- **Names are filtered.** A name that is a slur or plainly obscene (util.js `isOffensiveName`) becomes `"Player"`.
- **Reports.** A player may post `report_name` or `report_cheating` about the other side, during or after the game.
  A name report replaces that name with `"Player"` at once (in rematches too). Each kind counts once per player and
  is written to the worker's logs as a `player_report` line (Cloudflare dashboard → Workers → play → Logs).

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
  "look": "gilded",
  "white": { "name": "Alex", "seated": true, "online": true, "away": null, "claimableAt": null, "screenshots": 0, "recordings": 0 },
  "black": { "name": null, "seated": false, "online": false, "away": null, "claimableAt": null, "screenshots": 0, "recordings": 0 },
  "moves": ["e2e4", "e7e5"],
  "san": ["e4", "e5"],
  "fen": "rnbqkbnr/pppp1ppp/8/4p3/4P3/8/PPPP1PPP/RNBQKBNR w KQkq - 0 2",
  "turn": "white",
  "clocks": { "white": 600000, "black": 600000, "running": null, "since": null },
  "drawOffer": null,
  "rematch": null,
  "result": null,
  "leaveGraceMs": 60000,
  "now": 1761187200123
}
```

- `look`: the board look the creator plays with in the app (`BoardTheme.ID`, such as `"gilded"` or `"classic"`), so the
  browser shows the same board. Sent on create; anything but 2–20 lowercase letters is dropped. `null` for games from
  older apps: the browser then shows the app's default look. The browser's looks are exported from the app by
  `scripts/play/export_looks.py` into `public/looks/`, `looks.css` and `looks.js`.
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

Reasons: `checkmate`, `resign`, `timeout`, `left` (the other side claimed the win after this side left), `stalemate`, `repetition` (threefold),
`fifty_moves`, `insufficient`, `agreement`, `timeout_insufficient` (draw), `aborted` (stopped before both sides moved),
`cancelled` (the creator withdrew before anyone joined), `expired` (nobody joined within 7 days, or no move for 30 days).

## REST

All JSON. Errors are `{ "error": CODE, "message": "Plain words for a person", "game": GameState? }`.
Bodies are read as JSON whatever their content type, and the token may also come as `"token"` in the body
instead of the Authorization header, so a browser can report `away` with `navigator.sendBeacon` as a tab closes.

| Method & path | Body | Reply |
| --- | --- | --- |
| `POST /api/games` | `{ "name", "side": "white"\|"black"\|"random", "clock": {…}\|null, "look"? }` | `201 { "code", "url", "appUrl", "seat", "token", "game" }` |
| `GET /api/games/{code}` | – | `200 { "game" }` |
| `POST /api/games/{code}/join` | `{ "name" }` | `200 { "seat", "token", "game" }` |
| `POST /api/games/{code}/move` | `{ "uci", "ply" }` + Bearer | `200 { "game" }` |
| `POST /api/games/{code}/action` | `{ "type" }` + Bearer | `200 { "game" }` |

- `url` is the https invite link, `appUrl` the `chessgamekiller://c/{CODE}` link.
- `join`: takes the open seat. With a valid Bearer token for this game it just returns that seat, even after the game
  is over (re-join is harmless); a token that isn't for this game is `unauthorized`. Without a token: game over is
  `game_over`, and otherwise both seats taken is `seat_taken`.
- `move`: `ply` is the number of half-moves already played (the index this move will have). A different `ply` is
  `409 stale` with the current game, so the client can catch up. A missing promotion letter promotes to a queen.
- `action` types:
  - `resign` (before ply 2 it aborts instead), `abort` (only before ply 2), `cancel` (creator, while waiting);
    while waiting, `resign` and `abort` cancel too,
  - `offer_draw` (if the other side's offer is standing, this accepts it), `accept_draw` (`bad_request` when there's
    no offer from the other side), `decline_draw` (harmless when there's none),
  - `rematch` (after the game is over; see `rematch` above; asking again is harmless),
  - `away`, `back` (presence, see Fair play),
  - `screenshot`, `recording` (reported to the other side; counted only while the game is `active`),
  - `claim_win` (see Fair play; `cannot_claim` 409 when it's too early, the friend is back, or the rule doesn't apply),
  - `report_name`, `report_cheating` (see Fair play; `bad_request` before anyone joined).

Error codes: `not_found` 404, `bad_request` 400, `unauthorized` 401, `seat_taken` 409, `not_your_turn` 409,
`stale` 409, `game_over` 409, `cannot_claim` 409, `illegal_move` 422, `rate_limited` 429, and `server_error` 500 if something breaks on
the server (try again). A move before the friend has joined is `not_your_turn`.

## Play online (the lobby)

Players with the app can also play someone online they don't know: they wait in the lobby with a clock, and
anyone can take them on by name, or ask for a quick pairing. One Durable Object (class `Lobby`, binding
`LOBBY`, named `"lobby"`) holds everyone waiting and the ratings. Games paired there are ordinary games
(everything above applies, fair play included) that are also **rated**.

- **Player key**: 32 lowercase hex characters the app makes once and keeps. It is the app's private id for its
  player: ratings are kept by its hash. It is never shown to anyone.
- **Ratings**: Elo, 1200 to start; K = 40 for a player's first 10 games (shown as provisional), then 20.
  Aborted, cancelled and expired games don't count. A rematch of a rated game is rated too.
- **A seek** is one player waiting at a clock. A waiting app checks in every 2 s; a seek not checked for 20 s
  leaves the lobby. A player waits once: a new seek replaces their old one. Online games always have a clock.
- GameState gains `rated` (true for games paired here) and `ratings`: `null`, or for each side
  `{ "rating", "provisional", "after", "change" }` (`after` and `change` are `null` until the game is over and counted).

| Method & path | Body | Reply |
| --- | --- | --- |
| `GET /api/lobby` | – | `200 { "players": [Seek], "waiting", "now" }`, the longest waiting first (at most 40) |
| `POST /api/lobby/me` | `{ "player" }` | `200 { "you": { "rating", "games", "provisional" } }` |
| `POST /api/lobby/seeks` | `{ "name", "clock", "look"?, "player", "pair"? }` | `201 { "seek", "token", "you" }` waiting, or `200 { "match", "you" }` paired at once |
| `POST /api/lobby/seeks/{id}` | `{}` + Bearer seek token | `200 { "seek", "waiting" }` still waiting, or `200 { "match" }` |
| `POST /api/lobby/seeks/{id}/cancel` | `{}` + Bearer seek token | `200 { "cancelled": true }`, or `200 { "match" }` if someone took you on first |
| `POST /api/lobby/seeks/{id}/play` | `{ "name", "look"?, "player" }` | `200 { "match", "you" }`: you took that player on |

- `Seek`: `{ "id", "name", "rating", "provisional", "clock", "look", "waitingFor" }` (ms). Never a token or key.
- `match`: `{ "code", "seat", "token", "game"? }`: the new game, your seat in it and your seat's token. From then
  on it is a game like any other (`/api/games/{code}/…`).
- `pair` (default true): first take on the closest-rated player already waiting at the same clock, if any.
- Errors: `not_found` (that player isn't waiting any more, or your seek is gone), `bad_request` (taking yourself
  on, no clock, no player key), `pairing` 409 (cancel while someone is taking you on: check in again), `rate_limited`.
- Limits: making a seek or taking one on counts as a new game; check-ins and cancels count as actions.

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

- A refused upgrade is an HTTP error (401 for a token that isn't for this game, 404 for no game, 429 for a full game).
  A browser can't read that status: it only sees the socket fail to open. So a client whose socket fails to open
  twice in a row checks its seat with `join` (a 401 there means: forget the token and watch), and otherwise keeps up
  by polling `GET /api/games/{code}` every 3 s while it retries the socket.
- Close codes 4000–4999 are final: don't reconnect after one. 4001 means the seat's game is open somewhere newer;
  4002 means a player took this spectator's place.

## Pages

- `GET /c/{code}`: the invite page. Its `<head>` carries Open Graph tags naming the challenger, so Messages and
  Mail show a rich preview ("Alex challenged you to chess"). The page lets the friend open the app
  (`chessgamekiller://c/{code}`) or play right there in the browser.
- `GET /`: a short page about the app; a browser player can start a challenge from it too.
- `GET /.well-known/apple-app-site-association`: served only when the `APPLE_TEAM_ID` variable is set, for universal links later.

## Limits

- Per address: 20 new games a minute (asking for a rematch counts as one), 30 joins a minute, 240 moves and
  actions a minute. Over a limit: `rate_limited` 429 with `Retry-After`. Reading a game (`GET /api/games/{code}`)
  has no limit, because clients poll it every 3 s when their WebSocket can't connect; any future limit must stay
  well above 20 a minute per page.
- At most 8 WebSockets per game, and 3 per seat: a seat's 4th socket closes that seat's oldest with close code
  4001 (don't reconnect on 4001: the game is open somewhere newer). When 8 are open, a player's socket takes the
  oldest spectator's place (closed with 4002) and a new spectator is refused (429).
- A game nobody joins expires after 7 days; a game with no move for 30 days expires; finished games are deleted 30 days later.
