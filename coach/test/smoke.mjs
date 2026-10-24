// A quick end-to-end check of a deployed coach, run by the deploy workflow
// right after each deploy:
//
//   node coach/test/smoke.mjs https://coach.chess-game-killer.workers.dev
//
// It checks that the server answers, that it turns a broken request down,
// and that one real talk streams `checked`, then `answer`, then `voice`
// (Monolith's MP3, or why not), then `done`. The talk is the first case of
// test/fixtures/talks.json, or the protocol's own example without it. It
// costs two Claude calls and one short voice reading, and counts toward the
// day's budget. Exits with 1 on any failure.

import { readFileSync } from "node:fs";

const base = String(process.argv[2] || "").replace(/\/+$/, "");
if (!/^https?:\/\/[^/]+$/.test(base)) {
  console.error("Usage: node smoke.mjs https://coach.example.workers.dev");
  process.exit(2);
}

// Two Claude calls (12 s each at most) and a voice reading (8 s) fit well inside this.
const TALK_TIMEOUT_MS = 60000;
const UNAVAILABLE = new Set(["budget", "upstream", "not_configured"]);

// The example in PROTOCOL.md: Black's bishop eyes f2, and castling is best.
const EXAMPLE = {
  name: "the protocol's example",
  fen: "r1bqk2r/pppp1ppp/2n2n2/2b1p3/2B1P3/3P1N2/PPP2PPP/RNBQK2R w KQkq - 1 5",
  said: "his bishop eyes f2 so I'll castle, and my knight on f3 is safe",
  lastMove: "f8c5",
  facts: {
    depth: 12,
    moves: [
      { uci: "e1g1", eval: { cp: 31 }, pv: ["e1g1", "d7d6", "c2c3"] },
      { uci: "c2c3", eval: { cp: 28 }, pv: ["c2c3", "d7d6", "e1g1"] },
    ],
    threats: [{ uci: "c5f2", eval: { cp: -120 }, pv: ["c5f2", "e1f2", "f6g4"] }],
  },
};

const pause = (ms) => new Promise((resolve) => setTimeout(resolve, ms));

function check(condition, message) {
  if (!condition) throw new Error(message);
}

/** A fresh deploy can take a few seconds to answer everywhere. */
async function waitUntilUp() {
  let last = "no answer";
  for (let attempt = 0; attempt < 30; attempt += 1) {
    try {
      const response = await fetch(`${base}/`, { signal: AbortSignal.timeout(10000) });
      const text = await response.text();
      if (response.status === 200 && text.includes('"ok":true')) return;
      last = `HTTP ${response.status} ${text.slice(0, 100)}`;
    } catch (error) {
      last = error.message;
    }
    await pause(2000);
  }
  throw new Error(`${base}/ didn't answer {"ok":true} within a minute (${last})`);
}

/** The first fixture, or the protocol's example when there are no fixtures yet. */
function theTalk() {
  let fixture = EXAMPLE;
  try {
    const [first] = JSON.parse(readFileSync(new URL("./fixtures/talks.json", import.meta.url), "utf8"));
    if (first && typeof first.fen === "string" && typeof first.said === "string") fixture = first;
  } catch {
    // No fixtures yet: the example will do.
  }
  const body = { v: 1, fen: fixture.fen, said: fixture.said, typed: fixture.typed === true, reveal: fixture.reveal === true, context: "game", voice: true };
  if (fixture.lastMove) body.lastMove = fixture.lastMove;
  if (fixture.facts) body.facts = fixture.facts;
  return { name: fixture.name || "the first fixture", body };
}

/** Reads the NDJSON stream to its end: each line, how long after the request it came, and in which chunk. */
async function readLines(response, started) {
  const reader = response.body.getReader();
  const decoder = new TextDecoder();
  const lines = [];
  let buffer = "";
  for (let chunk = 0; ; chunk += 1) {
    const { value, done } = await reader.read();
    buffer += decoder.decode(value || new Uint8Array(0), { stream: !done });
    let newline = buffer.indexOf("\n");
    while (newline >= 0) {
      const text = buffer.slice(0, newline).trim();
      buffer = buffer.slice(newline + 1);
      if (text) {
        let line;
        try {
          line = JSON.parse(text);
        } catch {
          throw new Error(`a line isn't JSON: ${text.slice(0, 200)}`);
        }
        lines.push({ line, at: Date.now() - started, chunk });
      }
      newline = buffer.indexOf("\n");
    }
    if (done) break;
  }
  check(buffer.trim() === "", `the stream ended in the middle of a line: ${buffer.slice(0, 200)}`);
  return lines;
}

function checkChecked(line) {
  check(typeof line.understood === "boolean", `checked.understood is ${JSON.stringify(line.understood)}`);
  check(line.player === "white" || line.player === "black", `checked.player is ${JSON.stringify(line.player)}`);
  check(Array.isArray(line.claims) && line.claims.length <= 6, "checked.claims isn't a list of at most 6");
  for (const claim of line.claims) {
    check(claim && typeof claim.kind === "string" && ["right", "wrong", "partly", "unclear"].includes(claim.verdict), `a claim is ${JSON.stringify(claim)}`);
  }
  check(line.move === null || (line.move && typeof line.move.grade === "string"), `checked.move is ${JSON.stringify(line.move)}`);
  check(Array.isArray(line.missed), "checked.missed isn't a list");
  check(line.habits && typeof line.habits === "object", "checked.habits is missing");
}

/** Prints the last line, and exits once it's written (the workflow pipes this into the summary). */
function finish(code, message) {
  process.stdout.write(`${message}\n`, () => process.exit(code));
}

const steps = [];
const notes = [];
function done(step) {
  steps.push(step);
  console.log(`- ${step}`);
}

try {
  await waitUntilUp();
  done("the server answers");

  const missing = await fetch(`${base}/nope`, { signal: AbortSignal.timeout(10000) });
  await missing.text();
  check(missing.status === 404, `GET /nope: HTTP ${missing.status}`);
  const broken = await fetch(`${base}/talk`, {
    method: "POST",
    headers: { "content-type": "application/json" },
    body: "{",
    signal: AbortSignal.timeout(10000),
  });
  const brokenText = await broken.text();
  check(broken.status === 400 && brokenText.includes('"bad_request"'), `POST /talk with broken JSON: HTTP ${broken.status} ${brokenText.slice(0, 200)}`);
  done("it turns down a wrong path and a broken talk");

  const { name, body } = theTalk();
  const started = Date.now();
  const response = await fetch(`${base}/talk`, {
    method: "POST",
    headers: { "content-type": "application/json" },
    body: JSON.stringify(body),
    signal: AbortSignal.timeout(TALK_TIMEOUT_MS),
  });
  if (response.status !== 200) {
    throw new Error(`POST /talk (${name}): HTTP ${response.status} ${(await response.text()).slice(0, 300)}`);
  }
  check((response.headers.get("content-type") || "").startsWith("application/x-ndjson"), `the talk's content type is ${response.headers.get("content-type")}`);
  const lines = await readLines(response, started);
  const types = lines.map(({ line }) => line.type);
  const error = lines.find(({ line }) => line.type === "error");
  check(!error, `the talk ended with an error line: ${JSON.stringify(error && error.line)} (after ${types.join(", ")})`);
  check(types.join(",") === "checked,answer,voice,done", `the lines came as ${types.join(", ") || "nothing"}`);
  const [checked, answer, voice] = lines.map(({ line }) => line);

  checkChecked(checked);
  done(`${name}: checked, with ${checked.claims.length} claims and ${checked.move ? `the move ${checked.move.san || "(not legal)"} graded ${checked.move.grade}` : "no move"}`);

  check(typeof answer.text === "string" && answer.text.trim() !== "" && answer.text.length <= 320, `answer.text is ${JSON.stringify(answer.text)}`);
  check(answer.source === "leo" || answer.source === "template", `answer.source is ${JSON.stringify(answer.source)}`);
  if (answer.source === "template") notes.push("Leo's words came from the template: Claude was slow, failed or named an unchecked square.");
  done(`Leo says (${answer.source}): ${answer.text}`);

  if (voice.unavailable !== undefined) {
    check(UNAVAILABLE.has(voice.unavailable), `voice.unavailable is ${JSON.stringify(voice.unavailable)}`);
    notes.push(`No voice (${voice.unavailable}): the app would read the answer with the device's voice.`);
    done(`the voice is unavailable: ${voice.unavailable}`);
  } else {
    check(voice.format === "mp3" && typeof voice.audio === "string", `the voice line is ${JSON.stringify(voice).slice(0, 200)}`);
    const audio = Buffer.from(voice.audio, "base64");
    const mp3 = audio.subarray(0, 3).toString("latin1") === "ID3" || (audio[0] === 0xff && (audio[1] & 0xe0) === 0xe0);
    check(audio.length > 1000 && mp3, `the voice isn't an MP3 (${audio.length} bytes)`);
    done(`Monolith read it: ${Math.round(audio.length / 1024)} KB of MP3`);
  }

  const timing = lines.map(({ line, at }) => `${line.type} ${(at / 1000).toFixed(1)} s`).join(", ");
  done(`arrival: ${timing}`);
  if (lines.length > 1 && lines[0].chunk === lines[lines.length - 1].chunk) {
    notes.push("Every line came at once: something on the way buffers the stream, so the app gets `checked` no sooner than the rest.");
  }

  for (const note of notes) console.log(`- Note: ${note}`);
  finish(0, `\nSmoke test passed (${steps.length} steps).`);
} catch (error) {
  finish(1, `\nSmoke test FAILED: ${error.message}`);
}
