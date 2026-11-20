import assert from "node:assert/strict";
import { generateKeyPairSync, createVerify } from "node:crypto";
import { test } from "node:test";
import * as push from "../src/push.js";
import * as rules from "../src/game.js";

const T0 = Date.UTC(2026, 10, 20, 12, 0, 0);
const HOUR = 60 * 60 * 1000;
const DAY = 24 * HOUR;
const PHONE = "ab".repeat(32);

test("moves in plain words", () => {
  assert.equal(push.moveWords("Nf3"), "played knight to f3.");
  assert.equal(push.moveWords("e4"), "played pawn to e4.");
  assert.equal(push.moveWords("Bxd5"), "took on d5 with a bishop.");
  assert.equal(push.moveWords("exd5"), "took on d5 with a pawn.");
  assert.equal(push.moveWords("Qh5+"), "played queen to h5. Check.");
  assert.equal(push.moveWords("O-O"), "castled short.");
  assert.equal(push.moveWords("O-O-O+"), "castled long. Check.");
  assert.equal(push.moveWords("e8=Q"), "played pawn to e8, making a queen.");
  assert.equal(push.moveWords("Rae1"), "played rook to e1.");
  assert.equal(push.moveWords(""), null);
});

test("the four alerts read as Alex picked them", () => {
  assert.deepEqual(push.challengeAlert({ from: "Maya", clock: { initial: 600, increment: 0 } }), {
    title: "Maya challenges you",
    body: "10 minute game. Tap to accept.",
  });
  assert.equal(push.challengeAlert({ from: "Maya", clock: { initial: 180, increment: 2 } }).body, "3+2 game. Tap to accept.");
  assert.equal(push.challengeAlert({ from: "Maya", days: 3 }).body, "Daily game, 3 days a move. Tap to accept.");
  assert.equal(push.challengeAlert({ from: "Maya", days: 1 }).body, "Daily game, 1 day a move. Tap to accept.");
  assert.equal(push.challengeAlert({ from: "Maya" }).body, "Game with no clock. Tap to accept.");
  assert.deepEqual(push.acceptedAlert({ name: "Maya", seat: "white" }), { title: "Maya accepted", body: "The board is set. You play white." });
  assert.deepEqual(push.yourMoveAlert({ name: "Maya", san: "Nf3" }), { title: "Your move against Maya", body: "Maya played knight to f3." });
  assert.deepEqual(push.lastCallAlert({ name: "Sam" }), { title: "6 hours left to move", body: "Your daily game with Sam ends if you wait." });
  for (const alert of [push.challengeAlert({ from: "A" }), push.yourMoveAlert({ name: "A", san: "e4" }), push.lastCallAlert({ name: "A" })]) {
    assert.ok(!/[—–]/.test(alert.title + alert.body), "no dashes");
  }
});

test("the payload carries the game's code so a tap opens it", () => {
  assert.deepEqual(push.apnsPayload({ title: "T", body: "B" }, { kind: "move", code: "7KQ2XM" }), {
    aps: { alert: { title: "T", body: "B" }, sound: "default", "thread-id": "7KQ2XM" },
    kind: "move",
    code: "7KQ2XM",
  });
});

test("phone tokens", () => {
  assert.equal(push.parsePhoneToken(PHONE.toUpperCase()), PHONE);
  assert.equal(push.parsePhoneToken("abc"), null);
  assert.equal(push.parsePhoneToken(42), null);
});

test("seats keep the player key's hash, the view never shows it, and a rematch carries it", () => {
  const game = rules.createGame({ code: "7KQ2XM", name: "Alex", side: "white", tokenHash: "a".repeat(64), playerHash: "1".repeat(64), now: T0 });
  rules.join(game, { name: "Sam", tokenHash: "b".repeat(64), playerHash: "2".repeat(64) }, T0);
  assert.equal(rules.seatPlayer(game, "white"), "1".repeat(64));
  assert.equal(rules.seatPlayer(game, "black"), "2".repeat(64));
  assert.ok(!JSON.stringify(rules.view(game, T0)).includes("1".repeat(64)));
  const next = rules.rematchRecord(game, "ABCDEF", T0);
  assert.equal(rules.seatPlayer(next, "white"), "2".repeat(64));
  assert.equal(rules.seatPlayer(next, "black"), "1".repeat(64));

  const old = rules.createGame({ code: "7KQ2XM", name: "Alex", side: "white", tokenHash: "a".repeat(64), now: T0 });
  assert.equal(rules.seatPlayer(old, "white"), null);
  assert.equal(rules.setSeatPlayer(old, "white", "3".repeat(64), T0).changed, true);
  assert.equal(rules.setSeatPlayer(old, "white", "3".repeat(64), T0).changed, false);
  assert.equal(rules.seatPlayer(old, "white"), "3".repeat(64));
});

test("a daily game's last call comes 6 hours before the move is due, once per move", () => {
  const game = rules.createGame({ code: "7KQ2XM", name: "Alex", side: "white", days: 2, tokenHash: "a".repeat(64), now: T0 });
  rules.join(game, { name: "Sam", tokenHash: "b".repeat(64) }, T0);
  assert.equal(rules.lastCallAt(game, push.LAST_CALL_MS), null, "not before both sides have moved");
  rules.move(game, "white", { uci: "e2e4", ply: 0 }, T0 + HOUR);
  rules.move(game, "black", { uci: "e7e5", ply: 1 }, T0 + 2 * HOUR);
  const due = T0 + 2 * HOUR + 2 * DAY;
  assert.equal(rules.lastCallAt(game, push.LAST_CALL_MS), due - 6 * HOUR);
  rules.markLastCall(game, due - 6 * HOUR);
  assert.equal(rules.lastCallAt(game, push.LAST_CALL_MS), null, "sent once");
  rules.move(game, "white", { uci: "g1f3", ply: 2 }, due - HOUR);
  assert.equal(rules.lastCallAt(game, push.LAST_CALL_MS), due - HOUR + 2 * DAY - 6 * HOUR, "the next move gets its own");

  const timed = rules.createGame({ code: "7KQ2XM", name: "Alex", side: "white", clock: { initial: 600, increment: 0 }, tokenHash: "a".repeat(64), now: T0 });
  assert.equal(rules.lastCallAt(timed, push.LAST_CALL_MS), null);
});

function testKey() {
  const { privateKey, publicKey } = generateKeyPairSync("ec", { namedCurve: "P-256" });
  return { pem: privateKey.export({ type: "pkcs8", format: "pem" }), publicKey };
}

test("sending: a signed token, the right headers, and the sandbox tried when the phone is from Xcode", async () => {
  const { pem, publicKey } = testKey();
  const env = { APNS_KEY: pem, APNS_KEY_ID: "KEY1234567", APNS_TEAM_ID: "team123456" };
  const calls = [];
  const fetcher = async (url, init) => {
    calls.push({ url, init });
    if (url.startsWith("https://api.push.apple.com")) return Response.json({ reason: "BadDeviceToken" }, { status: 400 });
    return new Response(null, { status: 200 });
  };
  const payload = push.apnsPayload({ title: "T", body: "B" }, { kind: "move", code: "7KQ2XM" });
  const result = await push.sendAlert(env, { token: PHONE, sandbox: false, payload, collapseId: "move-7KQ2XM" }, fetcher);
  assert.deepEqual(result, { sent: true, sandbox: true, gone: false });
  assert.equal(calls.length, 2);
  assert.equal(calls[1].url, `https://api.sandbox.push.apple.com/3/device/${PHONE}`);
  const headers = calls[1].init.headers;
  assert.equal(headers["apns-topic"], "com.chessgamekiller.app");
  assert.equal(headers["apns-push-type"], "alert");
  assert.equal(headers["apns-collapse-id"], "move-7KQ2XM");
  assert.deepEqual(JSON.parse(calls[1].init.body), payload);

  const jwt = headers.authorization.replace("bearer ", "");
  const [head, claims, signature] = jwt.split(".");
  assert.deepEqual(JSON.parse(Buffer.from(head, "base64url")), { alg: "ES256", kid: "KEY1234567" });
  assert.equal(JSON.parse(Buffer.from(claims, "base64url")).iss, "TEAM123456");
  const verify = createVerify("SHA256");
  verify.update(`${head}.${claims}`);
  assert.ok(verify.verify({ key: publicKey, dsaEncoding: "ieee-p1363" }, Buffer.from(signature, "base64url")));
});

test("a phone that's gone is reported, and nothing is sent without the secrets", async () => {
  const { pem } = testKey();
  const env = { APNS_KEY: pem, APNS_KEY_ID: "KEY7654321", APNS_TEAM_ID: "TEAM123456" };
  const gone = await push.sendAlert(env, { token: PHONE, payload: {} }, async () => new Response(null, { status: 410 }));
  assert.equal(gone.gone, true);
  let called = false;
  const none = await push.sendAlert({}, { token: PHONE, payload: {} }, async () => {
    called = true;
  });
  assert.deepEqual(none, { sent: false, sandbox: false, gone: false });
  assert.equal(called, false);
});
