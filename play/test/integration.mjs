// Runs the game server with `wrangler dev` (Durable Objects, alarms, rate
// limits and all, on this machine) and plays real games against it over HTTP
// and WebSockets. Short settings make the timed parts quick: a 1.5-second
// grace for leaving, clocks as short as 1 second, and finished games deleted
// after 4 seconds instead of 30 days.
//
//   npm run test:integration
//
// Exits with 1 if anything fails, printing the server's log.

import assert from "node:assert/strict";
import { spawn } from "node:child_process";
import { cpSync, mkdtempSync, rmSync } from "node:fs";
import { createServer } from "node:net";
import { tmpdir } from "node:os";
import { dirname, join as joinPath } from "node:path";
import { fileURLToPath } from "node:url";
import { LiveSocket, api } from "./client.mjs";

const ROOT = joinPath(dirname(fileURLToPath(import.meta.url)), "..");
const GRACE_MS = 1500;
const KEEP_FINISHED_MS = 4000;

function freePort() {
  return new Promise((resolve, reject) => {
    const server = createServer();
    server.unref();
    server.on("error", reject);
    server.listen(0, "127.0.0.1", () => {
      const { port } = server.address();
      server.close(() => resolve(port));
    });
  });
}

const pause = (ms) => new Promise((resolve) => setTimeout(resolve, ms));

async function startServer() {
  const port = await freePort();
  const inspectorPort = await freePort();
  const work = mkdtempSync(joinPath(tmpdir(), "play-integration-"));
  // wrangler dev restarts the server whenever one of its files changes, which
  // cuts every socket in the middle of a scenario. So it runs from a copy of
  // the server: editing the project while the tests run can't upset them.
  const app = joinPath(work, "app");
  for (const part of ["src", "public", "wrangler.toml", "package.json"]) {
    cpSync(joinPath(ROOT, part), joinPath(app, part), { recursive: true });
  }
  const state = joinPath(work, "state");
  const log = [];
  const child = spawn(
    process.execPath,
    [
      joinPath(ROOT, "node_modules", "wrangler", "bin", "wrangler.js"),
      "dev",
      "--port", String(port),
      "--ip", "127.0.0.1",
      "--inspector-port", String(inspectorPort),
      "--persist-to", state,
      "--var", `LEAVE_GRACE_MS:${GRACE_MS}`,
      "--var", "MIN_CLOCK_SECONDS:1",
      "--var", `KEEP_FINISHED_MS:${KEEP_FINISHED_MS}`,
      "--show-interactive-dev-session=false",
    ],
    {
      cwd: app,
      env: { ...process.env, WRANGLER_SEND_METRICS: "false", NO_COLOR: "1", FORCE_COLOR: "0" },
      // Its own process group, so stopping it also stops the workerd it starts.
      detached: true,
      stdio: ["ignore", "pipe", "pipe"],
    },
  );
  const keep = (chunk) => {
    log.push(...String(chunk).split("\n"));
    if (log.length > 400) log.splice(0, log.length - 400);
  };
  child.stdout.on("data", keep);
  child.stderr.on("data", keep);
  let exited = null;
  child.on("exit", (code) => {
    exited = code;
  });

  const base = `http://127.0.0.1:${port}`;
  const stop = () => {
    try {
      process.kill(-child.pid, "SIGTERM");
    } catch {
      // Already gone.
    }
    rmSync(work, { recursive: true, force: true });
  };
  const deadline = Date.now() + 90000;
  for (;;) {
    if (exited !== null) {
      stop();
      throw new Error(`wrangler dev exited (${exited}):\n${log.join("\n")}`);
    }
    try {
      const response = await fetch(`${base}/`, { signal: AbortSignal.timeout(3000) });
      if (response.status === 200) break;
    } catch {
      // Not up yet.
    }
    if (Date.now() > deadline) {
      stop();
      throw new Error(`wrangler dev didn't start in 90 s:\n${log.join("\n")}`);
    }
    await pause(500);
  }
  return { base, log, stop };
}

// ---------------------------------------------------------------------------

const server = await startServer();
const { base } = server;
const sockets = [];
let failures = 0;

function live(code, token) {
  const socket = new LiveSocket(base, code, token);
  sockets.push(socket);
  return socket;
}

async function create(body) {
  const answer = await api(base, "POST", "/api/games", { body });
  assert.equal(answer.status, 201, answer.text);
  return answer.json;
}

async function join(code, name, token) {
  const answer = await api(base, "POST", `/api/games/${code}/join`, { body: { name }, token });
  assert.equal(answer.status, 200, answer.text);
  return answer.json;
}

/** A game with both players seated: { code, white, black } with each side's token. */
async function newGame(clock = null) {
  const made = await create({ name: "Alex", side: "white", clock });
  const joined = await join(made.code, "Sam");
  assert.equal(joined.seat, "black");
  return { code: made.code, white: made.token, black: joined.token, made };
}

async function move(code, token, uci, ply) {
  return api(base, "POST", `/api/games/${code}/move`, { body: { uci, ply }, token });
}

async function act(code, token, type) {
  return api(base, "POST", `/api/games/${code}/action`, { body: { type }, token });
}

async function scenario(name, run) {
  const started = Date.now();
  try {
    await run();
    console.log(`ok - ${name} (${Date.now() - started} ms)`);
  } catch (error) {
    failures += 1;
    console.log(`not ok - ${name}\n  ${String(error && error.stack ? error.stack : error).replace(/\n/g, "\n  ")}`);
  }
}

try {
  await scenario("the home page and invite pages are HTML, and an unknown code is a 404", async () => {
    const home = await api(base, "GET", "/");
    assert.equal(home.status, 200);
    assert.match(home.headers.get("content-type"), /^text\/html/);

    const made = await create({ name: "Alex <img src=x onerror=alert(1)>", side: "white", clock: null });
    const page = await api(base, "GET", `/c/${made.code.toLowerCase()}`);
    assert.equal(page.status, 200);
    assert.match(page.headers.get("content-type"), /^text\/html/);
    assert.ok(!page.text.includes("<img src=x"), "the challenger's name must be escaped on the page");

    const unknown = await api(base, "GET", "/c/ZZZZZZ");
    assert.equal(unknown.status, 404);
    assert.match(unknown.headers.get("content-type"), /^text\/html/);
    assert.equal((await api(base, "GET", "/c/not-a-code")).status, 404);
    assert.equal((await api(base, "GET", "/api/games/ZZZZZZ")).json.error, "not_found");
    assert.equal((await api(base, "GET", "/.well-known/apple-app-site-association")).status, 404);
    const vendor = await api(base, "GET", "/vendor/chess.js");
    assert.equal(vendor.status, 200);
    assert.match(vendor.text, /Jeff Hlywa/);
  });

  await scenario("fool's mate, with both players watching over WebSockets", async () => {
    const made = await create({ name: "Alex", side: "white", clock: null });
    assert.match(made.code, /^[23456789ABCDEFGHJKMNPQRSTUVWXYZ]{6}$/);
    assert.equal(made.url, `${base}/c/${made.code}`);
    assert.equal(made.appUrl, `chessgamekiller://c/${made.code}`);
    assert.match(made.token, /^[0-9a-f]{32}$/);
    assert.equal(made.seat, "white");
    assert.ok(!JSON.stringify(made.game).includes(made.token));

    const white = live(made.code, made.token);
    await white.opened;
    await white.state((g) => g.white.online === true, "White online");
    white.send("ping");
    await white.waitFor((m) => m === "pong", "pong");

    const joined = await join(made.code, "Sam");
    assert.equal(joined.seat, "black");
    assert.equal(joined.game.status, "active");
    await white.notice("joined", "black");
    // Joining again with the token is harmless and returns the same seat.
    const again = await join(made.code, "Someone else", joined.token);
    assert.equal(again.seat, "black");
    assert.equal(again.token, joined.token);
    assert.equal(again.game.black.name, "Sam");

    const black = live(made.code, joined.token);
    await black.opened;
    await white.state((g) => g.black.online === true, "Black online");

    const screenshot = await act(made.code, made.token, "screenshot");
    assert.equal(screenshot.status, 200);
    assert.equal(screenshot.json.game.white.screenshots, 1);
    await black.notice("screenshot", "white");

    // Refusals come with the game so the client can catch up.
    const early = await move(made.code, joined.token, "e7e5", 0);
    assert.equal(early.status, 409);
    assert.equal(early.json.error, "not_your_turn");
    const illegal = await move(made.code, made.token, "e2e5", 0);
    assert.equal(illegal.status, 422);
    assert.equal(illegal.json.error, "illegal_move");
    assert.equal(illegal.json.game.code, made.code);
    const noToken = await move(made.code, null, "e2e4", 0);
    assert.equal(noToken.status, 401);
    const wrongToken = await move(made.code, "0".repeat(32), "e2e4", 0);
    assert.equal(wrongToken.status, 401);

    const plies = [
      [made.token, "f2f3"],
      [joined.token, "e7e5"],
      [made.token, "g2g4"],
      [joined.token, "d8h4"],
    ];
    let last;
    for (const [index, [token, uci]] of plies.entries()) {
      last = await move(made.code, token, uci, index);
      assert.equal(last.status, 200, last.text);
    }
    const stale = await move(made.code, joined.token, "d8h4", 3);
    assert.equal(stale.status, 409);
    assert.ok(["stale", "game_over"].includes(stale.json.error));

    assert.deepEqual(last.json.game.result, { winner: "black", reason: "checkmate" });
    assert.deepEqual(last.json.game.san, ["f3", "e5", "g4", "Qh4#"]);
    for (const socket of [white, black]) {
      const final = await socket.state((g) => g.result && g.result.reason === "checkmate", "the checkmate");
      assert.equal(final.result.winner, "black");
      assert.equal(final.status, "over");
      assert.deepEqual(final.moves, ["f2f3", "e7e5", "g2g4", "d8h4"]);
    }
    const after = await move(made.code, made.token, "e2e4", 4);
    assert.equal(after.json.error, "game_over");
  });

  await scenario("resigning", async () => {
    const game = await newGame();
    assert.equal((await move(game.code, game.white, "e2e4", 0)).status, 200);
    assert.equal((await move(game.code, game.black, "c7c5", 1)).status, 200);
    const resigned = await act(game.code, game.white, "resign");
    assert.equal(resigned.status, 200);
    assert.deepEqual(resigned.json.game.result, { winner: "black", reason: "resign" });
  });

  let drawn;
  await scenario("a draw by agreement, and presence reported by a beacon", async () => {
    drawn = await newGame({ initial: 300, increment: 0 });
    const white = live(drawn.code, drawn.white);
    const black = live(drawn.code, drawn.black);
    await Promise.all([white.opened, black.opened]);
    await white.state((g) => g.black.online && g.white.online, "both online");

    // navigator.sendBeacon sends text/plain with the token in the body.
    const away = await api(base, "POST", `/api/games/${drawn.code}/action`, {
      body: JSON.stringify({ type: "away", token: drawn.white }),
      headers: { "content-type": "text/plain;charset=UTF-8" },
    });
    assert.equal(away.status, 200, away.text);
    assert.equal(away.json.game.white.online, false);
    await black.notice("away", "white");
    assert.equal((await act(drawn.code, drawn.white, "back")).json.game.white.online, true);
    await black.notice("back", "white");

    const offer = await act(drawn.code, drawn.white, "offer_draw");
    assert.equal(offer.json.game.drawOffer, "white");
    await black.notice("draw_offer", "white");
    const accepted = await act(drawn.code, drawn.black, "accept_draw");
    assert.deepEqual(accepted.json.game.result, { winner: null, reason: "agreement" });
    await white.state((g) => g.result && g.result.reason === "agreement", "the draw");
    drawn.sockets = { white, black };
  });

  await scenario("a rematch swaps the colors and the same tokens keep working", async () => {
    const { white, black } = drawn.sockets;
    const asked = await act(drawn.code, drawn.white, "rematch");
    assert.equal(asked.status, 200, asked.text);
    assert.deepEqual(asked.json.game.rematch, { by: "white", code: null });
    await black.notice("rematch_offer", "white");

    const agreed = await act(drawn.code, drawn.black, "rematch");
    assert.equal(agreed.status, 200, agreed.text);
    const next = agreed.json.game.rematch.code;
    assert.match(next, /^[23456789ABCDEFGHJKMNPQRSTUVWXYZ]{6}$/);
    assert.notEqual(next, drawn.code);
    await white.state((g) => g.rematch && g.rematch.code === next, "the rematch code");
    // Asking again just returns the same rematch.
    assert.equal((await act(drawn.code, drawn.white, "rematch")).json.game.rematch.code, next);

    const fresh = await api(base, "GET", `/api/games/${next}`);
    assert.equal(fresh.status, 200);
    const game = fresh.json.game;
    assert.equal(game.status, "active");
    assert.equal(game.white.name, "Sam");
    assert.equal(game.black.name, "Alex");
    assert.deepEqual(game.clock, { initial: 300, increment: 0 });
    assert.deepEqual(game.moves, []);

    // Sam (Black before) now plays White with the same token, and Alex Black.
    assert.equal((await move(next, drawn.white, "e2e4", 0)).json.error, "not_your_turn");
    assert.equal((await move(next, drawn.black, "e2e4", 0)).status, 200);
    assert.equal((await move(next, drawn.white, "e7e5", 1)).status, 200);
    assert.equal((await join(next, "x", drawn.white)).seat, "black");
    assert.equal((await join(next, "x", drawn.black)).seat, "white");
    const crowd = await api(base, "POST", `/api/games/${next}/join`, { body: { name: "Kim" } });
    assert.equal(crowd.status, 409);
    assert.equal(crowd.json.error, "seat_taken");
  });

  await scenario("leaving a timed game forfeits it after the grace period", async () => {
    const game = await newGame({ initial: 60, increment: 0 });
    const white = live(game.code, game.white);
    const black = live(game.code, game.black);
    await Promise.all([white.opened, black.opened]);
    assert.equal((await move(game.code, game.white, "e2e4", 0)).status, 200);
    assert.equal((await move(game.code, game.black, "e7e5", 1)).status, 200);

    const left = Date.now();
    white.close();
    await black.notice("away", "white");
    const over = await black.state((g) => g.result !== null, "the forfeit", 10000);
    const waited = Date.now() - left;
    assert.deepEqual(over.result, { winner: "black", reason: "left" });
    assert.ok(waited >= GRACE_MS - 200, `forfeited after ${waited} ms, before the ${GRACE_MS} ms grace`);
    assert.equal(over.white.online, false);
    assert.equal(over.clocks.running, null);
  });

  await scenario("a flag falls on a 1-second clock", async () => {
    const game = await newGame({ initial: 1, increment: 0 });
    const black = live(game.code, game.black);
    await black.opened;
    assert.equal((await move(game.code, game.white, "e2e4", 0)).status, 200);
    const second = await move(game.code, game.black, "e7e5", 1);
    assert.equal(second.status, 200);
    assert.equal(second.json.game.clocks.running, "white");
    assert.equal(second.json.game.clocks.white, 1000);
    const over = await black.state((g) => g.result !== null, "the flag", 10000);
    assert.deepEqual(over.result, { winner: "black", reason: "timeout" });
    assert.equal(over.clocks.white, 0);
    const late = await move(game.code, game.white, "g1f3", 2);
    assert.equal(late.status, 409);
    assert.equal(late.json.error, "game_over");
  });

  await scenario("at most 8 sockets per game, and a player can always get in", async () => {
    const game = await newGame();
    const watchers = [];
    for (let i = 0; i < 8; i += 1) watchers.push(live(game.code));
    await Promise.all(watchers.map((socket) => socket.opened));
    await Promise.all(watchers.map((socket) => socket.state((g) => g.code === game.code, "the state")));
    const ninth = live(game.code);
    await assert.rejects(ninth.opened);
    // A player takes the oldest watcher's place.
    const player = live(game.code, game.white);
    await player.opened;
    await player.state((g) => g.white.online, "White online");
    const evicted = await Promise.race(watchers.map((socket) => socket.whenClosing()));
    assert.equal(evicted, watchers[0], "the oldest watcher makes room");
    assert.equal(watchers.filter((socket) => socket.closing).length, 1);
    // A seat keeps at most 3 sockets; a 4th replaces the oldest (and takes a watcher's place too).
    const more = [];
    for (let i = 0; i < 3; i += 1) {
      const socket = live(game.code, game.white);
      await socket.opened;
      more.push(socket);
    }
    await player.whenClosing();
    assert.equal(more.filter((socket) => socket.closing).length, 0);
    const state = (await api(base, "GET", `/api/games/${game.code}`)).json.game;
    assert.equal(state.white.online, true, "White still has open sockets");
    assert.equal(state.white.away, null);
  });

  await scenario("a finished game is deleted once its time is up", async () => {
    const game = await newGame();
    const watcher = live(game.code);
    await watcher.opened;
    const ended = await act(game.code, game.white, "abort");
    assert.deepEqual(ended.json.game.result, { winner: null, reason: "aborted" });
    assert.equal((await api(base, "GET", `/api/games/${game.code}`)).status, 200);
    await watcher.whenClosing(KEEP_FINISHED_MS + 6000);
    const gone = await api(base, "GET", `/api/games/${game.code}`);
    assert.equal(gone.status, 404);
    assert.equal(gone.json.error, "not_found");
    assert.equal((await api(base, "GET", `/c/${game.code}`)).status, 404);
    assert.equal((await move(game.code, game.white, "e2e4", 0)).status, 404);
  });

  await scenario("the rate limits work in local dev too", async () => {
    let limited = null;
    for (let i = 0; i < 45 && !limited; i += 1) {
      const answer = await api(base, "POST", "/api/games", { body: { name: "Flood" } });
      if (answer.status === 429) limited = answer;
      else assert.equal(answer.status, 201, answer.text);
    }
    assert.ok(limited, "no 429 after 45 new games");
    assert.equal(limited.json.error, "rate_limited");
    assert.equal(limited.headers.get("retry-after"), "60");
  });
} finally {
  for (const socket of sockets) socket.close();
  if (failures > 0) {
    console.log("\n--- wrangler dev log (last lines) ---");
    console.log(server.log.slice(-80).join("\n"));
  }
  server.stop();
}

console.log(failures === 0 ? "\nAll integration scenarios passed." : `\n${failures} integration scenario(s) failed.`);
process.exit(failures === 0 ? 0 : 1);
