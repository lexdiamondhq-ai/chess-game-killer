// Play online: the rules of the lobby, with nothing Cloudflare-specific in
// them. The lobby is where app players who want a game right now wait, each
// with a clock. Another player can take one of them on by name ("challenge
// the online player"), or ask for a quick pairing: the waiting player at the
// same clock whose rating is closest.
//
// The lobby's record is a plain object the Lobby room (lobbyroom.js) keeps:
//   { seeks: { [id]: Seek } }
// A Seek is one player waiting:
//   { id, tokenHash, playerHash, name, rating, games, clock, look,
//     createdAt, seenAt, match: null | { code, seat, token, at } }
// - tokenHash: the hash of the seek's own token, which the waiting app sends
//   to check in (every 2 s) and to cancel.
// - playerHash: the hash of the player's key, the app's private id for its
//   player. Ratings are kept by it. It never leaves the server.
// - match: set once someone took the seek on. The waiting app picks up its
//   seat and token at the next check-in.
//
// A seek can instead be for a daily game (`days` per move, no clock): its player may close
// the app, so it stays up for a week with no check-ins and its game waits a week to be picked up.
//
// Ratings are Elo, kept per player key: 1200 to start, moving faster for a
// player's first games. Only games paired here are rated, and only those with a clock or days per move.
//
// Every function takes the time (`now`) as an argument, so tests can run the
// lobby through minutes in milliseconds.

import { cleanLook, parseClock, parseDays } from "./game.js";
import { cleanName } from "./util.js";

/** A waiting player who stops checking in for this long is gone. */
export const SEEK_STALE_MS = 20000;
/** A taken seek is kept this long for its player's app to pick up the game. */
export const MATCH_KEEP_MS = 120000;
/**
 * A daily seek (days per move) stays up without check-ins, since its player may close the app: it lasts this long,
 * and once taken its game waits this long for the player's app to pick it up.
 */
export const DAILY_SEEK_MS = 7 * 24 * 60 * 60 * 1000;
/** At most this many players wait at once. */
export const MAX_SEEKS = 200;
/** The lobby list shows at most this many. */
export const LIST_LIMIT = 40;

export const START_RATING = 1200;
/** Fewer games than this and a rating is still settling: it moves faster and shows with a "?". */
export const PROVISIONAL_GAMES = 10;

function invalid(message) {
  return { ok: false, error: "bad_request", message };
}

/**
 * Checks the body of a seek or of taking one on:
 * { name, clock (seek only; a clock, or null for none), look?, player (a 32-hex key) }.
 */
export function parseSeekInput(body, { needsClock = true, minClockSeconds = 60, isKey } = {}) {
  const input = body ?? {};
  const name = input.name ?? null;
  if (name !== null && typeof name !== "string") return invalid('"name" must be text.');
  if (!isKey(input.player)) return invalid('"player" must be the app\'s player key: 32 lowercase hex characters.');
  let clock = null;
  let days = null;
  if (needsClock) {
    // Days per move (a daily game) instead of a clock.
    const parsedDays = parseDays(input.days);
    if (!parsedDays.ok) return parsedDays;
    days = parsedDays.days;
    // No clock (null) is allowed: such games are just for fun, not rated.
    if (days === null && input.clock !== null && input.clock !== undefined) {
      const parsed = parseClock(input.clock, minClockSeconds);
      if (!parsed.ok) return parsed;
      clock = parsed.clock;
    }
  }
  return { ok: true, value: { name: cleanName(name), clock, days, look: cleanLook(input.look), player: input.player } };
}

export function emptyLobby() {
  return { seeks: {} };
}

function sameClock(a, b) {
  if (!a || !b) return !a && !b;
  return a.initial === b.initial && a.increment === b.increment;
}

/** Waiting for a daily game: kept without check-ins. */
export function isDaily(seek) {
  return Boolean(seek.days);
}

/** Same clock and same days per move. */
function samePace(seek, { clock, days }) {
  return sameClock(seek.clock, clock) && (seek.days ?? null) === (days ?? null);
}

/** Still open on its own terms: a live seek checked in lately, a daily one not yet a week old. */
function isFresh(seek, now) {
  return isDaily(seek) ? now - seek.createdAt <= DAILY_SEEK_MS : now - seek.seenAt <= SEEK_STALE_MS;
}

/** Drops waiting players who stopped checking in, and taken seeks already picked up long ago. Returns true if any went. */
export function sweep(lobby, now) {
  let changed = false;
  for (const [id, seek] of Object.entries(lobby.seeks)) {
    const keep = isDaily(seek) ? DAILY_SEEK_MS : MATCH_KEEP_MS;
    const gone = seek.match ? now - seek.match.at > keep : !isFresh(seek, now);
    if (gone) {
      delete lobby.seeks[id];
      changed = true;
    }
  }
  return changed;
}

/** Seeks still open: nobody has taken them and their player is still checking in. */
export function openSeeks(lobby, now) {
  return Object.values(lobby.seeks).filter((seek) => !seek.match && !seek.pairing && isFresh(seek, now));
}

/** What anyone may see of a waiting player: never the hashes, tokens or keys. */
export function seekView(seek, now) {
  return {
    id: seek.id,
    name: seek.name,
    rating: seek.rating,
    provisional: seek.games < PROVISIONAL_GAMES,
    clock: seek.clock ? { initial: seek.clock.initial, increment: seek.clock.increment } : null,
    days: seek.days ?? null,
    look: seek.look ?? null,
    waitingFor: Math.max(0, now - seek.createdAt),
  };
}

/**
 * The lobby list: who is waiting, the longest waiting first. Players waiting with
 * no clock are listed only for apps that ask (`untimed`), and daily ones only for apps
 * that ask for those too (`daily`): older apps can't read them.
 */
export function listView(lobby, now, { untimed = false, daily = false } = {}) {
  const open = openSeeks(lobby, now)
    .filter((seek) => (isDaily(seek) ? daily : untimed || seek.clock))
    .sort((a, b) => a.createdAt - b.createdAt);
  return { players: open.slice(0, LIST_LIMIT).map((seek) => seekView(seek, now)), waiting: open.length, now };
}

/**
 * The waiting player a quick pairing takes on: same clock, not the same
 * player, rating closest (on a tie, the one waiting longest). Null if none.
 */
export function bestOpponent(lobby, { clock, days = null, playerHash, rating }, now) {
  let best = null;
  for (const seek of openSeeks(lobby, now)) {
    if (seek.playerHash === playerHash || !samePace(seek, { clock, days })) continue;
    const gap = Math.abs(seek.rating - rating);
    if (!best || gap < best.gap || (gap === best.gap && seek.createdAt < best.seek.createdAt)) best = { seek, gap };
  }
  return best ? best.seek : null;
}

/**
 * Adds a waiting player. Their earlier seek of the same kind (a second phone, a lost check-in) is dropped:
 * a player waits once for a game now and once for a daily game.
 */
export function addSeek(lobby, { id, tokenHash, playerHash, name, rating, games, clock, days = null, look }, now) {
  dropSeeks(lobby, playerHash, Boolean(days));
  if (Object.keys(lobby.seeks).length >= MAX_SEEKS) return { ok: false, error: "rate_limited", message: "The lobby is full right now. Try again in a minute." };
  const seek = { id, tokenHash, playerHash, name, rating, games, clock, days: days ?? null, look, createdAt: now, seenAt: now, match: null };
  lobby.seeks[id] = seek;
  return { ok: true, seek };
}

/** Drops a player's open seeks of one kind (daily or not). */
export function dropSeeks(lobby, playerHash, daily) {
  for (const [other, seek] of Object.entries(lobby.seeks)) {
    if (seek.playerHash === playerHash && !seek.match && !seek.pairing && isDaily(seek) === daily) delete lobby.seeks[other];
  }
}

/**
 * New ratings after a game. `score` is White's: 1 for a win, 0.5 for a draw,
 * 0 for a loss. Each side's K is 40 while its rating is settling, then 20.
 */
export function eloAfter(white, black, score) {
  const expected = 1 / (1 + 10 ** ((black.rating - white.rating) / 400));
  const kWhite = white.games < PROVISIONAL_GAMES ? 40 : 20;
  const kBlack = black.games < PROVISIONAL_GAMES ? 40 : 20;
  const whiteChange = Math.round(kWhite * (score - expected));
  const blackChange = Math.round(kBlack * (expected - score));
  return {
    white: { rating: Math.max(100, white.rating + whiteChange), games: white.games + 1 },
    black: { rating: Math.max(100, black.rating + blackChange), games: black.games + 1 },
  };
}

/** Results that leave ratings alone: games that never really started. */
export const UNRATED_REASONS = new Set(["aborted", "cancelled", "expired"]);
