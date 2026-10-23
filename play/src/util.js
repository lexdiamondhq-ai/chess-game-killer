// Small helpers for the game server: game codes, seat tokens, players' names,
// reading request bodies and writing JSON replies. Nothing here depends on
// Cloudflare, so the unit tests run it straight in Node.

/** The letters a code is made of. No 0/O and no 1/I/L, so a code read out or typed in can't be misread. */
export const CODE_ALPHABET = "23456789ABCDEFGHJKMNPQRSTUVWXYZ";
export const CODE_LENGTH = 6;
const CODE_PATTERN = new RegExp(`^[${CODE_ALPHABET}]{${CODE_LENGTH}}$`);
const TOKEN_PATTERN = /^[0-9a-f]{32}$/;

export const NAME_MAX = 24;
export const DEFAULT_NAME = "Player";

/** The HTTP status that goes with each error code in PROTOCOL.md. */
export const ERROR_STATUS = {
  bad_request: 400,
  unauthorized: 401,
  not_found: 404,
  seat_taken: 409,
  not_your_turn: 409,
  stale: 409,
  game_over: 409,
  illegal_move: 422,
  rate_limited: 429,
  server_error: 500,
};

/** The largest request body we read. Every real request is far smaller. */
export const MAX_BODY_BYTES = 8 * 1024;

function randomBytes(count) {
  return crypto.getRandomValues(new Uint8Array(count));
}

function hex(bytes) {
  return Array.from(bytes, (byte) => byte.toString(16).padStart(2, "0")).join("");
}

/**
 * A fresh random game code. Each letter is equally likely: random bytes of
 * 248 or more are skipped, because 248 is the largest multiple of 31 that
 * fits in a byte and the rest would favour the first letters.
 */
export function newCode(bytes = randomBytes) {
  let code = "";
  while (code.length < CODE_LENGTH) {
    for (const byte of bytes(16)) {
      if (byte < 248 && code.length < CODE_LENGTH) code += CODE_ALPHABET[byte % 31];
    }
  }
  return code;
}

/** The code in upper case, or null if it can't be a game code. Codes are case-insensitive on input. */
export function normalizeCode(input) {
  if (typeof input !== "string") return null;
  const code = input.trim().toUpperCase();
  return CODE_PATTERN.test(code) ? code : null;
}

/** A seat token: 128 random bits as 32 lowercase hex characters. */
export function newToken(bytes = randomBytes) {
  return hex(bytes(16));
}

/** True for something shaped like a token (any letter case). */
export function isToken(value) {
  return typeof value === "string" && TOKEN_PATTERN.test(value.toLowerCase());
}

/**
 * The SHA-256 of a token, in hex. Games store only this, never the token, so
 * nothing in storage can be used to take someone's seat.
 */
export async function hashToken(token) {
  const digest = await crypto.subtle.digest("SHA-256", new TextEncoder().encode(token.toLowerCase()));
  return hex(new Uint8Array(digest));
}

// Characters that are removed from names: control characters, marks that flip
// the direction of text (they can make a name read as something else), and
// invisible characters that would let a name look blank.
const UNWANTED_IN_NAMES = /[\p{Cc}؜ᅟᅠ᠎​‎‏‪-‮⁠-⁤⁦-⁩ㅤﾠ]/gu;

/**
 * A player's name as others will see it: every kind of space or line break
 * becomes one plain space, control and invisible characters are removed,
 * the ends are trimmed and it is cut to 24 characters. Empty becomes "Player".
 * Names are stored as typed otherwise; the pages escape them when they show them.
 */
export function cleanName(input) {
  if (typeof input !== "string") return DEFAULT_NAME;
  let name = input
    .normalize("NFC")
    .replace(/\s/gu, " ")
    .replace(UNWANTED_IN_NAMES, "")
    .replace(/ {2,}/g, " ")
    .trim();
  const characters = Array.from(name);
  if (characters.length > NAME_MAX) {
    // Cut whole characters (an emoji is never split in half), then drop a
    // joiner or space the cut may have left dangling at the end.
    name = characters.slice(0, NAME_MAX).join("").replace(/[‍\s]+$/u, "");
  }
  return name || DEFAULT_NAME;
}

/** Reads a whole number from a setting such as LEAVE_GRACE_MS, kept within min and max. */
export function intSetting(value, fallback, min, max) {
  const number = Number.parseInt(String(value ?? ""), 10);
  if (!Number.isFinite(number)) return fallback;
  return Math.min(max, Math.max(min, number));
}

const DAY_MS = 24 * 60 * 60 * 1000;

/**
 * The server's settings, from the [vars] in wrangler.toml. KEEP_FINISHED_MS
 * (how long a finished game is kept) is only ever set by tests.
 */
export function readConfig(env = {}) {
  return {
    leaveGraceMs: intSetting(env.LEAVE_GRACE_MS, 20000, 0, 10 * 60 * 1000),
    minClockSeconds: intSetting(env.MIN_CLOCK_SECONDS, 60, 1, 3600),
    keepFinishedMs: intSetting(env.KEEP_FINISHED_MS, 30 * DAY_MS, 1000, 365 * DAY_MS),
  };
}

/**
 * Reads a request body as a JSON object, whatever its content type (a browser's
 * navigator.sendBeacon sends text/plain). An empty body is an empty object.
 * Returns { ok: true, value } or { ok: false, message }.
 */
export async function readJson(request, maxBytes = MAX_BODY_BYTES) {
  const declared = Number(request.headers.get("content-length") || 0);
  if (declared > maxBytes) return { ok: false, message: "The request is too large." };
  let text = "";
  if (request.body) {
    const reader = request.body.getReader();
    const decoder = new TextDecoder();
    let size = 0;
    for (;;) {
      const { done, value } = await reader.read();
      if (done) break;
      size += value.byteLength;
      if (size > maxBytes) {
        await reader.cancel().catch(() => {});
        return { ok: false, message: "The request is too large." };
      }
      text += decoder.decode(value, { stream: true });
    }
    text += decoder.decode();
  }
  if (text.trim() === "") return { ok: true, value: {} };
  let value;
  try {
    value = JSON.parse(text);
  } catch {
    return { ok: false, message: "The request body isn't valid JSON." };
  }
  if (value === null || typeof value !== "object" || Array.isArray(value)) {
    return { ok: false, message: "The request body must be a JSON object." };
  }
  return { ok: true, value };
}

/**
 * The seat token sent with a request: from "Authorization: Bearer {token}",
 * or else from a "token" field in the body. Returns null when none was sent
 * and "" when one was sent but can't be read, so the caller can refuse it.
 */
export function tokenFrom(request, body) {
  const header = request.headers.get("authorization");
  if (header !== null && header.trim() !== "") {
    const match = /^Bearer\s+(\S+)\s*$/i.exec(header.trim());
    return match ? match[1].toLowerCase() : "";
  }
  if (body && Object.hasOwn(body, "token") && body.token !== null) {
    return typeof body.token === "string" ? body.token.trim().toLowerCase() : "";
  }
  return null;
}

const JSON_HEADERS = {
  "content-type": "application/json; charset=utf-8",
  "cache-control": "no-store",
  "x-content-type-options": "nosniff",
};

/** A JSON reply. API replies are never cached: they describe a game that keeps changing. */
export function jsonResponse(body, status = 200, headers = {}) {
  return new Response(JSON.stringify(body), { status, headers: { ...JSON_HEADERS, ...headers } });
}

/** The body of an error reply: { error, message, game? }. */
export function errorBody(error, message, game) {
  return game ? { error, message, game } : { error, message };
}

/** An error reply with the status that goes with its code. */
export function errorResponse(error, message, game, headers) {
  return jsonResponse(errorBody(error, message, game), ERROR_STATUS[error] ?? 500, headers);
}
