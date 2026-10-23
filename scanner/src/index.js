// Chess Game Killer scanner: POST a photo or screenshot of a chess board to
// /read and get the position back. Claude does the reading; the Anthropic key
// never leaves this server.

const MAX_BYTES = 5 * 1024 * 1024;
const IMAGE_TYPES = new Set(["image/jpeg", "image/png", "image/webp", "image/gif"]);
const SIDES = new Set(["bottom", "top", "left", "right"]);
const CONFIDENCE = new Set(["high", "medium", "low"]);
const PIECES = new Set("KQRBNPkqrbnp");
const CELLS = [..."KQRBNPkqrbnp", "."];

// The answer's shape. The API's structured outputs guarantee Claude's reply
// matches it (Sonnet 5.5 no longer allows forcing a tool call).
export const SCHEMA = {
  type: "object",
  properties: {
    found: { type: "boolean", description: "False if there is no chess board in the picture." },
    rows: {
      type: "array",
      description:
        "The 8 rows of squares exactly as they appear in the picture, top row first. Each row lists its 8 squares from left to right, one entry per square: K Q R B N P for White, k q r b n p for Black, . for empty.",
      items: { type: "array", items: { type: "string", enum: CELLS } },
    },
    white_side: {
      type: "string",
      enum: ["bottom", "top", "left", "right"],
      description: "Which edge of the picture White's side of the board is on.",
    },
    side_to_move: {
      type: "string",
      enum: ["white", "black", "unknown"],
      description: "white or black only if the picture shows whose turn it is; otherwise unknown.",
    },
    confidence: {
      type: "string",
      enum: ["high", "medium", "low"],
      description: "How sure you are that every square is right.",
    },
  },
  required: ["found", "rows", "white_side", "side_to_move", "confidence"],
  additionalProperties: false,
};

// Not exported: once the worker has a Durable Object, the Workers runtime only accepts
// handlers, classes and functions as exports from this file, and refuses a plain string.
const PROMPT = `Read the chess position in this picture. It may be a photo of a real board or a screenshot of a chess app or website.

Go square by square and report the board exactly as it appears in the picture, without turning it around: the top row of squares first, each row from left to right. If the photo is taken at an angle, follow the board's own rows and columns, not the edges of the picture, and report only the 64 squares of the board. Captured pieces lying beside the board are not on it.

White's pieces are the lighter ones. Tell kings from queens and bishops from pawns carefully; every legal position has exactly one king of each color.

Think it through before answering. Find the board's edges and read any coordinates. Then go row by row and name all 8 squares of each row in order, empty ones too, so no piece slips into the next column. Finally count each color's pieces in the picture and check your rows have the same counts.

For white_side, use the coordinate letters and numbers if you can see them (a1 is in the corner on White's left). Otherwise judge from where the kings, queens and pawns stand.

Set side_to_move to white or black only if the picture shows whose turn it is, for example a highlighted last move, a "to move" label or a running clock; otherwise set it to unknown.

If there is no chess board in the picture, set found to false.`;

export default {
  async fetch(request, env) {
    const url = new URL(request.url);
    if (url.pathname === "/" && request.method === "GET") {
      return json({ ok: true });
    }
    if (url.pathname !== "/read") return json({ error: "not_found" }, 404);
    if (request.method !== "POST") return json({ error: "method_not_allowed" }, 405);

    if (env.SCAN_LIMITER) {
      const key = request.headers.get("cf-connecting-ip") || "unknown";
      const { success } = await env.SCAN_LIMITER.limit({ key });
      if (!success) return json({ error: "rate_limited" }, 429);
    }

    const type = (request.headers.get("content-type") || "").split(";")[0].trim().toLowerCase();
    if (!IMAGE_TYPES.has(type)) return json({ error: "unsupported_type" }, 415);

    const declared = Number(request.headers.get("content-length") || 0);
    if (declared > MAX_BYTES) return json({ error: "too_large" }, 413);
    const bytes = new Uint8Array(await request.arrayBuffer());
    if (bytes.length === 0) return json({ error: "empty" }, 400);
    if (bytes.length > MAX_BYTES) return json({ error: "too_large" }, 413);

    if (!apiKey(env)) return json({ error: "not_configured" }, 503);

    // The whole app shares a daily allowance, so the bill has a ceiling even if
    // someone scripts requests against this public address from many addresses.
    if (!(await withinDailyBudget(env))) return json({ error: "daily_limit" }, 429);

    try {
      return json(await readBoard(bytes, type, env));
    } catch (error) {
      console.error("reading failed:", error && error.message);
      return json({ error: "upstream", status: (error && error.status) || null }, 502);
    }
  },
};

/** Asks Claude to read the board and returns the cleaned-up answer. */
export async function readBoard(bytes, type, env) {
  const response = await fetch("https://api.anthropic.com/v1/messages", {
    method: "POST",
    headers: {
      "x-api-key": apiKey(env),
      "anthropic-version": "2023-06-01",
      "content-type": "application/json",
    },
    body: JSON.stringify(buildRequest(bytes, type, env.MODEL, env.EFFORT)),
  });
  if (!response.ok) {
    const detail = (await response.text()).slice(0, 300);
    const error = new Error(`Anthropic API ${response.status}: ${detail}`);
    error.status = response.status;
    throw error;
  }
  const message = await response.json();
  if (message.stop_reason === "refusal" || message.stop_reason === "max_tokens") {
    throw new Error(`Claude stopped early: ${message.stop_reason}`);
  }
  const text = (message.content || []).find((block) => block.type === "text");
  if (!text) throw new Error("Claude did not report a board");
  return normalize(JSON.parse(text.text));
}

/** The key without stray spaces or line breaks from pasting it into a secret. */
export function apiKey(env) {
  return String(env.ANTHROPIC_API_KEY || "").trim();
}

/** effort ("low" to "max") sets how hard Claude thinks; left out, the API's default. */
export function buildRequest(bytes, type, model, effort) {
  const output_config = { format: { type: "json_schema", schema: SCHEMA } };
  if (effort) output_config.effort = effort;
  return {
    model: model || "claude-sonnet-5-5",
    // Covers Claude's thinking too, which Sonnet 5.5 does by default.
    max_tokens: 16000,
    output_config,
    messages: [
      {
        role: "user",
        content: [
          { type: "image", source: { type: "base64", media_type: type, data: toBase64(bytes) } },
          { type: "text", text: PROMPT },
        ],
      },
    ],
  };
}

/** Keeps only well-formed answers: 8 rows of 8 known characters. Rows may come
 * as lists of squares or as strings; they go back to the app as strings. */
export function normalize(input) {
  const answer = input || {};
  const rows = Array.isArray(answer.rows) ? answer.rows : [];
  const clean = rows.map((row) =>
    (Array.isArray(row) ? row.map(String) : Array.from(String(row)))
      .map((cell) => (PIECES.has(cell) ? cell : "."))
      .join("")
  );
  const wellFormed = clean.length === 8 && clean.every((row) => row.length === 8);
  const anyPieces = wellFormed && clean.some((row) => /[^.]/.test(row));
  const found = answer.found !== false && wellFormed && anyPieces;

  if (!found) return { found: false };
  return {
    found: true,
    rows: clean,
    white_side: SIDES.has(answer.white_side) ? answer.white_side : "bottom",
    side_to_move: answer.side_to_move === "white" || answer.side_to_move === "black" ? answer.side_to_move : null,
    confidence: CONFIDENCE.has(answer.confidence) ? answer.confidence : "medium",
  };
}

/** Base64 without Node's Buffer, in chunks so big photos don't overflow the call stack. */
export function toBase64(bytes) {
  let binary = "";
  const chunk = 0x8000;
  for (let i = 0; i < bytes.length; i += chunk) {
    binary += String.fromCharCode.apply(null, bytes.subarray(i, i + chunk));
  }
  return btoa(binary);
}

/** Scans allowed per day across every player when DAILY_LIMIT isn't set. */
const DEFAULT_DAILY_LIMIT = 300;

/** Takes one scan from today's allowance. True when there was one left (or no budget is set up). */
export async function withinDailyBudget(env) {
  if (!env.BUDGET) return true;
  const limit = Number(env.DAILY_LIMIT) > 0 ? Math.floor(Number(env.DAILY_LIMIT)) : DEFAULT_DAILY_LIMIT;
  const budget = env.BUDGET.get(env.BUDGET.idFromName("global"));
  const answer = await budget.fetch(`https://budget/take?limit=${limit}`, { method: "POST" });
  return answer.status === 200;
}

/** Counts today's scans (days in UTC). One instance serves the whole app, so the count is exact. */
export class ScanBudget {
  constructor(ctx) {
    this.ctx = ctx;
  }

  async fetch(request) {
    const limit = Number(new URL(request.url).searchParams.get("limit")) || DEFAULT_DAILY_LIMIT;
    const ok = await this.take(limit);
    return new Response(ok ? "ok" : "spent", { status: ok ? 200 : 429 });
  }

  /** One scan, if today's count is still under `limit`. */
  async take(limit, now = Date.now()) {
    const day = new Date(now).toISOString().slice(0, 10);
    const saved = (await this.ctx.storage.get("today")) || { day, count: 0 };
    const today = saved.day === day ? saved : { day, count: 0 };
    if (today.count >= limit) return false;
    await this.ctx.storage.put("today", { day, count: today.count + 1 });
    return true;
  }
}

function json(body, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "content-type": "application/json" },
  });
}
