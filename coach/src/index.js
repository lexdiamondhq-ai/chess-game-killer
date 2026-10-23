// Coach Leo's "Talk it through" server. Before moving, the player tells Leo
// their plan; POST /talk checks every claim and streams Leo's answer back as
// NDJSON lines: checked, answer, voice, done. PROTOCOL.md is the contract.
//
// - claims.js: Claude call 1, what the player said as typed claims.
// - verify.js: the rules and Stockfish's numbers decide what is true.
// - answer.js: Claude call 2, Leo's words, with the server's own wording as a safety net.
// - voice.js: Leo's voice on ElevenLabs.
//
// This file checks each request, keeps the limits and runs the stream. It also
// exports TalkBudget, the Durable Object that counts the day's talks.
//
// Only functions, classes and handler objects are exported: once the worker
// has a Durable Object, the Workers runtime refuses a plain string or number
// exported from this file.

import Anthropic from "@anthropic-ai/sdk";
import { coachOf, templateAnswer, wordAnswer } from "./answer.js";
import { describePosition } from "./board.js";
import { claudeTimeoutMs, cleanText, failureCode, parseClaims } from "./claims.js";
import { Chess } from "./vendor/chess.js";
import { verifyTalk } from "./verify.js";
import { speak, toBase64, voiceKey } from "./voice.js";

const MAX_BODY_BYTES = 32 * 1024;
const MAX_SAID = 800;
const CONTEXTS = new Set(["game", "session", "analysis"]);
const UCI = /^[a-h][1-8][a-h][1-8][qrbn]?$/;
/** More than any position's legal moves (218 at most). */
const MAX_FACT_MOVES = 256;
/** The app asks Stockfish for 6 threats; a few spare. */
const MAX_THREATS = 16;
const MAX_PV = 10;
const DEFAULT_DAILY_TALKS = 400;
const DEFAULT_DAILY_VOICE_CHARS = 40000;
const ENCODER = new TextEncoder();
const STREAM_HEADERS = {
  "content-type": "application/x-ndjson",
  "cache-control": "no-store",
  "x-content-type-options": "nosniff",
};

/** The real steps. Tests swap any of them through createHandler. */
const REAL_STEPS = {
  describePosition,
  parseClaims,
  verifyTalk,
  wordAnswer,
  templateAnswer,
  speak,
  makeClient,
  now: () => Date.now(),
};

/**
 * The worker's request handler, built from its steps: { describePosition,
 * parseClaims, verifyTalk, wordAnswer, templateAnswer, speak, makeClient, now }.
 * Each one left out is the real one.
 */
export function createHandler(steps = {}) {
  const deps = { ...REAL_STEPS, ...steps };
  return {
    async fetch(request, env = {}, ctx = undefined) {
      const url = new URL(request.url);
      if (url.pathname === "/") {
        if (request.method === "GET" || request.method === "HEAD") return json({ ok: true });
        return json({ error: "method_not_allowed" }, 405, { allow: "GET, HEAD" });
      }
      if (url.pathname !== "/talk") return json({ error: "not_found" }, 404);
      if (request.method !== "POST") return json({ error: "method_not_allowed" }, 405, { allow: "POST" });
      try {
        return await talk(request, env, ctx, deps);
      } catch (error) {
        // Only a code: never the body, which holds what the player said.
        console.error(JSON.stringify({ talk: "failed", error: (error && error.name) || "error" }));
        return json({ error: "internal" }, 500);
      }
    },
  };
}

export default createHandler();

/** POST /talk: everything that can be refused is refused before the stream starts. */
async function talk(request, env, ctx, deps) {
  if (await overLimit(env.TALK_LIMITER, request)) {
    return json({ error: "rate_limited" }, 429, { "retry-after": "60" });
  }
  const type = (request.headers.get("content-type") || "").split(";")[0].trim().toLowerCase();
  if (type !== "application/json") return json({ error: "unsupported_type" }, 415);
  const body = await readBody(request, MAX_BODY_BYTES);
  if (body === null) return json({ error: "too_large" }, 413);
  let value;
  try {
    value = JSON.parse(body);
  } catch {
    return badRequest("The body isn't valid JSON.");
  }
  const checked = checkTalk(value);
  if (!checked.ok) return badRequest(checked.detail);
  if (!anthropicKey(env)) return json({ error: "not_configured" }, 503);
  // The whole app shares a daily allowance, so the bill has a ceiling even if
  // someone scripts requests against this public address from many addresses.
  if (!(await takeFromBudget(env, "talk", 1, dailyLimit(env.DAILY_TALKS, DEFAULT_DAILY_TALKS)))) {
    return json({ error: "daily_limit" }, 429);
  }

  const { readable, writable } = new TransformStream();
  const work = runTalk(checked.talk, env, deps, writable.getWriter());
  // The steps go on after the response has started, and finish even if the player hangs up.
  if (ctx && typeof ctx.waitUntil === "function") ctx.waitUntil(work);
  return new Response(readable, { status: 200, headers: STREAM_HEADERS });
}

// ---------------------------------------------------------------------------
// The stream

/**
 * Writes the lines in order: checked as soon as the claims are checked, then
 * answer, then voice (if asked for), then done. A failure writes one error
 * line in place of the lines still to come. Never throws. Logs one line of
 * codes and timings per talk, never what was said.
 */
async function runTalk(talk, env, deps, writer) {
  const started = deps.now();
  const log = { talk: "done", claims: 0, parse_ms: null, answer_ms: null, voice_ms: null, source: null, voice: null };
  let open = true;
  const send = async (line) => {
    if (!open) return false;
    try {
      await writer.write(ENCODER.encode(`${JSON.stringify(line)}\n`));
      return true;
    } catch {
      // The player hung up: stop, so nothing more is spent on them.
      open = false;
      log.talk = "hung_up";
      return false;
    }
  };
  const fail = async (step, code) => {
    log.talk = `${step}_failed`;
    log.error = code;
    await send({ type: "error", error: streamError(code) });
  };

  try {
    // 1. Claude hears the claims.
    let client;
    let parsed;
    const parseStarted = deps.now();
    try {
      client = deps.makeClient(env);
      const position = deps.describePosition(talk.fen);
      parsed = await deps.parseClaims(client, env, {
        fen: talk.fen,
        said: talk.said,
        typed: talk.typed,
        lastMove: talk.lastMove,
        context: talk.context,
        position,
      });
    } catch (error) {
      return await fail("parse", failureCode(error));
    } finally {
      log.parse_ms = deps.now() - parseStarted;
    }
    log.claims = Array.isArray(parsed && parsed.claims) ? parsed.claims.length : 0;

    // 2. The rules and the engine's numbers decide what is true.
    let checked;
    let spoken;
    try {
      ({ checked, spoken } = deps.verifyTalk({
        fen: talk.fen,
        facts: talk.facts,
        parsed,
        reveal: talk.reveal,
        said: talk.said,
      }));
      if (!isObject(checked)) throw new Error("no verdict");
    } catch {
      return await fail("verify", "internal");
    }
    if (!(await send(Object.assign({ type: "checked" }, checked, { type: "checked" })))) return;

    // 3. Leo's words: Claude's, or the server's own when Claude can't.
    const answerStarted = deps.now();
    let answer = null;
    try {
      answer = await deps.wordAnswer(client, env, { checked, spoken, coach: talk.coach });
    } catch {
      answer = null;
    }
    if (!answer || typeof answer.text !== "string" || !answer.text.trim() || answer.text.length > 320) {
      try {
        answer = { text: deps.templateAnswer(checked, spoken), source: "template" };
      } catch {
        return await fail("answer", "internal");
      }
    }
    log.answer_ms = deps.now() - answerStarted;
    log.source = answer.source === "leo" ? "leo" : "template";
    if (!(await send({ type: "answer", text: answer.text, source: log.source }))) return;

    // 4. Leo's voice, when the app wants it.
    if (talk.voice) {
      const voiceStarted = deps.now();
      const line = await voiceLine(answer.text, env, deps, talk.coach);
      log.voice_ms = deps.now() - voiceStarted;
      log.voice = line.unavailable || line.format;
      if (!(await send(line))) return;
    }
    await send({ type: "done" });
  } catch {
    await fail("talk", "internal");
  } finally {
    log.total_ms = deps.now() - started;
    console.log(JSON.stringify(log));
    if (open) await writer.close().catch(() => {});
  }
}

/** The voice line: the coach's MP3, or why there's none so the app uses the device's voice. */
async function voiceLine(text, env, deps, coach = "leo") {
  if (!voiceKey(env)) return { type: "voice", unavailable: "not_configured" };
  let allowed;
  try {
    allowed = await takeFromBudget(env, "voice", text.length, dailyLimit(env.DAILY_VOICE_CHARS, DEFAULT_DAILY_VOICE_CHARS));
  } catch (error) {
    console.error(JSON.stringify({ voice: "budget_failed", error: (error && error.name) || "error" }));
    return { type: "voice", unavailable: "upstream" };
  }
  if (!allowed) return { type: "voice", unavailable: "budget" };
  let audio = null;
  try {
    audio = await deps.speak(env, text, undefined, coach);
  } catch {
    audio = null;
  }
  if (!(audio instanceof Uint8Array) || audio.length === 0) return { type: "voice", unavailable: "upstream" };
  return { type: "voice", format: "mp3", audio: toBase64(audio) };
}

/** The stream's error codes: timeout, upstream (Claude failed or refused) or internal (a bug of ours). */
function streamError(code) {
  if (code === "timeout" || code === "internal") return code;
  return "upstream";
}

/** The Anthropic client for one talk. test/live.mjs builds its client here too. */
export function makeClient(env) {
  return new Anthropic({
    apiKey: anthropicKey(env),
    // One quick retry for a passing overload; the call's own deadline still holds.
    maxRetries: 1,
    timeout: claudeTimeoutMs(env),
    openTelemetry: false,
  });
}

/** The key without stray spaces or line breaks from pasting it into a secret. */
function anthropicKey(env) {
  return String(env.ANTHROPIC_API_KEY || "").trim();
}

// ---------------------------------------------------------------------------
// Checking the request

/**
 * Checks a POST /talk body. Returns { ok: true, talk } with every field
 * cleaned and defaulted, or { ok: false, detail } for a 400. Facts the server
 * can't use are dropped rather than refused.
 */
export function checkTalk(body) {
  if (!isObject(body)) return refuse("The body must be a JSON object.");
  if (body.v !== 1) return refuse('"v" must be 1.');
  if (typeof body.fen !== "string" || body.fen.trim() === "") return refuse('"fen" is required.');
  let chess;
  try {
    chess = new Chess(body.fen.trim());
  } catch (error) {
    return refuse(`"fen" isn't a position: ${error.message}`);
  }
  if (sideNotToMoveInCheck(chess)) return refuse('"fen" isn\'t a legal position: the side not to move is in check.');
  if (chess.isGameOver()) return refuse("The game is over in this position.");
  if (typeof body.said !== "string") return refuse('"said" is required.');
  const said = cleanText(body.said, 4 * MAX_SAID);
  if (said === "") return refuse('"said" is empty.');
  if ([...said].length > MAX_SAID) return refuse(`"said" is longer than ${MAX_SAID} characters.`);
  const legal = new Set(chess.moves({ verbose: true }).map((move) => move.from + move.to + (move.promotion || "")));
  return {
    ok: true,
    talk: {
      fen: chess.fen(),
      said,
      typed: body.typed === true,
      reveal: body.reveal === true,
      context: CONTEXTS.has(body.context) ? body.context : "game",
      lastMove: lastMoveOf(body.lastMove, chess),
      voice: body.voice !== false,
      facts: cleanFacts(body.facts, legal),
      coach: coachOf(body.coach),
    },
  };
}

function refuse(detail) {
  return { ok: false, detail };
}

function sideNotToMoveInCheck(chess) {
  const mover = chess.turn();
  const other = mover === "w" ? "b" : "w";
  return chess.findPiece({ type: "k", color: other }).some((square) => chess.isAttacked(square, mover));
}

/** The opponent's last move, kept only when it looks like one: an opponent's piece stands where it went. */
function lastMoveOf(value, chess) {
  if (typeof value !== "string") return null;
  const uci = value.trim().toLowerCase();
  if (!UCI.test(uci)) return null;
  const piece = chess.get(uci.slice(2, 4));
  return piece && piece.color !== chess.turn() ? uci : null;
}

/**
 * Stockfish's numbers as the app sent them, with everything malformed dropped:
 * entries without a move or a score, moves that aren't legal here, repeats,
 * and each line cut at its first move that isn't a move. Null without facts.
 * Whether a threat or a line is legal on its own board is verify.js's job.
 */
export function cleanFacts(facts, legal) {
  if (!isObject(facts)) return null;
  const depth = Number.isInteger(facts.depth) && facts.depth >= 0 && facts.depth <= 200 ? facts.depth : 0;
  const moves = cleanLines(facts.moves, MAX_FACT_MOVES).filter((line) => legal.has(line.uci));
  const threats = cleanLines(facts.threats, MAX_THREATS);
  return { depth, moves, threats };
}

function cleanLines(value, max) {
  const lines = [];
  const seen = new Set();
  for (const item of Array.isArray(value) ? value.slice(0, 4 * max) : []) {
    if (!isObject(item) || typeof item.uci !== "string") continue;
    const uci = item.uci.trim().toLowerCase();
    const evaluation = cleanEval(item.eval);
    if (!UCI.test(uci) || !evaluation || seen.has(uci)) continue;
    seen.add(uci);
    lines.push({ uci, eval: evaluation, pv: cleanPv(item.pv, uci) });
    if (lines.length === max) break;
  }
  return lines;
}

/** { cp } or { mate } with whole numbers; anything else is no score. */
function cleanEval(value) {
  if (!isObject(value)) return null;
  if (Number.isInteger(value.mate) && Math.abs(value.mate) <= 500) return { mate: value.mate };
  if (typeof value.cp === "number" && Number.isFinite(value.cp)) {
    return { cp: Math.round(Math.max(-100000, Math.min(100000, value.cp))) };
  }
  return null;
}

/** The line from the move, at most 10 moves, up to its first move that isn't one. */
function cleanPv(value, uci) {
  const pv = [];
  for (const item of Array.isArray(value) ? value : []) {
    const move = typeof item === "string" ? item.trim().toLowerCase() : "";
    if (!UCI.test(move)) break;
    pv.push(move);
    if (pv.length === MAX_PV) break;
  }
  return pv[0] === uci ? pv : [uci];
}

// ---------------------------------------------------------------------------
// Limits

/** True when this address has used up its talks for the minute. */
async function overLimit(limiter, request) {
  if (!limiter) return false;
  const key = request.headers.get("cf-connecting-ip") || "unknown";
  try {
    const { success } = await limiter.limit({ key });
    return !success;
  } catch (error) {
    // A limiter hiccup shouldn't stop people talking; the daily budget still holds.
    console.error(JSON.stringify({ limiter: "failed", error: (error && error.name) || "error" }));
    return false;
  }
}

/** A daily limit from a setting such as DAILY_TALKS, or the default without it. */
function dailyLimit(value, fallback) {
  const number = Number(value);
  return Number.isFinite(number) && number > 0 ? Math.floor(number) : fallback;
}

/**
 * Takes `amount` from today's allowance of `kind` ("talk" or "voice"). True
 * when it fit (or no budget is set up). Throws when the budget can't be asked,
 * so a broken budget never quietly lifts the ceiling.
 */
async function takeFromBudget(env, kind, amount, limit) {
  if (!env.BUDGET) return true;
  const budget = env.BUDGET.get(env.BUDGET.idFromName("global"));
  const answer = await budget.fetch(`https://budget/${kind}?amount=${amount}&limit=${limit}`, { method: "POST" });
  return answer.status === 200;
}

/**
 * Counts today's talks and characters of Leo's voice (days in UTC). One
 * instance serves the whole app, so the counts are exact.
 */
export class TalkBudget {
  constructor(ctx) {
    this.ctx = ctx;
  }

  /** POST /talk or /voice, with ?amount=&limit=. 200 when it fit, 429 when today's allowance is spent. */
  async fetch(request) {
    const url = new URL(request.url);
    const kind = { "/talk": "talk", "/voice": "voice" }[url.pathname];
    if (!kind) return new Response("not found", { status: 404 });
    const amount = Number(url.searchParams.get("amount"));
    const limit = Number(url.searchParams.get("limit"));
    const fallback = kind === "voice" ? DEFAULT_DAILY_VOICE_CHARS : DEFAULT_DAILY_TALKS;
    const ok = await this.take(
      kind,
      Number.isFinite(amount) && amount > 0 ? Math.ceil(amount) : 1,
      Number.isFinite(limit) && limit > 0 ? Math.floor(limit) : fallback,
    );
    return new Response(ok ? "ok" : "spent", { status: ok ? 200 : 429 });
  }

  /** Takes `amount` talks or voice characters, if today's count stays within `limit`. */
  async take(kind, amount, limit, now = Date.now()) {
    const day = new Date(now).toISOString().slice(0, 10);
    const saved = await this.ctx.storage.get("today");
    const today = saved && saved.day === day ? saved : { day, talks: 0, voice: 0 };
    const field = kind === "voice" ? "voice" : "talks";
    const used = Number(today[field]) || 0;
    if (used + amount > limit) return false;
    await this.ctx.storage.put("today", { ...today, [field]: used + amount });
    return true;
  }
}

// ---------------------------------------------------------------------------
// Helpers

/** Reads the body as text, or null when it's longer than `max` bytes. */
async function readBody(request, max) {
  const declared = Number(request.headers.get("content-length") || 0);
  if (declared > max) return null;
  if (!request.body) return "";
  const reader = request.body.getReader();
  const decoder = new TextDecoder();
  let size = 0;
  let text = "";
  for (;;) {
    const { done, value } = await reader.read();
    if (done) break;
    size += value.byteLength;
    if (size > max) {
      await reader.cancel().catch(() => {});
      return null;
    }
    text += decoder.decode(value, { stream: true });
  }
  return text + decoder.decode();
}

function badRequest(detail) {
  return json({ error: "bad_request", detail }, 400);
}

function json(body, status = 200, headers = {}) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "content-type": "application/json", "cache-control": "no-store", ...headers },
  });
}

function isObject(value) {
  return value !== null && typeof value === "object" && !Array.isArray(value);
}
