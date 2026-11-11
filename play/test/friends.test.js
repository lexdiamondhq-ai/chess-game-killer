import assert from "node:assert/strict";
import { test } from "node:test";
import { displayName, friendSeat, likeEscape, parseQuery, parseUsername, personView, ONLINE_MS } from "../src/friends.js";

test("usernames are made canonical", () => {
  assert.deepEqual(parseUsername(" @Maria_Lopez "), { ok: true, value: "maria_lopez" });
  assert.deepEqual(parseUsername("j.dog"), { ok: true, value: "j.dog" });
});

test("bad usernames are refused with a reason", () => {
  for (const bad of ["ab", "a".repeat(21), "1maria", "ma ria", "maría", "maria.", "ma..ria", "admin", "coach_leo", "fuckface", null]) {
    const parsed = parseUsername(bad);
    assert.equal(parsed.ok, false, String(bad));
    assert.ok(parsed.message);
  }
});

test("search queries", () => {
  assert.equal(parseQuery("@Mar"), "mar");
  assert.equal(parseQuery(" m "), null);
  assert.equal(parseQuery(42), null);
  assert.equal(likeEscape("a_b%c\\"), "a\\_b\\%c\\\\");
});

test("how a player is shown", () => {
  assert.equal(displayName("", "maria"), "maria");
  assert.equal(displayName("Maria Lopez", "maria"), "Maria Lopez");
  const now = 1_000_000;
  assert.deepEqual(personView({ username: "maria", name: "Maria", last_seen: now - 1000 }, now), { username: "maria", name: "Maria", online: true });
  assert.equal(personView({ username: "maria", name: "Maria", last_seen: now - ONLINE_MS }, now).online, false);
});

test("the invited friend takes the open seat", () => {
  assert.equal(friendSeat({ creator: "white" }), "black");
  assert.equal(friendSeat({ creator: "black" }), "white");
});
