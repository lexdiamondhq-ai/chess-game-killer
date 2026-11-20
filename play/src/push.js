// Phone alerts (Apple push notifications): what each alert says, and sending
// one to Apple. The words are pure functions, tested in test/push.test.js.
// The Directory (directory.js) keeps each player's phone and sends through
// sendAlert(); game rooms (room.js) ask the Directory to send.
//
// The four alerts (Alex picked "A, the essentials", 2026-11-20):
//   - a friend challenged you by @username      challengeAlert
//   - your friend took up your challenge         acceptedAlert
//   - it's your move (only when you're away)     yourMoveAlert
//   - 6 hours left in a daily game's move        lastCallAlert
//
// Sending needs three secrets on the worker: APNS_KEY (the .p8 file's text),
// APNS_KEY_ID (its 10-character Key ID) and APNS_TEAM_ID (the Apple team).
// With any missing, nothing is sent and nothing breaks.

/** The app's bundle ID: Apple's "topic" for its alerts. */
export const APNS_TOPIC = "com.chessgamekiller.app";
/** A daily game's last call comes this long before the move is due. */
export const LAST_CALL_MS = 6 * 60 * 60 * 1000;
/** An APNs device token: 64 hex characters today; Apple says it may grow, so up to 200. */
const PHONE_TOKEN = /^[0-9a-f]{64,200}$/;

/** A device token as the app sends it, lower-cased; null when it isn't one. */
export function parsePhoneToken(input) {
  if (typeof input !== "string") return null;
  const token = input.trim().toLowerCase();
  return PHONE_TOKEN.test(token) ? token : null;
}

// ---------------------------------------------------------------------------
// The words

const PIECES = { N: "knight", B: "bishop", R: "rook", Q: "queen", K: "king" };

/**
 * A move in plain words, from its SAN: "knight to f3", "took on d5 with a
 * bishop", "castled", "pawn to e8, making a queen". A check adds " Check."
 */
export function moveWords(san) {
  if (typeof san !== "string" || !san) return null;
  const check = /[+#]$/.test(san);
  const bare = san.replace(/[+#!?]+$/, "");
  let words;
  if (/^O-O(-O)?$/.test(bare)) {
    words = bare === "O-O" ? "castled short" : "castled long";
  } else {
    const square = (bare.match(/[a-h][1-8]/g) ?? []).at(-1);
    if (!square) return null;
    const piece = PIECES[bare[0]] ?? "pawn";
    const promo = bare.match(/=([NBRQ])/);
    if (bare.includes("x")) words = `took on ${square} with ${piece === "pawn" ? "a pawn" : `a ${piece}`}`;
    else words = `played ${piece} to ${square}`;
    if (promo) words += `, making a ${PIECES[promo[1]]}`;
  }
  return check ? `${words}. Check.` : `${words}.`;
}

/** "10 minute game", "3+2 game", "Daily game, 3 days a move", "Game with no clock". */
export function gameKind({ clock = null, days = null } = {}) {
  if (days) return `Daily game, ${days} ${days === 1 ? "day" : "days"} a move`;
  if (!clock) return "Game with no clock";
  const minutes = clock.initial / 60;
  const shown = Number.isInteger(minutes) ? String(minutes) : minutes.toFixed(1);
  if (clock.increment) return `${shown}+${clock.increment} game`;
  return `${shown} minute game`;
}

/** Someone challenged you by your @username. */
export function challengeAlert({ from, clock = null, days = null }) {
  return { title: `${from} challenges you`, body: `${gameKind({ clock, days })}. Tap to accept.` };
}

/** Your friend sat down in the game you made. */
export function acceptedAlert({ name, seat }) {
  return { title: `${name} accepted`, body: `The board is set. You play ${seat}.` };
}

/** It's your move: `name` is who just moved, `san` their move. */
export function yourMoveAlert({ name, san }) {
  const words = moveWords(san);
  return { title: `Your move against ${name}`, body: words ? `${name} ${words}` : `${name} has moved.` };
}

/** A daily game's move is due in 6 hours. */
export function lastCallAlert({ name }) {
  return { title: "6 hours left to move", body: `Your daily game with ${name} ends if you wait.` };
}

/** The JSON Apple wants: the words, a sound, and the game's code so a tap can open it. */
export function apnsPayload({ title, body }, { kind, code = null }) {
  const aps = { alert: { title, body }, sound: "default" };
  // Alerts for one game stack together on the lock screen.
  if (code) aps["thread-id"] = code;
  const payload = { aps, kind };
  if (code) payload.code = code;
  return payload;
}

// ---------------------------------------------------------------------------
// Sending

/** True when the worker has everything it needs to send. */
export function canSend(env) {
  return Boolean(env && env.APNS_KEY && env.APNS_KEY_ID && apnsTeam(env));
}

function apnsTeam(env) {
  const team = String(env.APNS_TEAM_ID || env.APPLE_TEAM_ID || "").trim().toUpperCase();
  return /^[A-Z0-9]{10}$/.test(team) ? team : null;
}

function base64url(bytes) {
  let text = "";
  for (const byte of bytes) text += String.fromCharCode(byte);
  return btoa(text).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
}

function jsonPart(value) {
  return base64url(new TextEncoder().encode(JSON.stringify(value)));
}

/** The .p8 file's text (PEM, PKCS #8) as the bytes inside it. */
export function pemBytes(pem) {
  const inner = String(pem).replace(/-----[^-]+-----/g, "").replace(/\\n/g, "").replace(/\s+/g, "");
  const raw = atob(inner);
  const bytes = new Uint8Array(raw.length);
  for (let i = 0; i < raw.length; i += 1) bytes[i] = raw.charCodeAt(i);
  return bytes;
}

/** Apple accepts one signed token for up to an hour; this one is made again after 50 minutes. */
const TOKEN_LIFE_MS = 50 * 60 * 1000;
let cached = null;

/** The signed token (a JWT, ES256) that proves the alert comes from us. */
export async function providerToken(env, now = Date.now()) {
  const keyId = String(env.APNS_KEY_ID).trim();
  const team = apnsTeam(env);
  if (cached && cached.keyId === keyId && cached.team === team && now - cached.at < TOKEN_LIFE_MS) return cached.jwt;
  const key = await crypto.subtle.importKey("pkcs8", pemBytes(env.APNS_KEY), { name: "ECDSA", namedCurve: "P-256" }, false, ["sign"]);
  const unsigned = `${jsonPart({ alg: "ES256", kid: keyId })}.${jsonPart({ iss: team, iat: Math.floor(now / 1000) })}`;
  // WebCrypto signs ECDSA in the raw r||s form, which is the form a JWT uses.
  const signature = new Uint8Array(await crypto.subtle.sign({ name: "ECDSA", hash: "SHA-256" }, key, new TextEncoder().encode(unsigned)));
  const jwt = `${unsigned}.${base64url(signature)}`;
  cached = { jwt, keyId, team, at: now };
  return jwt;
}

function host(sandbox) {
  return sandbox ? "https://api.sandbox.push.apple.com" : "https://api.push.apple.com";
}

/**
 * Sends one alert to one phone. `sandbox` is the app's guess of which Apple
 * server its phone uses (a build from Xcode uses the sandbox, the App Store
 * build doesn't); if Apple says the phone belongs to the other one, it tries
 * there too. Answers { sent, sandbox, gone }: `gone` means the phone no longer
 * takes alerts (the app was deleted), so it should be forgotten.
 */
export async function sendAlert(env, { token, sandbox = false, payload, collapseId = null }, fetcher = fetch) {
  if (!canSend(env)) return { sent: false, sandbox, gone: false };
  const jwt = await providerToken(env);
  const headers = {
    authorization: `bearer ${jwt}`,
    "apns-topic": APNS_TOPIC,
    "apns-push-type": "alert",
    "apns-priority": "10",
    // An alert not delivered within a day is no longer worth showing.
    "apns-expiration": String(Math.floor(Date.now() / 1000) + 24 * 60 * 60),
    "content-type": "application/json",
  };
  if (collapseId) headers["apns-collapse-id"] = collapseId.slice(0, 64);
  const body = JSON.stringify(payload);
  for (const tryingSandbox of [sandbox, !sandbox]) {
    const response = await fetcher(`${host(tryingSandbox)}/3/device/${token}`, { method: "POST", headers, body });
    if (response.ok) return { sent: true, sandbox: tryingSandbox, gone: false };
    let reason = "";
    try {
      reason = (await response.json()).reason ?? "";
    } catch {
      // No body.
    }
    if (response.status === 410 || reason === "Unregistered") return { sent: false, sandbox, gone: true };
    // A sandbox phone sent to the real server (or the other way round) is a "bad device token".
    if (reason === "BadDeviceToken" && tryingSandbox === sandbox) continue;
    if (reason === "BadDeviceToken") return { sent: false, sandbox, gone: true };
    console.error(`push failed: ${response.status} ${reason}`);
    return { sent: false, sandbox, gone: false };
  }
  return { sent: false, sandbox, gone: false };
}
