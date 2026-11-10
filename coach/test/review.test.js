import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { test } from "node:test";
import { ClaudeFailure } from "../src/claims.js";
import { TalkBudget, createHandler } from "../src/index.js";
import {
  KINDS,
  MAX_REVIEW_CHARS,
  REVIEW_SCHEMA,
  buildReviewRequest,
  checkParts,
  checkReview,
  describeGame,
  movesNamed,
  reviewPrompt,
  reviewTimeoutMs,
  writeReview,
} from "../src/review.js";

const GAME = JSON.parse(readFileSync(new URL("./fixtures/review-game.json", import.meta.url), "utf8"));
const MP3 = new Uint8Array([0xff, 0xfb, 0x90, 0x64, 0, 1, 2, 3]);

/** The fixture game, checked. */
function checked(change = {}) {
  const result = checkReview({ ...GAME, ...change });
  assert.equal(result.ok, true, result.detail);
  return result.review;
}

const LONG = "You castled early and built a real centre, and that is exactly how the opening should be played against a stronger opponent.";
/** A review as Claude would send it: an opening word, praise, the story's mistakes and a habit. */
const RAW = {
  parts: [
    { label: "The opening", kind: "intro", move: 0, by: "none", better: "", text: LONG },
    { label: "The opening", kind: "praise", move: 12, by: "player", better: "", text: `On move 12, pawn to e5 hit back in the centre. ${LONG}` },
    { label: "The pawn on d4", kind: "mistake", move: 10, by: "player", better: "cxd4", text: `On move 10 you played bishop to f4, when taking back with the c-pawn kept the game level. ${LONG}` },
    { label: "The pawn on d4", kind: "mistake", move: 13, by: "player", better: "cxd4", text: "On move thirteen the same pawn was still there to take." },
    { label: "The end", kind: "moment", move: 28, by: "opponent", better: "", text: "And on move 28 the queen landed on g2." },
    { label: "One habit", kind: "habit", move: 0, by: "none", better: "", text: "When they take something, ask whether you can take back." },
  ],
};

// ---------------------------------------------------------------------------
// The request

test("a game is replayed by the rules and its grades attached to the player's moves", () => {
  const review = checked();
  assert.equal(review.player, "w");
  assert.equal(review.rival, "The Berserker");
  assert.equal(review.result, "loss");
  assert.equal(review.ending, "checkmate");
  assert.equal(review.coach, "leo");
  assert.equal(review.voice, true);
  assert.equal(review.plies.length, 56);
  const tenth = review.plies[18];
  assert.deepEqual(
    { number: tenth.number, color: tenth.color, san: tenth.san, byPlayer: tenth.byPlayer, grade: tenth.grade, best: tenth.best },
    { number: 10, color: "w", san: "Bf4", byPlayer: true, grade: "mistake", best: "cxd4" },
  );
  assert.equal(tenth.line[0], "cxd4");
  // The opponent's moves carry no grade.
  assert.equal(review.plies[19].byPlayer, false);
  assert.equal(review.plies[19].grade, undefined);
  // A best move is the move played: no better move to name.
  assert.equal(review.plies[0].best, undefined);
});

test("what can't be a review is refused", () => {
  const refused = (change, pattern) => {
    const result = checkReview({ ...GAME, ...change });
    assert.equal(result.ok, false);
    assert.match(result.detail, pattern);
  };
  assert.equal(checkReview(null).ok, false);
  refused({ v: 2 }, /"v"/);
  refused({ player: "red" }, /"player"/);
  refused({ result: "unfinished" }, /"result"/);
  refused({ moves: "e4 e5" }, /"moves"/);
  refused({ moves: GAME.moves.slice(0, 6) }, /too short/);
  refused({ moves: Array.from({ length: 700 }, () => "e4") }, /too long/);
  refused({ moves: ["e4", "e5", "Ke3", ...GAME.moves.slice(3)] }, /Move 3 .* isn't legal/);
  refused({ start: "not a position" }, /"start"/);
  refused({ graded: [] }, /"graded"/);
  refused({ graded: [{ ply: 2, grade: "best" }] }, /"graded"/);
});

test("grades the server can't use are dropped, not refused", () => {
  const review = checked({
    graded: [
      { ply: 1, grade: "best", before: 0.04, after: 0.05 },
      { ply: 2, grade: "blunder" }, // the opponent's move
      { ply: 3, grade: "superb" }, // not a grade
      { ply: 5, grade: "mistake", before: 5, after: "low", best: "Qh5" }, // the knight is in the way: not legal
      { ply: 7, grade: "inaccuracy", before: 0.1, after: 0, line: ["Nc3", "Bb4", "Qxh7"] },
      { ply: 999, grade: "best" },
      "nonsense",
    ],
  });
  assert.equal(review.plies[1].grade, undefined);
  assert.equal(review.plies[2].grade, undefined);
  assert.equal(review.plies[4].grade, "mistake");
  assert.equal(review.plies[4].best, undefined);
  assert.equal(review.plies[4].before, 1);
  assert.equal(review.plies[4].after, null);
  // The line is cut at its first move that isn't one.
  assert.deepEqual(review.plies[6].line, ["Nc3", "Bb4"]);
});

test("the names, ratings, coach and voice are cleaned", () => {
  const review = checked({ rival: "  The\u0000 Berserker\n", rating: 99999, rivalRating: "1600", coach: "vera", voice: false });
  assert.equal(review.rival, "The Berserker");
  assert.equal(review.rating, null);
  assert.equal(review.rivalRating, null);
  assert.equal(review.coach, "vera");
  assert.equal(review.voice, false);
  assert.equal(checked({ rival: 7 }).rival, "your opponent");
});

test("a game from a position of its own is replayed from there", () => {
  const start = "rnbqkbnr/pppppppp/8/8/4P3/8/PPPP1PPP/RNBQKBNR b KQkq - 0 1";
  const review = checked({
    start,
    player: "black",
    moves: GAME.moves.slice(1, 21),
    graded: [{ ply: 1, grade: "best", before: 0, after: 0 }],
  });
  assert.equal(review.player, "b");
  assert.deepEqual(
    { number: review.plies[0].number, color: review.plies[0].color, byPlayer: review.plies[0].byPlayer },
    { number: 1, color: "b", byPlayer: true },
  );
  assert.equal(review.plies[1].number, 2);
  assert.equal(review.ending, "");
});

// ---------------------------------------------------------------------------
// The game in words

test("the game is described move by move, with costs only on costly moves", () => {
  const text = describeGame(checked());
  assert.match(text, /^The player had White, rated about 1350\. Black was The Berserker, rated about 1600\.$/m);
  assert.match(text, /^The player lost by checkmate\. It lasted 28 moves\.$/m);
  assert.match(text, /^10\. Bf4 \| player \| mistake \| chances \d+% to \d+% \| engine wanted cxd4 \(line: cxd4 [^)]+\)$/m);
  assert.match(text, /^10\.\.\. Bxf3 \| opponent$/m);
  // A well-played move names no better one, even when the engine preferred another.
  assert.match(text, /^5\. Qe2 \| player \| good \| chances \d+% to \d+%$/m);
  assert.match(text, /^28\.\.\. Qg2# \| opponent$/m);
});

test("a game that didn't end on the board says so", () => {
  const text = describeGame(checked({ moves: GAME.moves.slice(0, 40), result: "win" }));
  assert.match(text, /The player won\. The game did not end on the board: someone resigned or ran out of time\. It lasted 20 moves\./);
});

// ---------------------------------------------------------------------------
// The request to Claude

test("the review is asked of Opus, thinking a little, in the review's shape", () => {
  const request = buildReviewRequest(checked());
  assert.equal(request.model, "claude-opus-5-5");
  assert.equal(request.output_config.effort, "medium");
  assert.deepEqual(request.output_config.format, { type: "json_schema", schema: REVIEW_SCHEMA });
  assert.equal(request.fallbacks, "default");
  assert.deepEqual(request.betas, ["server-side-fallback-2026-07-01"]);
  assert.equal(request.thinking, undefined);
  assert.equal(request.temperature, undefined);
  assert.match(request.system[0].text, /^You are Leo, /);
  assert.match(request.system[0].text, /200 to 260 words/);
  assert.match(request.messages[0].content, /^The player had White/);
  const tuned = buildReviewRequest(checked({ coach: "vera" }), { REVIEW_MODEL: " claude-fable-5-2 ", REVIEW_EFFORT: "HIGH" });
  assert.equal(tuned.model, "claude-fable-5-2");
  assert.equal(tuned.output_config.effort, "high");
  assert.match(tuned.system[0].text, /^You are Vera, /);
  assert.equal(reviewPrompt("someone"), reviewPrompt("leo"));
});

test("every field of the shape is required and nothing else allowed", () => {
  const part = REVIEW_SCHEMA.properties.parts.items;
  assert.deepEqual(part.required.toSorted(), Object.keys(part.properties).toSorted());
  assert.equal(part.additionalProperties, false);
  assert.equal(REVIEW_SCHEMA.additionalProperties, false);
  assert.deepEqual(part.properties.kind.enum, KINDS);
});

test("the review may take longer than a talk, within limits", () => {
  assert.equal(reviewTimeoutMs({}), 45000);
  assert.equal(reviewTimeoutMs({ REVIEW_TIMEOUT_MS: "60000" }), 60000);
  assert.equal(reviewTimeoutMs({ REVIEW_TIMEOUT_MS: "10" }), 5000);
  assert.equal(reviewTimeoutMs({ REVIEW_TIMEOUT_MS: "9999999" }), 120000);
});

// ---------------------------------------------------------------------------
// Checking the review against the grades

test("a sound review comes through with the ply each part shows", () => {
  const parts = checkParts(RAW, checked());
  assert.deepEqual(
    parts.map((part) => [part.label, part.kind, part.ply]),
    [
      ["The opening", "intro", null],
      ["The opening", "praise", 23],
      ["The pawn on d4", "mistake", 19],
      ["The pawn on d4", "mistake", 25],
      ["The end", "moment", 56],
      ["One habit", "habit", null],
    ],
  );
  assert.equal(parts[3].text, "On move thirteen the same pawn was still there to take.");
  assert.deepEqual(Object.keys(parts[0]), ["label", "kind", "ply", "text"]);
});

test("a part the grades don't back is dropped", () => {
  const review = checked();
  const kept = (part) => {
    const parts = checkParts({ parts: [...RAW.parts, { label: "Extra", better: "", ...part }] }, review);
    return parts.some((item) => item.label === "Extra");
  };
  // A mistake has to be a costly move of the player's, and its better move the engine's.
  assert.equal(kept({ kind: "mistake", move: 11, by: "player", better: "Qxf3", text: "Take with the queen." }), true);
  assert.equal(kept({ kind: "mistake", move: 11, by: "player", better: "", text: "Take with the queen." }), true);
  assert.equal(kept({ kind: "mistake", move: 11, by: "player", better: "Kh1", text: "Tuck the king away." }), false);
  assert.equal(kept({ kind: "mistake", move: 12, by: "player", better: "", text: "Pawn to e5 was a mistake." }), false);
  assert.equal(kept({ kind: "mistake", move: 10, by: "opponent", better: "", text: "They slipped." }), false);
  assert.equal(kept({ kind: "mistake", move: 0, by: "none", better: "", text: "You slipped somewhere." }), false);
  // Praise is for moves the engine liked.
  assert.equal(kept({ kind: "praise", move: 4, by: "player", text: "Castling early was right." }), true);
  assert.equal(kept({ kind: "praise", move: 13, by: "player", text: "Bishop to g3 was strong." }), false);
  assert.equal(kept({ kind: "praise", move: 0, by: "none", text: "You fought hard." }), true);
  // A move the game never reached, in digits or in words.
  assert.equal(kept({ kind: "moment", move: 28, by: "opponent", text: "On move 31 it was over." }), false);
  assert.equal(kept({ kind: "moment", move: 28, by: "opponent", text: "On move thirty-one it was over." }), false);
  assert.equal(kept({ kind: "moment", move: 99, by: "opponent", text: "It was over." }), true);
  // Words are needed; an unknown kind is only a moment.
  assert.equal(kept({ kind: "moment", move: 5, by: "player", text: "   " }), false);
  assert.equal(kept({ kind: "aside", move: 5, by: "player", text: "Queen to e2 is a quiet move." }), true);
});

test("too little left is no review at all", () => {
  const review = checked();
  assert.equal(checkParts(null, review), null);
  assert.equal(checkParts({ parts: [] }, review), null);
  assert.equal(checkParts({ parts: RAW.parts.slice(0, 2) }, review), null);
  const short = { parts: RAW.parts.map((part) => ({ ...part, text: "Good." })) };
  assert.equal(checkParts(short, review), null);
});

test("a review that runs long is cut at a part", () => {
  const long = { parts: Array.from({ length: 40 }, () => ({ label: "On", kind: "intro", move: 0, by: "none", better: "", text: `${LONG} ${LONG} ${LONG}` })) };
  const parts = checkParts(long, checked());
  const length = parts.reduce((sum, part) => sum + part.text.length, 0);
  assert.ok(length <= MAX_REVIEW_CHARS, `${length} characters`);
  assert.ok(parts.length >= 5 && parts.length < 14);
});

test("move numbers are read from digits and words", () => {
  assert.deepEqual(movesNamed("On move 13, and again on moves 16 and 17."), [13, 16]);
  assert.deepEqual(movesNamed("Move thirteen, then move twenty-three, move forty and move seven."), [13, 23, 40, 7]);
  assert.deepEqual(movesNamed("Your move was fine, and a move like that wins."), []);
});

// ---------------------------------------------------------------------------
// Claude's reply

function message(text, extra = {}) {
  return { stop_reason: "end_turn", content: [{ type: "thinking", thinking: "" }, { type: "text", text }], ...extra };
}

function fakeClient(reply) {
  const sent = [];
  return {
    sent,
    beta: {
      messages: {
        create: async (params, options) => {
          sent.push({ params, options });
          if (reply instanceof Error) throw reply;
          return reply;
        },
      },
    },
  };
}

test("Claude's review is read, checked and returned as parts", async () => {
  const client = fakeClient(message(JSON.stringify(RAW)));
  const parts = await writeReview(client, { REVIEW_TIMEOUT_MS: "30000" }, checked());
  assert.equal(parts.length, 6);
  assert.equal(client.sent[0].params.model, "claude-opus-5-5");
  assert.equal(client.sent[0].options.timeout, 30000);
});

test("a reply that isn't a review fails, with a code", async () => {
  const fails = async (reply, code) => {
    await assert.rejects(writeReview(fakeClient(reply), {}, checked()), (error) => {
      assert.ok(error instanceof ClaudeFailure);
      assert.equal(error.code, code);
      return true;
    });
  };
  await fails(message("not json"), "bad_output");
  await fails(message(JSON.stringify({ parts: RAW.parts.slice(0, 1) })), "bad_output");
  await fails(message("", { stop_reason: "refusal" }), "refusal");
  await fails(message('{"parts": [', { stop_reason: "max_tokens" }), "max_tokens");
});

// ---------------------------------------------------------------------------
// POST /review

const PARTS = [
  { label: "The opening", kind: "intro", ply: null, text: "Your opening was well played." },
  { label: "The pawn on d4", kind: "mistake", ply: 19, text: "On move 10, take back with the c-pawn." },
  { label: "One habit", kind: "habit", ply: null, text: "Ask whether you can take back." },
];

function memoryStorage() {
  const saved = new Map();
  return { get: async (key) => saved.get(key), put: async (key, value) => void saved.set(key, value) };
}

function fakeBudget() {
  const budget = new TalkBudget({ storage: memoryStorage() });
  const asked = [];
  return {
    asked,
    namespace: {
      idFromName: (name) => ({ name }),
      get: () => ({
        fetch: async (url, init) => {
          asked.push(url);
          return budget.fetch(new Request(url, init));
        },
      }),
    },
  };
}

function setup(steps = {}, vars = {}, { limit = true } = {}) {
  const calls = { writeReview: [], speak: [], limiter: [] };
  const budget = fakeBudget();
  let clock = 1000;
  const handler = createHandler({
    makeClient: () => ({ fake: "client" }),
    writeReview: async (client, env, review) => {
      calls.writeReview.push({ client, review });
      return PARTS;
    },
    speak: async (env, text, fetchImpl, coach, around) => {
      calls.speak.push({ text, coach, around });
      return MP3;
    },
    now: () => (clock += 7),
    ...steps,
  });
  const env = {
    ANTHROPIC_API_KEY: "sk-ant-test",
    ELEVENLABS_API_KEY: "xi-test",
    BUDGET: budget.namespace,
    REVIEW_LIMITER: {
      limit: async ({ key }) => {
        calls.limiter.push(key);
        return { success: limit };
      },
    },
    ...vars,
  };
  return { handler, env, calls, budget };
}

function post(body, headers = {}) {
  return new Request("https://coach.example/review", {
    method: "POST",
    headers: { "content-type": "application/json", "cf-connecting-ip": "203.0.113.9", ...headers },
    body: typeof body === "string" ? body : JSON.stringify(body),
  });
}

async function linesOf(response) {
  return (await response.text())
    .split("\n")
    .filter(Boolean)
    .map((line) => JSON.parse(line));
}

test("a review streams its words, then each part's voice, then done", async () => {
  const { handler, env, calls, budget } = setup();
  const response = await handler.fetch(post(GAME), env);
  assert.equal(response.status, 200);
  assert.equal(response.headers.get("content-type"), "application/x-ndjson");
  const lines = await linesOf(response);
  assert.deepEqual(lines[0], { type: "review", coach: "leo", parts: PARTS });
  const voices = lines.slice(1, -1);
  assert.deepEqual(voices.map((line) => line.part).toSorted(), [0, 1, 2]);
  for (const line of voices) {
    assert.equal(line.type, "voice");
    assert.equal(line.format, "mp3");
    assert.deepEqual([...Buffer.from(line.audio, "base64")], [...MP3]);
  }
  assert.deepEqual(lines.at(-1), { type: "done" });
  // Claude was given the checked game, and each part read as the middle of the talk.
  assert.equal(calls.writeReview[0].review.plies.length, 56);
  const second = calls.speak.find((call) => call.text === PARTS[1].text);
  assert.deepEqual(second.around, { before: PARTS[0].text, after: PARTS[2].text });
  assert.equal(second.coach, "leo");
  assert.deepEqual(calls.limiter, ["203.0.113.9"]);
  // One review from the day's allowance, and nothing from Talk's voice allowance.
  assert.deepEqual(budget.asked, ["https://budget/review?amount=1&limit=150"]);
});

test("a muted review has no voice lines", async () => {
  const { handler, env, calls } = setup();
  const lines = await linesOf(await handler.fetch(post({ ...GAME, voice: false }), env));
  assert.deepEqual(lines.map((line) => line.type), ["review", "done"]);
  assert.equal(calls.speak.length, 0);
});

test("a voice that fails leaves the part to the device's voice", async () => {
  const noKey = setup({}, { ELEVENLABS_API_KEY: "" });
  const silent = await linesOf(await noKey.handler.fetch(post(GAME), noKey.env));
  assert.deepEqual(silent.slice(1, -1).map((line) => line.unavailable), ["not_configured", "not_configured", "not_configured"]);
  const broken = setup({
    speak: async (env, text) => {
      if (text === PARTS[1].text) throw new Error("down");
      return text === PARTS[2].text ? null : MP3;
    },
  });
  const lines = await linesOf(await broken.handler.fetch(post(GAME), broken.env));
  const byPart = Object.fromEntries(lines.slice(1, -1).map((line) => [line.part, line]));
  assert.equal(byPart[0].format, "mp3");
  assert.equal(byPart[1].unavailable, "upstream");
  assert.equal(byPart[2].unavailable, "upstream");
  assert.deepEqual(lines.at(-1), { type: "done" });
});

test("Claude failing ends the stream with an error line", async () => {
  const cases = [
    [new ClaudeFailure("timeout"), "timeout"],
    [new ClaudeFailure("bad_output"), "upstream"],
    [new ClaudeFailure("refusal"), "upstream"],
    [new TypeError("bug"), "internal"],
  ];
  for (const [error, code] of cases) {
    const { handler, env, calls } = setup({
      writeReview: async () => {
        throw error;
      },
    });
    const lines = await linesOf(await handler.fetch(post(GAME), env));
    assert.deepEqual(lines, [{ type: "error", error: code }]);
    assert.equal(calls.speak.length, 0);
  }
});

test("requests are refused before anything is spent", async () => {
  const { handler, env, calls, budget } = setup();
  const refused = async (request, status, error) => {
    const response = await handler.fetch(request, env);
    assert.equal(response.status, status);
    assert.equal((await response.json()).error, error);
  };
  await refused(new Request("https://coach.example/review"), 405, "method_not_allowed");
  await refused(post(GAME, { "content-type": "text/plain" }), 415, "unsupported_type");
  await refused(post("{not json"), 400, "bad_request");
  await refused(post({ ...GAME, moves: GAME.moves.slice(0, 4) }), 400, "bad_request");
  await refused(post("x".repeat(300 * 1024)), 413, "too_large");
  assert.equal(calls.writeReview.length, 0);
  assert.equal(budget.asked.length, 0);

  const noKey = setup({}, { ANTHROPIC_API_KEY: " " });
  const response = await noKey.handler.fetch(post(GAME), noKey.env);
  assert.equal(response.status, 503);
  assert.equal(noKey.budget.asked.length, 0);
});

test("one address can't ask for reviews without end", async () => {
  const { handler, env, calls } = setup({}, {}, { limit: false });
  const response = await handler.fetch(post(GAME), env);
  assert.equal(response.status, 429);
  assert.deepEqual(await response.json(), { error: "rate_limited" });
  assert.equal(calls.writeReview.length, 0);
});

test("the day's reviews across everyone have a ceiling of their own", async () => {
  const { handler, env, calls } = setup({}, { DAILY_REVIEWS: "2" });
  for (let i = 0; i < 2; i += 1) {
    const response = await handler.fetch(post(GAME), env);
    assert.equal(response.status, 200);
    await response.text();
  }
  const third = await handler.fetch(post(GAME), env);
  assert.equal(third.status, 429);
  assert.deepEqual(await third.json(), { error: "daily_limit" });
  assert.equal(calls.writeReview.length, 2);
});

test("the budget counts reviews apart from talks and voice", async () => {
  const budget = new TalkBudget({ storage: memoryStorage() });
  const now = Date.UTC(2026, 10, 10, 12);
  assert.equal(await budget.take("review", 1, 1, now), true);
  assert.equal(await budget.take("review", 1, 1, now), false);
  assert.equal(await budget.take("talk", 1, 1, now), true);
  assert.equal(await budget.take("voice", 300, 300, now), true);
  // A new day starts every count again.
  assert.equal(await budget.take("review", 1, 1, now + 24 * 3600 * 1000), true);
  const answer = await budget.fetch(new Request("https://budget/review?amount=1&limit=5", { method: "POST" }));
  assert.equal(answer.status, 200);
  assert.equal((await budget.fetch(new Request("https://budget/else", { method: "POST" }))).status, 404);
});
