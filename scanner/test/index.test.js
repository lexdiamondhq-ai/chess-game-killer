import assert from "node:assert/strict";
import { afterEach, test } from "node:test";
import worker, { SCHEMA, buildRequest, normalize, toBase64 } from "../src/index.js";

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
