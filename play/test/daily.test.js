import assert from "node:assert/strict";
import { test } from "node:test";
import { counted, isDailyDay, parseDailyReport, playerKey, tallyKey } from "../src/daily.js";
import { isToken } from "../src/util.js";

const NOW = Date.parse("2026-10-29T15:00:00Z");
const KEY = "0123456789abcdef0123456789abcdef";

test("a day is a real date close to today", () => {
  assert.equal(isDailyDay("2026-10-29", NOW), true);
  // Players ahead of or behind the server's date, across the world's time zones.
  assert.equal(isDailyDay("2026-10-28", NOW), true);
  assert.equal(isDailyDay("2026-10-30", NOW), true);
  assert.equal(isDailyDay("2026-10-20", NOW), false);
  assert.equal(isDailyDay("2026-11-05", NOW), false);
  assert.equal(isDailyDay("2026-02-31", Date.parse("2026-02-28T12:00:00Z")), false);
  assert.equal(isDailyDay("29-10-2026", NOW), false);
  assert.equal(isDailyDay(20261029, NOW), false);
});

test("a report needs the player key, the puzzle id and whether it was found", () => {
  assert.deepEqual(parseDailyReport({ player: KEY, puzzle: "vTa44", found: true }, { isKey: isToken }), {
    ok: true,
    value: { player: KEY, puzzle: "vTa44", found: true },
  });
  assert.equal(parseDailyReport({ player: "nope", puzzle: "vTa44", found: true }, { isKey: isToken }).ok, false);
  assert.equal(parseDailyReport({ player: KEY, puzzle: "a b", found: true }, { isKey: isToken }).ok, false);
  assert.equal(parseDailyReport({ player: KEY, puzzle: "vTa44", found: "yes" }, { isKey: isToken }).ok, false);
  assert.equal(parseDailyReport(null, { isKey: isToken }).ok, false);
});

test("each player counts once a day", () => {
  let tally = counted(undefined, { found: true, seen: false });
  assert.deepEqual(tally, { players: 1, found: 1 });
  tally = counted(tally, { found: false, seen: false });
  assert.deepEqual(tally, { players: 2, found: 1 });
  // The same player again: nothing changes.
  assert.deepEqual(counted(tally, { found: true, seen: true }), { players: 2, found: 1 });
});

test("the tally is kept per day and puzzle, the player mark per day", () => {
  assert.equal(tallyKey("2026-10-29", "vTa44"), "daily:2026-10-29:vTa44");
  assert.equal(playerKey("2026-10-29", "abc"), "daily-player:2026-10-29:abc");
});
