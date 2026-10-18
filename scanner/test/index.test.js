import assert from "node:assert/strict";
import { afterEach, test } from "node:test";
import worker, { buildRequest, normalize, toBase64 } from "../src/index.js";

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
      JSON.stringify({ content: [{ type: "tool_use", name: "report_board", input }] }),
      { status: 200, headers: { "content-type": "application/json" } }
    );
  };
}

test("reads a board through Claude", async () => {
  const capture = {};
  claudeAnswers(
    { observations: "", found: true, rows: ROWS, white_side: "bottom", side_to_move: "black", confidence: "high" },
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
  assert.equal(sent.tool_choice.name, "report_board");
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
  globalThis.fetch = async () => new Response("overloaded", { status: 529 });
  assert.equal((await worker.fetch(post(), env)).status, 502);
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

test("the request asks for the board tool with the picture", () => {
  const request = buildRequest(new Uint8Array([255]), "image/png");
  assert.equal(request.model, "claude-sonnet-5-5");
  assert.equal(request.messages[0].content[0].source.media_type, "image/png");
  assert.equal(request.tools[0].name, "report_board");
});
