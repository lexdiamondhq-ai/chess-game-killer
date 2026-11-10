// The deep review for real, in Node instead of Workers: the game in
// test/fixtures/review-game.json is checked (review.js), Claude writes Leo's
// review of it, the review is checked against the engine's grades, and one
// part is read aloud (voice.js) when there's an ElevenLabs key. It prints the
// review in Markdown, which the workflow adds to the pull request's checks.
//
//   ANTHROPIC_API_KEY=… [ELEVENLABS_API_KEY=…] node coach/test/review-live.mjs
//     [--game other.json] [--audio part.mp3]
//
// The settings are wrangler.toml's [vars]; an environment variable of the
// same name wins (REVIEW_MODEL=claude-fable-5-2, say). It exits with 1 only
// when something is broken: a crash, a game the server would refuse, a reply
// that isn't a review, or Anthropic refusing the request itself (a 4xx other
// than 429). A busy API, a timeout and a failing voice are reported for a
// person to read, not failed.

import Anthropic from "@anthropic-ai/sdk";
import { readFileSync, writeFileSync } from "node:fs";
import { failureCode } from "../src/claims.js";
import { makeClient } from "../src/index.js";
import { checkReview, reviewModel, writeReview } from "../src/review.js";
import { speak } from "../src/voice.js";

// List prices in dollars per million tokens, input and output.
const PRICES = { "claude-opus-5-5": [4, 20], "claude-fable-5-2": [8, 40], "claude-sonnet-5-5": [2, 10] };

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

/** Whether a failed call means our side is broken, or the API was busy, slow or careful. */
function fatal(error) {
  if (error instanceof Anthropic.APIError && !(error instanceof Anthropic.APIConnectionError) && !(error instanceof Anthropic.APIUserAbortError)) {
    const status = Number(error.status);
    return status >= 400 && status < 500 && status !== 429;
  }
  return !["timeout", "connection", "rate_limited", "refusal"].includes(failureCode(error));
}

const env = settings();
if (!env.ANTHROPIC_API_KEY) {
  console.log("No ANTHROPIC_API_KEY: nothing to check.");
  process.exit(0);
}

const path = argument("--game") || new URL("./fixtures/review-game.json", import.meta.url);
const checked = checkReview(JSON.parse(readFileSync(path, "utf8")));
if (!checked.ok) {
  console.log(`The server would refuse this game: ${checked.detail}`);
  process.exit(1);
}

// The review's client, with what Claude sent back written down.
const real = makeClient(env);
let message = null;
const client = {
  beta: {
    messages: {
      create: async (params, options) => (message = await real.beta.messages.create(params, options)),
    },
  },
};

const model = reviewModel(env);
console.log(`## Leo's deep review (${model}, ${env.REVIEW_EFFORT || "medium"})\n`);
const started = Date.now();
let parts;
try {
  parts = await writeReview(client, env, checked.review);
} catch (error) {
  const seconds = ((Date.now() - started) / 1000).toFixed(1);
  console.log(`**No review** after ${seconds} s: \`${failureCode(error)}\` ${error && error.message ? error.message : ""}`);
  if (message) console.log(`\nWhat came back (stop reason \`${message.stop_reason}\`):\n\n\`\`\`\n${JSON.stringify(message.content).slice(0, 4000)}\n\`\`\``);
  process.exit(fatal(error) ? 1 : 0);
}
const seconds = ((Date.now() - started) / 1000).toFixed(1);

const words = parts.reduce((sum, part) => sum + part.text.split(/\s+/).filter(Boolean).length, 0);
const characters = parts.reduce((sum, part) => sum + part.text.length, 0);
const usage = (message && message.usage) || {};
const input = (usage.input_tokens || 0) + (usage.cache_read_input_tokens || 0) + (usage.cache_creation_input_tokens || 0);
const output = usage.output_tokens || 0;
const served = (message && message.model) || model;
const price = PRICES[served] || PRICES[model];
const cents = price ? ((input * price[0] + output * price[1]) / 1e6) * 100 : null;

console.log("| Move | Chapter | Kind | Leo says |");
console.log("|---|---|---|---|");
for (const part of parts) {
  const ply = part.ply === null ? null : checked.review.plies[part.ply - 1];
  const move = ply ? `${ply.number}${ply.color === "w" ? "." : "..."} ${ply.san}` : "";
  console.log(`| ${move} | ${part.label} | ${part.kind} | ${part.text.replace(/\|/g, "/")} |`);
}
console.log("");
console.log(`${parts.length} parts, ${words} words, ${characters} characters to voice, ${seconds} s.`);
console.log(`Served by \`${served}\`: ${input} tokens in, ${output} out${cents === null ? "" : `, about ${cents.toFixed(1)}¢ at list prices`}.`);

if (!env.ELEVENLABS_API_KEY) {
  console.log("\nNo ELEVENLABS_API_KEY: the voice wasn't checked.");
  process.exit(0);
}
// One part is enough to hear that the voice works in the middle of a review.
const index = Math.min(1, parts.length - 1);
const around = { before: index > 0 ? parts[index - 1].text : "", after: index + 1 < parts.length ? parts[index + 1].text : "" };
const voiceStarted = Date.now();
try {
  const audio = await speak(env, parts[index].text, fetch, checked.review.coach, around);
  const took = ((Date.now() - voiceStarted) / 1000).toFixed(1);
  if (audio && audio.byteLength > 0) {
    console.log(`\nPart ${index + 1} read aloud: ${Math.round(audio.byteLength / 1024)} KB of mp3 in ${took} s.`);
    const out = argument("--audio");
    if (out) writeFileSync(out, audio);
  } else {
    console.log(`\nThe voice came back empty after ${took} s.`);
  }
} catch (error) {
  console.log(`\nThe voice failed: ${error && error.message ? error.message : error}`);
}
