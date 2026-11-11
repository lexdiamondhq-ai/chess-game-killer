// Friends by @username: the rules, with no Cloudflare in them (tested in
// test/friends.test.js). The Directory Durable Object (directory.js) keeps the
// players and their invites; the router checks requests with these helpers.
//
// A player is the app's private player key (the same one Play online and
// Today's Move use). The server keeps only its hash. A player who picks a
// @username can be found by it or by their name, and sent challenges.

import { cleanName, isOffensiveName } from "./util.js";

export const USERNAME_MIN = 3;
export const USERNAME_MAX = 20;
/** Lower-case letters, digits, "_" and "."; starts with a letter; no "." at the end and no "..". */
const USERNAME_PATTERN = /^[a-z][a-z0-9_.]*$/;

/** Names nobody may take: they would look like the app speaking. */
const RESERVED = new Set([
  "admin", "administrator", "support", "help", "official", "moderator", "mod", "staff", "system",
  "beautyofchess", "beauty_of_chess", "chessgamekiller", "coach", "coachleo", "leo", "player", "you", "me",
  "null", "undefined", "anonymous",
]);

/** A seat waits this long after the app last checked in to count as online. */
export const ONLINE_MS = 90 * 1000;
/** Invites older than this are gone: a challenge nobody joins expires after 7 days anyway. */
export const INVITE_TTL_MS = 7 * 24 * 60 * 60 * 1000;
/** At most this many people in "Your people", and this many search results. */
export const PEOPLE_MAX = 12;
export const SEARCH_MAX = 8;
/** At most this many waiting invites to one player from one sender. */
export const INVITES_PER_PAIR = 3;

/**
 * A username as typed ("@Maria", " maria ") made canonical ("maria"), or
 * { ok: false, message } saying what's wrong with it.
 */
export function parseUsername(input) {
  if (typeof input !== "string") return { ok: false, message: "Pick a username." };
  const name = input.trim().replace(/^@+/, "").toLowerCase();
  if (name.length < USERNAME_MIN) return { ok: false, message: `A username has at least ${USERNAME_MIN} letters.` };
  if (name.length > USERNAME_MAX) return { ok: false, message: `A username has at most ${USERNAME_MAX} letters.` };
  if (!USERNAME_PATTERN.test(name)) {
    return { ok: false, message: "Use letters, numbers, _ and . only, starting with a letter." };
  }
  if (name.endsWith(".") || name.includes("..")) return { ok: false, message: "A username can't end with a dot or have two in a row." };
  if (RESERVED.has(name.replace(/[._]/g, "")) || RESERVED.has(name)) return { ok: false, message: "That username isn't available." };
  if (isOffensiveName(name)) return { ok: false, message: "That username isn't available." };
  return { ok: true, value: name };
}

/**
 * What someone typed in the find box, made ready to search: lower case,
 * without a leading "@", at most 24 characters. Null when it's too short to search.
 */
export function parseQuery(input) {
  if (typeof input !== "string") return null;
  const q = input.trim().replace(/^@+/, "").toLowerCase().slice(0, 24);
  return q.length >= 2 ? q : null;
}

/** Escapes text for a SQL LIKE pattern that uses "\" as its escape character. */
export function likeEscape(text) {
  return text.replace(/[\\%_]/g, (c) => `\\${c}`);
}

/** The name a player is shown with: their own name, cleaned; their username when they gave none. */
export function displayName(name, username) {
  const clean = cleanName(name ?? "");
  return clean === "Player" && username ? username : clean;
}

/** A player as others see them. */
export function personView(row, now) {
  return {
    username: row.username,
    name: displayName(row.name, row.username),
    online: typeof row.last_seen === "number" && now - row.last_seen < ONLINE_MS,
  };
}

/** True when a game can still be joined by an invited friend. */
export function isInvitable(game) {
  return !!game && game.status === "waiting";
}

/** The seat an invited friend takes in a waiting game: the one the creator left open. */
export function friendSeat(game) {
  return game.creator === "white" ? "black" : "white";
}
