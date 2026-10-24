// The real thing, end to end, but in Node instead of Workers: for every case
// in test/fixtures/talks.json, Claude hears the player's words (claims.js),
// the rules and Stockfish's numbers check them (verify.js), Claude words
// Leo's answer (answer.js), and Monolith reads one of the answers aloud
// (voice.js) when there's an ElevenLabs key. It prints a Markdown table, which
// the workflow adds to the pull request's checks.
//
//   ANTHROPIC_API_KEY=… [ELEVENLABS_API_KEY=…] node coach/test/live.mjs
//     [--fixtures other.json] [--only <name>] [--audio leo.mp3]
//
// The settings are wrangler.toml's [vars]; an environment variable of the
// same name wins (CLAUDE_TIMEOUT_MS=30000, say). It exits with 1 only when
// something is broken: a crash, a fixture the server would refuse, claims
// that don't match the schema, a cut-off reply, a verdict of the wrong shape,
// or Anthropic refusing the request itself (a 4xx other than 429). Wording, a
// busy API (429, 5xx), timeouts and a failing voice are reported for a person
// to read, not failed.

import Anthropic from "@anthropic-ai/sdk";
import { existsSync, readFileSync, writeFileSync } from "node:fs";
import { fileURLToPath } from "node:url";
import { wordAnswer } from "../src/answer.js";
import { describePosition } from "../src/board.js";
import { CLAIMS_SCHEMA, KINDS, MAX_CLAIMS, failureCode, messageText, parseClaims } from "../src/claims.js";
import { checkTalk, makeClient } from "../src/index.js";
import { verifyTalk } from "../src/verify.js";
import { speak } from "../src/voice.js";

// Opus 5.5's list prices, in dollars per million tokens (5-minute cache writes).
const PRICE = { input: 4, output: 20, cacheRead: 0.2, cacheWrite: 5 };
const VERDICTS = new Set(["right", "wrong", "partly", "unclear"]);
const GRADES = new Set(["checkmate", "best", "excellent", "good", "inaccuracy", "mistake", "blunder", "illegal", "unknown"]);
const HABITS = new Set(["good", "missed", "none"]);

function argument(name) {
  const index = process.argv.indexOf(name);
  return index > 0 ? process.argv[index + 1] : undefined;
}

/** wrangler.toml's [vars], with the environment's own values on top. */
function settings() {
  const toml = readFileSync(new URL("../wrangler.toml", import.meta.url), "utf8");
  const vars = {};
  let inVars = false;
  for (const line of toml.split("\n")) {
    if (/^\s*\[/.test(line)) inVars = /^\s*\[vars\]\s*$/.test(line);
    const pair = inVars && /^\s*([A-Z_][A-Z0-9_]*)\s*=\s*"([^"]*)"/.exec(line);
    if (pair) vars[pair[1]] = pair[2];
  }
  for (const key of [...Object.keys(vars), "ANTHROPIC_API_KEY", "ELEVENLABS_API_KEY", "VOICE_TIMEOUT_MS"]) {
    if (process.env[key] !== undefined && process.env[key] !== "") vars[key] = process.env[key];
  }
  return vars;
}

/** The talk's client, with every call to Claude written down: how long, how many tokens, what came back. */
function recordingClient(env) {
  const real = makeClient(env);
  const calls = [];
  const create = async (params, options) => {
    const call = { step: params.output_config && params.output_config.format ? "parse" : "answer", ms: null };
    calls.push(call);
    const started = Date.now();
    try {
      call.message = await real.beta.messages.create(params, options);
      return call.message;
    } catch (error) {
      call.error = error;
      throw error;
    } finally {
      call.ms = Date.now() - started;
    }
  };
  return { client: { beta: { messages: { create } } }, calls };
}

/**
 * Whether a failed call means our side is broken (fatal) or the API was busy,
 * slow or careful (a warning). A 4xx other than 429 is our request or our key.
 */
function judge(error) {
  const code = failureCode(error);
  if (error instanceof Anthropic.APIError && !(error instanceof Anthropic.APIConnectionError) && !(error instanceof Anthropic.APIUserAbortError)) {
    const status = Number(error.status);
    return { code, fatal: status >= 400 && status < 500 && status !== 429 };
  }
  return { code, fatal: !["timeout", "connection", "rate_limited", "refusal"].includes(code) };
}

/** A small JSON Schema check, enough for CLAIMS_SCHEMA: types, enums, required keys, no extra keys. */
function schemaErrors(schema, value, path = "$") {
  const types = { object: (v) => v !== null && typeof v === "object" && !Array.isArray(v), array: Array.isArray, string: (v) => typeof v === "string", boolean: (v) => typeof v === "boolean" };
  if (schema.type && !types[schema.type](value)) return [`${path} isn't a ${schema.type}`];
  if (schema.enum && !schema.enum.includes(value)) return [`${path} is ${JSON.stringify(value)}, not one of the enum`];
  const errors = [];
  if (schema.type === "object") {
    for (const key of schema.required || []) if (!(key in value)) errors.push(`${path}.${key} is missing`);
    for (const [key, item] of Object.entries(value)) {
      if (schema.properties && schema.properties[key]) errors.push(...schemaErrors(schema.properties[key], item, `${path}.${key}`));
      else if (schema.additionalProperties === false) errors.push(`${path}.${key} isn't in the schema`);
    }
  }
  if (schema.type === "array" && schema.items) value.forEach((item, i) => errors.push(...schemaErrors(schema.items, item, `${path}[${i}]`)));
  return errors;
}

/** What's wrong with a verdict's shape, as the app reads it. */
function verdictErrors(checked, reveal) {
  const errors = [];
  if (!checked || typeof checked !== "object") return ["checked isn't an object"];
  if (typeof checked.understood !== "boolean") errors.push("understood isn't true or false");
  if (checked.player !== "white" && checked.player !== "black") errors.push(`player is ${JSON.stringify(checked.player)}`);
  if (!Array.isArray(checked.claims) || checked.claims.length > MAX_CLAIMS) errors.push("claims isn't a list of at most 6");
  for (const [i, claim] of (Array.isArray(checked.claims) ? checked.claims : []).entries()) {
    if (!claim || !KINDS.includes(claim.kind) || !VERDICTS.has(claim.verdict) || typeof claim.note !== "string" || typeof claim.id !== "string") {
      errors.push(`claims[${i}] is ${JSON.stringify(claim)}`);
    }
  }
  if (checked.move !== null && !(checked.move && GRADES.has(checked.move.grade))) errors.push(`move is ${JSON.stringify(checked.move)}`);
  if (!Array.isArray(checked.missed) || checked.missed.length > 2) errors.push("missed isn't a list of at most 2");
  const habits = checked.habits || {};
  if (!["threats", "forcing", "safety"].every((key) => HABITS.has(habits[key]))) errors.push(`habits is ${JSON.stringify(checked.habits)}`);
  if (!reveal && checked.best !== null) errors.push("best is shown without reveal");
  if (checked.understood === false && (checked.move !== null || checked.claims.length > 0)) errors.push("not understood, yet it has a move or claims");
  return errors;
}

/** The claims Claude heard, short: "move O-O; attacks (them) Bc5→f2". */
function heardWords(parsed) {
  const parts = [];
  if (parsed.move) parts.push(`move ${parsed.move.san || `“${parsed.move.said}”`}`);
  for (const claim of parsed.claims) {
    const where = `${claim.piece}${claim.square}${claim.target ? `→${claim.target}` : ""}`;
    const extra = [claim.moves.join(" "), claim.eval, claim.gain, claim.afterMove ? "after the move" : ""].filter(Boolean).join(", ");
    parts.push(`${claim.kind}${claim.side === "opponent" ? " (them)" : ""}${where ? ` ${where}` : ""}${extra ? ` [${extra}]` : ""}`);
  }
  return parts.join("; ") || "nothing";
}

/** The verdicts, short: "O-O best · right · wrong". */
function verdictWords(checked) {
  const parts = [];
  if (checked.move) parts.push(`${checked.move.san || "move"} ${checked.move.grade}`);
  for (const claim of Array.isArray(checked.claims) ? checked.claims : []) parts.push(claim && claim.verdict);
  const missed = Array.isArray(checked.missed) ? checked.missed : [];
  if (missed.length) parts.push(`missed ${missed.map((item) => item && item.kind).join(", ")}`);
  return checked.understood ? parts.join(" · ") || "—" : "not understood";
}

/** How close Claude's hearing came to the fixture's hand-written `parsed`, and the verdict to its `expect`. */
function matchWords(fixture, parsed, checked, spoken) {
  const parts = [];
  if (fixture.parsed && typeof fixture.parsed === "object") {
    const wanted = Array.isArray(fixture.parsed.claims) ? fixture.parsed.claims : [];
    const san = (move) => (move && move.san) || "";
    parts.push(san(parsed.move) === san(fixture.parsed.move) ? "move ✓" : `move ✗ (${san(parsed.move) || "none"})`);
    const left = [...parsed.claims];
    let found = 0;
    for (const claim of wanted) {
      const at = left.findIndex(
        (heard) =>
          heard.kind === claim.kind &&
          heard.side === claim.side &&
          ["piece", "square", "target"].every((key) => !claim[key] || heard[key] === claim[key]),
      );
      if (at >= 0) {
        found += 1;
        left.splice(at, 1);
      }
    }
    parts.push(`claims ${found}/${wanted.length}${left.length ? ` +${left.length}` : ""}`);
  }
  if (fixture.expect !== undefined) {
    const at = firstDifference(fixture.expect, { ...checked, checked, spoken });
    parts.push(at === null ? "expect ✓" : `expect ✗ at ${at}`);
  }
  return parts.join(" · ") || "—";
}

/** The first path where `actual` doesn't have what `expected` has (the words said aside), or null. */
function firstDifference(expected, actual, path = "") {
  if (Array.isArray(expected)) {
    if (!Array.isArray(actual)) return path || "(top)";
    if (expected.length !== actual.length) return `${path}.length`;
    for (let i = 0; i < expected.length; i += 1) {
      const at = firstDifference(expected[i], actual[i], `${path}[${i}]`);
      if (at !== null) return at;
    }
    return null;
  }
  if (expected !== null && typeof expected === "object") {
    if (actual === null || typeof actual !== "object") return path || "(top)";
    for (const [key, value] of Object.entries(expected)) {
      if (key === "said") continue;
      const at = firstDifference(value, actual[key], path ? `${path}.${key}` : key);
      if (at !== null) return at;
    }
    return null;
  }
  return Object.is(expected, actual) ? null : path || "(top)";
}

function usageOf(calls) {
  const total = { input: 0, cacheRead: 0, cacheWrite: 0, output: 0 };
  for (const call of calls) {
    const usage = (call.message && call.message.usage) || {};
    total.input += usage.input_tokens || 0;
    total.cacheRead += usage.cache_read_input_tokens || 0;
    total.cacheWrite += usage.cache_creation_input_tokens || 0;
    total.output += usage.output_tokens || 0;
  }
  return total;
}

function dollars(usage) {
  return (usage.input * PRICE.input + usage.cacheRead * PRICE.cacheRead + usage.cacheWrite * PRICE.cacheWrite + usage.output * PRICE.output) / 1e6;
}

const k = (n) => (n >= 1000 ? `${(n / 1000).toFixed(1)}k` : String(n));
const seconds = (call) => (call && call.ms !== null ? (call.ms / 1000).toFixed(1) : "—");

/** Safe in a Markdown table cell and in the step summary's HTML. */
function cell(text, max = 0) {
  let value = String(text ?? "").replace(/\s+/g, " ").trim();
  if (max && value.length > max) value = `${value.slice(0, max - 1)}…`;
  return value.replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;").replace(/\|/g, "\\|") || "—";
}

/** One fixture through the whole pipeline. Returns its row, with `fatal` and `warnings` filled in. */
async function runCase(fixture, env) {
  const row = { name: String(fixture.name || "unnamed"), said: String(fixture.said || ""), fatal: [], warnings: [], calls: [] };
  const request = checkTalk({
    v: 1,
    fen: fixture.fen,
    said: fixture.said,
    typed: fixture.typed === true,
    reveal: fixture.reveal === true,
    lastMove: fixture.lastMove,
    facts: fixture.facts,
    voice: false,
  });
  if (!request.ok) {
    row.fatal.push(`the server would refuse this fixture: ${request.detail}`);
    return row;
  }
  const talk = request.talk;
  const { client, calls } = recordingClient(env);
  row.calls = calls;

  // 1. Claude hears the claims.
  let parsed;
  try {
    parsed = await parseClaims(client, env, {
      fen: talk.fen,
      said: talk.said,
      typed: talk.typed,
      lastMove: talk.lastMove,
      context: talk.context,
      position: describePosition(talk.fen),
    });
  } catch (error) {
    const { code, fatal } = judge(error);
    (fatal ? row.fatal : row.warnings).push(`hearing the claims failed: ${code}${error.status ? "" : ` (${error.message})`}`);
    row.heard = `failed: ${code}`;
    return row;
  }
  const parseCall = calls.find((call) => call.step === "parse" && call.message);
  if (parseCall) {
    const errors = schemaErrors(CLAIMS_SCHEMA, JSON.parse(messageText(parseCall.message)));
    if (errors.length) row.fatal.push(`Claude's claims don't match the schema: ${errors.slice(0, 3).join("; ")}`);
    if (!String(parseCall.message.model).startsWith(env.MODEL)) row.warnings.push(`the claims came from ${parseCall.message.model}`);
  }
  row.parsed = parsed;
  row.heard = heardWords(parsed);

  // 2. The rules and the engine's numbers decide what's true.
  const { checked, spoken } = verifyTalk({ fen: talk.fen, facts: talk.facts, parsed, reveal: talk.reveal, said: talk.said });
  const shape = verdictErrors(checked, talk.reveal);
  if (shape.length) row.fatal.push(`the verdict has the wrong shape: ${shape.slice(0, 3).join("; ")}`);
  row.checked = checked;
  row.verdicts = verdictWords(checked);
  row.matches = matchWords(fixture, parsed, checked, spoken);

  // 3. Leo's words.
  const answer = await wordAnswer(client, env, { checked, spoken });
  if (!answer || typeof answer.text !== "string" || !answer.text.trim() || answer.text.length > 320) {
    row.fatal.push(`no usable answer: ${JSON.stringify(answer)}`);
    return row;
  }
  row.answer = answer;
  const answerCall = calls.find((call) => call.step === "answer");
  row.source = answer.source;
  if (answerCall && answerCall.error) {
    const { code, fatal } = judge(answerCall.error);
    (fatal ? row.fatal : row.warnings).push(`wording the answer failed: ${code}`);
    row.source = `template (${code})`;
  } else if (answerCall && answer.source === "template" && !answerCall.message) {
    // Still on its way when the deadline passed.
    row.warnings.push("wording the answer timed out");
    row.source = "template (timeout)";
  } else if (answerCall && answer.source === "template") {
    try {
      row.turnedDown = messageText(answerCall.message);
      row.source = "template (guard)";
    } catch (error) {
      row.warnings.push(`Leo's wording came back unusable: ${failureCode(error)}`);
      row.source = `template (${failureCode(error)})`;
    }
  } else if (!answerCall) {
    row.source = checked.understood === false ? "template (not understood)" : "template (no call)";
  }
  if (answerCall && answerCall.message && !String(answerCall.message.model).startsWith(env.MODEL)) {
    row.warnings.push(`the answer came from ${answerCall.message.model}`);
  }
  return row;
}

/** One reading by Monolith, timed. Never fatal: without a voice the app speaks with the device's. */
async function tryVoice(env, text, audioPath) {
  if (!env.ELEVENLABS_API_KEY) return "Voice: not tried (no ELEVENLABS_API_KEY).";
  let status = "no answer";
  const recordingFetch = async (url, options) => {
    const response = await fetch(url, options);
    status = `HTTP ${response.status} ${(response.headers.get("content-type") || "").split(";")[0]}`;
    return response;
  };
  const started = Date.now();
  const audio = await speak(env, text, recordingFetch);
  const ms = Date.now() - started;
  if (!audio) return `Voice: ⚠️ Monolith didn't read it (${status}, ${(ms / 1000).toFixed(1)} s); the app would use the device's voice.`;
  const mp3 = (audio[0] === 0x49 && audio[1] === 0x44 && audio[2] === 0x33) || (audio[0] === 0xff && (audio[1] & 0xe0) === 0xe0);
  if (audioPath) writeFileSync(audioPath, audio);
  return `Voice: Monolith read ${text.length} characters in ${(ms / 1000).toFixed(1)} s: ${k(audio.length)}B of ${mp3 ? "MP3" : "audio that doesn't look like MP3 ⚠️"}${audioPath ? `, saved to ${audioPath}` : ""}.`;
}

function report(rows, env, voiceLine) {
  const lines = [
    `### Talk It Through, live (${env.MODEL}, effort ${env.PARSE_EFFORT}/${env.ANSWER_EFFORT})`,
    "",
    "| Case | Said | Heard | Verdicts | Matches fixture | Leo | Source | Parse s | Answer s | Tokens |",
    "|---|---|---|---|---|---|---|---|---|---|",
  ];
  const all = { input: 0, cacheRead: 0, cacheWrite: 0, output: 0 };
  for (const row of rows) {
    const usage = usageOf(row.calls);
    for (const key of Object.keys(all)) all[key] += usage[key];
    const parse = row.calls.find((call) => call.step === "parse");
    const answer = row.calls.find((call) => call.step === "answer");
    const flag = row.fatal.length ? "❌ " : row.warnings.length ? "⚠️ " : "";
    lines.push(
      `| ${flag}${cell(row.name)} | ${cell(row.said, 90)} | ${cell(row.heard)} | ${cell(row.verdicts)} | ${cell(row.matches)} | ` +
        `${cell(row.answer && row.answer.text)} | ${cell(row.source)} | ${seconds(parse)} | ${seconds(answer)} | ` +
        `${k(usage.input + usage.cacheRead + usage.cacheWrite)} in (${k(usage.cacheRead)} cached), ${k(usage.output)} out |`,
    );
  }
  const talks = rows.filter((row) => row.calls.length > 0).length || 1;
  lines.push(
    "",
    voiceLine,
    "",
    `Claude: ${k(all.input + all.cacheRead + all.cacheWrite)} tokens in (${k(all.cacheRead)} read from the cache, ${k(all.cacheWrite)} written to it), ` +
      `${k(all.output)} out (thinking included), about $${dollars(all).toFixed(4)} in all, $${(dollars(all) / talks).toFixed(4)} a talk at list prices.`,
  );
  const notes = rows.filter((row) => row.fatal.length || row.warnings.length || row.turnedDown);
  if (notes.length) {
    lines.push("", "<details><summary>Notes</summary>", "");
    for (const row of notes) {
      lines.push(`**${cell(row.name)}**`, "");
      for (const problem of row.fatal) lines.push(`- ❌ ${cell(problem)}`);
      for (const warning of row.warnings) lines.push(`- ⚠️ ${cell(warning)}`);
      if (row.turnedDown) lines.push(`- The guard turned down Claude's wording: ${cell(row.turnedDown)}`);
      lines.push("");
    }
    lines.push("</details>");
  }
  return lines.join("\n");
}

async function main() {
  const file = argument("--fixtures") || fileURLToPath(new URL("./fixtures/talks.json", import.meta.url));
  if (!existsSync(file)) {
    console.log(`No fixtures at ${file}: the live check needs coach/test/fixtures/talks.json (see make_facts.mjs).`);
    return 1;
  }
  const env = settings();
  if (!String(env.ANTHROPIC_API_KEY || "").trim()) {
    console.log("Set ANTHROPIC_API_KEY to run the live check.");
    return 1;
  }
  const only = argument("--only");
  const fixtures = JSON.parse(readFileSync(file, "utf8")).filter((fixture) => !only || String(fixture.name).includes(only));
  if (fixtures.length === 0) {
    console.log(`No cases in ${file}${only ? ` named like "${only}"` : ""}.`);
    return 1;
  }

  const rows = [];
  for (const fixture of fixtures) {
    let row;
    try {
      row = await runCase(fixture, env);
    } catch (error) {
      row = { name: String(fixture.name || "unnamed"), said: String(fixture.said || ""), fatal: [`crashed: ${error.stack || error}`], warnings: [], calls: [] };
    }
    rows.push(row);
    const parse = row.calls.find((call) => call.step === "parse");
    const answer = row.calls.find((call) => call.step === "answer");
    console.error(`${row.name}: parse ${seconds(parse)} s, answer ${seconds(answer)} s, ${row.source || "no answer"}${row.fatal.length ? `, FAILED: ${row.fatal[0]}` : ""}`);
  }

  const spoken = rows.find((row) => row.answer);
  const voiceLine = spoken ? await tryVoice(env, spoken.answer.text, argument("--audio")) : "Voice: not tried (no answer to read).";
  console.log(report(rows, env, voiceLine));

  const failed = rows.filter((row) => row.fatal.length);
  const cases = `${rows.length} case${rows.length === 1 ? "" : "s"}`;
  console.log(failed.length ? `\n❌ ${failed.length} of ${cases} broke (see Notes).` : `\n${cases} ran; nothing broke.`);
  return failed.length ? 1 : 0;
}

process.exitCode = await main();
