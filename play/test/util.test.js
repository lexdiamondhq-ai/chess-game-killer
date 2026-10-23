import assert from "node:assert/strict";
import { createHash } from "node:crypto";
import { test } from "node:test";
import {
  CODE_ALPHABET,
  ERROR_STATUS,
  cleanName,
  errorResponse,
  hashToken,
  isToken,
  jsonResponse,
  newCode,
  newToken,
  normalizeCode,
  readConfig,
  readJson,
  tokenFrom,
} from "../src/util.js";

test("the code alphabet has 31 letters and none that can be misread", () => {
  assert.equal(CODE_ALPHABET.length, 31);
  assert.equal(new Set(CODE_ALPHABET).size, 31);
  for (const confusing of "01OIL") assert.ok(!CODE_ALPHABET.includes(confusing), confusing);
});

test("codes are 6 letters from the alphabet, and every letter turns up", () => {
  const seen = new Set();
  for (let i = 0; i < 3000; i += 1) {
    const code = newCode();
    assert.match(code, /^[23456789ABCDEFGHJKMNPQRSTUVWXYZ]{6}$/);
    for (const letter of code) seen.add(letter);
  }
  assert.equal(seen.size, 31);
});

test("codes skip the random bytes that would favour some letters", () => {
  // 248 and up are thrown away; 0 is "2", 30 is "Z", 31 wraps to "2" again.
  const bytes = [255, 248, 0, 30, 31, 62, 249, 247, 1];
  const code = newCode((count) => new Uint8Array(count).map((_, i) => bytes[i % bytes.length]));
  assert.equal(code, "2Z22Z3");
});

test("codes are read in any case and checked", () => {
  assert.equal(normalizeCode("7kq2xm"), "7KQ2XM");
  assert.equal(normalizeCode(" 7KQ2XM "), "7KQ2XM");
  for (const bad of ["7KQ2X", "7KQ2XMM", "7KQ2X0", "7KQ2XO", "7KQ2X1", "7KQ2XI", "7KQ2XL", "7KQ-XM", "", null, 123456]) {
    assert.equal(normalizeCode(bad), null, String(bad));
  }
});

test("tokens are 128 random bits in lowercase hex", () => {
  const a = newToken();
  const b = newToken();
  assert.match(a, /^[0-9a-f]{32}$/);
  assert.notEqual(a, b);
  assert.ok(isToken(a));
  assert.ok(isToken(a.toUpperCase()));
  for (const bad of [a.slice(1), `${a}0`, "g".repeat(32), "", null, 42]) assert.equal(isToken(bad), false, String(bad));
});

test("only a token's SHA-256 is kept", async () => {
  const token = "0123456789abcdef0123456789abcdef";
  const expected = createHash("sha256").update(token).digest("hex");
  assert.equal(await hashToken(token), expected);
  assert.equal(await hashToken(token.toUpperCase()), expected);
  assert.notEqual(await hashToken("f".repeat(32)), expected);
});

test("names are tidied before anyone sees them", () => {
  assert.equal(cleanName("  Alex   Smith  "), "Alex Smith");
  assert.equal(cleanName("Alex\nSmith\t!"), "Alex Smith !");
  assert.equal(cleanName("\u0000Bo\u0007b\u007f\u009f"), "Bob");
  assert.equal(cleanName("‮evil‬ name"), "evil name");
  assert.equal(cleanName("​​ㅤ"), "Player");
  assert.equal(cleanName(" Ana Lu　"), "Ana Lu");
  assert.equal(cleanName(""), "Player");
  assert.equal(cleanName("   "), "Player");
  assert.equal(cleanName(null), "Player");
  assert.equal(cleanName(undefined), "Player");
  assert.equal(cleanName(42), "Player");
  // Escaping is the pages' job; the name itself is kept as typed.
  assert.equal(cleanName("<b>Kim</b> & \"Lee\""), "<b>Kim</b> & \"Lee\"");
  // Composed into one character.
  assert.equal(cleanName("René"), "René");
});

test("names are cut to 24 whole characters", () => {
  assert.equal(cleanName("a".repeat(30)), "a".repeat(24));
  assert.equal(cleanName(`${"a".repeat(23)} bcd`), "a".repeat(23));
  const emoji = cleanName("😀".repeat(30));
  assert.equal(Array.from(emoji).length, 24);
  assert.equal(emoji, "😀".repeat(24));
  // A cut through an emoji sequence doesn't leave a dangling joiner.
  assert.equal(cleanName(`${"a".repeat(23)}👩‍👩‍👧`), `${"a".repeat(23)}👩`);
  assert.equal(cleanName(`${"a".repeat(22)}👩‍👩`), `${"a".repeat(22)}👩`);
  assert.equal(cleanName(cleanName(" x ".repeat(20))), cleanName(" x ".repeat(20)));
});

test("settings come from the vars, with safe defaults", () => {
  const DAY = 24 * 60 * 60 * 1000;
  assert.deepEqual(readConfig({}), { leaveGraceMs: 20000, minClockSeconds: 60, keepFinishedMs: 30 * DAY });
  assert.deepEqual(readConfig({ LEAVE_GRACE_MS: "1500", MIN_CLOCK_SECONDS: "1", KEEP_FINISHED_MS: "4000" }), {
    leaveGraceMs: 1500,
    minClockSeconds: 1,
    keepFinishedMs: 4000,
  });
  assert.deepEqual(readConfig({ LEAVE_GRACE_MS: "soon", MIN_CLOCK_SECONDS: "0", KEEP_FINISHED_MS: "" }), {
    leaveGraceMs: 20000,
    minClockSeconds: 1,
    keepFinishedMs: 30 * DAY,
  });
  assert.deepEqual(readConfig({ LEAVE_GRACE_MS: "-5", MIN_CLOCK_SECONDS: "99999", KEEP_FINISHED_MS: "1" }), {
    leaveGraceMs: 0,
    minClockSeconds: 3600,
    keepFinishedMs: 1000,
  });
});

function post(body, headers = {}) {
  return new Request("https://play.example/api/games", { method: "POST", body, headers });
}

test("bodies are read as JSON whatever their content type", async () => {
  assert.deepEqual(await readJson(post('{"type":"away"}', { "content-type": "text/plain" })), { ok: true, value: { type: "away" } });
  assert.deepEqual(await readJson(post("")), { ok: true, value: {} });
  assert.deepEqual(await readJson(new Request("https://play.example/")), { ok: true, value: {} });
  assert.equal((await readJson(post("{nope"))).ok, false);
  assert.equal((await readJson(post("[1,2]"))).ok, false);
  assert.equal((await readJson(post("null"))).ok, false);
  assert.equal((await readJson(post('"text"'))).ok, false);
});

test("bodies over 8 KB are refused", async () => {
  const big = JSON.stringify({ name: "x".repeat(9000) });
  assert.equal((await readJson(post(big))).ok, false);
  // Also when the size isn't declared up front.
  const stream = new ReadableStream({
    start(controller) {
      for (let i = 0; i < 10; i += 1) controller.enqueue(new TextEncoder().encode("x".repeat(1000)));
      controller.close();
    },
  });
  const request = new Request("https://play.example/", { method: "POST", body: stream, duplex: "half" });
  assert.equal((await readJson(request)).ok, false);
});

test("the token comes from the Authorization header or the body", () => {
  const token = "0123456789abcdef0123456789abcdef";
  const withHeader = (value) => new Request("https://play.example/", { headers: { authorization: value } });
  const bare = new Request("https://play.example/");
  assert.equal(tokenFrom(withHeader(`Bearer ${token}`), {}), token);
  assert.equal(tokenFrom(withHeader(`bearer   ${token.toUpperCase()}`), {}), token);
  assert.equal(tokenFrom(withHeader(`Basic ${token}`), {}), "");
  assert.equal(tokenFrom(withHeader(`Bearer ${token}`), { token: "f".repeat(32) }), token);
  assert.equal(tokenFrom(bare, { token }), token);
  assert.equal(tokenFrom(bare, { token: 12 }), "");
  assert.equal(tokenFrom(bare, { token: null }), null);
  assert.equal(tokenFrom(bare, {}), null);
});

test("JSON replies are never cached and errors carry their status", async () => {
  const ok = jsonResponse({ a: 1 }, 201);
  assert.equal(ok.status, 201);
  assert.equal(ok.headers.get("content-type"), "application/json; charset=utf-8");
  assert.equal(ok.headers.get("cache-control"), "no-store");
  const statuses = Object.fromEntries(
    ["not_found", "bad_request", "unauthorized", "seat_taken", "not_your_turn", "stale", "game_over", "illegal_move", "rate_limited"].map(
      (code) => [code, ERROR_STATUS[code]],
    ),
  );
  assert.deepEqual(statuses, {
    not_found: 404,
    bad_request: 400,
    unauthorized: 401,
    seat_taken: 409,
    not_your_turn: 409,
    stale: 409,
    game_over: 409,
    illegal_move: 422,
    rate_limited: 429,
  });
  const error = errorResponse("stale", "Moved on", { code: "7KQ2XM" });
  assert.equal(error.status, 409);
  assert.deepEqual(await error.json(), { error: "stale", message: "Moved on", game: { code: "7KQ2XM" } });
  assert.deepEqual(await errorResponse("not_found", "Gone").json(), { error: "not_found", message: "Gone" });
});
