import assert from "node:assert/strict";
import { createHash } from "node:crypto";
import { test } from "node:test";
import { createGame, view } from "../src/game.js";
import { handleRequest } from "../src/router.js";

const ORIGIN = "https://play.example";
const TOKEN = "0123456789abcdef0123456789abcdef";

/** A GameState like the rooms send, for the page renderer. */
function sampleGame(code = "7KQ2XM") {
  const game = createGame({ code, name: "Alex", side: "white", clock: { initial: 600, increment: 0 }, tokenHash: "a".repeat(64), now: 1 });
  return view(game, 2);
}

/**
 * A stand-in for Cloudflare: GAMES hands out fake rooms that record each
 * call, and the limiters say yes unless told otherwise.
 */
function fakeEnv({ rooms = {}, limits = {}, vars = {} } = {}) {
  const calls = [];
  const limiter = (name) => ({
    async limit({ key }) {
      calls.push(["limit", name, key]);
      const rule = limits[name];
      if (rule === "throw") throw new Error("limiter down");
      return { success: rule !== false };
    },
  });
  const room = (code) => {
    const answer = (method, fallback) =>
      async (input) => {
        calls.push([method, code, input]);
        const handler = rooms[method];
        return handler ? handler(code, input) : fallback(code, input);
      };
    return {
      create: answer("create", (c, input) => ({ seat: input.side === "black" ? "black" : "white", game: sampleGame(c) })),
      read: answer("read", () => ({ status: 404, body: { error: "not_found", message: "No game" } })),
      join: answer("join", () => ({ status: 200, body: { seat: "black", token: TOKEN, game: {} } })),
      move: answer("move", () => ({ status: 200, body: { game: {} } })),
      action: answer("action", () => ({ status: 200, body: { game: {} } })),
      fetch: async (request) => {
        calls.push(["fetch", code, request.url]);
        return rooms.fetch ? rooms.fetch(code, request) : new Response("upgraded");
      },
    };
  };
  const env = {
    GAMES: { idFromName: (name) => ({ name }), get: (id) => room(id.name) },
    CREATE_LIMITER: limiter("create"),
    JOIN_LIMITER: limiter("join"),
    MOVE_LIMITER: limiter("move"),
    LEAVE_GRACE_MS: "20000",
    MIN_CLOCK_SECONDS: "60",
    ...vars,
  };
  return { env, calls, called: (method) => calls.filter((call) => call[0] === method) };
}

function request(method, path, { body, headers = {} } = {}) {
  return new Request(ORIGIN + path, {
    method,
    headers: { "cf-connecting-ip": "203.0.113.7", ...headers },
    body: body === undefined ? undefined : typeof body === "string" ? body : JSON.stringify(body),
  });
}

async function send(env, method, path, options) {
  const response = await handleRequest(request(method, path, options), env);
  const text = await response.text();
  let json = null;
  try {
    json = JSON.parse(text);
  } catch {
    // A page.
  }
  return { status: response.status, headers: response.headers, text, json };
}

const bearer = { authorization: `Bearer ${TOKEN}` };

// ---------------------------------------------------------------------------

test("the home page is HTML", async () => {
  const { env } = fakeEnv();
  const home = await send(env, "GET", "/");
  assert.equal(home.status, 200);
  assert.equal(home.headers.get("content-type"), "text/html; charset=utf-8");
  assert.equal(home.headers.get("x-frame-options"), "DENY");
  assert.equal((await send(env, "HEAD", "/")).status, 200);
  assert.equal((await send(env, "POST", "/")).status, 405);
});

test("an invite link shows the game, and the same page with a 404 when there's none", async () => {
  const { env, called } = fakeEnv({
    rooms: { read: (code) => (code === "7KQ2XM" ? { status: 200, body: { game: sampleGame(code) } } : { status: 404, body: { error: "not_found" } }) },
  });
  const found = await send(env, "GET", "/c/7kq2xm");
  assert.equal(found.status, 200);
  assert.equal(found.headers.get("content-type"), "text/html; charset=utf-8");
  assert.equal(found.headers.get("cache-control"), "no-store");
  assert.deepEqual(called("read").map((call) => call[1]), ["7KQ2XM"]);

  const missing = await send(env, "GET", "/c/ZZZZZZ");
  assert.equal(missing.status, 404);
  assert.equal(missing.headers.get("content-type"), "text/html; charset=utf-8");

  // Not a code at all: no game is asked, and the path never reaches the page as it came.
  const junk = await send(env, "GET", "/c/%3Cscript%3Ealert(1)%3C%2Fscript%3E");
  assert.equal(junk.status, 404);
  assert.ok(!junk.text.includes("<script>alert"));
  assert.equal(called("read").length, 2);
});

test("making a game returns its links and a token; the room gets only the token's hash", async () => {
  const { env, called } = fakeEnv();
  const made = await send(env, "POST", "/api/games", { body: { name: "  Alex\n", side: "black", clock: { initial: 180, increment: 2 } } });
  assert.equal(made.status, 201);
  const { code, url, appUrl, seat, token, game } = made.json;
  assert.match(code, /^[23456789ABCDEFGHJKMNPQRSTUVWXYZ]{6}$/);
  assert.equal(url, `${ORIGIN}/c/${code}`);
  assert.equal(appUrl, `chessgamekiller://c/${code}`);
  assert.equal(seat, "black");
  assert.match(token, /^[0-9a-f]{32}$/);
  assert.equal(game.code, code);
  const [[, roomCode, input]] = called("create");
  assert.equal(roomCode, code);
  assert.deepEqual(input, {
    code,
    name: "Alex",
    side: "black",
    clock: { initial: 180, increment: 2 },
    tokenHash: createHash("sha256").update(token).digest("hex"),
  });
  assert.equal(made.headers.get("cache-control"), "no-store");
});

test("a code that already has a game is drawn again", async () => {
  let first = true;
  const { env, called } = fakeEnv({
    rooms: {
      create: (code) => {
        if (first) {
          first = false;
          return { inUse: true };
        }
        return { seat: "white", game: sampleGame(code) };
      },
    },
  });
  const made = await send(env, "POST", "/api/games", { body: {} });
  assert.equal(made.status, 201);
  const codes = called("create").map((call) => call[1]);
  assert.equal(codes.length, 2);
  assert.equal(made.json.code, codes[1]);
});

test("a request to make a game is checked first", async () => {
  const { env, called } = fakeEnv();
  for (const body of ["{oops", "[]", { side: "red" }, { name: 5 }, { clock: { initial: 30 } }, { clock: { initial: 600, increment: 90 } }]) {
    const answer = await send(env, "POST", "/api/games", { body });
    assert.equal(answer.status, 400, JSON.stringify(body));
    assert.equal(answer.json.error, "bad_request");
    assert.equal(typeof answer.json.message, "string");
  }
  assert.equal(called("create").length, 0);
  const wrong = await send(env, "GET", "/api/games");
  assert.equal(wrong.status, 405);
  assert.equal(wrong.headers.get("allow"), "POST");
  // Tests run with shorter clocks allowed.
  const short = fakeEnv({ vars: { MIN_CLOCK_SECONDS: "1" } });
  assert.equal((await send(short.env, "POST", "/api/games", { body: { clock: { initial: 1 } } })).status, 201);
});

test("too many requests from one address are turned away", async () => {
  const { env, called } = fakeEnv({ limits: { create: false, join: false, move: false } });
  const made = await send(env, "POST", "/api/games", { body: {} });
  assert.equal(made.status, 429);
  assert.equal(made.json.error, "rate_limited");
  assert.equal(made.headers.get("retry-after"), "60");
  assert.equal((await send(env, "POST", "/api/games/7KQ2XM/join", { body: {} })).status, 429);
  assert.equal((await send(env, "POST", "/api/games/7KQ2XM/move", { body: { uci: "e2e4", ply: 0 }, headers: bearer })).status, 429);
  assert.equal((await send(env, "POST", "/api/games/7KQ2XM/action", { body: { type: "resign" }, headers: bearer })).status, 429);
  assert.equal(called("create").length + called("join").length + called("move").length + called("action").length, 0);
  // Limits are per address.
  assert.ok(called("limit").every((call) => call[2] === "203.0.113.7"));
});

test("a rematch also counts as a new game", async () => {
  const { env, called } = fakeEnv({ limits: { create: false } });
  const asked = await send(env, "POST", "/api/games/7KQ2XM/action", { body: { type: "rematch" }, headers: bearer });
  assert.equal(asked.status, 429);
  assert.equal(called("action").length, 0);
  const resign = await send(env, "POST", "/api/games/7KQ2XM/action", { body: { type: "resign" }, headers: bearer });
  assert.equal(resign.status, 200);
});

test("a limiter that fails doesn't stop anyone playing", async () => {
  const { env } = fakeEnv({ limits: { create: "throw" } });
  assert.equal((await send(env, "POST", "/api/games", { body: {} })).status, 201);
});

test("game addresses are checked before any game is asked", async () => {
  const { env, called } = fakeEnv();
  assert.equal((await send(env, "GET", "/api/games/0OOOOO")).json.error, "not_found");
  assert.equal((await send(env, "GET", "/api/games/7KQ2X")).status, 404);
  assert.equal((await send(env, "GET", "/api/games/7KQ2XM/somewhere")).status, 404);
  for (const part of ["constructor", "__proto__", "tostring"]) {
    const answer = await send(env, "GET", `/api/games/7KQ2XM/${part}`);
    assert.equal(answer.status, 404, part);
    assert.equal(answer.json.error, "not_found", part);
  }
  assert.equal((await send(env, "POST", "/api/games/7KQ2XM")).status, 405);
  assert.equal((await send(env, "GET", "/api/games/7KQ2XM/move")).status, 405);
  assert.equal((await send(env, "GET", "/api/elsewhere")).json.error, "not_found");
  assert.equal(called("read").length, 0);
  await send(env, "GET", "/api/games/7kq2xm");
  assert.deepEqual(called("read").map((call) => call[1]), ["7KQ2XM"]);
});

test("moves and actions need a seat's token, from the header or the body", async () => {
  const { env, called } = fakeEnv();
  const none = await send(env, "POST", "/api/games/7KQ2XM/move", { body: { uci: "e2e4", ply: 0 } });
  assert.equal(none.status, 401);
  assert.equal(none.json.error, "unauthorized");
  assert.equal((await send(env, "POST", "/api/games/7KQ2XM/move", { body: { uci: "e2e4", ply: 0 }, headers: { authorization: "Bearer nope" } })).status, 401);
  assert.equal((await send(env, "POST", "/api/games/7KQ2XM/action", { body: { type: "away", token: "short" } })).status, 401);
  assert.equal(called("move").length + called("action").length, 0);

  assert.equal((await send(env, "POST", "/api/games/7KQ2XM/move", { body: { uci: "e2e4", ply: 0 }, headers: bearer })).status, 200);
  assert.deepEqual(called("move")[0][2], { token: TOKEN, uci: "e2e4", ply: 0 });

  // navigator.sendBeacon: text/plain, token in the body.
  const beacon = await send(env, "POST", "/api/games/7KQ2XM/action", {
    body: JSON.stringify({ type: "away", token: TOKEN.toUpperCase() }),
    headers: { "content-type": "text/plain;charset=UTF-8" },
  });
  assert.equal(beacon.status, 200);
  assert.deepEqual(called("action")[0][2], { token: TOKEN, type: "away" });
});

test("only the listed actions reach a game", async () => {
  const { env, called } = fakeEnv();
  for (const type of ["explode", "", 3, undefined]) {
    const answer = await send(env, "POST", "/api/games/7KQ2XM/action", { body: { type }, headers: bearer });
    assert.equal(answer.status, 400, String(type));
  }
  assert.equal(called("action").length, 0);
});

test("joining, with or without a token", async () => {
  const { env, called } = fakeEnv();
  assert.equal((await send(env, "POST", "/api/games/7KQ2XM/join")).status, 200);
  assert.deepEqual(called("join")[0][2], { token: null, name: null });
  await send(env, "POST", "/api/games/7KQ2XM/join", { body: { name: "Sam" }, headers: bearer });
  assert.deepEqual(called("join")[1][2], { token: TOKEN, name: "Sam" });
  assert.equal((await send(env, "POST", "/api/games/7KQ2XM/join", { body: {}, headers: { authorization: "Basic x" } })).status, 401);
  assert.equal((await send(env, "POST", "/api/games/7KQ2XM/join", { body: { name: ["Sam"] } })).status, 400);
  assert.equal(called("join").length, 2);
});

test("the live address takes only WebSockets", async () => {
  const { env, called } = fakeEnv();
  assert.equal((await send(env, "GET", "/api/games/7KQ2XM/live")).status, 426);
  const upgrade = { upgrade: "websocket" };
  assert.equal((await send(env, "GET", "/api/games/7KQ2XM/live?token=nope", { headers: upgrade })).status, 401);
  assert.equal((await send(env, "GET", `/api/games/7kq2xm/live?token=${TOKEN}`, { headers: upgrade })).text, "upgraded");
  assert.equal((await send(env, "GET", "/api/games/7KQ2XM/live", { headers: upgrade })).text, "upgraded");
  assert.deepEqual(called("fetch").map((call) => call[1]), ["7KQ2XM", "7KQ2XM"]);
});

test("the app-site file for universal links needs a team ID", async () => {
  const off = fakeEnv();
  assert.equal((await send(off.env, "GET", "/.well-known/apple-app-site-association")).status, 404);
  const on = fakeEnv({ vars: { APPLE_TEAM_ID: "abcde12345" } });
  const file = await send(on.env, "GET", "/.well-known/apple-app-site-association");
  assert.equal(file.status, 200);
  assert.equal(file.headers.get("content-type"), "application/json; charset=utf-8");
  assert.deepEqual(file.json.applinks.details[0].appIDs, ["ABCDE12345.com.chessgamekiller.app"]);
  assert.deepEqual(file.json.applinks.details[0].components[0]["/"], "/c/*");
});

test("anything else is a plain 404", async () => {
  const { env } = fakeEnv();
  const answer = await send(env, "GET", "/nothing/here");
  assert.equal(answer.status, 404);
  assert.match(answer.headers.get("content-type"), /^text\/plain/);
});

test("a failure inside a game is a 500 that gives nothing away", async () => {
  const { env } = fakeEnv({
    rooms: {
      read: () => {
        throw new Error("storage on fire");
      },
      fetch: () => {
        throw new Error("socket trouble");
      },
    },
  });
  const original = console.error;
  const logged = [];
  console.error = (...args) => logged.push(args.join(" "));
  try {
    const api = await send(env, "GET", "/api/games/7KQ2XM");
    assert.equal(api.status, 500);
    assert.equal(api.json.error, "server_error");
    assert.ok(!api.text.includes("storage on fire"));
    const page = await send(env, "GET", "/c/7KQ2XM");
    assert.equal(page.status, 500);
    // The live address's token is in the query, which is never logged.
    const live = await send(env, "GET", `/api/games/7KQ2XM/live?token=${TOKEN}`, { headers: { upgrade: "websocket" } });
    assert.equal(live.status, 500);
  } finally {
    console.error = original;
  }
  assert.equal(logged.length, 3);
  assert.ok(logged.every((line) => !line.includes(TOKEN)));
});
