// Today's Move: one puzzle a day, the same for every player (the app's
// Shared/Daily/daily-moves.csv). Each player's try is counted once a day, by
// the hash of their private player key, so the app can say "62% of 1,284
// players found it". Kept in the Lobby object (lobbyroom.js); these are the rules.

/** How far a day may be from the server's own date: the world's time zones and a little slack. */
export const DAY_SLACK_MS = 2 * 24 * 60 * 60 * 1000;

const DAY = /^\d{4}-\d{2}-\d{2}$/;
const PUZZLE = /^[A-Za-z0-9]{4,10}$/;

/** True for "2026-10-29" within two days of `now`. */
export function isDailyDay(day, now = Date.now()) {
  if (typeof day !== "string" || !DAY.test(day)) return false;
  const at = Date.parse(`${day}T12:00:00Z`);
  if (Number.isNaN(at)) return false;
  // "2026-02-31" parses as March 3: only a real date round-trips.
  if (new Date(at).toISOString().slice(0, 10) !== day) return false;
  return Math.abs(at - now) <= DAY_SLACK_MS;
}

/** Checks a report's body: { player, puzzle, found }. */
export function parseDailyReport(body, { isKey }) {
  if (!body || typeof body !== "object") return { ok: false, message: "Send a JSON object." };
  if (!isKey(body.player)) return { ok: false, message: '"player" must be the app\'s player key.' };
  if (typeof body.puzzle !== "string" || !PUZZLE.test(body.puzzle)) {
    return { ok: false, message: '"puzzle" must be the puzzle\'s id.' };
  }
  if (typeof body.found !== "boolean") return { ok: false, message: '"found" must be true or false.' };
  return { ok: true, value: { player: body.player, puzzle: body.puzzle, found: body.found } };
}

/** The storage keys: the day's tally for its puzzle, and the mark that a player was counted. */
export function tallyKey(day, puzzle) {
  return `daily:${day}:${puzzle}`;
}

export function playerKey(day, playerHash) {
  return `daily-player:${day}:${playerHash}`;
}

/** A tally with one more try counted; the same tally when the player was counted already. */
export function counted(tally, { found, seen }) {
  const current = { players: tally?.players ?? 0, found: tally?.found ?? 0 };
  if (seen) return current;
  return { players: current.players + 1, found: current.found + (found ? 1 : 0) };
}
