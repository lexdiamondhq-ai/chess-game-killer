// Tries the test boards with different models and effort levels, straight
// against the Claude API, and prints how many squares each got right and how
// long it took. Run it from the "Scanner server" workflow (Run workflow, with
// "compare" filled in) to pick the MODEL and EFFORT in wrangler.toml.
// Usage: ANTHROPIC_API_KEY=... node scanner/test/compare.mjs claude-sonnet-5-5:high claude-opus-5-5:high
import { readFile } from "node:fs/promises";
import { join } from "node:path";
import { apiKey, buildRequest, normalize } from "../src/index.js";

const folder = new URL("./boards/", import.meta.url).pathname;
const expected = JSON.parse(await readFile(join(folder, "expected.json"), "utf8"));
const key = apiKey(process.env);
const configs = process.argv.slice(2).flatMap((arg) => arg.split(/[\s,]+/)).filter(Boolean);
if (!key || configs.length === 0) {
  console.log("Needs ANTHROPIC_API_KEY and at least one model:effort.");
  process.exit(1);
}

/** FEN placement to 8 strings, rank 8 first, files a to h. */
function grid(placement) {
  return placement.split("/").map((row) => row.replace(/\d/g, (n) => ".".repeat(Number(n))));
}

/** Rows as seen in the picture to rank 8..1, files a..h (same as the app). */
function toWhiteView(rows, side) {
  const board = Array.from({ length: 8 }, () => Array(8).fill("."));
  rows.forEach((text, r) => {
    [...text].forEach((ch, c) => {
      const [file, rank] =
        side === "bottom" ? [c, 7 - r] : side === "top" ? [7 - c, r] : side === "left" ? [r, c] : [7 - r, 7 - c];
      board[7 - rank][file] = ch;
    });
  });
  return board.map((row) => row.join(""));
}

async function read(bytes, model, effort) {
  const response = await fetch("https://api.anthropic.com/v1/messages", {
    method: "POST",
    headers: { "x-api-key": key, "anthropic-version": "2023-06-01", "content-type": "application/json" },
    body: JSON.stringify(buildRequest(bytes, "image/png", model, effort)),
  });
  const message = await response.json();
  if (!response.ok) throw new Error(`${response.status} ${message.error?.message}`);
  const text = (message.content || []).find((block) => block.type === "text");
  if (!text) throw new Error(`no answer (${message.stop_reason})`);
  return { answer: normalize(JSON.parse(text.text)), usage: message.usage || {} };
}

for (const config of configs) {
  const [model, effort] = config.split(":");
  let total = 0;
  const lines = [];
  for (const [name, want] of Object.entries(expected)) {
    const bytes = new Uint8Array(await readFile(join(folder, name)));
    const started = Date.now();
    try {
      const { answer, usage } = await read(bytes, model, effort);
      const seconds = ((Date.now() - started) / 1000).toFixed(0);
      if (!answer.found) {
        lines.push(`  ${name}: no board found, ${seconds} s`);
        continue;
      }
      const got = toWhiteView(answer.rows, answer.white_side);
      const truth = grid(want.placement);
      let right = 0;
      for (let r = 0; r < 8; r++) for (let c = 0; c < 8; c++) if (got[r][c] === truth[r][c]) right++;
      total += right;
      const side = answer.white_side === want.white_side ? "" : " (wrong side)";
      lines.push(`  ${name}: ${right}/64${side}, ${seconds} s, ${usage.output_tokens ?? "?"} output tokens`);
    } catch (error) {
      lines.push(`  ${name}: failed: ${error.message}`);
    }
  }
  console.log(`${model} ${effort || "default"}: ${total}/${64 * Object.keys(expected).length} squares`);
  for (const line of lines) console.log(line);
}
