// Times the photo reader: each setting reads every test board twice and
// reports squares right and seconds (1 decimal). A setting is model:effort,
// plus optional flags joined with "+":
//   +compact  rows come back as 8 strings ("rnbqkbnr") instead of 64 one-square entries
//   +small    the smaller pictures in boards-small/ (photos 1024 px, screenshots 640 px)
// "live:N" posts to the real scanner server with X-Scan-Count N (1 = fast model, 101 = slow).
// Usage: ANTHROPIC_API_KEY=... node scanner/test/speed.mjs claude-opus-5-5:low claude-opus-5-5:low+compact live:1
import { readFile } from "node:fs/promises";
import { join } from "node:path";
import { SCHEMA, apiKey, buildRequest, normalize, whiteView } from "../src/index.js";

const base = new URL("./", import.meta.url).pathname;
const expected = JSON.parse(await readFile(join(base, "boards", "expected.json"), "utf8"));
const key = apiKey(process.env);
const live = process.env.SCANNER_URL || "https://chess-game-killer-scanner.chess-game-killer.workers.dev";
const configs = process.argv.slice(2).flatMap((arg) => arg.split(/[\s,]+/)).filter(Boolean);
const ROUNDS = 2;

const COMPACT = structuredClone(SCHEMA);
COMPACT.properties.rows = {
  type: "array",
  description:
    "The 8 rows of squares exactly as they appear in the picture, top row first. Each row is one string of exactly 8 characters, its squares from left to right: K Q R B N P for White, k q r b n p for Black, . for empty.",
  items: { type: "string" },
};

function grid(placement) {
  return placement.split("/").map((row) => row.replace(/\d/g, (n) => ".".repeat(Number(n))));
}

function picture(name, small) {
  if (!small) return { path: join(base, "boards", name), type: name.endsWith(".jpg") ? "image/jpeg" : "image/png" };
  return { path: join(base, "boards-small", name.replace(/\.png$/, ".jpg")), type: "image/jpeg" };
}

async function direct(bytes, type, model, effort, compact) {
  const body = buildRequest(bytes, type, model, effort);
  if (compact) body.output_config.format.schema = COMPACT;
  const response = await fetch("https://api.anthropic.com/v1/messages", {
    method: "POST",
    headers: { "x-api-key": key, "anthropic-version": "2023-06-01", "content-type": "application/json" },
    body: JSON.stringify(body),
  });
  const message = await response.json();
  if (!response.ok) throw new Error(`${response.status} ${message.error?.message}`);
  const text = (message.content || []).find((block) => block.type === "text");
  if (!text) throw new Error(`no answer (${message.stop_reason})`);
  return { answer: normalize(JSON.parse(text.text)), tokens: message.usage?.output_tokens };
}

async function server(bytes, type, count) {
  const response = await fetch(`${live}/read`, {
    method: "POST",
    headers: { "content-type": type, "x-scan-count": String(count) },
    body: bytes,
  });
  if (!response.ok) throw new Error(`${response.status} ${await response.text()}`);
  return { answer: await response.json(), tokens: "?" };
}

for (const config of configs) {
  const [head, ...flags] = config.split("+");
  const [model, effort] = head.split(":");
  const compact = flags.includes("compact");
  const small = flags.includes("small");
  let right = 0;
  let squares = 0;
  const times = [];
  const lines = [];
  for (const [name, want] of Object.entries(expected)) {
    const { path, type } = picture(name, small);
    const bytes = new Uint8Array(await readFile(path));
    for (let round = 0; round < ROUNDS; round++) {
      const started = Date.now();
      try {
        const { answer, tokens } =
          model === "live" ? await server(bytes, type, Number(effort) || 1) : await direct(bytes, type, model, effort, compact);
        const seconds = (Date.now() - started) / 1000;
        times.push(seconds);
        if (!answer.found) {
          lines.push(`  ${name}: no board, ${seconds.toFixed(1)} s`);
          squares += 64;
          continue;
        }
        const got = whiteView(answer.rows, answer.white_side);
        const truth = grid(want.placement);
        let ok = 0;
        for (let r = 0; r < 8; r++) for (let c = 0; c < 8; c++) if (got[r][c] === truth[r][c]) ok++;
        right += ok;
        squares += 64;
        const side = answer.white_side === want.white_side ? "" : " (wrong side)";
        lines.push(`  ${name}: ${ok}/64${side}, ${seconds.toFixed(1)} s, ${tokens ?? "?"} output tokens`);
      } catch (error) {
        squares += 64;
        lines.push(`  ${name}: failed: ${error.message}`);
      }
    }
  }
  times.sort((a, b) => a - b);
  const median = times.length ? times[Math.floor(times.length / 2)].toFixed(1) : "?";
  const worst = times.length ? times[times.length - 1].toFixed(1) : "?";
  console.log(`\n**${config}**: ${right}/${squares} squares, median ${median} s, slowest ${worst} s`);
  for (const line of lines) console.log(line);
}
