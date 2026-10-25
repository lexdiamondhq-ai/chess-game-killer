// The rules of a friend game, with nothing Cloudflare-specific in them:
// creating and joining a game, moves, clocks, draw offers, presence and the
// leave rule, results, expiry and rematches.
//
// A game is a plain object, the "record", which the game room (room.js)
// saves as it is. The functions here change the record in place and report
// what happened in an "outcome":
//   { ok, changed, notices, error?, message?, seat?, rematchReady? }
// - changed: the record changed and must be saved (true even for some
//   refusals: a move that arrives after the flag fell ends the game on time).
// - notices: moments to tell the other side about ({ kind, seat, at }).
// Every function takes the time as an argument (`now`, ms since the epoch),
// so tests can play through days of a game in milliseconds.
//
// view() turns a record into the GameState that players see (PROTOCOL.md).
// The record also holds the hashes of the seat tokens; view() leaves them out.

import { Chess, DEFAULT_POSITION } from "../public/vendor/chess.js";
import { cleanName } from "./util.js";

export const SEATS = ["white", "black"];
export const SIDES = ["white", "black", "random"];
export const ACTIONS = [
  "resign",
  "abort",
  "cancel",
  "offer_draw",
  "accept_draw",
  "decline_draw",
  "rematch",
  "away",
  "back",
  "screenshot",
  "recording",
];

const DAY = 24 * 60 * 60 * 1000;
/** A game nobody joins expires after 7 days. */
export const WAITING_EXPIRY_MS = 7 * DAY;
/** A game with no move for 30 days expires. */
export const IDLE_EXPIRY_MS = 30 * DAY;
/** A finished game is deleted 30 days after it ended. */
export const KEEP_FINISHED_MS = 30 * DAY;

export const MAX_CLOCK_SECONDS = 3600;
export const MAX_INCREMENT_SECONDS = 60;

const UCI_PATTERN = /^[a-h][1-8][a-h][1-8][qrbn]?$/;

export function other(seat) {
  return seat === "white" ? "black" : "white";
}

/** "waiting" (only the creator is seated), "active" (both seated, not over) or "over". */
export function statusOf(game) {
  if (game.result) return "over";
  return game.white && game.black ? "active" : "waiting";
}

/** The side to move in the current position. */
export function turnOf(game) {
  return game.fen.split(" ")[1] === "b" ? "black" : "white";
}

/** Which seat a token (by its hash) holds, or null. */
export function seatForToken(game, tokenHash) {
  if (!tokenHash) return null;
  for (const seat of SEATS) {
    if (game[seat] && game[seat].tokenHash === tokenHash) return seat;
  }
  return null;
}

// ---------------------------------------------------------------------------
// Creating a game

function invalid(message) {
  return { ok: false, error: "bad_request", message };
}

/**
 * Checks a clock from a request: null (or left out) for no clock, otherwise
 * whole seconds { initial, increment } with initial from minClockSeconds to
 * 3600 and increment from 0 to 60 (0 when left out).
 */
export function parseClock(clock, minClockSeconds = 60) {
  if (clock === null || clock === undefined) return { ok: true, clock: null };
  if (typeof clock !== "object" || Array.isArray(clock)) {
    return invalid('"clock" must be null or { "initial": seconds, "increment": seconds }.');
  }
  const { initial } = clock;
  const increment = clock.increment ?? 0;
  if (!Number.isInteger(initial) || initial < minClockSeconds || initial > MAX_CLOCK_SECONDS) {
    return invalid(`The clock must start with a whole number of seconds from ${minClockSeconds} to ${MAX_CLOCK_SECONDS}.`);
  }
  if (!Number.isInteger(increment) || increment < 0 || increment > MAX_INCREMENT_SECONDS) {
    return invalid(`The increment must be a whole number of seconds from 0 to ${MAX_INCREMENT_SECONDS}.`);
  }
  return { ok: true, clock: { initial, increment } };
}

/** Checks the body of POST /api/games. Returns { ok: true, value: { name, side, clock } } or an error. */
export function parseCreateInput(body, { minClockSeconds = 60 } = {}) {
  const input = body ?? {};
  const name = input.name ?? null;
  if (name !== null && typeof name !== "string") return invalid('"name" must be text.');
  const side = input.side ?? "random";
  if (!SIDES.includes(side)) return invalid('"side" must be "white", "black" or "random".');
  const clock = parseClock(input.clock, minClockSeconds);
  if (!clock.ok) return clock;
  return { ok: true, value: { name: cleanName(name), side, clock: clock.clock, look: cleanLook(input.look) } };
}

/**
 * The creator's board look in the app ("gilded", "classic", ...), shown to the friend in the
 * browser. Only a short lowercase word is kept; anything else (or an older app sending none)
 * is null, and the browser shows the app's default look.
 */
export function cleanLook(value) {
  return typeof value === "string" && /^[a-z]{2,20}$/.test(value) ? value : null;
}

function randomSide() {
  return crypto.getRandomValues(new Uint8Array(1))[0] & 1 ? "black" : "white";
}

function newSeat(name, tokenHash) {
  return { name: cleanName(name), tokenHash, away: null, screenshots: 0, recordings: 0 };
}

/**
 * A new game with its creator seated. A "random" side is settled here, once,
 * so the creator knows their color from the start. pickSide is for tests.
 */
export function createGame({ code, name, side = "random", clock = null, look = null, tokenHash, now, leaveGraceMs = 20000, pickSide = randomSide }) {
  const seat = side === "white" || side === "black" ? side : pickSide();
  const game = {
    v: 1,
    code,
    createdAt: now,
    updatedAt: now,
    clock: clock ? { initial: clock.initial, increment: clock.increment } : null,
    creator: seat,
    look: cleanLook(look),
    leaveGraceMs,
    white: null,
    black: null,
    moves: [],
    san: [],
    fen: DEFAULT_POSITION,
    positions: [positionKey(DEFAULT_POSITION)], // for the repetition rule; see move()
    // Each side's time left in ms. For the side whose clock runs (`running`),
    // it is the time left as of `since`, the moment that clock started.
    remaining: clock ? { white: clock.initial * 1000, black: clock.initial * 1000 } : null,
    running: null,
    since: null,
    drawOffer: null,
    rematch: null,
    result: null,
    joinedAt: null, // when the second player sat down
    lastMoveAt: null, // the last move, or the join; a game idle for 30 days expires
    timedFrom: null, // when the clocks started (both sides had moved)
    endedAt: null,
  };
  game[seat] = newSeat(name, tokenHash);
  return game;
}

/**
 * The record for a rematch: the same players and clock with the colors
 * swapped, both already seated, and each player's token (by its hash) now
 * holding their new seat. The original creator stays the creator.
 */
export function rematchRecord(game, code, now, leaveGraceMs = game.leaveGraceMs) {
  const next = createGame({
    code,
    name: game.black.name,
    side: "white",
    clock: game.clock,
    look: game.look,
    tokenHash: game.black.tokenHash,
    now,
    leaveGraceMs,
  });
  next.black = newSeat(game.white.name, game.white.tokenHash);
  next.creator = other(game.creator);
  next.joinedAt = now;
  next.lastMoveAt = now;
  return next;
}

/** Records the code of the rematch once it has been made, so both players can switch to it. */
export function setRematchCode(game, code, now) {
  const out = blank();
  game.rematch = { by: game.rematch ? game.rematch.by : null, code };
  touch(game, out, now);
  return out;
}

// ---------------------------------------------------------------------------
// Outcomes

function blank() {
  return { ok: true, changed: false, notices: [] };
}

/** Starts an outcome, first applying anything that has happened by `now` (a flag fall, a forfeit, expiry). */
function begin(game, now) {
  const out = blank();
  catchUp(game, now, out);
  return out;
}

function fail(out, error, message) {
  out.ok = false;
  out.error = error;
  out.message = message;
  return out;
}

function touch(game, out, now) {
  out.changed = true;
  game.updatedAt = now;
}

function notify(out, kind, seat, at) {
  out.notices.push({ kind, seat, at });
}

const GAME_OVER = "This game is over.";
const NOT_JOINED = "Your friend hasn't joined yet.";

// ---------------------------------------------------------------------------
// Time: flags, the leave rule and expiry

/** Applies whatever has happened by `now`. Used by every request and by the room's alarm. */
export function tick(game, now) {
  return begin(game, now);
}

function catchUp(game, now, out) {
  const event = nextEvent(game);
  if (event && event.at <= now) {
    finish(game, event.winner, event.reason, event.at);
    touch(game, out, now);
  }
}

/** True once the leave rule is in force: a timed game in progress where both sides have moved. */
export function leaveRuleApplies(game) {
  return game.clock !== null && statusOf(game) === "active" && game.moves.length >= 2;
}

/**
 * The next thing that will end this game on its own, if nothing else happens
 * first: { at, winner, reason }, or null once the game is over.
 */
function nextEvent(game) {
  if (game.result) return null;
  if (statusOf(game) === "waiting") {
    return { at: game.createdAt + WAITING_EXPIRY_MS, winner: null, reason: "expired" };
  }
  const events = [];
  if (game.running) {
    // The running side's flag falls when its time is used up.
    const loser = game.running;
    const winner = other(loser);
    const at = game.since + game.remaining[loser];
    events.push(
      hasMatingMaterial(game.fen, winner)
        ? { at, winner, reason: "timeout" }
        : { at, winner: null, reason: "timeout_insufficient" },
    );
  }
  if (leaveRuleApplies(game)) {
    // An absence counts from when it began, but never from before the
    // clocks started. The side to move is listed first, so it loses a tie.
    const toMove = turnOf(game);
    for (const seat of [toMove, other(toMove)]) {
      const away = game[seat].away;
      if (away !== null) {
        events.push({ at: Math.max(away, game.timedFrom ?? 0) + game.leaveGraceMs, winner: other(seat), reason: "left" });
      }
    }
  }
  events.push({ at: (game.lastMoveAt ?? game.createdAt) + IDLE_EXPIRY_MS, winner: null, reason: "expired" });
  // The earliest wins; on a tie the first listed (a flag beats a forfeit).
  return events.reduce((first, event) => (event.at < first.at ? event : first));
}

/**
 * When the room's alarm should next go off: the next flag fall, forfeit or
 * expiry, or for a finished game the moment it is deleted (keepMs after it
 * ended; tests shorten that).
 */
export function nextDeadline(game, keepMs = KEEP_FINISHED_MS) {
  if (game.result) return game.endedAt + keepMs;
  return nextEvent(game).at;
}

/** True once a finished game has been kept long enough (30 days) and should be deleted. */
export function shouldDelete(game, now, keepMs = KEEP_FINISHED_MS) {
  return game.result !== null && now >= game.endedAt + keepMs;
}

/** Ends the game at time `at`: stops the clock (charging the running side up to `at`) and sets the result. */
function finish(game, winner, reason, at) {
  if (game.running) {
    const used = Math.max(0, at - game.since);
    game.remaining[game.running] = Math.max(0, game.remaining[game.running] - used);
  }
  game.running = null;
  game.since = null;
  game.drawOffer = null;
  game.result = { winner, reason };
  game.endedAt = at;
}

/**
 * Whether `seat` still has pieces that could ever give mate (with the other
 * side's help), the test for a draw when the other side's flag falls. The
 * same rule as Lichess:
 * - a lone king can't mate;
 * - one knight can't mate a side that has only queens left (no piece of
 *   theirs could block their own king in), but can mate anything else;
 * - bishops all on one color can't mate unless the other side has a knight
 *   or a pawn, or a bishop on the other color, that could block.
 */
export function hasMatingMaterial(fen, seat) {
  const mine = { p: 0, n: 0, b: 0, r: 0, q: 0 };
  const theirs = { p: 0, n: 0, b: 0, r: 0, q: 0 };
  const bishopSquareColors = new Set();
  const rows = fen.split(" ")[0].split("/");
  rows.forEach((row, index) => {
    const rank = 7 - index;
    let file = 0;
    for (const symbol of row) {
      if (symbol >= "1" && symbol <= "8") {
        file += Number(symbol);
        continue;
      }
      const type = symbol.toLowerCase();
      if (type !== "k") {
        const isWhite = symbol !== type;
        (isWhite === (seat === "white") ? mine : theirs)[type] += 1;
        if (type === "b") bishopSquareColors.add((file + rank) % 2);
      }
      file += 1;
    }
  });
  if (mine.p || mine.r || mine.q) return true;
  if (mine.n === 0 && mine.b === 0) return false;
  if (mine.b === 0) return mine.n >= 2 || theirs.p + theirs.n + theirs.b + theirs.r > 0;
  if (mine.n === 0) return bishopSquareColors.size === 2 || theirs.n + theirs.p > 0;
  return true;
}

// ---------------------------------------------------------------------------
// Joining

/** Seats a second player. The caller makes their token; only its hash is kept. */
export function join(game, { name, tokenHash }, now) {
  const out = begin(game, now);
  if (game.result) return fail(out, "game_over", GAME_OVER);
  const seat = !game.white ? "white" : !game.black ? "black" : null;
  if (!seat) return fail(out, "seat_taken", "Both seats are taken. You can still watch.");
  game[seat] = newSeat(name, tokenHash);
  game.joinedAt = now;
  game.lastMoveAt = now;
  touch(game, out, now);
  notify(out, "joined", seat, now);
  out.seat = seat;
  return out;
}

// ---------------------------------------------------------------------------
// Moves

// A move is checked on a board loaded from the position the record holds
// (game.fen), so it costs the same in move 5 as in move 150. Replaying the
// whole game instead would take tens of milliseconds of CPU in a long game.
//
// A board loaded that way doesn't know the positions that came before, so
// chess.js can't spot a threefold repetition by itself. The record keeps
// them instead, in `positions`: one key for each position since the last
// capture or pawn move, the current one included. No earlier position can
// come back after one of those, and the fifty-move rule ends the game after
// 100 half-moves without one, so the list never holds more than 101 keys.

/**
 * What makes two positions the same for the repetition rule: the pieces,
 * the side to move, the castling rights and the en passant square. These are
 * the first four fields of a FEN. chess.js writes the en passant square only
 * when an en passant capture is really possible, which is what the rules of
 * chess ask for. The move counters at the end of the FEN don't count.
 */
export function positionKey(fen) {
  return fen.split(" ", 4).join(" ");
}

/** The FEN's halfmove clock: half-moves since the last capture or pawn move. */
function halfmoveClock(fen) {
  return Number(fen.split(" ")[4]);
}

/**
 * The legal move a UCI string means in this position, as chess.js wants it,
 * or null. A promotion with no letter becomes a queen; a letter on a move
 * that isn't a promotion makes it illegal. Castling written as the king
 * taking its own rook (e1h1), as some programs do, means castling.
 */
function findMove(chess, uci) {
  const from = uci.slice(0, 2);
  const to = uci.slice(2, 4);
  const promotion = uci[4];
  const legal = chess.moves({ square: from, verbose: true });
  let matches = legal.filter((move) => move.to === to);
  if (matches.length === 0 && to[1] === from[1] && (to[0] === "h" || to[0] === "a")) {
    const flag = to[0] === "h" ? "k" : "q";
    matches = legal.filter((move) => move.piece === "k" && move.flags.includes(flag));
  }
  if (matches.length === 0) return null;
  if (matches[0].promotion) {
    const wanted = promotion ?? "q";
    const match = matches.find((move) => move.promotion === wanted);
    return match ? { from, to: match.to, promotion: wanted } : null;
  }
  return promotion ? null : { from, to: matches[0].to };
}

/** How the position ends the game, if it does, after `mover` moved. */
function positionResult(game, chess, mover) {
  if (chess.isCheckmate()) return { winner: mover, reason: "checkmate" };
  if (chess.isStalemate()) return { winner: null, reason: "stalemate" };
  if (chess.isInsufficientMaterial()) return { winner: null, reason: "insufficient" };
  const key = game.positions.at(-1);
  if (game.positions.filter((seen) => seen === key).length >= 3) return { winner: null, reason: "repetition" };
  if (chess.isDrawByFiftyMoves()) return { winner: null, reason: "fifty_moves" };
  return null;
}

/**
 * Plays a move for `seat`. `uci` is the move ("e2e4", "e7e8q") and `ply` the
 * number of half-moves the player believes were already played; if the game
 * has moved on, the move is refused as stale so the player can catch up.
 */
export function move(game, seat, { uci, ply } = {}, now) {
  const out = begin(game, now);
  const text = typeof uci === "string" ? uci.trim().toLowerCase() : "";
  if (!UCI_PATTERN.test(text)) return fail(out, "bad_request", 'Send the move as "uci", like "e2e4" or "e7e8q".');
  if (!Number.isInteger(ply) || ply < 0) return fail(out, "bad_request", 'Send "ply", the number of half-moves already played.');
  if (game.result) return fail(out, "game_over", GAME_OVER);
  if (statusOf(game) === "waiting") return fail(out, "not_your_turn", NOT_JOINED);
  if (ply !== game.moves.length) return fail(out, "stale", "The game has moved on. Here is where it stands.");
  if (turnOf(game) !== seat) return fail(out, "not_your_turn", "It's not your turn.");

  const chess = new Chess(game.fen);
  const choice = findMove(chess, text);
  if (!choice) return fail(out, "illegal_move", "That move isn't allowed in this position.");
  const played = chess.move(choice);
  game.moves.push(played.from + played.to + (played.promotion ?? ""));
  game.san.push(played.san);
  game.fen = chess.fen();
  const key = positionKey(game.fen);
  if (halfmoveClock(game.fen) === 0) {
    game.positions = [key]; // a capture or pawn move: nothing before can come back
  } else {
    // (`??=` only for a record saved before `positions` was kept: it counts from here.)
    (game.positions ??= []).push(key);
  }

  // Each side's first move is free. From then on the mover pays for the
  // time since their clock started and earns the increment.
  if (game.clock && ply >= 2) {
    game.remaining[seat] += game.clock.increment * 1000 - (now - game.since);
    game.since = now;
  }
  game.lastMoveAt = now;
  // A draw offer lapses when the side it was made to moves instead of answering.
  if (game.drawOffer === other(seat)) game.drawOffer = null;
  // Someone who moves is plainly here.
  if (game[seat].away !== null) {
    game[seat].away = null;
    notify(out, "back", seat, now);
  }
  touch(game, out, now);

  const ending = positionResult(game, chess, seat);
  if (ending) {
    finish(game, ending.winner, ending.reason, now);
  } else if (game.clock && game.moves.length >= 2) {
    if (game.moves.length === 2) game.timedFrom = now;
    game.running = other(seat);
    game.since = now;
  }
  return out;
}

// ---------------------------------------------------------------------------
// Actions

/** Marks a seat away (its app went to the background or its last socket closed) or back. */
export function setAway(game, seat, away, now) {
  const out = begin(game, now);
  const player = game[seat];
  if (!player) return out;
  if (away && player.away === null) {
    player.away = now;
    touch(game, out, now);
    notify(out, "away", seat, now);
  } else if (!away && player.away !== null) {
    player.away = null;
    touch(game, out, now);
    notify(out, "back", seat, now);
  }
  return out;
}

/** Applies one of the action types in PROTOCOL.md for `seat`. */
export function act(game, seat, type, now) {
  if (type === "away" || type === "back") return setAway(game, seat, type === "away", now);
  const out = begin(game, now);
  const status = statusOf(game);
  switch (type) {
    case "screenshot":
    case "recording": {
      // Only a game in progress is reported. A screenshot of the waiting
      // screen (to send the code) or of a finished game is nobody's business.
      if (status !== "active") return out;
      game[seat][type === "screenshot" ? "screenshots" : "recordings"] += 1;
      touch(game, out, now);
      notify(out, type, seat, now);
      return out;
    }
    case "rematch":
      return askForRematch(game, seat, now, out);
    case "cancel":
      if (status === "over") return fail(out, "game_over", GAME_OVER);
      if (status === "active") return fail(out, "bad_request", "Your friend has already joined. You can abort or resign instead.");
      finish(game, null, "cancelled", now);
      touch(game, out, now);
      return out;
    case "abort":
    case "resign":
      if (status === "over") return fail(out, "game_over", GAME_OVER);
      if (status === "waiting") {
        // Nobody else is here yet: stopping now withdraws the challenge.
        finish(game, null, "cancelled", now);
      } else if (game.moves.length < 2) {
        finish(game, null, "aborted", now);
      } else if (type === "abort") {
        return fail(out, "bad_request", "Both sides have moved, so the game can't be aborted. You can resign.");
      } else {
        finish(game, other(seat), "resign", now);
      }
      touch(game, out, now);
      return out;
    case "offer_draw":
      if (status === "over") return fail(out, "game_over", GAME_OVER);
      if (status === "waiting") return fail(out, "bad_request", NOT_JOINED);
      if (game.drawOffer === other(seat)) {
        // Both sides want a draw.
        finish(game, null, "agreement", now);
        touch(game, out, now);
        return out;
      }
      if (game.drawOffer === seat) return out;
      game.drawOffer = seat;
      touch(game, out, now);
      notify(out, "draw_offer", seat, now);
      return out;
    case "accept_draw":
      if (status === "over") return fail(out, "game_over", GAME_OVER);
      if (game.drawOffer !== other(seat)) return fail(out, "bad_request", "There's no draw offer to accept.");
      finish(game, null, "agreement", now);
      touch(game, out, now);
      return out;
    case "decline_draw":
      if (status === "over") return fail(out, "game_over", GAME_OVER);
      // Nothing to decline (the offer may have lapsed): that's fine.
      if (game.drawOffer !== other(seat)) return out;
      game.drawOffer = null;
      touch(game, out, now);
      notify(out, "draw_declined", seat, now);
      return out;
    default:
      return fail(out, "bad_request", "Unknown action.");
  }
}

function askForRematch(game, seat, now, out) {
  if (!game.result) return fail(out, "bad_request", "You can ask for a rematch once the game is over.");
  if (!game.white || !game.black) return fail(out, "bad_request", "Nobody joined this game, so there's no one to play a rematch with.");
  if (game.rematch && game.rematch.code) return out; // already made: switch to rematch.code
  if (!game.rematch) {
    game.rematch = { by: seat, code: null };
    touch(game, out, now);
    notify(out, "rematch_offer", seat, now);
    return out;
  }
  if (game.rematch.by === seat) return out; // still waiting for the other side
  // Both sides want a rematch: the room makes the new game.
  out.rematchReady = true;
  return out;
}

// ---------------------------------------------------------------------------
// What players see

function seatView(player, connected) {
  if (!player) return { name: null, seated: false, online: false, away: null, screenshots: 0, recordings: 0 };
  return {
    name: player.name,
    seated: true,
    online: Boolean(connected) && player.away === null,
    away: player.away,
    screenshots: player.screenshots,
    recordings: player.recordings,
  };
}

/**
 * The GameState in PROTOCOL.md. `connected` says which seats have an open
 * WebSocket right now ({ white, black }); `now` is the server's time.
 */
export function view(game, now, connected = {}) {
  return {
    code: game.code,
    status: statusOf(game),
    createdAt: game.createdAt,
    updatedAt: game.updatedAt,
    clock: game.clock ? { initial: game.clock.initial, increment: game.clock.increment } : null,
    creator: game.creator,
    look: game.look ?? null,
    white: seatView(game.white, connected.white),
    black: seatView(game.black, connected.black),
    moves: game.moves.slice(),
    san: game.san.slice(),
    fen: game.fen,
    turn: turnOf(game),
    clocks: game.clock
      ? { white: game.remaining.white, black: game.remaining.black, running: game.running, since: game.since }
      : null,
    drawOffer: game.drawOffer,
    rematch: game.rematch ? { by: game.rematch.by, code: game.rematch.code } : null,
    result: game.result ? { winner: game.result.winner, reason: game.result.reason } : null,
    leaveGraceMs: game.leaveGraceMs,
    now,
  };
}
