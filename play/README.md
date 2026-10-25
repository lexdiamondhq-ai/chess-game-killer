# Challenge a friend: the game server

A player sends a link by text or email; the friend opens it in the app or plays right in the browser.
This folder is that server: a Cloudflare Worker with one Durable Object per game, plus the browser board.

Live at **https://play.chess-game-killer.workers.dev** (invite links look like `/c/7KQ2XM`).
[PROTOCOL.md](PROTOCOL.md) is the contract the app and the browser board code against: codes, tokens, clocks,
the fair-play rules, the GameState, the REST API, the WebSocket and the limits.

## How it fits together

- `src/index.js`: the entry point. It exports the request handler and the Durable Object class, and nothing else.
- `src/router.js`: checks each request (path, method, game code, body, token, rate limit) and passes it to the
  game's room. Also serves the home page, the invite page `/c/{code}` and the Apple app-site file.
- `src/room.js`: `GameRoom`, the Durable Object that holds one game. It saves the game after every change, keeps the
  players' WebSockets (with hibernation, so an idle game costs nothing) and sets one alarm for the next thing that
  can happen on its own: a flag falling, an absent player's grace running out, expiry, or deleting a finished game.
- `src/game.js`: the rules, with no Cloudflare in them and the time passed in, so tests can run days of a game in
  milliseconds. Moves are checked with chess.js on a board loaded from the stored position, so a move costs the
  same CPU in a long game as in a short one; the record keeps the positions since the last capture or pawn move
  for the threefold-repetition rule.
- `src/util.js`: codes, tokens (only their SHA-256 is stored), names, request bodies and JSON replies.
- `public/`: the browser board, served as static files. `public/vendor/chess.js` is
  [chess.js](https://github.com/jhlywa/chess.js) 1.4.0 (BSD-2-Clause), shared by the server and the browser.
- `src/pages.js`: the HTML for the home and invite pages (owned by the browser board).

## Run it

Needs Node 22 or later.

```sh
cd play
npm ci
npm run dev                 # http://localhost:8787
npm test                    # unit tests of the rules, helpers and router
npm run test:integration    # real games against wrangler dev, over HTTP and WebSockets
npm run smoke -- http://localhost:8787   # the post-deploy check, against any server
```

`wrangler dev` runs the Durable Objects, alarms and rate limits locally. For quick experiments with the timed rules:
`npx wrangler dev --var LEAVE_GRACE_MS:1500 --var MIN_CLOCK_SECONDS:1` (a 1.5-second grace for leaving, and clocks
as short as 1 second).

## Deploying

`.github/workflows/play.yml` runs the unit and integration tests on every pull request that touches `play/`, and on
pushes to `main` also deploys with wrangler and plays a game on the live server (`test/smoke.mjs`). It needs one
repository secret, `CLOUDFLARE_API_TOKEN` (made from Cloudflare's "Edit Cloudflare Workers" template); the account
ID is looked up from the token. It runs on the Workers Free plan: the Durable Objects use SQLite storage.

Settings (`[vars]` in `wrangler.toml`): `LEAVE_GRACE_MS` (60000, how long someone may be away before their friend can claim the win) and `MIN_CLOCK_SECONDS` (60). Setting
`APPLE_TEAM_ID` serves `/.well-known/apple-app-site-association`, so iOS can open invite links in the app.
