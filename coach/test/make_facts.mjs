// Fills in Stockfish's numbers ("facts") for every case of a fixture file, the way the app works
// them out while the player talks: every legal move of P (MultiPV, at most 40 lines) at depth 12
// from the player's view, and the null-move position N (P with the opponent to move) at MultiPV
// 6, depth 12, from the opponent's view. N is skipped when the player is in check. Lines keep at
// most 10 moves; evals are UCI's own ({ cp } or { mate }), from the side to move at that root.
//
// Stockfish isn't a dependency of the coach. Install the WASM build somewhere else, then run:
//
//   mkdir -p /tmp/sf && (cd /tmp/sf && npm install stockfish@17.1.0)
//   node coach/test/make_facts.mjs coach/test/fixtures/talks.json \
//     --engine /tmp/sf/node_modules/stockfish/src/stockfish-17.1-single-a496a04.js
//
// (STOCKFISH=<path> works instead of --engine.) The file is rewritten in place: the same cases in
// the same order, each with its facts. One thread, a cleared hash before every search and a fixed
// depth make the numbers come out the same on every run.

import { spawn } from "node:child_process";
import { readFileSync, writeFileSync } from "node:fs";
import { Position } from "../src/board.js";

const DEPTH = 12;
const MOVE_LINES = 40;
const THREAT_LINES = 6;
const PV_LENGTH = 10;

function argument(name) {
  const index = process.argv.indexOf(name);
  return index > 0 ? process.argv[index + 1] : undefined;
}

/** A UCI engine in a child process: send commands, wait for a line. */
class Engine {
  constructor(path) {
    this.child = spawn(process.execPath, [path], { stdio: ["pipe", "pipe", "inherit"] });
    this.buffer = "";
    this.listeners = [];
    this.child.stdout.setEncoding("utf8");
    this.child.stdout.on("data", (chunk) => {
      this.buffer += chunk;
      let newline = this.buffer.indexOf("\n");
      while (newline >= 0) {
        const line = this.buffer.slice(0, newline).trim();
        this.buffer = this.buffer.slice(newline + 1);
        for (const listener of [...this.listeners]) listener(line);
        newline = this.buffer.indexOf("\n");
      }
    });
  }

  send(command) {
    this.child.stdin.write(`${command}\n`);
  }

  /** Sends a command and collects output lines until one starts with `until`. */
  ask(command, until) {
    return new Promise((resolve) => {
      const lines = [];
      const listener = (line) => {
        lines.push(line);
        if (line.startsWith(until)) {
          this.listeners = this.listeners.filter((other) => other !== listener);
          resolve(lines);
        }
      };
      this.listeners.push(listener);
      this.send(command);
    });
  }

  async start() {
    await this.ask("uci", "uciok");
    this.send("setoption name Threads value 1");
    this.send("setoption name Hash value 16");
    await this.ask("isready", "readyok");
  }

  /** The engine's best `lines` lines from `fen` at the fixed depth, best first. */
  async analyze(fen, lines) {
    this.send("ucinewgame");
    this.send(`setoption name MultiPV value ${lines}`);
    await this.ask("isready", "readyok");
    this.send(`position fen ${fen}`);
    const output = await this.ask(`go depth ${DEPTH}`, "bestmove");
    return readLines(output);
  }

  stop() {
    this.send("quit");
    this.child.stdin.end();
  }
}

const INFO = /^info .*?\bdepth (\d+)\b.*?\bmultipv (\d+)\b.*?\bscore (cp|mate) (-?\d+)( (?:upper|lower)bound)?\b.*?\bpv (.+)$/;

/** The last exact line for each MultiPV slot at the deepest depth reached, in slot order. */
function readLines(output) {
  const slots = new Map();
  for (const line of output) {
    const match = INFO.exec(line);
    if (!match || match[5]) continue;
    const depth = Number(match[1]);
    const slot = Number(match[2]);
    const previous = slots.get(slot);
    if (previous && previous.depth > depth) continue;
    const evaluation = match[3] === "cp" ? { cp: Number(match[4]) } : { mate: Number(match[4]) };
    const pv = match[6].trim().split(/\s+/).slice(0, PV_LENGTH);
    slots.set(slot, { depth, line: { uci: pv[0], eval: evaluation, pv } });
  }
  return [...slots.keys()].sort((a, b) => a - b).map((slot) => slots.get(slot).line);
}

async function factsFor(engine, fen) {
  const position = new Position(fen);
  const moves = await engine.analyze(position.fen, Math.min(MOVE_LINES, position.legal.length));
  const opponent = position.nullMove();
  const threats = opponent ? await engine.analyze(opponent.fen, Math.min(THREAT_LINES, opponent.legal.length)) : [];
  return { depth: DEPTH, moves, threats };
}

// The fixture's own key order, so a regenerated file only differs where the numbers do.
const KEY_ORDER = ["name", "fen", "said", "typed", "reveal", "lastMove", "facts", "parsed", "expect", "notes"];

function ordered(fixture) {
  const out = {};
  for (const key of KEY_ORDER) if (key in fixture) out[key] = fixture[key];
  for (const key of Object.keys(fixture)) if (!(key in out)) out[key] = fixture[key];
  return out;
}

/** JSON with two-space indents, but each engine line on one line of its own, so the file stays readable. */
function format(value, indent = "") {
  const inner = `${indent}  `;
  if (Array.isArray(value)) {
    if (!value.length) return "[]";
    if (value.every((item) => typeof item !== "object" || item === null)) return JSON.stringify(value);
    return `[\n${value.map((item) => inner + format(item, inner)).join(",\n")}\n${indent}]`;
  }
  if (value && typeof value === "object") {
    if ("uci" in value && "eval" in value && "pv" in value) return JSON.stringify(value);
    const pairs = Object.entries(value).map(([key, item]) => `${JSON.stringify(key)}: ${JSON.stringify(item)}`);
    const flat = Object.values(value).every((item) => typeof item !== "object" || item === null);
    if (flat && pairs.join(", ").length < 72) return `{ ${pairs.join(", ")} }`;
    const entries = Object.entries(value).map(([key, item]) => `${inner}${JSON.stringify(key)}: ${format(item, inner)}`);
    return `{\n${entries.join(",\n")}\n${indent}}`;
  }
  return JSON.stringify(value);
}

async function main() {
  const file = process.argv[2];
  const enginePath = argument("--engine") ?? process.env.STOCKFISH;
  if (!file || !enginePath) {
    console.error("usage: node coach/test/make_facts.mjs <fixtures.json> --engine <stockfish.js>");
    process.exit(2);
  }
  const fixtures = JSON.parse(readFileSync(file, "utf8"));
  const engine = new Engine(enginePath);
  await engine.start();
  const out = [];
  for (const fixture of fixtures) {
    const facts = await factsFor(engine, fixture.fen);
    out.push(ordered({ ...fixture, facts }));
    console.error(`${fixture.name}: ${facts.moves.length} moves, ${facts.threats.length} threats`);
  }
  engine.stop();
  writeFileSync(file, `${format(out)}\n`);
}

main().catch((error) => {
  console.error(error);
  process.exit(1);
});
