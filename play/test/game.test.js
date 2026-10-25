import assert from "node:assert/strict";
import { test } from "node:test";
import * as rules from "../src/game.js";
import { LONE_BLACK_KING, FIFTY_MOVES, INSUFFICIENT } from "./sequences.js";

const T0 = Date.UTC(2026, 9, 23, 12, 0, 0);
const SECOND = 1000;
const DAY = 24 * 60 * 60 * SECOND;
const WHITE = "a".repeat(64); // token hashes
const BLACK = "b".repeat(64);
const GRACE = 60000;

/** A game Alex (White) created at T0, with Sam (Black) already joined unless joined is false. */
function newGame({ clock = null, joined = true, side = "white" } = {}) {
  const game = rules.createGame({ code: "7KQ2XM", name: "Alex", side, clock, tokenHash: side === "black" ? BLACK : WHITE, now: T0, leaveGraceMs: GRACE });
  if (joined) {
    const out = rules.join(game, { name: "Sam", tokenHash: side === "black" ? WHITE : BLACK }, T0);
    assert.equal(out.ok, true);
  }
  return game;
}

/** Plays moves (space-separated UCI) for whoever is to move, `step` ms apart. Returns the last outcome and time. */
function play(game, moves, { from = T0, step = SECOND } = {}) {
  let now = from;
  let out = null;
  for (const uci of moves.split(" ")) {
    now += step;
    out = rules.move(game, rules.turnOf(game), { uci, ply: game.moves.length }, now);
    assert.equal(out.ok, true, `${uci} at ply ${game.moves.length}: ${out.error} ${out.message}`);
  }
  return { out, now };
}

function moveAs(game, seat, uci, now, ply = game.moves.length) {
  return rules.move(game, seat, { uci, ply }, now);
}

const FOOLS_MATE = "f2f3 e7e5 g2g4 d8h4";

// ---------------------------------------------------------------------------
// Creating and joining

test("a new game seats its creator and waits", () => {
  const game = newGame({ joined: false, clock: { initial: 600, increment: 0 } });
  const state = rules.view(game, T0 + 5, { white: true });
  assert.deepEqual(state, {
    code: "7KQ2XM",
    status: "waiting",
    createdAt: T0,
    updatedAt: T0,
    clock: { initial: 600, increment: 0 },
    creator: "white",
    look: null,
    white: { name: "Alex", seated: true, online: true, away: null, claimableAt: null, screenshots: 0, recordings: 0 },
    black: { name: null, seated: false, online: false, away: null, claimableAt: null, screenshots: 0, recordings: 0 },
    moves: [],
    san: [],
    fen: "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1",
    turn: "white",
    clocks: { white: 600000, black: 600000, running: null, since: null },
    drawOffer: null,
    rematch: null,
    result: null,
    leaveGraceMs: GRACE,
    rated: false,
    ratings: null,
    now: T0 + 5,
  });
});

test("a random side is settled when the game is made", () => {
  const make = (pick) =>
    rules.createGame({ code: "7KQ2XM", name: "A", side: "random", clock: null, tokenHash: WHITE, now: T0, pickSide: () => pick });
  const asBlack = make("black");
  assert.equal(asBlack.creator, "black");
  assert.equal(asBlack.black.name, "A");
  assert.equal(asBlack.white, null);
  assert.equal(make("white").creator, "white");
  const sides = new Set();
  for (let i = 0; i < 64; i += 1) sides.add(rules.createGame({ code: "7KQ2XM", name: "A", side: "random", tokenHash: WHITE, now: T0 }).creator);
  assert.deepEqual([...sides].sort(), ["black", "white"]);
});

test("the creator's board look is kept, shown and carried into a rematch", () => {
  const game = rules.createGame({ code: "7KQ2XM", name: "A", side: "white", clock: null, look: "midnight", tokenHash: WHITE, now: T0 });
  assert.equal(rules.view(game, T0).look, "midnight");
  game.black = { name: "B", tokenHash: BLACK, away: null, screenshots: 0, recordings: 0 };
  assert.equal(rules.rematchRecord(game, "8KQ2XM", T0).look, "midnight");
  const older = rules.createGame({ code: "7KQ2XM", name: "A", side: "white", tokenHash: WHITE, now: T0 });
  assert.equal(rules.view(older, T0).look, null);
});

test("the request to make a game is checked", () => {
  const ok = (body, options) => rules.parseCreateInput(body, options);
  assert.deepEqual(ok({}), { ok: true, value: { name: "Player", side: "random", clock: null, look: null } });
  assert.deepEqual(ok({ name: "  Alex ", side: "black", clock: { initial: 180, increment: 2 } }), {
    ok: true,
    value: { name: "Alex", side: "black", clock: { initial: 180, increment: 2 }, look: null },
  });
  // The creator's board look rides along; anything odd is dropped, never refused.
  assert.equal(ok({ look: "classic" }).value.look, "classic");
  for (const look of ["", "Gilded", "../x", 7, "a".repeat(21), null]) assert.equal(ok({ look }).value.look, null);
  assert.deepEqual(ok({ clock: { initial: 300 } }).value.clock, { initial: 300, increment: 0 });
  assert.equal(ok({ side: null }).value.side, "random");
  assert.equal(ok({ clock: null }).value.clock, null);
  for (const body of [
    { side: "red" },
    { name: 7 },
    { clock: { initial: 59 } },
    { clock: { initial: 3601 } },
    { clock: { initial: 180.5 } },
    { clock: { initial: "180" } },
    { clock: { initial: 180, increment: 61 } },
    { clock: { initial: 180, increment: -1 } },
    { clock: "3+2" },
    { clock: [180, 2] },
  ]) {
    const result = ok(body);
    assert.equal(result.ok, false, JSON.stringify(body));
    assert.equal(result.error, "bad_request");
    assert.equal(typeof result.message, "string");
  }
  // Tests may allow a 1-second clock.
  assert.deepEqual(ok({ clock: { initial: 1 } }, { minClockSeconds: 1 }).value.clock, { initial: 1, increment: 0 });
});

test("joining takes the open seat and tells the creator", () => {
  const game = newGame({ joined: false, side: "black" });
  const out = rules.join(game, { name: " Sam\n", tokenHash: WHITE }, T0 + 1000);
  assert.equal(out.ok, true);
  assert.equal(out.seat, "white");
  assert.deepEqual(out.notices, [{ kind: "joined", seat: "white", at: T0 + 1000 }]);
  assert.equal(rules.statusOf(game), "active");
  assert.equal(game.white.name, "Sam");
  assert.equal(rules.seatForToken(game, WHITE), "white");
  assert.equal(rules.seatForToken(game, BLACK), "black");
  assert.equal(rules.seatForToken(game, "c".repeat(64)), null);
  assert.equal(rules.seatForToken(game, null), null);

  const third = rules.join(game, { name: "Kim", tokenHash: "c".repeat(64) }, T0 + 2000);
  assert.equal(third.ok, false);
  assert.equal(third.error, "seat_taken");
  assert.equal(third.changed, false);
});

test("a cancelled game can't be joined", () => {
  const game = newGame({ joined: false });
  assert.equal(rules.act(game, "white", "cancel", T0 + 1000).ok, true);
  const out = rules.join(game, { name: "Sam", tokenHash: BLACK }, T0 + 2000);
  assert.equal(out.error, "game_over");
});

test("a GameState never holds a token or its hash", () => {
  const game = newGame();
  const text = JSON.stringify(rules.view(game, T0));
  assert.ok(!text.includes(WHITE));
  assert.ok(!text.includes(BLACK));
  assert.ok(!text.includes("tokenHash"));
});

// ---------------------------------------------------------------------------
// Moves and how games end on the board

test("fool's mate", () => {
  const game = newGame();
  const { out } = play(game, FOOLS_MATE);
  assert.deepEqual(game.result, { winner: "black", reason: "checkmate" });
  assert.deepEqual(game.moves, ["f2f3", "e7e5", "g2g4", "d8h4"]);
  assert.deepEqual(game.san, ["f3", "e5", "g4", "Qh4#"]);
  assert.equal(game.fen, "rnb1kbnr/pppp1ppp/8/4p3/6Pq/5P2/PPPPP2P/RNBQKBNR w KQkq - 1 3");
  assert.equal(out.changed, true);
  const state = rules.view(game, T0 + 10 * SECOND);
  assert.equal(state.status, "over");
  assert.equal(state.turn, "white");
  assert.equal(game.endedAt, T0 + 4 * SECOND);
  // Nothing more can be played.
  assert.equal(moveAs(game, "white", "e2e4", T0 + 20 * SECOND).error, "game_over");
});

test("scholar's mate", () => {
  const game = newGame();
  play(game, "e2e4 e7e5 d1h5 b8c6 f1c4 g8f6 h5f7");
  assert.deepEqual(game.result, { winner: "white", reason: "checkmate" });
  assert.equal(game.san.at(-1), "Qxf7#");
});

test("stalemate is a draw", () => {
  const game = newGame();
  play(game, "e2e3 a7a5 d1h5 a8a6 h5a5 h7h5 h2h4 a6h6 a5c7 f7f6 c7d7 e8f7 d7b7 d8d3 b7b8 d3h7 b8c8 f7g6 c8e6");
  assert.deepEqual(game.result, { winner: null, reason: "stalemate" });
});

test("the same position three times is a draw", () => {
  const game = newGame();
  play(game, "g1f3 g8f6 f3g1 f6g8 g1f3 g8f6 f3g1");
  assert.equal(game.result, null);
  play(game, "f6g8");
  assert.deepEqual(game.result, { winner: null, reason: "repetition" });
});

test("a repetition is still seen after the game is saved and loaded again", () => {
  const game = newGame();
  play(game, "g1f3 g8f6 f3g1 f6g8 g1f3 g8f6 f3g1");
  // What storage hands back after the room has slept: the same data in a new object.
  const loaded = JSON.parse(JSON.stringify(game));
  play(loaded, "f6g8");
  assert.deepEqual(loaded.result, { winner: null, reason: "repetition" });
  // A record saved before positions were kept plays on, counting from where it stands.
  const old = newGame();
  play(old, "g1f3");
  delete old.positions;
  play(old, "g8f6 f3g1", { from: T0 + 5 * SECOND });
  assert.equal(old.positions.length, 2);
});

test("castling rights are part of the position", () => {
  // The kings walk out and back three times. Back home the first time they
  // can no longer castle, so that isn't the position from before, when they could.
  const game = newGame();
  play(game, "e2e4 e7e5 e1e2 e8e7 e2e1 e7e8 e1e2 e8e7 e2e1 e7e8 e1e2");
  assert.equal(game.result, null);
  play(game, "e8e7", { from: T0 + 20 * SECOND });
  assert.deepEqual(game.result, { winner: null, reason: "repetition" });
});

test("en passant is part of the position, but only when the capture is possible", () => {
  // After d7d5 White could take en passant; once the knights have moved, no
  // longer. So the knights don't come back to the position after d7d5.
  const possible = newGame();
  play(possible, "e2e4 a7a6 e4e5 d7d5 g1f3 g8f6 f3g1 f6g8 g1f3 g8f6 f3g1 f6g8");
  assert.equal(possible.result, null);
  play(possible, "g1f3", { from: T0 + 20 * SECOND });
  assert.deepEqual(possible.result, { winner: null, reason: "repetition" });
  // After e2e4 no black pawn can take en passant, so when the knights come
  // back it is the same position as after e2e4.
  const impossible = newGame();
  play(impossible, "e2e4 g8f6 g1f3 f6g8 f3g1 g8f6 g1f3 f6g8");
  assert.equal(impossible.result, null);
  play(impossible, "f3g1", { from: T0 + 20 * SECOND });
  assert.deepEqual(impossible.result, { winner: null, reason: "repetition" });
});

test("the record keeps only the positions that can still come back", () => {
  const game = newGame();
  assert.deepEqual(game.positions, [rules.positionKey(game.fen)]);
  play(game, "g1f3 g8f6 f3g1 f6g8");
  assert.equal(game.positions.length, 5);
  play(game, "e2e4", { from: T0 + 10 * SECOND }); // a pawn move: nothing before it can come back
  assert.deepEqual(game.positions, [rules.positionKey(game.fen)]);
  assert.equal(rules.positionKey(game.fen), "rnbqkbnr/pppppppp/8/8/4P3/8/PPPP1PPP/RNBQKBNR b KQkq -");
  // Players never see them.
  assert.equal("positions" in rules.view(game, T0), false);
});

test("fifty moves each with no capture or pawn move is a draw", () => {
  const moves = FIFTY_MOVES.split(" ");
  assert.equal(moves.length, 100);
  const game = newGame();
  play(game, moves.slice(0, 99).join(" "));
  assert.equal(game.result, null);
  play(game, moves[99]);
  assert.deepEqual(game.result, { winner: null, reason: "fifty_moves" });
  // The longest the list of positions can get: the start and 100 half-moves.
  assert.equal(game.positions.length, 101);
});

test("a position where nobody can mate is a draw", () => {
  const moves = INSUFFICIENT.split(" ");
  const game = newGame();
  play(game, moves.slice(0, -1).join(" "));
  assert.equal(game.result, null);
  play(game, moves.at(-1));
  assert.deepEqual(game.result, { winner: null, reason: "insufficient" });
});

const TO_PROMOTE = "a2a4 b7b5 a4b5 a7a6 b5a6 c8b7 a6a7 b7c6";

test("a promotion with no letter makes a queen", () => {
  const game = newGame();
  play(game, TO_PROMOTE);
  const out = moveAs(game, "white", "a7b8", T0 + 20 * SECOND);
  assert.equal(out.ok, true);
  assert.equal(game.moves.at(-1), "a7b8q");
  assert.equal(game.san.at(-1), "axb8=Q");
  assert.equal(game.fen.split(" ")[0], "rQ1qkbnr/2pppppp/2b5/8/8/8/1PPPPPPP/RNBQKBNR");
});

test("a promotion with a letter makes that piece", () => {
  const game = newGame();
  play(game, TO_PROMOTE);
  assert.equal(moveAs(game, "white", "A7B8N", T0 + 20 * SECOND).ok, true);
  assert.equal(game.moves.at(-1), "a7b8n");
  assert.equal(game.san.at(-1), "axb8=N");
  // A letter that isn't a piece one can promote to isn't a move at all.
  const other = newGame();
  play(other, TO_PROMOTE);
  assert.equal(moveAs(other, "white", "a7b8k", T0 + 20 * SECOND).error, "bad_request");
});

test("a promotion letter on an ordinary move makes it illegal", () => {
  const game = newGame();
  const out = moveAs(game, "white", "e2e4q", T0 + SECOND);
  assert.equal(out.error, "illegal_move");
  assert.equal(game.moves.length, 0);
});

test("castling, also written as the king taking its own rook", () => {
  const game = newGame();
  play(game, "e2e4 e7e5 g1f3 b8c6 f1c4 g8f6");
  assert.equal(moveAs(game, "white", "e1h1", T0 + 10 * SECOND).ok, true);
  assert.equal(game.moves.at(-1), "e1g1");
  assert.equal(game.san.at(-1), "O-O");
  play(game, "f8c5 d2d3 d7d6 c1g5 c8g4 b1c3 d8d7 a2a3", { from: T0 + 10 * SECOND });
  assert.equal(moveAs(game, "black", "e8c8", T0 + 30 * SECOND).ok, true);
  assert.equal(game.san.at(-1), "O-O-O");
});

test("illegal moves are refused and change nothing", () => {
  const game = newGame();
  for (const uci of ["e2e5", "e7e5", "e1e2", "a1a3", "h2g3"]) {
    const out = moveAs(game, "white", uci, T0 + SECOND);
    assert.equal(out.ok, false, uci);
    assert.equal(out.error, "illegal_move", uci);
    assert.equal(out.changed, false, uci);
  }
  // A move that ignores a check is illegal; one that blocks it is fine.
  play(game, "e2e4 e7e5 d2d4 f8b4");
  assert.equal(moveAs(game, "white", "g1f3", T0 + 10 * SECOND).error, "illegal_move");
  assert.equal(moveAs(game, "white", "c2c3", T0 + 10 * SECOND).ok, true);
  // A pinned piece can't move.
  const pinned = newGame();
  play(pinned, "e2e4 e7e5 g1f3 d7d6 f1b5 b8c6 a2a3");
  assert.equal(moveAs(pinned, "black", "c6d4", T0 + 10 * SECOND).error, "illegal_move");
  assert.equal(pinned.moves.length, 7);
});

test("moving out of turn is refused", () => {
  const game = newGame();
  const out = moveAs(game, "black", "e7e5", T0 + SECOND);
  assert.equal(out.error, "not_your_turn");
  play(game, "e2e4");
  assert.equal(moveAs(game, "white", "d2d4", T0 + 5 * SECOND).error, "not_your_turn");
});

test("a move for a ply that has passed (or not come) is stale", () => {
  const game = newGame();
  play(game, "e2e4 e7e5");
  // A retried request for a move that already went through.
  const again = moveAs(game, "black", "e7e5", T0 + 5 * SECOND, 1);
  assert.equal(again.error, "stale");
  assert.equal(moveAs(game, "white", "g1f3", T0 + 5 * SECOND, 3).error, "stale");
  assert.equal(moveAs(game, "white", "g1f3", T0 + 5 * SECOND, 2).ok, true);
});

test("a move must be sent properly", () => {
  const game = newGame();
  for (const input of [{}, { uci: "e2-e4", ply: 0 }, { uci: "e9e4", ply: 0 }, { uci: 42, ply: 0 }, { uci: "e2e4" }, { uci: "e2e4", ply: -1 }, { uci: "e2e4", ply: "0" }, { uci: "e2e4", ply: 0.5 }]) {
    assert.equal(rules.move(game, "white", input, T0 + SECOND).error, "bad_request", JSON.stringify(input));
  }
  assert.equal(rules.move(game, "white", { uci: " E2E4 ", ply: 0 }, T0 + SECOND).ok, true);
});

test("nobody moves before the friend has joined", () => {
  const game = newGame({ joined: false });
  assert.equal(moveAs(game, "white", "e2e4", T0 + SECOND).error, "not_your_turn");
});

// ---------------------------------------------------------------------------
// Clocks

test("the clocks start once both sides have moved, and each move earns the increment", () => {
  const game = newGame({ clock: { initial: 60, increment: 2 } });
  assert.equal(moveAs(game, "white", "e2e4", T0 + 5000).ok, true);
  assert.deepEqual(rules.view(game, T0 + 5000).clocks, { white: 60000, black: 60000, running: null, since: null });
  assert.equal(moveAs(game, "black", "e7e5", T0 + 9000).ok, true);
  assert.deepEqual(rules.view(game, T0 + 9000).clocks, { white: 60000, black: 60000, running: "white", since: T0 + 9000 });
  assert.equal(game.timedFrom, T0 + 9000);
  assert.equal(moveAs(game, "white", "g1f3", T0 + 12000).ok, true);
  assert.deepEqual(rules.view(game, T0 + 12000).clocks, { white: 59000, black: 60000, running: "black", since: T0 + 12000 });
  assert.equal(moveAs(game, "black", "b8c6", T0 + 20000).ok, true);
  assert.deepEqual(rules.view(game, T0 + 20000).clocks, { white: 59000, black: 54000, running: "white", since: T0 + 20000 });
  assert.equal(rules.nextDeadline(game), T0 + 20000 + 59000);
});

test("a game without a clock has no clocks", () => {
  const game = newGame();
  play(game, "e2e4 e7e5 g1f3");
  const state = rules.view(game, T0 + 10 * SECOND);
  assert.equal(state.clock, null);
  assert.equal(state.clocks, null);
  assert.equal(game.running, null);
});

test("a fallen flag loses, and a late move is refused", () => {
  const game = newGame({ clock: { initial: 60, increment: 0 } });
  play(game, "e2e4 e7e5");
  const since = T0 + 2 * SECOND;
  assert.equal(rules.nextDeadline(game), since + 60000);
  assert.equal(rules.tick(game, since + 59999).changed, false);
  assert.equal(game.result, null);
  // The move arrives a moment too late: it is refused and the game ends on time.
  const late = moveAs(game, "white", "g1f3", since + 60000);
  assert.equal(late.ok, false);
  assert.equal(late.error, "game_over");
  assert.equal(late.changed, true);
  assert.deepEqual(game.result, { winner: "black", reason: "timeout" });
  assert.deepEqual(rules.view(game, since + 61000).clocks, { white: 0, black: 60000, running: null, since: null });
  assert.equal(game.endedAt, since + 60000);
  assert.deepEqual(game.moves, ["e2e4", "e7e5"]);
});

test("the alarm finds the flag fall", () => {
  const game = newGame({ clock: { initial: 60, increment: 0 } });
  play(game, "e2e4 e7e5 g1f3");
  // Black's clock has run since the third move.
  const out = rules.tick(game, T0 + 3 * SECOND + 60000);
  assert.equal(out.changed, true);
  assert.deepEqual(game.result, { winner: "white", reason: "timeout" });
  assert.equal(rules.view(game, T0).clocks.black, 0);
  assert.equal(rules.view(game, T0).clocks.white, 59000);
});

test("a fallen flag is a draw when the other side can't mate", () => {
  const game = newGame({ clock: { initial: 3600, increment: 0 } });
  const { now } = play(game, LONE_BLACK_KING);
  assert.equal(game.result, null);
  assert.equal(rules.turnOf(game), "white");
  assert.equal(game.running, "white");
  const flag = game.since + game.remaining.white;
  rules.tick(game, Math.max(now, flag));
  assert.deepEqual(game.result, { winner: null, reason: "timeout_insufficient" });
});

test("mating material follows the Lichess rule", () => {
  const cases = [
    ["4k3/8/8/8/8/8/8/4K3 w - - 0 1", "white", false], // lone king
    ["4k3/8/8/8/8/8/8/3QK3 w - - 0 1", "white", true],
    ["4k3/8/8/8/8/8/8/3RK3 w - - 0 1", "white", true],
    ["4k3/8/8/8/8/8/4P3/4K3 w - - 0 1", "white", true],
    ["4k3/8/8/8/8/8/8/3NK3 w - - 0 1", "white", false], // a knight alone
    ["3qk3/8/8/8/8/8/8/3NK3 w - - 0 1", "white", false], // a knight against queens only
    ["3rk3/8/8/8/8/8/8/3NK3 w - - 0 1", "white", true], // the rook can block its own king
    ["4k3/4p3/8/8/8/8/8/3NK3 w - - 0 1", "white", true],
    ["4k3/8/8/8/8/8/8/2NNK3 w - - 0 1", "white", true], // two knights
    ["4k3/8/8/8/8/8/8/2B1K3 w - - 0 1", "white", false], // a bishop alone
    ["3rk3/8/8/8/8/8/8/2B1K3 w - - 0 1", "white", false], // a bishop against a rook
    ["3nk3/8/8/8/8/8/8/2B1K3 w - - 0 1", "white", true], // against a knight
    ["4k3/4p3/8/8/8/8/8/2B1K3 w - - 0 1", "white", true], // against a pawn
    ["2b1k3/8/8/8/8/8/8/2B1K3 w - - 0 1", "white", true], // bishops on both colors
    ["3bk3/8/8/8/8/8/8/2B1K3 w - - 0 1", "white", false], // all bishops on one color
    ["4k3/8/8/8/8/8/8/2BBK3 w - - 0 1", "white", true], // a bishop pair
    ["4k3/8/8/8/8/8/8/B1B1K3 w - - 0 1", "white", false], // two bishops, one color
    ["4k3/8/8/8/8/8/8/2BNK3 w - - 0 1", "white", true], // bishop and knight
    ["4k3/8/8/8/8/8/8/3QK3 w - - 0 1", "black", false], // Black has only the king
    ["3nk3/8/8/8/8/8/8/3QK3 w - - 0 1", "black", false], // Black's knight faces only a queen
    ["3nk3/8/8/8/8/8/4P3/3QK3 w - - 0 1", "black", true], // the pawn could block
  ];
  for (const [fen, seat, expected] of cases) {
    assert.equal(rules.hasMatingMaterial(fen, seat), expected, `${seat} in ${fen}`);
  }
});

// ---------------------------------------------------------------------------
// Presence and the leave rule

/** A 10-minute game that reached ply 2 at T0 + 2 s, when the clocks started. */
function timedGame() {
  const game = newGame({ clock: { initial: 600, increment: 0 } });
  play(game, "e2e4 e7e5");
  return game;
}

test("leaving a timed game lets the other side claim the win after the grace period", () => {
  const game = timedGame();
  const away = rules.setAway(game, "white", true, T0 + 5000);
  assert.deepEqual(away.notices, [{ kind: "away", seat: "white", at: T0 + 5000 }]);
  assert.equal(game.white.away, T0 + 5000);
  const seen = rules.view(game, T0 + 5000, { white: true, black: true });
  assert.equal(seen.white.online, false);
  assert.equal(seen.white.claimableAt, T0 + 5000 + GRACE);
  assert.equal(seen.black.claimableAt, null);
  // Leaving never ends the game on its own: the alarm only waits for White's flag.
  assert.equal(rules.nextDeadline(game), T0 + 2000 + 600000);
  rules.tick(game, T0 + 5000 + GRACE + 30000);
  assert.equal(game.result, null);

  const early = rules.act(game, "black", "claim_win", T0 + 5000 + GRACE - 1);
  assert.equal(early.ok, false);
  assert.equal(early.error, "cannot_claim");
  assert.match(early.message, /1 seconds left/);
  assert.equal(game.result, null);
  assert.equal(rules.act(game, "white", "claim_win", T0 + 5000 + GRACE).error, "cannot_claim", "Black is here");

  const claim = rules.act(game, "black", "claim_win", T0 + 5000 + GRACE + 30000);
  assert.equal(claim.ok, true);
  assert.equal(claim.changed, true);
  assert.deepEqual(game.result, { winner: "black", reason: "left" });
  // White's clock was charged up to the moment of the claim.
  assert.equal(game.remaining.white, 600000 - (5000 + GRACE + 30000 - 2000));
  assert.equal(rules.act(game, "black", "claim_win", T0 + 5000 + GRACE + 31000).error, "game_over");
});

test("a claim fails once the player is back, and in games the rule doesn't cover", () => {
  const game = timedGame();
  rules.setAway(game, "white", true, T0 + 5000);
  rules.setAway(game, "white", false, T0 + 5000 + GRACE + 1000);
  const late = rules.act(game, "black", "claim_win", T0 + 5000 + GRACE + 2000);
  assert.equal(late.error, "cannot_claim");
  assert.equal(late.message, "Your friend is back.");

  const untimed = newGame();
  play(untimed, "e2e4 e7e5");
  rules.setAway(untimed, "white", true, T0 + 3000);
  assert.equal(rules.act(untimed, "black", "claim_win", T0 + DAY).error, "cannot_claim");
  assert.equal(rules.view(untimed, T0 + DAY).white.claimableAt, null);

  const waiting = newGame({ joined: false, clock: { initial: 600, increment: 0 } });
  assert.equal(rules.act(waiting, "white", "claim_win", T0 + DAY).error, "bad_request");
});

test("coming back in time keeps the game going", () => {
  const game = timedGame();
  rules.setAway(game, "black", true, T0 + 5000);
  const back = rules.setAway(game, "black", false, T0 + 15000);
  assert.deepEqual(back.notices, [{ kind: "back", seat: "black", at: T0 + 15000 }]);
  rules.tick(game, T0 + 60000);
  assert.equal(game.result, null);
  // Saying "away" twice doesn't restart the absence.
  rules.setAway(game, "black", true, T0 + 70000);
  assert.equal(rules.setAway(game, "black", true, T0 + 80000).changed, false);
  assert.equal(game.black.away, T0 + 70000);
});

test("a move ends the mover's absence", () => {
  const game = timedGame();
  rules.setAway(game, "white", true, T0 + 3000);
  const out = moveAs(game, "white", "g1f3", T0 + 4000);
  assert.equal(out.ok, true);
  assert.deepEqual(out.notices, [{ kind: "back", seat: "white", at: T0 + 4000 }]);
  assert.equal(game.white.away, null);
});

test("an absence from before the clocks started counts from when they started", () => {
  const game = newGame({ clock: { initial: 600, increment: 0 } });
  play(game, "e2e4"); // ply 1 at T0 + 1 s
  rules.setAway(game, "white", true, T0 + 1500);
  assert.equal(rules.view(game, T0 + 1600).white.claimableAt, null, "no leave rule before both sides have moved");
  const started = T0 + 1500 + GRACE + 6000;
  assert.equal(moveAs(game, "black", "e7e5", started).ok, true);
  assert.equal(rules.view(game, started).white.claimableAt, started + GRACE);
  assert.equal(rules.act(game, "black", "claim_win", started + GRACE - 1).error, "cannot_claim");
  assert.equal(rules.act(game, "black", "claim_win", started + GRACE).ok, true);
  assert.deepEqual(game.result, { winner: "black", reason: "left" });
});

test("when both leave, nobody can claim, and the running flag decides", () => {
  const game = timedGame();
  rules.setAway(game, "black", true, T0 + 3000);
  rules.setAway(game, "white", true, T0 + 4000);
  rules.tick(game, T0 + 4000 + GRACE + 10000);
  assert.equal(game.result, null);
  // White is to move, so White's clock runs out first.
  rules.tick(game, T0 + 2000 + 600000);
  assert.deepEqual(game.result, { winner: "black", reason: "timeout" });
});

test("a flag that falls before the grace runs out is a loss on time", () => {
  const game = newGame({ clock: { initial: 60, increment: 0 } });
  play(game, "e2e4 e7e5"); // White's clock runs from T0 + 2 s with 60 s
  rules.setAway(game, "black", true, T0 + 50000); // Black's grace would end at T0 + 110 s
  rules.tick(game, T0 + 90000);
  assert.deepEqual(game.result, { winner: "black", reason: "timeout" });
});

test("games with no clock ignore absence", () => {
  const game = newGame();
  play(game, "e2e4 e7e5");
  rules.setAway(game, "white", true, T0 + 3000);
  rules.setAway(game, "black", true, T0 + 4000);
  rules.tick(game, T0 + 2 * DAY);
  assert.equal(game.result, null);
  assert.equal(rules.statusOf(game), "active");
  assert.equal(rules.nextDeadline(game), T0 + 2 * SECOND + 30 * DAY);
});

test("online needs an open socket and no absence", () => {
  const game = newGame();
  assert.equal(rules.view(game, T0, { white: true }).white.online, true);
  assert.equal(rules.view(game, T0, { white: false }).white.online, false);
  assert.equal(rules.view(game, T0, {}).black.online, false);
  rules.setAway(game, "white", true, T0 + 1);
  const state = rules.view(game, T0 + 2, { white: true });
  assert.equal(state.white.online, false);
  assert.equal(state.white.away, T0 + 1);
});

// ---------------------------------------------------------------------------
// Draws, aborting, resigning, cancelling

test("a draw offer can be accepted", () => {
  const game = newGame();
  play(game, "e2e4 e7e5");
  const offer = rules.act(game, "white", "offer_draw", T0 + 5000);
  assert.deepEqual(offer.notices, [{ kind: "draw_offer", seat: "white", at: T0 + 5000 }]);
  assert.equal(rules.view(game, T0).drawOffer, "white");
  assert.equal(rules.act(game, "white", "offer_draw", T0 + 6000).changed, false);
  assert.equal(rules.act(game, "white", "accept_draw", T0 + 6000).error, "bad_request", "can't accept your own offer");
  assert.equal(rules.act(game, "black", "accept_draw", T0 + 7000).ok, true);
  assert.deepEqual(game.result, { winner: null, reason: "agreement" });
  assert.equal(game.drawOffer, null);
});

test("a draw offer can be declined", () => {
  const game = newGame();
  play(game, "e2e4 e7e5");
  rules.act(game, "black", "offer_draw", T0 + 5000);
  const declined = rules.act(game, "white", "decline_draw", T0 + 6000);
  assert.deepEqual(declined.notices, [{ kind: "draw_declined", seat: "white", at: T0 + 6000 }]);
  assert.equal(game.drawOffer, null);
  assert.equal(game.result, null);
  // Declining when there's nothing to decline is harmless; accepting isn't possible.
  assert.equal(rules.act(game, "white", "decline_draw", T0 + 7000).ok, true);
  assert.equal(rules.act(game, "white", "accept_draw", T0 + 7000).error, "bad_request");
});

test("a draw offer lapses when the other side moves instead", () => {
  const game = newGame();
  play(game, "e2e4 e7e5");
  rules.act(game, "white", "offer_draw", T0 + 5000);
  // The one who offered may still move: the offer stands.
  assert.equal(moveAs(game, "white", "g1f3", T0 + 6000).ok, true);
  assert.equal(game.drawOffer, "white");
  assert.equal(moveAs(game, "black", "b8c6", T0 + 7000).ok, true);
  assert.equal(game.drawOffer, null);
  assert.equal(rules.act(game, "black", "accept_draw", T0 + 8000).error, "bad_request");
});

test("offering when the other side already offered is a draw", () => {
  const game = newGame();
  rules.act(game, "black", "offer_draw", T0 + 5000);
  rules.act(game, "white", "offer_draw", T0 + 6000);
  assert.deepEqual(game.result, { winner: null, reason: "agreement" });
});

test("no draw offers before the friend joins or after the end", () => {
  const waiting = newGame({ joined: false });
  assert.equal(rules.act(waiting, "white", "offer_draw", T0 + 1).error, "bad_request");
  const over = newGame();
  play(over, FOOLS_MATE);
  for (const type of ["offer_draw", "accept_draw", "decline_draw", "resign", "abort", "cancel"]) {
    assert.equal(rules.act(over, "white", type, T0 + 10 * SECOND).error, "game_over", type);
  }
});

test("aborting or resigning before both sides moved aborts", () => {
  for (const [type, moves] of [
    ["abort", ""],
    ["abort", "e2e4"],
    ["resign", ""],
    ["resign", "e2e4"],
  ]) {
    const game = newGame({ clock: { initial: 300, increment: 0 } });
    if (moves) play(game, moves);
    const out = rules.act(game, "black", type, T0 + 5000);
    assert.equal(out.ok, true);
    assert.deepEqual(game.result, { winner: null, reason: "aborted" }, `${type} after "${moves}"`);
  }
});

test("after both sides moved, abort is refused and resigning loses", () => {
  const game = newGame();
  play(game, "e2e4 e7e5");
  assert.equal(rules.act(game, "white", "abort", T0 + 5000).error, "bad_request");
  assert.equal(game.result, null);
  assert.equal(rules.act(game, "white", "resign", T0 + 6000).ok, true);
  assert.deepEqual(game.result, { winner: "black", reason: "resign" });
});

test("the creator can cancel while nobody has joined", () => {
  for (const type of ["cancel", "abort", "resign"]) {
    const game = newGame({ joined: false });
    assert.equal(rules.act(game, "white", type, T0 + 1000).ok, true);
    assert.deepEqual(game.result, { winner: null, reason: "cancelled" }, type);
  }
  const joined = newGame();
  assert.equal(rules.act(joined, "white", "cancel", T0 + 1000).error, "bad_request");
});

test("unknown actions are refused", () => {
  const game = newGame();
  assert.equal(rules.act(game, "white", "explode", T0).error, "bad_request");
  assert.equal(rules.act(game, "white", undefined, T0).error, "bad_request");
});

// ---------------------------------------------------------------------------
// Screenshots

test("screenshots and recordings during a game are reported", () => {
  const game = newGame();
  const shot = rules.act(game, "white", "screenshot", T0 + 1000);
  assert.deepEqual(shot.notices, [{ kind: "screenshot", seat: "white", at: T0 + 1000 }]);
  rules.act(game, "white", "screenshot", T0 + 2000);
  rules.act(game, "black", "recording", T0 + 3000);
  const state = rules.view(game, T0 + 4000);
  assert.equal(state.white.screenshots, 2);
  assert.equal(state.black.recordings, 1);
  assert.equal(state.black.screenshots, 0);
});

test("screenshots while waiting or after the end don't count", () => {
  const waiting = newGame({ joined: false });
  const out = rules.act(waiting, "white", "screenshot", T0 + 1000);
  assert.equal(out.ok, true);
  assert.equal(out.changed, false);
  assert.equal(waiting.white.screenshots, 0);
  const over = newGame();
  play(over, FOOLS_MATE);
  assert.equal(rules.act(over, "black", "recording", T0 + 10 * SECOND).changed, false);
  assert.equal(over.black.recordings, 0);
});

// ---------------------------------------------------------------------------
// Rematch

test("a rematch needs both players, then swaps colors and keeps each token", () => {
  const game = newGame({ clock: { initial: 180, increment: 2 } });
  assert.equal(rules.act(game, "white", "rematch", T0 + 1000).error, "bad_request", "not before the end");
  play(game, FOOLS_MATE);

  const first = rules.act(game, "black", "rematch", T0 + 10 * SECOND);
  assert.deepEqual(first.notices, [{ kind: "rematch_offer", seat: "black", at: T0 + 10 * SECOND }]);
  assert.deepEqual(rules.view(game, T0).rematch, { by: "black", code: null });
  assert.equal(rules.act(game, "black", "rematch", T0 + 11 * SECOND).changed, false);
  assert.equal(rules.act(game, "black", "rematch", T0 + 11 * SECOND).rematchReady, undefined);

  const second = rules.act(game, "white", "rematch", T0 + 12 * SECOND);
  assert.equal(second.ok, true);
  assert.equal(second.rematchReady, true);

  const next = rules.rematchRecord(game, "NEWC0D".replace("0", "9"), T0 + 13 * SECOND);
  assert.equal(next.code, "NEWC9D");
  assert.equal(rules.statusOf(next), "active");
  assert.equal(next.white.name, "Sam");
  assert.equal(next.black.name, "Alex");
  assert.equal(rules.seatForToken(next, BLACK), "white");
  assert.equal(rules.seatForToken(next, WHITE), "black");
  assert.deepEqual(next.clock, { initial: 180, increment: 2 });
  assert.deepEqual(next.remaining, { white: 180000, black: 180000 });
  assert.equal(next.creator, "black", "Alex made the first game and is Black now");
  assert.deepEqual(next.moves, []);
  assert.equal(next.result, null);
  assert.equal(next.rematch, null);
  assert.equal(next.white.screenshots, 0);
  assert.notEqual(next.white, game.black, "the new game has its own seat objects");
  // The new game plays normally, with the new White moving first.
  assert.equal(moveAs(next, "white", "e2e4", T0 + 14 * SECOND).ok, true);

  rules.setRematchCode(game, "NEWC9D", T0 + 13 * SECOND);
  assert.deepEqual(rules.view(game, T0).rematch, { by: "black", code: "NEWC9D" });
  const late = rules.act(game, "white", "rematch", T0 + 14 * SECOND);
  assert.equal(late.ok, true);
  assert.equal(late.rematchReady, undefined);
});

test("no rematch of a game nobody joined", () => {
  const game = newGame({ joined: false });
  rules.act(game, "white", "cancel", T0 + 1000);
  assert.equal(rules.act(game, "white", "rematch", T0 + 2000).error, "bad_request");
});

// ---------------------------------------------------------------------------
// Expiry and deletion

test("a game nobody joins expires after 7 days", () => {
  const game = newGame({ joined: false });
  assert.equal(rules.nextDeadline(game), T0 + 7 * DAY);
  rules.tick(game, T0 + 7 * DAY - 1);
  assert.equal(game.result, null);
  rules.tick(game, T0 + 7 * DAY);
  assert.deepEqual(game.result, { winner: null, reason: "expired" });
  assert.equal(rules.join(game, { name: "Late", tokenHash: BLACK }, T0 + 7 * DAY + 1).error, "game_over");
});

test("a game with no move for 30 days expires", () => {
  const game = newGame();
  play(game, "e2e4 e7e5"); // last move at T0 + 2 s
  rules.tick(game, T0 + 2000 + 30 * DAY - 1);
  assert.equal(game.result, null);
  rules.tick(game, T0 + 2000 + 30 * DAY);
  assert.deepEqual(game.result, { winner: null, reason: "expired" });
  // A joined game with no moves counts from the join.
  const idle = newGame();
  assert.equal(rules.nextDeadline(idle), T0 + 30 * DAY);
});

test("a finished game is deleted 30 days after it ended", () => {
  const game = newGame();
  play(game, FOOLS_MATE); // over at T0 + 4 s
  const end = T0 + 4000;
  assert.equal(rules.nextDeadline(game), end + 30 * DAY);
  assert.equal(rules.shouldDelete(game, end + 30 * DAY - 1), false);
  assert.equal(rules.shouldDelete(game, end + 30 * DAY), true);
  assert.equal(rules.shouldDelete(newGame(), T0 + 365 * DAY), false, "only finished games are deleted");
  // Tests may keep finished games for less time.
  assert.equal(rules.nextDeadline(game, 5000), end + 5000);
  assert.equal(rules.shouldDelete(game, end + 5000, 5000), true);
  // Time passing doesn't change a finished game.
  assert.equal(rules.tick(game, end + 10 * DAY).changed, false);
});

// ---------------------------------------------------------------------------
// Reports

test("reporting a name hides it at once, in the rematch too", () => {
  const game = newGame();
  play(game, "e2e4 e7e5");
  const out = rules.act(game, "white", "report_name", T0 + 5000);
  assert.equal(out.ok, true);
  assert.equal(out.changed, true);
  assert.deepEqual(out.notices, [], "the reported player isn't told");
  assert.deepEqual(out.report, { code: "7KQ2XM", by: "white", reason: "name", at: T0 + 5000, name: "Sam", moves: 2, status: "active" });
  assert.equal(game.black.name, "Player");
  assert.equal(rules.view(game, T0 + 5000).black.name, "Player");
  // Once per kind of report.
  const again = rules.act(game, "white", "report_name", T0 + 6000);
  assert.equal(again.changed, false);
  assert.equal(again.report, undefined);
  // Reporting works after the game too, and cheating is its own report.
  rules.act(game, "black", "resign", T0 + 7000);
  const cheat = rules.act(game, "white", "report_cheating", T0 + 8000);
  assert.equal(cheat.report.reason, "cheating");
  assert.equal(cheat.report.status, "over");
  assert.equal(game.reports.length, 2);
  const next = rules.rematchRecord(game, "NEXT22", T0 + 9000);
  assert.equal(next.white.name, "Player");
});

test("there is no one to report before a friend joins", () => {
  const game = newGame({ joined: false });
  assert.equal(rules.act(game, "white", "report_name", T0 + 1000).error, "bad_request");
});

test("offensive names become Player when a game is made or joined", () => {
  const game = rules.createGame({ code: "7KQ2XM", name: "sh1thead", tokenHash: WHITE, now: T0, pickSide: () => "white" });
  assert.equal(game.white.name, "Player");
  rules.join(game, { name: "F u c k", tokenHash: BLACK }, T0);
  assert.equal(game.black.name, "Player");
});
