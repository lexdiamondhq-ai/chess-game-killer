import assert from "node:assert/strict";
import { test } from "node:test";
import { act, createPairedGame, needsRatingReport, rematchRecord, setRatingsAfter, view, whiteScore } from "../src/game.js";
import {
  addSeek,
  bestOpponent,
  eloAfter,
  emptyLobby,
  listView,
  parseSeekInput,
  SEEK_STALE_MS,
  MATCH_KEEP_MS,
  sweep,
} from "../src/lobby.js";
import { isToken } from "../src/util.js";

const T0 = 1_792_756_800_000;
const KEY = "0123456789abcdef0123456789abcdef";
const BLITZ = { initial: 300, increment: 0 };
const RAPID = { initial: 600, increment: 0 };

function seek(lobby, id, { player = id, rating = 1200, games = 0, clock = BLITZ, at = T0, name = id } = {}) {
  return addSeek(lobby, { id, tokenHash: `t-${id}`, playerHash: player, name, rating, games, clock, look: null }, at);
}

test("a seek needs a name, a player key and a clock", () => {
  const ok = parseSeekInput({ name: "  Alex  ", clock: BLITZ, player: KEY, look: "gilded" }, { isKey: isToken });
  assert.deepEqual(ok, { ok: true, value: { name: "Alex", clock: BLITZ, look: "gilded", player: KEY } });
  assert.equal(parseSeekInput({ name: "A", clock: null, player: KEY }, { isKey: isToken }).ok, false);
  assert.equal(parseSeekInput({ name: "A", clock: BLITZ, player: "nope" }, { isKey: isToken }).ok, false);
  assert.equal(parseSeekInput({ name: 3, clock: BLITZ, player: KEY }, { isKey: isToken }).ok, false);
  // Taking a waiting player on needs no clock: theirs is used.
  assert.equal(parseSeekInput({ name: "A", player: KEY }, { needsClock: false, isKey: isToken }).ok, true);
  // Offensive names are filtered as in friend games.
  assert.equal(parseSeekInput({ name: "fuck", clock: BLITZ, player: KEY }, { isKey: isToken }).value.name, "Player");
});

test("the list shows open seeks, longest waiting first, and never a hash or token", () => {
  const lobby = emptyLobby();
  seek(lobby, "b", { at: T0 + 1000, rating: 1500, games: 12 });
  seek(lobby, "a", { at: T0 });
  const list = listView(lobby, T0 + 2000);
  assert.deepEqual(list.players.map((p) => p.id), ["a", "b"]);
  assert.equal(list.waiting, 2);
  assert.deepEqual(list.players[1], {
    id: "b", name: "b", rating: 1500, provisional: false, clock: BLITZ, look: null, waitingFor: 1000,
  });
  assert.equal(list.players[0].provisional, true);
  assert.doesNotMatch(JSON.stringify(list), /t-a|tokenHash|playerHash/);
});

test("quick pairing takes the closest rating at the same clock, never yourself", () => {
  const lobby = emptyLobby();
  seek(lobby, "far", { rating: 1900 });
  seek(lobby, "near", { rating: 1250 });
  seek(lobby, "rapid", { rating: 1200, clock: RAPID });
  seek(lobby, "me", { rating: 1200 });
  assert.equal(bestOpponent(lobby, { clock: BLITZ, playerHash: "me", rating: 1200 }, T0).id, "near");
  assert.equal(bestOpponent(lobby, { clock: RAPID, playerHash: "rapid", rating: 1200 }, T0), null);
  assert.equal(bestOpponent(lobby, { clock: { initial: 180, increment: 2 }, playerHash: "x", rating: 1200 }, T0), null);
  // A taken seek or one being paired is nobody else's.
  lobby.seeks.near.pairing = true;
  assert.equal(bestOpponent(lobby, { clock: BLITZ, playerHash: "me", rating: 1200 }, T0).id, "far");
});

test("a player waits once: a new seek replaces their old one", () => {
  const lobby = emptyLobby();
  seek(lobby, "one", { player: "p" });
  seek(lobby, "two", { player: "p" });
  assert.deepEqual(Object.keys(lobby.seeks), ["two"]);
});

test("players who stop checking in leave the lobby; taken seeks wait to be picked up", () => {
  const lobby = emptyLobby();
  seek(lobby, "quiet");
  seek(lobby, "taken");
  lobby.seeks.taken.match = { code: "7KQ2XM", seat: "white", token: KEY, at: T0 };
  assert.equal(listView(lobby, T0 + SEEK_STALE_MS + 1).waiting, 0);
  assert.equal(sweep(lobby, T0 + SEEK_STALE_MS + 1), true);
  assert.deepEqual(Object.keys(lobby.seeks), ["taken"]);
  sweep(lobby, T0 + MATCH_KEEP_MS + 1);
  assert.deepEqual(Object.keys(lobby.seeks), []);
});

test("Elo: a win against an equal player gains 20 while settling, 10 after", () => {
  const fresh = eloAfter({ rating: 1200, games: 0 }, { rating: 1200, games: 0 }, 1);
  assert.deepEqual(fresh, { white: { rating: 1220, games: 1 }, black: { rating: 1180, games: 1 } });
  const settled = eloAfter({ rating: 1500, games: 30 }, { rating: 1500, games: 30 }, 0.5);
  assert.deepEqual(settled, { white: { rating: 1500, games: 31 }, black: { rating: 1500, games: 31 } });
  const upset = eloAfter({ rating: 1200, games: 30 }, { rating: 1600, games: 30 }, 1);
  assert.equal(upset.white.rating - 1200, 18);
});

function pairedGame() {
  return createPairedGame({
    code: "ONL1NE",
    white: { name: "Alex", tokenHash: "hw" },
    black: { name: "Sam", tokenHash: "hb" },
    clock: BLITZ,
    look: "gilded",
    rated: { white: { player: "pw", rating: 1200, games: 0 }, black: { player: "pb", rating: 1450, games: 20 } },
    now: T0,
  });
}

test("a paired game starts with both seated, rated, and shows ratings but no player keys", () => {
  const game = pairedGame();
  const state = view(game, T0);
  assert.equal(state.status, "active");
  assert.equal(state.white.name, "Alex");
  assert.equal(state.black.name, "Sam");
  assert.equal(state.rated, true);
  assert.deepEqual(state.ratings, {
    white: { rating: 1200, provisional: true, after: null, change: null },
    black: { rating: 1450, provisional: false, after: null, change: null },
  });
  assert.doesNotMatch(JSON.stringify(state), /"pw"|"pb"|"hw"|"hb"/);
});

test("a rated game is reported once it ends in a way that counts", () => {
  const game = pairedGame();
  assert.equal(needsRatingReport(game), false);
  act(game, "white", "resign", T0 + 1000); // before both moved: aborted, unrated
  assert.equal(game.result.reason, "aborted");
  assert.equal(needsRatingReport(game), false);

  const played = pairedGame();
  played.moves = ["e2e4", "e7e5"]; // past the opening moves, a resignation counts
  act(played, "black", "resign", T0 + 1000);
  assert.equal(played.result.winner, "white");
  assert.equal(needsRatingReport(played), true);
  assert.equal(whiteScore(played), 1);
  played.rated.reported = true;
  assert.equal(needsRatingReport(played), false);
  setRatingsAfter(played, { white: { rating: 1232, games: 1 }, black: { rating: 1436, games: 21 } }, T0 + 2000);
  assert.deepEqual(view(played, T0 + 2000).ratings.white, { rating: 1200, provisional: true, after: 1232, change: 32 });
  assert.equal(view(played, T0 + 2000).ratings.black.change, -14);
});

test("a rematch of a rated game is rated, colors swapped, from the newest ratings", () => {
  const game = pairedGame();
  game.result = { winner: "white", reason: "resign" };
  game.endedAt = T0;
  game.rated.reported = true;
  game.rated.after = { white: { rating: 1232, games: 1 }, black: { rating: 1436, games: 21 } };
  const next = rematchRecord(game, "R3MTCH", T0 + 10);
  assert.deepEqual(next.rated.white, { player: "pb", rating: 1436, games: 21 });
  assert.deepEqual(next.rated.black, { player: "pw", rating: 1232, games: 1 });
  assert.equal(next.rated.reported, false);
});
