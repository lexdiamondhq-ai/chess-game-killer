// The front door of the game server. Every request that isn't for a static
// file in ./public lands here (see wrangler.toml). This file checks the
// request (address, method, game code, body, token, rate limits) and hands
// game requests to the game's own room, the GameRoom Durable Object for its
// code. It also serves the two HTML pages and the Apple app-site file.
//
// Everything is same-origin: the browser board is served from this same
// address, so no CORS headers are needed, and the app talks to it directly.

import { parseCreateInput, ACTIONS } from "./game.js";
import { parseSeekInput } from "./lobby.js";
import { isDailyDay, parseDailyReport } from "./daily.js";
import { renderHomePage, renderInvitePage } from "./pages.js";
import {
  errorResponse,
  hashToken,
  isToken,
  jsonResponse,
  newCode,
  newToken,
  normalizeCode,
  readConfig,
  readJson,
  tokenFrom,
} from "./util.js";

/** The app's own link for a game. */
export const APP_LINK = "chessgamekiller://c/";
/** The app's bundle ID (project.yml), for universal links. */
export const BUNDLE_ID = "com.chessgamekiller.app";

const GAME_PATH = /^\/api\/games\/([^/]+)(?:\/([a-z_]+))?\/?$/;
const INVITE_PATH = /^\/c\/([^/]+)\/?$/;
/** Today's Move: /api/daily/{yyyy-mm-dd}. */
const DAILY_PATH = /^\/api\/daily\/([^/]+)\/?$/;
/** The addresses under /api/games/{code} and the method each takes. */
const METHOD_FOR = new Map([
  ["", "GET"],
  ["join", "POST"],
  ["move", "POST"],
  ["action", "POST"],
  ["live", "GET"],
]);

export async function handleRequest(request, env) {
  const url = new URL(request.url);
  try {
    return await route(request, env, url);
  } catch (error) {
    // Only the path and the error's message: never the query (it can hold a token) or the body.
    console.error(`${request.method} ${url.pathname} failed:`, error && error.message);
    if (url.pathname.startsWith("/api/")) {
      return errorResponse("server_error", "Something went wrong on our side. Please try again.");
    }
    return textResponse("Something went wrong. Please try again.", 500);
  }
}

async function route(request, env, url) {
  const path = url.pathname;
  const method = request.method;
  const reading = method === "GET" || method === "HEAD";

  if (path === "/api/games" || path === "/api/games/") {
    return method === "POST" ? createGame(request, env, url) : wrongMethod("POST");
  }
  if (path === "/api/lobby" || path.startsWith("/api/lobby/")) return lobbyRequest(request, env, url, path);
  const daily = DAILY_PATH.exec(path);
  if (daily) return dailyRequest(request, env, daily[1]);
  const game = GAME_PATH.exec(path);
  if (game) return gameRequest(request, env, url, game[1], game[2] ?? "");
  if (path.startsWith("/api/") || path === "/api") {
    return errorResponse("not_found", "There's nothing at this address.");
  }

  if (path === "/") {
    if (!reading) return textResponse("Not allowed", 405, { allow: "GET, HEAD" });
    return htmlResponse(renderHomePage({ origin: url.origin }), 200, "public, max-age=300");
  }
  const invite = INVITE_PATH.exec(path);
  if (invite) {
    if (!reading) return textResponse("Not allowed", 405, { allow: "GET, HEAD" });
    return invitePage(env, url, invite[1]);
  }
  if (path === "/.well-known/apple-app-site-association") {
    return appSiteAssociation(env);
  }
  // Anything else under a path that reaches the worker first may still be a file.
  if (path.startsWith("/.well-known/") && env.ASSETS) return env.ASSETS.fetch(request);
  return textResponse("Not found", 404);
}

// ---------------------------------------------------------------------------
// API

function roomFor(env, code) {
  return env.GAMES.get(env.GAMES.idFromName(code));
}

/** Turns a room's { status, body } into a response. */
function fromRoom(answer) {
  return jsonResponse(answer.body, answer.status);
}

function wrongMethod(allowed) {
  return jsonResponse(
    { error: "bad_request", message: `Use ${allowed} for this address.` },
    405,
    { allow: allowed === "GET" ? "GET, HEAD" : allowed },
  );
}

function badRequest(message) {
  return errorResponse("bad_request", message);
}

function unauthorized() {
  return errorResponse("unauthorized", "Send your seat's token as \"Authorization: Bearer {token}\".");
}

/** True when this address has used up its allowance on this limiter. */
async function overLimit(limiter, request) {
  if (!limiter) return false;
  const key = request.headers.get("cf-connecting-ip") || "unknown";
  try {
    const { success } = await limiter.limit({ key });
    return !success;
  } catch (error) {
    // A limiter hiccup shouldn't stop people playing.
    console.error("rate limiter failed:", error && error.message);
    return false;
  }
}

function rateLimited() {
  return errorResponse("rate_limited", "That's a lot of requests. Wait a moment and try again.", undefined, {
    "retry-after": "60",
  });
}

/** POST /api/games: a new game with its creator seated. */
async function createGame(request, env, url) {
  if (await overLimit(env.CREATE_LIMITER, request)) return rateLimited();
  const body = await readJson(request);
  if (!body.ok) return badRequest(body.message);
  const input = parseCreateInput(body.value, readConfig(env));
  if (!input.ok) return badRequest(input.message);

  const token = newToken();
  const tokenHash = await hashToken(token);
  // A code that already has a game is drawn again. With 887 million codes
  // this almost never happens, but it must never mix two games.
  for (let attempt = 0; attempt < 5; attempt += 1) {
    const code = newCode();
    const made = await roomFor(env, code).create({ code, ...input.value, tokenHash });
    if (made.inUse) continue;
    return jsonResponse(
      { code, url: `${url.origin}/c/${code}`, appUrl: `${APP_LINK}${code}`, seat: made.seat, token, game: made.game },
      201,
    );
  }
  throw new Error("no free game code after 5 tries");
}

/** Everything under /api/games/{code}. */
async function gameRequest(request, env, url, rawCode, part) {
  const allowed = METHOD_FOR.get(part);
  if (!allowed) return errorResponse("not_found", "There's nothing at this address.");
  const method = request.method;
  if (method !== allowed && !(allowed === "GET" && method === "HEAD")) return wrongMethod(allowed);
  const code = normalizeCode(rawCode);
  if (!code) return errorResponse("not_found", "There's no game with that code.");
  const room = roomFor(env, code);

  if (part === "") return fromRoom(await room.read());

  if (part === "live") {
    if ((request.headers.get("upgrade") || "").toLowerCase() !== "websocket") {
      return jsonResponse({ error: "bad_request", message: "Connect to this address with a WebSocket." }, 426);
    }
    const token = url.searchParams.get("token");
    if (token && !isToken(token)) return unauthorized();
    // The room takes the WebSocket itself.
    return room.fetch(request);
  }

  const limiter = part === "join" ? env.JOIN_LIMITER : env.MOVE_LIMITER;
  if (await overLimit(limiter, request)) return rateLimited();
  const body = await readJson(request);
  if (!body.ok) return badRequest(body.message);
  const token = tokenFrom(request, body.value);

  if (part === "join") {
    if (token !== null && !isToken(token)) return unauthorized();
    const name = body.value.name ?? null;
    if (name !== null && typeof name !== "string") return badRequest('"name" must be text.');
    return fromRoom(await room.join({ token, name }));
  }

  if (!isToken(token)) return unauthorized();
  if (part === "move") {
    return fromRoom(await room.move({ token, uci: body.value.uci, ply: body.value.ply }));
  }

  const type = body.value.type;
  if (typeof type !== "string" || !ACTIONS.includes(type)) {
    return badRequest(`"type" must be one of: ${ACTIONS.join(", ")}.`);
  }
  // A rematch can start a new game, so it also counts against the new-game limit.
  if (type === "rematch" && (await overLimit(env.CREATE_LIMITER, request))) return rateLimited();
  return fromRoom(await room.action({ token, type }));
}

// ---------------------------------------------------------------------------
// Play online: the lobby (PROTOCOL.md, "Play online")

const SEEK_PATH = /^\/api\/lobby\/seeks\/([0-9a-f]{12})(?:\/(cancel))?\/?$/;
const TAKE_PATH = /^\/api\/lobby\/seeks\/([0-9a-f]{12})\/play\/?$/;

function lobbyRoom(env) {
  return env.LOBBY.get(env.LOBBY.idFromName("lobby"));
}

/** POST /api/daily/{day}: counts a player's try at Today's Move once and answers the day's tally. */
async function dailyRequest(request, env, day) {
  if (request.method !== "POST") return wrongMethod("POST");
  if (!isDailyDay(day)) return badRequest('The day must be a date like "2026-10-29", within two days of today.');
  if (await overLimit(env.MOVE_LIMITER, request)) return rateLimited();
  const body = await readJson(request);
  if (!body.ok) return badRequest(body.message);
  const input = parseDailyReport(body.value, { isKey: isToken });
  if (!input.ok) return badRequest(input.message);
  const { player, puzzle, found } = input.value;
  return fromRoom(await lobbyRoom(env).dailyReport({ day, puzzle, found, playerHash: await hashToken(player) }));
}

async function lobbyRequest(request, env, url, path) {
  const method = request.method;
  const lobby = lobbyRoom(env);
  if (path === "/api/lobby" || path === "/api/lobby/") {
    if (method !== "GET" && method !== "HEAD") return wrongMethod("GET");
    return fromRoom(await lobby.list());
  }
  if (path === "/api/lobby/me" || path === "/api/lobby/me/") {
    if (method !== "POST") return wrongMethod("POST");
    const body = await readJson(request);
    if (!body.ok) return badRequest(body.message);
    if (!isToken(body.value.player)) return badRequest('"player" must be the app\'s player key.');
    return fromRoom(await lobby.me({ playerHash: await hashToken(body.value.player) }));
  }
  if (path === "/api/lobby/seeks" || path === "/api/lobby/seeks/") {
    if (method !== "POST") return wrongMethod("POST");
    if (await overLimit(env.CREATE_LIMITER, request)) return rateLimited();
    const body = await readJson(request);
    if (!body.ok) return badRequest(body.message);
    const input = parseSeekInput(body.value, { minClockSeconds: readConfig(env).minClockSeconds, isKey: isToken });
    if (!input.ok) return badRequest(input.message);
    const token = newToken();
    const answer = await lobby.seek({
      tokenHash: await hashToken(token),
      playerHash: await hashToken(input.value.player),
      name: input.value.name,
      clock: input.value.clock,
      look: input.value.look,
      pair: body.value.pair !== false,
    });
    // A seek's own token comes back only to the player who made it.
    if (answer.status === 201) answer.body.token = token;
    return fromRoom(answer);
  }
  const take = TAKE_PATH.exec(path);
  if (take) {
    if (method !== "POST") return wrongMethod("POST");
    if (await overLimit(env.CREATE_LIMITER, request)) return rateLimited();
    const body = await readJson(request);
    if (!body.ok) return badRequest(body.message);
    const input = parseSeekInput(body.value, { needsClock: false, isKey: isToken });
    if (!input.ok) return badRequest(input.message);
    return fromRoom(
      await lobby.take({ id: take[1], playerHash: await hashToken(input.value.player), name: input.value.name, look: input.value.look }),
    );
  }
  const seek = SEEK_PATH.exec(path);
  if (seek) {
    if (method !== "POST") return wrongMethod("POST");
    if (await overLimit(env.MOVE_LIMITER, request)) return rateLimited();
    const body = await readJson(request);
    if (!body.ok) return badRequest(body.message);
    const token = tokenFrom(request, body.value);
    if (!isToken(token)) return unauthorized();
    const tokenHash = await hashToken(token);
    return fromRoom(seek[2] === "cancel" ? await lobby.cancel({ id: seek[1], tokenHash }) : await lobby.check({ id: seek[1], tokenHash }));
  }
  return errorResponse("not_found", "There's nothing at this address.");
}

// ---------------------------------------------------------------------------
// Pages

function htmlResponse(html, status, cacheControl) {
  return new Response(html, {
    status,
    headers: {
      "content-type": "text/html; charset=utf-8",
      "cache-control": cacheControl,
      "x-content-type-options": "nosniff",
      "x-frame-options": "DENY",
    },
  });
}

function textResponse(text, status, headers = {}) {
  return new Response(text, {
    status,
    headers: { "content-type": "text/plain; charset=utf-8", "x-content-type-options": "nosniff", ...headers },
  });
}

/** GET /c/{code}: the invite page, or the same page saying there's no such game (404). */
async function invitePage(env, url, rawCode) {
  const code = normalizeCode(rawCode);
  let game = null;
  if (code) {
    const answer = await roomFor(env, code).read();
    if (answer.status === 200) game = answer.body.game;
  }
  // An unknown code is shown back only as the letters and digits it holds.
  const shown = code ?? safeCode(rawCode);
  return htmlResponse(renderInvitePage({ game, origin: url.origin, code: shown }), game ? 200 : 404, "no-store");
}

function safeCode(raw) {
  let text = raw;
  try {
    text = decodeURIComponent(raw);
  } catch {
    // Not valid percent-encoding: use it as it came.
  }
  return text.toUpperCase().replace(/[^A-Z0-9]/g, "").slice(0, 12);
}

/**
 * /.well-known/apple-app-site-association lets iOS open invite links in the
 * app (universal links). Served only once APPLE_TEAM_ID is set.
 */
function appSiteAssociation(env) {
  const team = String(env.APPLE_TEAM_ID || "").trim().toUpperCase();
  if (!/^[A-Z0-9]{10}$/.test(team)) return textResponse("Not found", 404);
  return jsonResponse(
    { applinks: { details: [{ appIDs: [`${team}.${BUNDLE_ID}`], components: [{ "/": "/c/*", comment: "Challenge links" }] }] } },
    200,
    { "cache-control": "public, max-age=3600" },
  );
}
