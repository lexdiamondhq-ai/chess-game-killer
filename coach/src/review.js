// The deep review: after a game, the coach talks the player through the whole
// of it once, the way a coach does across the table. POST /review takes the
// game with the grades Stockfish gave on the phone, Claude finds the story and
// words it in parts, and each part is read aloud while the app's board moves
// to the move it is about.
//
// The phone's engine supplies every fact. Claude only chooses what matters and
// how to say it, and checkParts drops any part that points at a move the
// grades don't back: a "mistake" that wasn't one, praise for a costly move, or
// a better move that isn't the engine's.

import { COACHES, coachOf } from "./answer.js";
import { ClaudeFailure, FALLBACK_BETA, callClaude, cleanText, effortOf, messageText, sanOf } from "./claims.js";
import { Chess } from "./vendor/chess.js";

/** A game shorter than this has no story to tell. */
export const MIN_PLIES = 12;
/** Far past any real game (the longest tournament game ran 269 moves). */
export const MAX_PLIES = 600;
export const MAX_LINE = 6;
/** The whole review: about two minutes aloud. A longer one is cut at a part. */
export const MAX_REVIEW_CHARS = 2400;
export const MAX_PART_CHARS = 700;
export const MIN_PARTS = 3;
export const MAX_PARTS = 14;
export const GRADES = ["checkmate", "best", "excellent", "good", "inaccuracy", "mistake", "blunder"];
const COSTLY = new Set(["inaccuracy", "mistake", "blunder"]);
const WELL_PLAYED = new Set(["checkmate", "best", "excellent", "good"]);
const RESULTS = new Set(["win", "loss", "draw"]);
export const KINDS = ["intro", "praise", "mistake", "moment", "habit"];

const DEFAULT_MODEL = "claude-opus-5-5";
const DEFAULT_TIMEOUT_MS = 45000;

// ---------------------------------------------------------------------------
// Checking the request

/**
 * Checks a POST /review body. Returns { ok: true, review } with the game
 * replayed by the rules, or { ok: false, detail } for a 400. A grade the
 * server can't use (a ply that isn't the player's, a better move that isn't
 * legal there) is dropped rather than refused.
 *
 * review: { player: "w" | "b", rival, rating, rivalRating, result, ending,
 * coach, voice, plies: [{ ply, number, color, san, byPlayer, grade?, before?,
 * after?, best?, line? }] }.
 */
export function checkReview(body) {
  if (!isObject(body)) return refuse("The body must be a JSON object.");
  if (body.v !== 1) return refuse('"v" must be 1.');
  if (body.player !== "white" && body.player !== "black") return refuse('"player" must be "white" or "black".');
  if (!RESULTS.has(body.result)) return refuse('"result" must be "win", "loss" or "draw".');
  if (!Array.isArray(body.moves)) return refuse('"moves" is required.');
  if (body.moves.length < MIN_PLIES) return refuse("The game is too short to review.");
  if (body.moves.length > MAX_PLIES) return refuse("The game is too long.");
  const player = body.player === "white" ? "w" : "b";

  let chess;
  try {
    chess = typeof body.start === "string" && body.start.trim() ? new Chess(body.start.trim()) : new Chess();
  } catch (error) {
    return refuse(`"start" isn't a position: ${error.message}`);
  }
  const plies = [];
  for (const [index, value] of body.moves.entries()) {
    const san = typeof value === "string" ? value.trim() : "";
    const fenBefore = chess.fen();
    const number = Number(fenBefore.split(" ")[5]) || 1;
    let move;
    try {
      move = san ? chess.move(san) : null;
    } catch {
      move = null;
    }
    if (!move) return refuse(`Move ${index + 1} of "moves" isn't legal.`);
    plies.push({ ply: index + 1, number, color: move.color, san: move.san, byPlayer: move.color === player, fenBefore });
  }

  for (const item of Array.isArray(body.graded) ? body.graded.slice(0, MAX_PLIES) : []) {
    if (!isObject(item) || !Number.isInteger(item.ply)) continue;
    const ply = plies[item.ply - 1];
    if (!ply || !ply.byPlayer || ply.grade || !GRADES.includes(item.grade)) continue;
    ply.grade = item.grade;
    ply.before = chances(item.before);
    ply.after = chances(item.after);
    const line = lineFrom(ply.fenBefore, item.line, item.best);
    // A better move only counts when it is another move than the one played.
    if (line.length > 0 && line[0] !== ply.san) {
      ply.best = line[0];
      ply.line = line;
    }
  }
  if (!plies.some((ply) => ply.grade)) return refuse('"graded" has no grade the server can use.');

  return {
    ok: true,
    review: {
      player,
      rival: cleanText(body.rival, 60) || "your opponent",
      rating: ratingOf(body.rating),
      rivalRating: ratingOf(body.rivalRating),
      result: body.result,
      ending: endingOf(chess),
      coach: coachOf(body.coach),
      voice: body.voice !== false,
      plies,
    },
  };
}

function refuse(detail) {
  return { ok: false, detail };
}

/** Winning chances for the mover, -1 to 1; null when the phone sent none. */
function chances(value) {
  return typeof value === "number" && Number.isFinite(value) ? Math.max(-1, Math.min(1, value)) : null;
}

function ratingOf(value) {
  return Number.isInteger(value) && value >= 100 && value <= 4000 ? value : null;
}

/** How the game stood at its last move: "checkmate", "stalemate", "draw" or "" (resigned, time, or stopped). */
function endingOf(chess) {
  if (chess.isCheckmate()) return "checkmate";
  if (chess.isStalemate()) return "stalemate";
  if (chess.isDraw()) return "draw";
  return "";
}

/**
 * The engine's line from a position, in standard notation: `line` when it has
 * one, else just `best`. Cut at the first move that isn't legal on its board.
 */
function lineFrom(fen, line, best) {
  const wanted = Array.isArray(line) && line.length > 0 ? line : [best];
  const chess = new Chess(fen);
  const moves = [];
  for (const value of wanted.slice(0, MAX_LINE)) {
    const san = sanOf(value);
    if (!san) break;
    try {
      moves.push(chess.move(san).san);
    } catch {
      break;
    }
  }
  return moves;
}

// ---------------------------------------------------------------------------
// The game in words, for Claude

/** "13." for White's move 13, "13..." for Black's. */
function numbered(ply) {
  return `${ply.number}${ply.color === "w" ? "." : "..."} ${ply.san}`;
}

/** Winning chances as a whole percentage: -1 is 0%, 1 is 100%. */
function percent(value) {
  return `${Math.round(((value + 1) / 2) * 100)}%`;
}

/** Everything the coach knows about the game: who played, how it ended, and every move with its grade. */
export function describeGame(review) {
  const side = review.player === "w" ? "White" : "Black";
  const other = review.player === "w" ? "Black" : "White";
  const ending = { checkmate: " by checkmate", stalemate: " by stalemate", draw: "" }[review.ending] ?? "";
  const result = {
    win: `The player won${ending}.`,
    loss: `The player lost${ending}.`,
    draw: `The game was drawn${ending}.`,
  }[review.result];
  const lines = [
    `The player had ${side}${review.rating ? `, rated about ${review.rating}` : ""}. ${other} was ${review.rival}${review.rivalRating ? `, rated about ${review.rivalRating}` : ""}.`,
    `${result}${review.ending ? "" : " The game did not end on the board: someone resigned or ran out of time."} It lasted ${review.plies.at(-1).number} moves.`,
    "",
    "Each line is one move. The player's moves carry the engine's grade, the player's winning chances before and after the move, and for a costly move the move the engine wanted with its line.",
    "",
  ];
  for (const ply of review.plies) {
    const parts = [numbered(ply), ply.byPlayer ? "player" : "opponent"];
    if (ply.grade) parts.push(ply.grade);
    if (ply.before !== null && ply.before !== undefined && ply.after !== null && ply.after !== undefined) {
      parts.push(`chances ${percent(ply.before)} to ${percent(ply.after)}`);
    }
    if (ply.best && COSTLY.has(ply.grade)) parts.push(`engine wanted ${ply.best} (line: ${ply.line.join(" ")})`);
    lines.push(parts.join(" | "));
  }
  return lines.join("\n");
}

// ---------------------------------------------------------------------------
// Claude's review

const RULES = `The player has just finished a game, and you sit down with them and talk them through it once, the way a coach does across the table. A voice reads your words aloud, and the board on their screen moves to the move each part is about.

You are given every move of the game. For the player's own moves you also have the engine's grade, their winning chances before and after, and for each costly move the move the engine wanted with its line. Those are your facts. Everything you say about the chess must follow from them or from the moves themselves: never state a tactic, a threat or a line that the facts and the moves do not support. If you are not sure something is true on the board, leave it out.

What a good review does
- It finds the story of this game: the one or two ideas that decided it, not a list of every mistake. If the same kind of mistake came back more than once, that pattern is the story.
- It names something the player did well, and means it. Praise only moves the engine graded best, excellent or good.
- It ends with one habit to take into their next game, put so they will remember it at the board.
- In a game the player won, it is glad with them first, and still finds the one thing to work on.

How you say it
- Talk to the player as "you". Call the opponent by their name or "they".
- Say moves in words: "bishop to f4", "take back with the c-pawn", "castle". Squares are fine; notation such as Bxh7+ or O-O is not.
- Give the move number when you turn to a move, so the board can follow.
- Never quote winning chances, percentages or scores. Mention the engine once at most; "the better move was" says the same.
- 200 to 260 words in all. Plain spoken words only: no lists, no markdown, no emoji.

How you shape it
Give the review as 6 to 10 parts, in the order you say them. A part is one to three sentences about one move at most, so the board can show that move while the part is read. For each part:
- label: the chapter it belongs to, in one to three words, such as "The opening" or "The pawn on d4". Parts of the same chapter share a label. Three to five chapters in all.
- kind: "intro" for words about no single move, "praise" for a move of the player's that was well played, "mistake" for a costly move of the player's, "moment" for any other move worth showing (the opponent's blow, how it ended), "habit" for the closing advice.
- move and by: the move number the board should show, and whether it was the player's move or the opponent's. For "intro" and "habit", move is 0 and by is "none".
- better: for a "mistake", the move the engine wanted, exactly as the facts write it. Otherwise "".
- text: what you say.`;

/** The shape of Claude's reply. Structured outputs guarantee the reply matches it. */
export const REVIEW_SCHEMA = {
  type: "object",
  properties: {
    parts: {
      type: "array",
      description: "The review, in the order it is spoken.",
      items: {
        type: "object",
        properties: {
          label: { type: "string", description: "The chapter this part belongs to, one to three words." },
          kind: { type: "string", enum: KINDS },
          move: { type: "integer", description: "The move number the board shows; 0 for none." },
          by: { type: "string", enum: ["player", "opponent", "none"] },
          better: { type: "string", description: 'For a "mistake": the engine\'s move, as the facts write it. Otherwise "".' },
          text: { type: "string", description: "What the coach says: one to three sentences." },
        },
        required: ["label", "kind", "move", "by", "better", "text"],
        additionalProperties: false,
      },
    },
  },
  required: ["parts"],
  additionalProperties: false,
};

/** The system prompt for a coach: who they are, then how every coach reviews. */
export function reviewPrompt(coach = "leo") {
  return `${COACHES[coachOf(coach)].persona} ${RULES}`;
}

/** REVIEW_MODEL, or Claude Opus 5.5. */
export function reviewModel(env = {}) {
  return String(env.REVIEW_MODEL || "").trim() || DEFAULT_MODEL;
}

/** REVIEW_TIMEOUT_MS, kept between 5 and 120 seconds. */
export function reviewTimeoutMs(env = {}) {
  const value = Number.parseInt(String(env.REVIEW_TIMEOUT_MS ?? ""), 10);
  if (!Number.isFinite(value)) return DEFAULT_TIMEOUT_MS;
  return Math.min(120000, Math.max(5000, value));
}

/** The request that writes the review. */
export function buildReviewRequest(review, env = {}) {
  return {
    model: reviewModel(env),
    // Room for Claude's thinking as well as the review.
    max_tokens: 12000,
    betas: [FALLBACK_BETA],
    fallbacks: "default",
    output_config: {
      effort: effortOf(env.REVIEW_EFFORT || "medium"),
      format: { type: "json_schema", schema: REVIEW_SCHEMA },
    },
    system: [{ type: "text", text: reviewPrompt(review.coach), cache_control: { type: "ephemeral" } }],
    messages: [{ role: "user", content: describeGame(review) }],
  };
}

/**
 * Asks Claude for the review and checks it against the grades. Returns the
 * parts the app plays: [{ label, kind, ply, text }], ply null for a part about
 * no single move. Throws a ClaudeFailure when Claude fails or too little of
 * the review holds up.
 */
export async function writeReview(client, env, review) {
  const message = await callClaude(client, buildReviewRequest(review, env), reviewTimeoutMs(env));
  let raw;
  try {
    raw = JSON.parse(messageText(message));
  } catch (error) {
    if (error instanceof ClaudeFailure) throw error;
    throw new ClaudeFailure("bad_output");
  }
  const parts = checkParts(raw, review);
  if (!parts) throw new ClaudeFailure("bad_output");
  return parts;
}

// ---------------------------------------------------------------------------
// Checking the review against the grades

/**
 * The parts that hold up, as the app plays them, or null when too little is
 * left to be a review. A part is dropped when it has no words, or when what it
 * points at isn't what the grades say: a mistake that wasn't the player's
 * costly move, a better move that isn't the engine's, praise for a costly
 * move, or a move number the game never reached. A long review is cut at a part.
 */
export function checkParts(raw, review) {
  const items = isObject(raw) && Array.isArray(raw.parts) ? raw.parts : [];
  const last = review.plies.at(-1).number;
  const parts = [];
  let length = 0;
  for (const item of items.slice(0, 2 * MAX_PARTS)) {
    if (!isObject(item)) continue;
    const text = cleanText(item.text, MAX_PART_CHARS);
    const kind = KINDS.includes(item.kind) ? item.kind : "moment";
    if (!text || movesNamed(text).some((number) => number > last)) continue;
    const ply = plyOf(item, review);
    if (kind === "mistake") {
      if (!ply || !ply.byPlayer || !COSTLY.has(ply.grade)) continue;
      const better = sanOf(item.better);
      if (better && better !== ply.best) continue;
    }
    if (kind === "praise" && ply && (!ply.byPlayer || !WELL_PLAYED.has(ply.grade))) continue;
    if (length + text.length > MAX_REVIEW_CHARS) break;
    length += text.length;
    parts.push({
      label: cleanText(item.label, 28) || "The game",
      kind,
      ply: ply ? ply.ply : null,
      text,
    });
    if (parts.length === MAX_PARTS) break;
  }
  return parts.length >= MIN_PARTS && length >= 300 ? parts : null;
}

/** The ply a part points at, from its move number and whose move it was. Null for none. */
function plyOf(item, review) {
  if (!Number.isInteger(item.move) || item.move < 1 || (item.by !== "player" && item.by !== "opponent")) return null;
  return review.plies.find((ply) => ply.number === item.move && ply.byPlayer === (item.by === "player")) ?? null;
}

const NUMBER_WORDS = Object.freeze({
  one: 1, two: 2, three: 3, four: 4, five: 5, six: 6, seven: 7, eight: 8, nine: 9, ten: 10,
  eleven: 11, twelve: 12, thirteen: 13, fourteen: 14, fifteen: 15, sixteen: 16, seventeen: 17, eighteen: 18, nineteen: 19,
  twenty: 20, thirty: 30, forty: 40, fifty: 50, sixty: 60, seventy: 70, eighty: 80, ninety: 90,
});

/** Every move number a text names after the word "move": "move 13", "move thirteen", "move twenty-three". */
export function movesNamed(text) {
  const found = [];
  const pattern = /\bmoves?\s+(\d{1,3}|[a-z]+(?:[- ][a-z]+)?)/gi;
  for (const match of String(text).matchAll(pattern)) {
    const said = match[1].toLowerCase();
    if (/^\d+$/.test(said)) {
      found.push(Number(said));
      continue;
    }
    const [tens, units] = said.split(/[- ]/);
    const first = NUMBER_WORDS[tens];
    if (!first) continue;
    const second = first >= 20 && units ? NUMBER_WORDS[units] : undefined;
    found.push(first + (second && second < 10 ? second : 0));
  }
  return found;
}

function isObject(value) {
  return value !== null && typeof value === "object" && !Array.isArray(value);
}
