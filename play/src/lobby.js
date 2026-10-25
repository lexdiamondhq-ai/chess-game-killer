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
// Ratings are Elo, kept per player key: 1200 to start, moving faster for a
// player's first games. Only games paired here are rated.
//
// Every function takes the time (`now`) as an argument, so tests can run the
// lobby through minutes in milliseconds.

import { cleanLook, parseClock } from "./game.js";
import { cleanName } from "./util.js";

/** A waiting player who stops checking in for this long is gone. */
export const SEEK_STALE_MS = 20000;
/** A taken seek is kept this long for its player's app to pick up the game. */
export const MATCH_KEEP_MS = 120000;
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
 * { name, clock (seek only; must be a clock), look?, player (a 32-hex key) }.
 */
export function parseSeekInput(body, { needsClock = true, minClockSeconds = 60, isKey } = {}) {
  const input = body ?? {};
  const name = input.name ?? null;
  if (name !== null && typeof name !== "string") return invalid('"name" must be text.');
  if (!isKey(input.player)) return invalid('"player" must be the app\'s player key: 32 lowercase hex characters.');
  let clock = null;
  if (needsClock) {
    if (input.clock === null || input.clock === undefined) return invalid("Games with players online always have a clock.");
    const parsed = parseClock(input.clock, minClockSeconds);
    if (!parsed.ok) return parsed;
    clock = parsed.clock;
  }
  return { ok: true, value: { name: cleanName(name), clock, look: cleanLook(input.look), player: input.player } };
}

export function emptyLobby() {
  return { seeks: {} };
}

function sameClock(a, b) {
  return a.initial === b.initial && a.increment === b.increment;
}

/** Drops waiting players who stopped checking in, and taken seeks already picked up long ago. Returns true if any went. */
export function sweep(lobby, now) {
  let changed = false;
  for (const [id, seek] of Object.entries(lobby.seeks)) {
    const gone = seek.match ? now - seek.match.at > MATCH_KEEP_MS : now - seek.seenAt > SEEK_STALE_MS;
    if (gone) {
      delete lobby.seeks[id];
      changed = true;
    }
  }
  return changed;
}

/** Seeks still open: nobody has taken them and their player is still checking in. */
export function openSeeks(lobby, now) {
  return Object.values(lobby.seeks).filter((seek) => !seek.match && !seek.pairing && now - seek.seenAt <= SEEK_STALE_MS);
}

/** What anyone may see of a waiting player: never the hashes, tokens or keys. */
export function seekView(seek, now) {
  return {
    id: seek.id,
    name: seek.name,
    rating: seek.rating,
    provisional: seek.games < PROVISIONAL_GAMES,
    clock: { initial: seek.clock.initial, increment: seek.clock.increment },
    look: seek.look ?? null,
    waitingFor: Math.max(0, now - seek.createdAt),
  };
}

/** The lobby list: who is waiting, the longest waiting first. */
export function listView(lobby, now) {
  const open = openSeeks(lobby, now).sort((a, b) => a.createdAt - b.createdAt);
  return { players: open.slice(0, LIST_LIMIT).map((seek) => seekView(seek, now)), waiting: open.length, now };
}

/**
 * The waiting player a quick pairing takes on: same clock, not the same
 * player, rating closest (on a tie, the one waiting longest). Null if none.
 */
export function bestOpponent(lobby, { clock, playerHash, rating }, now) {
  let best = null;
  for (const seek of openSeeks(lobby, now)) {
    if (seek.playerHash === playerHash || !sameClock(seek.clock, clock)) continue;
    const gap = Math.abs(seek.rating - rating);
    if (!best || gap < best.gap || (gap === best.gap && seek.createdAt < best.seek.createdAt)) best = { seek, gap };
  }
  return best ? best.seek : null;
}

/** Adds a waiting player. Their earlier seeks (a second phone, a lost check-in) are dropped. */
export function addSeek(lobby, { id, tokenHash, playerHash, name, rating, games, clock, look }, now) {
  for (const [other, seek] of Object.entries(lobby.seeks)) {
    if (seek.playerHash === playerHash && !seek.match) delete lobby.seeks[other];
  }
  if (Object.keys(lobby.seeks).length >= MAX_SEEKS) return { ok: false, error: "rate_limited", message: "The lobby is full right now. Try again in a minute." };
  const seek = { id, tokenHash, playerHash, name, rating, games, clock, look, createdAt: now, seenAt: now, match: null };
  lobby.seeks[id] = seek;
  return { ok: true, seek };
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
