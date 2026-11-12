import assert from "node:assert/strict";
import { afterEach, test } from "node:test";
import worker, { SCHEMA, buildRequest, normalize, orient, settingsFor, toBase64, whiteView } from "../src/index.js";

const realFetch = globalThis.fetch;
afterEach(() => {
  globalThis.fetch = realFetch;
});

const ROWS = ["r.bqkbnr", "pppp.ppp", "..n.....", "....p...", "....P...", ".....N..", "PPPP.PPP", "RNBQKB.R"];
const env = { ANTHROPIC_API_KEY: "test-key", MODEL: "claude-test" };

function post(body = new Uint8Array([1, 2, 3]), type = "image/jpeg") {
  return new Request("https://scanner.example/read", {
    method: "POST",
    headers: { "content-type": type },
    body,
  });
}

function claudeAnswers(input, capture = {}) {
  globalThis.fetch = async (url, options) => {
    capture.url = url;
    capture.options = options;
    return new Response(
      JSON.stringify({ content: [{ type: "text", text: JSON.stringify(input) }], stop_reason: "end_turn" }),
      { status: 200, headers: { "content-type": "application/json" } }
    );
  };
}

test("reads a board through Claude", async () => {
  const capture = {};
  claudeAnswers(
    // Claude lists each row's squares; the app gets them back as strings.
    { found: true, rows: ROWS.map((row) => [...row]), white_side: "bottom", side_to_move: "black", confidence: "high" },
    capture
  );
  const response = await worker.fetch(post(), env);
  assert.equal(response.status, 200);
  assert.deepEqual(await response.json(), {
    found: true,
    rows: ROWS,
    white_side: "bottom",
    side_to_move: "black",
    confidence: "high",
  });

  assert.equal(capture.url, "https://api.anthropic.com/v1/messages");
  assert.equal(capture.options.headers["x-api-key"], "test-key");
  const sent = JSON.parse(capture.options.body);
  assert.equal(sent.model, "claude-test");
  assert.equal(sent.output_config.format.type, "json_schema");
  assert.equal(sent.output_config.effort, undefined);
  assert.equal(sent.tool_choice, undefined);
  assert.equal(sent.messages[0].content[0].source.data, "AQID");
});

test("rejects requests that aren't images", async () => {
  assert.equal((await worker.fetch(post(new Uint8Array([1]), "text/plain"), env)).status, 415);
  assert.equal((await worker.fetch(post(new Uint8Array([])), env)).status, 400);
  const get = await worker.fetch(new Request("https://scanner.example/read"), env);
  assert.equal(get.status, 405);
  const other = await worker.fetch(new Request("https://scanner.example/nope", { method: "POST" }), env);
  assert.equal(other.status, 404);
});

test("health check", async () => {
  const response = await worker.fetch(new Request("https://scanner.example/"), env);
  assert.deepEqual(await response.json(), { ok: true });
});

test("too many scans are turned away", async () => {
  const limited = { ...env, SCAN_LIMITER: { limit: async () => ({ success: false }) } };
  assert.equal((await worker.fetch(post(), limited)).status, 429);
});

test("a limiter hiccup doesn't stop a scan, and a surprise still answers in JSON", async () => {
  claudeAnswers({ found: false });
  const hiccup = {
    ...env,
    SCAN_LIMITER: {
      limit: async () => {
        throw new Error("limiter down");
      },
    },
  };
  assert.equal((await worker.fetch(post(), hiccup)).status, 200);

  // The budget counter can't be reached: a JSON 500, never an unhandled crash.
  const broken = {
    ...env,
    BUDGET: {
      idFromName: () => "global",
      get: () => ({
        fetch: async () => {
          throw new Error("counter down");
        },
      }),
    },
  };
  const response = await worker.fetch(post(), broken);
  assert.equal(response.status, 500);
  assert.deepEqual(await response.json(), { error: "internal" });
});

test("a missing key or a failing API is reported, not crashed on", async () => {
  assert.equal((await worker.fetch(post(), { MODEL: "x" })).status, 503);
  assert.equal((await worker.fetch(post(), { ANTHROPIC_API_KEY: "  \n" })).status, 503);
  globalThis.fetch = async () => new Response("overloaded", { status: 529 });
  const failed = await worker.fetch(post(), env);
  assert.equal(failed.status, 502);
  assert.deepEqual(await failed.json(), { error: "upstream", status: 529 });
});

test("spaces around a pasted key are dropped", async () => {
  const capture = {};
  claudeAnswers({ found: false }, capture);
  await worker.fetch(post(), { ...env, ANTHROPIC_API_KEY: " test-key\n" });
  assert.equal(capture.options.headers["x-api-key"], "test-key");
});

test("cleans up what Claude sends back", () => {
  assert.deepEqual(normalize({ found: false }), { found: false });
  assert.deepEqual(normalize({ found: true, rows: ["........"] }), { found: false });
  assert.deepEqual(normalize({ found: true, rows: Array(8).fill("........") }), { found: false });

  const messy = normalize({
    found: true,
    rows: ["r.bqkbnr", "pppp-ppp", ...ROWS.slice(2)],
    white_side: "diagonal",
    side_to_move: "nobody",
    confidence: "certain",
  });
  assert.equal(messy.rows[1], "pppp.ppp");
  assert.equal(messy.white_side, "bottom");
  assert.equal(messy.side_to_move, null);
  assert.equal(messy.confidence, "medium");
});

test("base64 matches Node's for big inputs", () => {
  const bytes = new Uint8Array(200_000).map((_, i) => (i * 7) % 256);
  assert.equal(toBase64(bytes), Buffer.from(bytes).toString("base64"));
});

test("the request asks for the board's shape with the picture", () => {
  const request = buildRequest(new Uint8Array([255]), "image/png");
  assert.equal(request.model, "claude-sonnet-5-5");
  assert.equal(request.messages[0].content[0].source.media_type, "image/png");
  assert.equal(request.output_config.format.schema, SCHEMA);
  assert.equal(buildRequest(new Uint8Array([1]), "image/png", "m", "max").output_config.effort, "max");
});

test("rows given as lists of squares are checked square by square", () => {
  const rows = ROWS.map((row) => [...row]);
  rows[1][4] = "x";
  assert.equal(normalize({ found: true, rows }).rows[1], "pppp.ppp");
  rows[2] = rows[2].slice(0, 7);
  assert.deepEqual(normalize({ found: true, rows }), { found: false });
});

test("a refused or cut-off answer is a failure, not a board", async () => {
  for (const stop_reason of ["refusal", "max_tokens"]) {
    globalThis.fetch = async () =>
      new Response(JSON.stringify({ content: [{ type: "text", text: "{" }], stop_reason }), { status: 200 });
    assert.equal((await worker.fetch(post(), env)).status, 502);
  }
});

test("the answer's shape follows the structured outputs rules", () => {
  // Every object closes off extra keys, and arrays have no size limits.
  assert.equal(SCHEMA.additionalProperties, false);
  assert.deepEqual(SCHEMA.required, Object.keys(SCHEMA.properties));
  assert.equal(SCHEMA.properties.rows.minItems, undefined);
  assert.equal(SCHEMA.properties.rows.maxItems, undefined);
  // The API rejects an enum next to a list of types, so each field has one type.
  for (const field of Object.values(SCHEMA.properties)) assert.equal(typeof field.type, "string");
});

test("an unknown turn comes back as null", () => {
  const answer = normalize({ found: true, rows: ROWS, white_side: "top", side_to_move: "unknown", confidence: "low" });
  assert.equal(answer.side_to_move, null);
});

// The daily allowance shared by everyone.
import { ScanBudget, withinDailyBudget } from "../src/index.js";

function memoryStorage() {
  const saved = new Map();
  return { get: async (key) => saved.get(key), put: async (key, value) => void saved.set(key, value) };
}

test("the daily allowance runs out, and comes back the next day", async () => {
  const budget = new ScanBudget({ storage: memoryStorage() });
  const lateMonday = Date.UTC(2026, 9, 19, 23, 50);
  assert.equal(await budget.take(2, lateMonday), true);
  assert.equal(await budget.take(2, lateMonday), true);
  assert.equal(await budget.take(2, lateMonday), false);
  const earlyTuesday = Date.UTC(2026, 9, 20, 0, 5);
  assert.equal(await budget.take(2, earlyTuesday), true);

  // Over fetch, as the worker asks it.
  const fresh = new ScanBudget({ storage: memoryStorage() });
  const take = () => fresh.fetch(new Request("https://budget/take?limit=1", { method: "POST" }));
  assert.equal((await take()).status, 200);
  assert.equal((await take()).status, 429);
});

test("a spent allowance turns scans away before Claude is asked", async () => {
  let asked = false;
  globalThis.fetch = async () => {
    asked = true;
    throw new Error("Claude should not be asked");
  };
  const spent = {
    ...env,
    BUDGET: { idFromName: () => "global", get: () => ({ fetch: async () => new Response("spent", { status: 429 }) }) },
  };
  const response = await worker.fetch(post(), spent);
  assert.equal(response.status, 429);
  assert.deepEqual(await response.json(), { error: "daily_limit" });
  assert.equal(asked, false);
});

test("the allowance follows DAILY_LIMIT, or the default without it", async () => {
  const limits = [];
  const namespace = {
    idFromName: () => "global",
    get: () => ({
      fetch: async (url) => {
        limits.push(new URL(url).searchParams.get("limit"));
        return new Response("ok");
      },
    }),
  };
  assert.equal(await withinDailyBudget({ BUDGET: namespace, DAILY_LIMIT: "25" }), true);
  assert.equal(await withinDailyBudget({ BUDGET: namespace }), true);
  // Without DAILY_LIMIT the default of 300 applies.
  assert.deepEqual(limits, ["25", "300"]);
  // Without the binding (local tests, an older deploy) scans are not blocked.
  assert.equal(await withinDailyBudget({}), true);
});

// Alex's scan (2026-11-08): read with White at the bottom, the black pawns
// marched up the board and the white king sat on a8. Turned round, it's a
// normal game: White's king on h1, Black's on e7.
const BACKWARDS = ["K.......", "....P...", "..B..B.N", "........", ".p.p...P", "p..r....", "...k.p..", "........"];

test("a board read the wrong way round is turned", () => {
  assert.equal(orient(BACKWARDS, "bottom"), "top");
  assert.equal(normalize({ found: true, rows: BACKWARDS, white_side: "bottom" }).white_side, "top");
  assert.deepEqual(whiteView(BACKWARDS, "top"), [
    "........", "..p.k...", "....r..p", "P...p.p.", "........", "N.B..B..", "...P....", ".......K",
  ]);
});

test("a board read the right way round is left alone", () => {
  assert.equal(orient(ROWS, "bottom"), "bottom");
  assert.equal(orient([...ROWS].reverse().map((row) => [...row].reverse().join("")), "top"), "top");
  // Passed pawns racing to promote look backwards, but too close to call.
  const race = ["........", "P.......", "........", "...k....", "....K...", "........", ".......p", "........"];
  assert.equal(orient(race, "bottom"), "bottom");
});

test("pawns on the first or last rank give the side away", () => {
  const sideways = ["........", "...k....", "........", "P......p", "P......p", "........", "....K...", "........"];
  // Seen with White on the left, these pawns stand on ranks 1 and 8: impossible.
  assert.notEqual(orient(sideways, "left"), "left");
});

test("a player's first 100 scans a month read with the fast model", async () => {
  const fastEnv = { ...env, EFFORT: "high", FAST_MODEL: "claude-fast", FAST_EFFORT: "low", FAST_SCANS: "100" };
  const sent = async (count) => {
    const capture = {};
    claudeAnswers({ found: true, rows: ROWS, white_side: "bottom", side_to_move: "white", confidence: "high" }, capture);
    const request = post();
    if (count !== undefined) request.headers.set("x-scan-count", String(count));
    assert.equal((await worker.fetch(request, fastEnv)).status, 200);
    const body = JSON.parse(capture.options.body);
    return `${body.model}:${body.output_config.effort}`;
  };
  assert.equal(await sent(1), "claude-fast:low");
  assert.equal(await sent(100), "claude-fast:low");
  assert.equal(await sent(101), "claude-test:high");
  assert.equal(await sent(undefined), "claude-test:high");
  assert.equal(await sent("lots"), "claude-test:high");
  assert.equal(settingsFor(post(), env).model, "claude-test");
});
