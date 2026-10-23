// Leo checks what the player said. Claude has already turned their words into typed claims
// (`parsed`, see PROTOCOL.md); here the rules (chess.js, through board.js) and Stockfish's
// numbers (the request's `facts`) decide what is true. Nothing is guessed: when the facts don't
// cover something and the rules alone can't settle it, the verdict is "unclear".
//
// The positions (PROTOCOL.md, "Words"):
// - P: the request's position, with the player to move.
// - M: the move the player says they'll play. P2 (P′ in the protocol): P after M, the opponent to move.
// - N: P with the opponent to move: what they would do if it were their turn, which is a threat.
// Stockfish's numbers for them: facts.moves are the player's moves in P, from the player's view;
// facts.threats are the opponent's moves in N, from the opponent's view; and in P2 the only line
// is M's own, whose second move is the opponent's best reply.
//
// verifyTalk returns `checked` (the stream's first line, without "type") and `spoken`: the same
// verdicts in plain words with no move notation, for Claude to word Leo's answer.

import {
  Position,
  VALUES,
  attackersOf,
  balance,
  blockersOnLine,
  canTakeBack,
  captureValue,
  exchange,
  hits,
  other,
  pieceCounts,
  pinOn,
  playLine,
  resolveMove,
  settleExchange,
  squareIndex,
  squareName,
  squaresOf,
} from "./board.js";
import { BAND_WORDS, GAIN_WORDS, capitalize, lineWords, moveWords, numberWord, pieceName, tradeOf, tradeWords } from "./words.js";

export const CLAIM_KINDS = [
  "threat", "attacks", "defends", "safe", "hanging", "pinned", "check",
  "mate", "wins", "line", "eval", "material", "plan",
];
const MAX_CLAIMS = 6;
// The moves of a `line` claim that get checked; nobody talks through more than this.
const MAX_LINE = 8;
// Mates sort beyond any centipawn score.
const MATE = 100000;
// A threat gains at least a pawn over the current eval; a missed one worth raising, a pawn and a half.
const THREAT_CP = 100;
const MISSED_CP = 150;
// A check that gains this much is a decisive one, for "my king is safe".
const DECISIVE_CP = 300;
const BANDS = ["losing", "worse", "slightly_worse", "equal", "slightly_better", "better", "winning"];
// What a `gain` is worth in pawns. Mate is beyond any material.
const GAINS = { pawn: 1, two_pawns: 2, exchange: 2, piece: 3, rook: 5, queen: 9, even: 0, mate: Infinity };
const GOOD_GRADES = ["checkmate", "best", "excellent", "good"];
const BAD_GRADES = ["inaccuracy", "mistake", "blunder"];
const TYPES = "kqrbnp";

// ---------------------------------------------------------------------------
// Evals and grades

/** An eval as the request carries it, or null: { cp } or { mate } in whole numbers. */
function readEval(value) {
  if (!value || typeof value !== "object") return null;
  if (Number.isInteger(value.mate)) return { mate: value.mate };
  if (typeof value.cp === "number" && Number.isFinite(value.cp)) return { cp: Math.round(value.cp) };
  return null;
}

const isMate = (evaluation) => evaluation.mate !== undefined;
const mates = (evaluation) => isMate(evaluation) && evaluation.mate > 0;
const getsMated = (evaluation) => isMate(evaluation) && evaluation.mate <= 0;

/** The same eval from the other side's view. */
function flip(evaluation) {
  return isMate(evaluation) ? { mate: 0 - evaluation.mate } : { cp: 0 - evaluation.cp };
}

/** An eval as one number, for comparing: centipawns, with mates beyond any of them. */
function score(evaluation) {
  if (!isMate(evaluation)) return evaluation.cp;
  return evaluation.mate > 0 ? MATE - evaluation.mate : -MATE - evaluation.mate;
}

/** Winning chances from -1 to 1, the app's formula (Evaluation.winningChances). */
export function winningChances(evaluation) {
  if (isMate(evaluation)) return evaluation.mate > 0 ? 1 : -1;
  const cp = Math.max(-1000, Math.min(1000, evaluation.cp));
  return 2 / (1 + Math.exp(-0.00368208 * cp)) - 1;
}

/** The app's grade (MoveReview.grade) for a move with eval `played` when the best move has `best`. */
export function gradeMove(best, played, isBest) {
  if (isBest) return "best";
  const loss = winningChances(best) - winningChances(played);
  if (loss < 0.04) return "excellent";
  if (loss < 0.1) return "good";
  if (loss < 0.2) return "inaccuracy";
  if (loss < 0.3) return "mistake";
  return "blunder";
}

/** The protocol's eval band for an eval from one side's view. */
export function bandOf(evaluation) {
  if (isMate(evaluation)) return evaluation.mate > 0 ? "winning" : "losing";
  const cp = evaluation.cp;
  if (cp >= 300) return "winning";
  if (cp >= 100) return "better";
  if (cp > 40) return "slightly_better";
  if (cp >= -40) return "equal";
  if (cp > -100) return "slightly_worse";
  if (cp > -300) return "worse";
  return "losing";
}

// ---------------------------------------------------------------------------
// Sentences in two forms

/**
 * Builds one sentence in both forms: `note` for the screen, where move notation is fine, and
 * `speech` for Claude and the voice, with moves in words. Strings are the same in both; a move
 * part ({ note, speech }) differs.
 */
function say(...parts) {
  let note = "";
  let speech = "";
  for (const part of parts) {
    if (typeof part === "string") {
      note += part;
      speech += part;
    } else {
      note += part.note;
      speech += part.speech;
    }
  }
  return { note: sentenceCase(note), speech: sentenceCase(speech) };
}

/** A capital first letter, except before a square or a pawn move ("e4 is good", "exd5 wins"). */
function sentenceCase(text) {
  return /^[a-h]([1-8]|x)/.test(text) ? text : capitalize(text);
}

/** A move as a sentence part: SAN on the screen, words in speech ("castling", as a move is a noun here). */
function mv(san, options) {
  return { note: san, speech: moveWords(san, { noun: true, ...options }) };
}

/** A move with its check sign left off in speech, for sentences that say "is check" themselves. */
function bare(san) {
  return mv(san, { suffix: false, noun: true });
}

/** A move with no check sign at all, for "after Bxa8, Qxh2 is mate". */
function plain(san) {
  return { note: san.replace(/[+#]+$/, ""), speech: moveWords(san, { suffix: false, noun: true }) };
}

function arrow(from, to, tone) {
  return { from, to, tone };
}

function verdict(kind, text, squares = [], arrows = []) {
  return { verdict: kind, note: text.note, speech: text.speech, squares: unique(squares), arrows };
}

function unique(squares) {
  return [...new Set(squares.filter(Boolean))];
}

const unclear = (text) => verdict("unclear", text);

/** "Stockfish didn't look at Nf3.", or, with no numbers from the app at all, that they didn't come through. */
function notLooked(ctx, san) {
  if (!ctx.lines.length) return unclear(say("I can't check that: Stockfish's numbers didn't come through."));
  return unclear(say("Stockfish didn't look at ", bare(san), "."));
}

/** A move as written, without check signs or spaces, for comparing what was said with SAN. */
const strip = (san) => san.replace(/[+#!?\s]/g, "");

/** "your" or "their" for a color. */
function owner(ctx, color) {
  return color === ctx.player ? "your" : "their";
}

/** "you" or "they" for a color, for board.js reasons. */
function who(ctx, color) {
  return color === ctx.player ? "you" : "they";
}

function pieceAt(cells, index, ownerWord = "the") {
  return `${ownerWord} ${pieceName(cells[index].type)} on ${squareName(index)}`;
}

// ---------------------------------------------------------------------------
// The facts

/** The usable lines of facts.moves or facts.threats in `position`: legal first move, readable eval. */
function readLines(list, position) {
  const lines = [];
  const seen = new Set();
  let dropped = 0;
  for (const item of Array.isArray(list) ? list : []) {
    const move = position && item && typeof item.uci === "string" ? position.byUci(item.uci) : null;
    const evaluation = readEval(item?.eval);
    if (!move || !evaluation) {
      dropped += 1;
      continue;
    }
    if (seen.has(move.uci)) continue;
    seen.add(move.uci);
    const pv = Array.isArray(item.pv) ? item.pv.filter((uci) => typeof uci === "string").map((uci) => uci.trim().toLowerCase()) : [];
    const first = pv.length ? position.byUci(pv[0]) : null;
    lines.push({ uci: move.uci, move, eval: evaluation, pv: first === move ? pv.slice(0, 12) : [move.uci] });
  }
  return { lines, dropped };
}

function contextFor(P, facts, reveal) {
  const N = P.nullMove();
  const moves = readLines(facts?.moves, P);
  const threats = N ? readLines(facts?.threats, N) : { lines: [], dropped: 0 };
  return {
    P,
    N,
    reveal: reveal === true,
    player: P.turn,
    opponent: other(P.turn),
    lines: moves.lines,
    threats: threats.lines,
    // When no line was thrown away, every move Stockfish didn't list is weaker than its last one.
    complete: { moves: moves.dropped === 0, threats: threats.dropped === 0 },
    best: moves.lines[0] ?? null,
    M: null,
    P2: null,
    mLine: null,
    mGrade: null,
    replyLines: [],
    memo: new Map(),
    realities: new Map(),
  };
}

/** Stockfish's lines for the side to move at `pos`, from that side's view, best first. */
function linesAt(ctx, pos) {
  if (pos === ctx.P) return ctx.lines;
  if (pos === ctx.N) return ctx.threats;
  if (pos && pos === ctx.P2) return ctx.replyLines;
  return [];
}

function lineAt(ctx, pos, uci) {
  return linesAt(ctx, pos).find((line) => line.uci === uci) ?? null;
}

/** The weakest line Stockfish listed at `pos`, when every move it left out must be weaker still. */
function weakestListed(ctx, pos) {
  if (pos === ctx.P && ctx.complete.moves) return ctx.lines[ctx.lines.length - 1] ?? null;
  if (pos === ctx.N && ctx.complete.threats) return ctx.threats[ctx.threats.length - 1] ?? null;
  return null;
}

/**
 * Whether an opponent's line in N is a real threat: it mates, or it gains a pawn over the current
 * eval and its line wins material. The material test matters when the player has a strong move of
 * their own: then P's eval is high, and every move of theirs in N "gains" against it, even a
 * plain retreat. { real, mate, gain, outcome }.
 */
function threatReality(ctx, line) {
  const gain = threatGain(ctx, line);
  // Below a pawn of gain only a mate would count, and the eval would show it: no need to play the line.
  if (!mates(line.eval) && gain !== null && gain < THREAT_CP) return { real: false, mate: false, gain, outcome: null };
  const outcome = followFactLine(ctx, ctx.N, line, line.move.color);
  const mate = outcome.mateFor === line.move.color;
  return { real: mate || outcome.gain >= 1, mate, gain, outcome };
}

/** How much an opponent's move in N gains over the current position, in centipawns (their view). */
function threatGain(ctx, line) {
  if (!ctx.best) return null;
  const now = flip(ctx.best.eval);
  if (mates(line.eval)) return MATE;
  if (isMate(line.eval)) return -MATE;
  // A forced mate is already on the board: only a mate of their own would change anything.
  if (isMate(now)) return 0;
  return line.eval.cp - now.cp;
}

/** The grade of a line of facts.moves against the best line. */
function gradeOfLine(ctx, line) {
  return gradeMove(ctx.best.eval, line.eval, line === ctx.best);
}

/**
 * Follows a line from `pos` as far as it is legal and says what it does for `color`:
 * { gain (pawns), mateFor (a color or null), played, trade (words or null), cells }.
 * A line that stops in the middle of an exchange is finished with the exchange count there.
 */
function followLine(ctx, pos, ucis, color) {
  const key = `${pos.fen}|${ucis.join(" ")}|${color}`;
  if (ctx.memo.has(key)) return ctx.memo.get(key);
  // Only the first two moves' SAN is ever shown (the move and the reply).
  const walk = playLine(pos, ucis, { sanCount: 2 });
  let cells = walk.cells;
  const last = walk.played[walk.played.length - 1];
  if (!walk.mate && last && last.captured) {
    const settled = settleExchange(cells, last.toIndex, walk.turn);
    if (settled.value > 0) cells = settled.cells;
  }
  const gain = balance(cells, color) - balance(pos.cells, color);
  const winner = gain >= 0 ? color : other(color);
  const before = pieceCounts(pos.cells);
  const after = pieceCounts(cells);
  const result = {
    gain,
    mateFor: walk.mate ? other(walk.turn) : null,
    played: walk.played,
    trade: tradeWords(before, after, winner),
    // What `color` took, like for like taken out.
    won: tradeOf(before, after, color).won,
    cells,
  };
  ctx.memo.set(key, result);
  return result;
}

/** followLine for a line of the facts, where the eval also tells about a mate the line is too short to show. */
function followFactLine(ctx, pos, line, color) {
  const result = followLine(ctx, pos, line.pv, color);
  if (result.mateFor || !isMate(line.eval)) return result;
  const mover = line.move.color;
  return { ...result, mateFor: line.eval.mate > 0 ? mover : other(mover) };
}

// ---------------------------------------------------------------------------
// Reading a claim

function readClaim(raw) {
  const kind = CLAIM_KINDS.includes(raw?.kind) ? raw.kind : null;
  if (!kind) return null;
  const piece = typeof raw.piece === "string" ? raw.piece.trim().toLowerCase() : "";
  const moves = Array.isArray(raw.moves) ? raw.moves.filter((move) => typeof move === "string" && move.trim()) : [];
  return {
    kind,
    said: typeof raw.said === "string" ? raw.said.trim() : "",
    side: raw.side === "opponent" ? "opponent" : "me",
    piece: piece.length === 1 && TYPES.includes(piece) ? piece : "",
    square: squareIndex(typeof raw.square === "string" ? raw.square.trim().toLowerCase() : ""),
    target: squareIndex(typeof raw.target === "string" ? raw.target.trim().toLowerCase() : ""),
    moves: moves.slice(0, MAX_LINE).map((move) => move.trim()),
    afterMove: raw.afterMove === true,
    eval: BANDS.includes(raw.eval) ? raw.eval : "",
    gain: Object.hasOwn(GAINS, raw.gain) ? raw.gain : "",
  };
}

function colorOf(ctx, side) {
  return side === "opponent" ? ctx.opponent : ctx.player;
}

/** The position a claim is about: P2 when it is about after the move (only if M is legal), else P. */
function sceneOf(ctx, claim) {
  if (!claim.afterMove) return ctx.P;
  return ctx.P2;
}

/** The position where `color` is to move, starting from `pos`: itself, or its null move (none in check). */
function turnAt(pos, color) {
  return pos.turn === color ? pos : pos.nullMove();
}

/**
 * The squares of the pieces a claim could mean, best guess first. The named square wins when it
 * holds what they said; otherwise every piece of that kind and side (a misheard or missing square);
 * otherwise the piece on the named square, if they only mixed up whose it is.
 */
function piecesMeant(pos, color, type, square) {
  const piece = square >= 0 ? pos.cells[square] : null;
  const fits = (candidate, side) => candidate && candidate.color === side && (!type || candidate.type === type);
  if (fits(piece, color)) return [square];
  const same = type ? squaresOf(pos.cells, color, type) : [];
  if (same.length) return same;
  if (piece && (!type || piece.type === type)) return [square];
  return [];
}

function noSuchPiece(ctx, claim, color) {
  const name = claim.piece ? pieceName(claim.piece) : "piece";
  const people = color === ctx.player ? "You" : "They";
  if (!claim.piece && claim.square < 0) return unclear(say("I couldn't tell which piece you mean."));
  if (claim.square >= 0 && !claim.piece) return verdict("wrong", say(`There's nothing on ${squareName(claim.square)}.`));
  return verdict("wrong", say(`${people} don't have a ${name}.`));
}

function needMove() {
  return unclear(say("That's about after your move, and I didn't catch a legal one."));
}

// ---------------------------------------------------------------------------
// What moves do

/**
 * What a move does for its side, from Stockfish's line when there is one, else from the rules:
 * { source: "engine" | "board" | "exchange", gain, mateFor, line, played, trade } or null when
 * neither can tell.
 */
function moveOutcome(ctx, pos, move) {
  const line = lineAt(ctx, pos, move.uci);
  if (line) return { source: "engine", line, ...followFactLine(ctx, pos, line, move.color) };
  if (move.mate) return { source: "board", gain: 0, mateFor: move.color, line: null, played: [], trade: null, won: null };
  if (move.isCapture) {
    const gain = captureValue(pos.cells.slice(), move.fromIndex, move.toIndex, move.takenIndex);
    return { source: "exchange", gain, mateFor: null, line: null, played: [], trade: null, won: null };
  }
  return null;
}

/**
 * Whether a move is a real threat for its side at `pos` (a pawn or more, or mate):
 * { real: true | false | null, mate, gain (cp, from facts, or null), loses, outcome, source }.
 * In N it is threatReality; elsewhere the material of its line; without a line, the exchange count.
 */
function threatValue(ctx, pos, move) {
  if (move.mate) return { real: true, mate: true, gain: MATE, loses: false, outcome: null, source: "board" };
  const line = lineAt(ctx, pos, move.uci);
  if (line) {
    if (pos === ctx.N) {
      const reality = threatReality(ctx, line);
      const outcome = reality.outcome ?? followFactLine(ctx, pos, line, move.color);
      const loses = outcome.mateFor === other(move.color) || outcome.gain <= -1;
      return { ...reality, outcome, loses, source: "engine", line };
    }
    const outcome = followFactLine(ctx, pos, line, move.color);
    const mate = outcome.mateFor === move.color;
    const loses = outcome.mateFor === other(move.color) || outcome.gain <= -1;
    return { real: mate || outcome.gain >= 1, mate, gain: null, loses, outcome, source: "engine", line };
  }
  const weakest = pos === ctx.N ? weakestListed(ctx, pos) : null;
  const ceiling = weakest ? threatGain(ctx, weakest) : null;
  const value = move.isCapture ? captureValue(pos.cells.slice(), move.fromIndex, move.toIndex, move.takenIndex) : null;
  if (ceiling !== null && ceiling < THREAT_CP) {
    return { real: false, mate: false, gain: null, loses: value !== null && value < 0, outcome: null, source: "engine" };
  }
  if (value !== null) {
    return { real: value > 0, mate: false, gain: value * 100, loses: value < 0, outcome: null, source: "exchange" };
  }
  return { real: null, mate: false, gain: null, loses: false, outcome: null, source: null };
}

/**
 * What the reply in a line of the facts does: its own move and the trades on its square, settled
 * by the exchange count (so later trades in the line aren't pinned on it), or the whole line when
 * the gain comes later, like after a fork. { reply, replier, mate, mateNow, gain, trade } or null.
 */
function replyEffect(ctx, pos, line) {
  const outcome = followFactLine(ctx, pos, line, line.move.color);
  const reply = outcome.played[1];
  if (!reply) return null;
  const replier = other(line.move.color);
  const mate = outcome.mateFor === replier;
  const mateNow = Boolean(reply.san && reply.san.endsWith("#"));
  const soon = followLine(ctx, pos, line.pv.slice(0, 2), replier);
  if (soon.gain >= 1) return { reply, replier, mate, mateNow, gain: soon.gain, trade: soon.trade };
  return { reply, replier, mate, mateNow, gain: -outcome.gain, trade: -outcome.gain >= 1 ? outcome.trade : null };
}

/** "After h6, Qxf2 is mate." / "After h6, Bxh6 wins a pawn." / null when the reply wins nothing. */
function replySentence(start, move, effect) {
  if (effect.mate) {
    if (effect.mateNow) return say(start, mv(move.san), ", ", plain(effect.reply.san), " is mate.");
    return say(start, mv(move.san), ", ", mv(effect.reply.san), " leads to mate.");
  }
  if (effect.gain >= 1 && effect.trade) return say(start, mv(move.san), ", ", mv(effect.reply.san), ` wins ${effect.trade}.`);
  return null;
}

/** What a line does, in words: "is mate", "leads to mate", "wins a pawn"; null when it wins nothing. */
function effectWords(outcome, color, firstMates) {
  if (outcome.mateFor === color) return firstMates ? "is mate" : "leads to mate";
  if (outcome.gain >= 1 && outcome.trade) return `wins ${outcome.trade}`;
  return null;
}

// ---------------------------------------------------------------------------
// Danger to a piece

/**
 * Whether the side to move at `pos` can win the piece on `square` by taking it. A capture wins it
 * when the exchange count says so (legal moves only) and Stockfish's lines don't refute it, or
 * when Stockfish's line after the capture comes out at least that piece ahead. A capture that
 * only starts something else (a trade, then another pawn falls) doesn't make this piece unsafe.
 * Returns { status: "wins" | "poisoned" | "safe", capture, value, line, pinned }.
 */
function dangerTo(ctx, pos, square) {
  const worth = VALUES[pos.cells[square]?.type] ?? 0;
  const captures = pos.legal.filter((move) => move.takenIndex === square);
  let poisoned = null;
  let wins = null;
  for (const capture of captures) {
    const value = captureValue(pos.cells.slice(), capture.fromIndex, capture.toIndex, capture.takenIndex);
    const engine = captureVerdict(ctx, pos, capture);
    const found = { capture, value, line: engine?.line ?? null };
    let falls = value > 0;
    if (engine && !engine.pays) falls = false;
    if (engine && engine.pays && (engine.mate || engine.material >= worth - 0.5)) falls = true;
    if (falls) {
      if (!wins || (found.line && !wins.line) || value > wins.value) wins = found;
    } else if (value > 0 && engine && !engine.pays && !poisoned) {
      poisoned = found;
    }
  }
  if (wins) return { status: "wins", ...wins, pinned: pinnedDefenders(pos, square, wins.capture) };
  if (poisoned) return { status: "poisoned", ...poisoned, pinned: [] };
  return { status: "safe", capture: captures[0] ?? null, value: 0, line: null, pinned: [] };
}

/**
 * Stockfish's opinion of a capture at `pos`: { pays, material, mate, line }, or null when its
 * lines don't say. It pays when its line wins material (or mates), and in N also gains a pawn over
 * the current eval, and in P isn't a mistake. A capture Stockfish left out is weaker than its
 * weakest line, so when even that line doesn't pay (in N) or is a mistake (in P), it doesn't either.
 */
function captureVerdict(ctx, pos, capture) {
  const line = lineAt(ctx, pos, capture.uci);
  if (!line) {
    const weakest = weakestListed(ctx, pos);
    if (!weakest) return null;
    if (pos === ctx.N) {
      const ceiling = threatGain(ctx, weakest);
      return ceiling !== null && ceiling < THREAT_CP ? { pays: false, material: null, mate: false, line: null } : null;
    }
    const grade = gradeOfLine(ctx, weakest);
    return grade === "mistake" || grade === "blunder" ? { pays: false, material: null, mate: false, line: null } : null;
  }
  const outcome = followFactLine(ctx, pos, line, capture.color);
  const mate = outcome.mateFor === capture.color;
  let pays = mate || outcome.gain >= 1;
  if (pos === ctx.N) {
    const gain = threatGain(ctx, line);
    if (gain !== null && gain < THREAT_CP) pays = false;
  }
  if (pos === ctx.P) {
    const grade = gradeOfLine(ctx, line);
    if (grade === "mistake" || grade === "blunder") pays = false;
  }
  return { pays, material: outcome.gain, mate, line };
}

/** Defenders of `square` that would take back if a pin didn't hold them: the reason a piece falls. */
function pinnedDefenders(pos, square, capture) {
  const cells = pos.cells;
  const owner = cells[square]?.color;
  if (!owner) return [];
  const withPins = captureValue(cells.slice(), capture.fromIndex, capture.toIndex, capture.takenIndex);
  const withoutPins = captureValue(cells.slice(), capture.fromIndex, capture.toIndex, capture.takenIndex, { pins: false });
  if (withoutPins >= withPins) return [];
  return attackersOf(cells, square, owner).filter((from) => {
    const pin = pinOn(cells, from);
    return pin && pin.absolute;
  });
}

/** The cheapest piece of `color` guarding `square` that may legally take back there, or -1. */
function guardOf(cells, square, color) {
  const guards = attackersOf(cells, square, color).filter((from) => canTakeBack(cells, from, square).ok);
  const order = "pnbrqk";
  guards.sort((a, b) => order.indexOf(cells[a].type) - order.indexOf(cells[b].type));
  return guards[0] ?? -1;
}

// ---------------------------------------------------------------------------
// The claims

function judgeAttacks(ctx, claim, pos) {
  const color = colorOf(ctx, claim.side);
  if (claim.target < 0) return unclear(say("Which square do you mean?"));
  const pieces = piecesMeant(pos, color, claim.piece, claim.square);
  if (!pieces.length) return noSuchPiece(ctx, claim, color);
  const cells = pos.cells;
  const target = squareName(claim.target);
  const tone = color === ctx.player ? "good" : "info";
  const hitting = pieces.find((from) => hits(cells, from, claim.target));
  if (hitting !== undefined) {
    const piece = pieceAt(cells, hitting);
    return verdict(
      "right",
      { note: capitalize(`${piece} hits ${target}.`), speech: capitalize(`${piece} does hit ${target}.`) },
      [squareName(hitting), target],
      [arrow(squareName(hitting), target, tone)],
    );
  }
  for (const from of pieces) {
    const blockers = blockersOnLine(cells, from, claim.target);
    if (!blockers) continue;
    return verdict(
      "partly",
      say(`${pieceAt(cells, from)} lines up with ${target}, but ${pieceAt(cells, blockers[0])} is in the way.`),
      [squareName(from), squareName(blockers[0]), target],
      [arrow(squareName(from), squareName(blockers[0]), "info")],
    );
  }
  const first = pieces[0];
  const text = pieces.length === 1
    ? say(`${pieceAt(cells, first)} doesn't hit ${target}.`)
    : say(`No ${pieceName(cells[first].type)} of ${owner(ctx, color) === "your" ? "yours" : "theirs"} hits ${target}.`);
  return verdict("wrong", text, [...pieces.map(squareName), target]);
}

function judgeDefends(ctx, claim, pos) {
  const color = colorOf(ctx, claim.side);
  if (claim.target < 0) return unclear(say("Which square do you mean?"));
  const pieces = piecesMeant(pos, color, claim.piece, claim.square);
  if (!pieces.length) return noSuchPiece(ctx, claim, color);
  const cells = pos.cells;
  const target = squareName(claim.target);
  const covering = pieces.filter((from) => hits(cells, from, claim.target));
  if (!covering.length) {
    for (const from of pieces) {
      const blockers = blockersOnLine(cells, from, claim.target);
      if (blockers) {
        return verdict(
          "wrong",
          say(`${pieceAt(cells, from)} doesn't cover ${target}: ${pieceAt(cells, blockers[0])} is in the way.`),
          [squareName(from), squareName(blockers[0]), target],
        );
      }
    }
    return verdict("wrong", say(`${pieceAt(cells, pieces[0])} doesn't cover ${target}.`), [squareName(pieces[0]), target]);
  }
  const checks = covering.map((from) => ({ from, retake: canTakeBack(cells, from, claim.target) }));
  const sound = checks.find((check) => check.retake.ok);
  if (sound) {
    return verdict(
      "right",
      say(`${pieceAt(cells, sound.from)} covers ${target}.`),
      [squareName(sound.from), target],
      [arrow(squareName(sound.from), target, color === ctx.player ? "good" : "info")],
    );
  }
  const { from, retake } = checks[0];
  const defender = pieceAt(cells, from);
  if (retake.pin) {
    const pin = retake.pin;
    const shield = pieceAt(cells, pin.behind, owner(ctx, color));
    const reason = pin.absolute ? `it's pinned to ${owner(ctx, color)} king` : `it's pinned to ${shield}`;
    return verdict(
      "partly",
      say(`${defender} covers ${target}, but ${reason} by ${pieceAt(cells, pin.by)}, so it can't take back.`),
      [squareName(from), target, squareName(pin.by)],
      [arrow(squareName(pin.by), squareName(pin.behind), "bad"), arrow(squareName(from), target, "info")],
    );
  }
  const by = retake.coveredBy >= 0 ? `: ${pieceAt(cells, retake.coveredBy)} covers it too` : "";
  return verdict(
    "partly",
    say(`${defender} covers ${target}, but it can't take back${by}.`),
    [squareName(from), target, retake.coveredBy >= 0 ? squareName(retake.coveredBy) : null],
    [arrow(squareName(from), target, "info")],
  );
}

function judgeSafe(ctx, claim, scene) {
  const color = colorOf(ctx, claim.side);
  const takerPos = turnAt(scene, other(color));
  if (!takerPos) return inCheckFirst(ctx, color);
  if (!claim.piece && claim.square < 0) return everythingSafe(ctx, scene, takerPos, color);
  const pieces = piecesMeant(scene, color, claim.piece, claim.square);
  if (!pieces.length) return noSuchPiece(ctx, claim, color);
  if (scene.cells[pieces[0]].type === "k") return kingSafe(ctx, takerPos, color, pieces[0]);
  const dangers = pieces.map((square) => ({ square, danger: dangerTo(ctx, takerPos, square) }));
  const safe = dangers.find((entry) => entry.danger.status !== "wins") ?? null;
  const unsafe = dangers.find((entry) => entry.danger.status === "wins") ?? null;
  if (safe && unsafe) {
    // "My knight is safe" with two knights, one of them hanging: say both.
    const capture = unsafe.danger.capture;
    return verdict(
      "partly",
      say(`${pieceAt(scene.cells, safe.square)} is safe, but ${pieceAt(scene.cells, unsafe.square)} isn't: `, mv(capture.san), " wins it."),
      [squareName(safe.square), squareName(unsafe.square), capture.from],
      [arrow(capture.from, capture.to, "bad")],
    );
  }
  if (safe) return safePieceVerdict(ctx, scene, safe.square, safe.danger, color);
  const { square, danger } = dangers[0];
  return unsafeVerdict(ctx, scene, square, danger, color);
}

/** A side can't move in the claim's position: the other side is in check there and moves first. */
function cantMove(ctx, color) {
  return unclear(say(color === ctx.opponent ? "You're in check, so you move first." : "They're in check after your move, so they move first."));
}

/** The side in check must answer it first, so nothing of theirs can be taken in the meantime. */
function inCheckFirst(ctx, color) {
  return unclear(say(color === ctx.player ? "You're in check, so start with your move." : "They're in check after your move, so they must answer that first."));
}

function safePieceVerdict(ctx, pos, square, danger, color) {
  const piece = pieceAt(pos.cells, square);
  const where = squareName(square);
  if (danger.status === "poisoned") {
    return verdict(
      "right",
      say(capitalize(`${piece} can be taken, but taking it doesn't pay for ${color === ctx.player ? "them" : "you"}.`)),
      [where],
    );
  }
  return verdict("right", say(`Nothing can take ${piece} and win it.`), [where]);
}

function unsafeVerdict(ctx, pos, square, danger, color) {
  const cells = pos.cells;
  const piece = pieceAt(cells, square);
  const capture = danger.capture;
  const marks = [squareName(square), capture.from];
  const arrows = [arrow(capture.from, capture.to, "bad")];
  if (danger.pinned.length) {
    const pinned = danger.pinned[0];
    const pin = pinOn(cells, pinned);
    marks.push(squareName(pinned), pin ? squareName(pin.by) : null);
    if (pin) arrows.push(arrow(squareName(pin.by), squareName(pin.behind), "info"));
    return verdict(
      "wrong",
      say(`${piece} isn't safe: ${pieceAt(cells, pinned, owner(ctx, color))} is pinned, so `, mv(capture.san), " wins it."),
      marks,
      arrows,
    );
  }
  return verdict("wrong", say(`${piece} isn't safe: `, mv(capture.san), " wins it."), marks, arrows);
}

/** "My king is safe": no mate or decisive check against it in the facts, nor a mate in one on the board. */
function kingSafe(ctx, takerPos, color, kingSquare) {
  const danger = kingDanger(ctx, takerPos);
  const king = squareName(kingSquare);
  const yours = owner(ctx, color);
  if (danger) {
    const move = danger.move;
    const what = danger.mate ? (move.mate ? "" : ", which leads to mate") : ", which wins";
    return verdict(
      "wrong",
      say(`${capitalize(yours)} king isn't safe: `, mv(move.san), `${what}.`),
      [king, move.from, move.to],
      [arrow(move.from, move.to, "bad")],
    );
  }
  if (!linesAt(ctx, takerPos).length) {
    return unclear(say(`There's no mate in one against ${yours} king, but Stockfish didn't look further.`));
  }
  return verdict("right", say(`No mate or big check against ${yours} king.`), [king]);
}

/** A mate or a decisive check for the side to move at `pos`: { move, mate } or null. */
function kingDanger(ctx, pos) {
  const lines = linesAt(ctx, pos);
  const mating = lines.find((line) => mates(line.eval));
  if (mating) return { move: mating.move, mate: true };
  if (pos === ctx.N) {
    const decisive = lines.find((line) => line.move.check && threatGain(ctx, line) >= DECISIVE_CP);
    if (decisive) return { move: decisive.move, mate: false };
  }
  if (pos === ctx.P2 && lines[0] && lines[0].move.check && ["mistake", "blunder"].includes(ctx.mGrade)) {
    return { move: lines[0].move, mate: false };
  }
  const mateInOne = pos.mateInOne();
  return mateInOne ? { move: mateInOne, mate: true } : null;
}

/** "Nothing of mine is in danger" / "they have no threats": every piece safe and no real threat. */
function everythingSafe(ctx, scene, takerPos, color) {
  for (const square of squaresOf(scene.cells, color)) {
    if (scene.cells[square].type === "k") continue;
    const danger = dangerTo(ctx, takerPos, square);
    if (danger.status === "wins") return unsafeVerdict(ctx, scene, square, danger, color);
  }
  const king = kingDanger(ctx, takerPos);
  if (king) {
    const taker = takerPos.turn === ctx.player ? "You" : "They";
    return verdict(
      "wrong",
      say(`${taker} ${king.mate ? "threaten mate" : "have a strong check"}: `, mv(king.move.san), "."),
      [king.move.from, king.move.to],
      [arrow(king.move.from, king.move.to, "bad")],
    );
  }
  const lines = linesAt(ctx, takerPos);
  const threat = takerPos === ctx.N ? firstRealThreat(ctx) : null;
  if (threat) {
    const move = threat.line.move;
    const effect = effectWords(threat.outcome, ctx.opponent, false);
    return verdict(
      "wrong",
      say("They do have a threat: ", mv(move.san), effect ? `, which ${effect}.` : "."),
      [move.from, move.to],
      [arrow(move.from, move.to, "bad")],
    );
  }
  if (!lines.length) return unclear(say("Nothing can be won by taking, but Stockfish didn't look further."));
  const people = color === ctx.player ? "Your" : "Their";
  return verdict("right", say(`${people} pieces are all safe, and there's no real threat.`));
}

function judgeHanging(ctx, claim, scene) {
  const color = colorOf(ctx, claim.side);
  const takerPos = turnAt(scene, other(color));
  if (!takerPos) return inCheckFirst(ctx, color);
  const square = claim.square >= 0 ? claim.square : claim.target;
  const pieces = piecesMeant(scene, color, claim.piece, square);
  if (!pieces.length) return noSuchPiece(ctx, { ...claim, square }, color);
  const dangers = pieces.map((at) => ({ at, danger: dangerTo(ctx, takerPos, at) }));
  const pick = dangers.find((entry) => entry.danger.status === "wins")
    ?? dangers.find((entry) => entry.danger.status === "poisoned")
    ?? dangers[0];
  const { at, danger } = pick;
  const cells = scene.cells;
  const piece = pieceAt(cells, at);
  const where = squareName(at);
  const takerIsPlayer = other(color) === ctx.player;
  if (danger.status === "wins") {
    const capture = danger.capture;
    return verdict(
      "right",
      say(`${piece} is ${takerIsPlayer ? "free" : "hanging"}: `, mv(capture.san), " wins it."),
      [where, capture.from],
      [arrow(capture.from, capture.to, takerIsPlayer ? "good" : "bad")],
    );
  }
  if (danger.status === "poisoned") return poisonedVerdict(ctx, takerPos, at, danger, takerIsPlayer);
  return notHangingVerdict(ctx, takerPos, at, color);
}

function poisonedVerdict(ctx, pos, square, danger, takerIsPlayer) {
  const capture = danger.capture;
  const where = squareName(square);
  const arrows = [arrow(capture.from, capture.to, "info")];
  const effect = danger.line ? replyEffect(ctx, pos, danger.line) : null;
  const start = takerIsPlayer ? "It looks free, but after " : "They can take it, but after ";
  if (!effect) {
    const text = takerIsPlayer
      ? say(`It looks free, but taking on ${where} doesn't pay.`)
      : say(`They can take on ${where}, but it doesn't pay for them.`);
    return verdict("partly", text, [where, capture.from], arrows);
  }
  const reply = effect.reply;
  arrows.push(arrow(reply.from, reply.to, "bad"));
  const marks = [where, capture.from, reply.from, reply.to];
  const sentence = replySentence(start, capture, effect);
  if (sentence) return verdict("partly", sentence, marks, arrows);
  const back = effect.replier === ctx.player ? "you win it back" : "they win it back";
  return verdict("partly", say(start, mv(capture.san), " ", mv(reply.san), `, ${back}.`), marks, arrows);
}

function notHangingVerdict(ctx, pos, square, color) {
  const cells = pos.cells;
  const piece = pieceAt(cells, square);
  const where = squareName(square);
  const takers = pos.legal.filter((move) => move.takenIndex === square);
  const takerWord = other(color) === ctx.player ? "yours" : "theirs";
  if (!takers.length) return verdict("wrong", say(`Nothing of ${takerWord} can take ${piece}.`), [where]);
  const passing = takers.find((move) => move.enPassant);
  if (passing && takers.length === 1) {
    const after = pos.after(passing);
    const back = guardOf(after.cells, passing.toIndex, color);
    if (back >= 0) {
      return verdict(
        "wrong",
        say(`${piece} isn't free: after `, mv(passing.san), ` ${pieceAt(after.cells, back)} takes back.`),
        [where, passing.to, squareName(back)],
        [arrow(squareName(back), passing.to, "info")],
      );
    }
  }
  const guard = guardOf(cells, square, color);
  if (guard >= 0) {
    const best = exchange(pos, square, other(color));
    const trade = best.value === 0 ? " Taking it is only a trade." : "";
    return verdict(
      "wrong",
      say(`${piece} isn't free: ${pieceAt(cells, guard)} guards it.${trade}`),
      [where, squareName(guard)],
      [arrow(squareName(guard), where, "info")],
    );
  }
  return verdict("wrong", say(`Taking ${piece} doesn't win anything.`), [where]);
}

function judgePinned(ctx, claim, pos) {
  const color = colorOf(ctx, claim.side);
  const pieces = piecesMeant(pos, color, claim.piece, claim.square >= 0 ? claim.square : claim.target);
  if (!pieces.length) return noSuchPiece(ctx, claim, color);
  const cells = pos.cells;
  const pins = pieces.map((square) => pinOn(cells, square));
  const index = pins.findIndex(Boolean);
  if (index < 0) {
    const text = pieces.length === 1
      ? say(`${pieceAt(cells, pieces[0])} isn't pinned.`)
      : say(`No ${pieceName(cells[pieces[0]].type)} of ${color === ctx.player ? "yours" : "theirs"} is pinned.`);
    return verdict("wrong", text, pieces.map(squareName));
  }
  const pin = pins[index];
  const shield = pin.absolute ? `${owner(ctx, color)} king` : pieceAt(cells, pin.behind, owner(ctx, color));
  return verdict(
    "right",
    say(`${pieceAt(cells, pin.square)} is pinned to ${shield} by ${pieceAt(cells, pin.by)}.`),
    [squareName(pin.square), squareName(pin.by), squareName(pin.behind)],
    [arrow(squareName(pin.by), squareName(pin.behind), "info")],
  );
}

/** Reads the claim's first move at the position where its side is to move. */
function claimMove(ctx, claim, scene, color) {
  const pos = turnAt(scene, color);
  if (!pos) return { pos: null };
  const written = claim.moves[0];
  const found = resolveMove(pos, written, who(ctx, color));
  return { pos, written, ...found };
}

/** "Bb5 isn't possible: …" for a move that can't be played. */
function impossible(written, reason) {
  return verdict("wrong", say(mv(written, { suffix: false }), ` isn't possible: ${lowerFirst(reason)}`));
}

function lowerFirst(text) {
  if (/^(I|I'm|I've)\b/.test(text)) return text;
  return text[0].toLowerCase() + text.slice(1);
}

function judgeCheck(ctx, claim, scene) {
  const color = colorOf(ctx, claim.side);
  if (!claim.moves.length) return checkNow(ctx, claim, scene, color);
  const found = claimMove(ctx, claim, scene, color);
  if (!found.pos) return cantMove(ctx, color);
  if (found.illegal) return impossible(found.written, found.illegal);
  const options = found.ambiguous ?? [found.move];
  const move = options.find((option) => option.check) ?? options[0];
  const marks = [move.from, move.to];
  const tone = color === ctx.player ? "good" : "bad";
  if (move.mate) return verdict("right", say(bare(move.san), " is even checkmate."), marks, [arrow(move.from, move.to, tone)]);
  if (move.check) return verdict("right", say(bare(move.san), " is check."), marks, [arrow(move.from, move.to, tone)]);
  return verdict("wrong", say(bare(move.san), " isn't check."), marks);
}

/** "He's checking me": is the other side's king in check right now? */
function checkNow(ctx, claim, pos, color) {
  const victim = other(color);
  if (pos.turn !== victim || !pos.inCheck) {
    return verdict("wrong", say(`${capitalize(owner(ctx, victim))} king isn't in check.`));
  }
  const king = squaresOf(pos.cells, victim, "k")[0];
  const checkers = attackersOf(pos.cells, king, color);
  const named = claim.piece ? checkers.find((square) => pos.cells[square].type === claim.piece) : checkers[0];
  const first = named ?? checkers[0];
  return verdict(
    named === undefined ? "partly" : "right",
    named === undefined
      ? say(`It is check, but from ${pieceAt(pos.cells, first)}.`)
      : say(`${pieceAt(pos.cells, first)} is giving check.`),
    [squareName(first), squareName(king)],
    [arrow(squareName(first), squareName(king), color === ctx.player ? "good" : "bad")],
  );
}

const MATE_NUMBERS = { one: 1, two: 2, three: 3, four: 4, five: 5, six: 6 };

/** "mate in one", "a forced mate in three". */
function mateIn(n) {
  return n === 1 ? "mate in one" : `a forced mate in ${numberWord(n)}`;
}

/** The n of "mate in two" in the player's words, or null. */
function mateCount(said) {
  const match = /mate in (\d+|one|two|three|four|five|six)\b/i.exec(said);
  if (!match) return null;
  return MATE_NUMBERS[match[1].toLowerCase()] ?? Number(match[1]);
}

function judgeMate(ctx, claim, scene) {
  const color = colorOf(ctx, claim.side);
  const pos = turnAt(scene, color);
  if (!pos) return cantMove(ctx, color);
  if (claim.moves.length > 1) return mateLine(ctx, claim, pos, color);
  if (claim.moves.length === 1) return mateMove(ctx, claim, pos, color);
  return mateAnywhere(ctx, claim, pos, color);
}

/** "Qxf7 is mate": one move. */
function mateMove(ctx, claim, pos, color) {
  const found = resolveMove(pos, claim.moves[0], who(ctx, color));
  if (found.illegal) return impossible(claim.moves[0], found.illegal);
  const options = found.ambiguous ?? [found.move];
  const move = options.find((option) => option.mate) ?? options[0];
  const marks = [move.from, move.to];
  const tone = color === ctx.player ? "good" : "bad";
  if (move.mate) return verdict("right", say(bare(move.san), " is checkmate."), marks, [arrow(move.from, move.to, tone)]);
  const line = lineAt(ctx, pos, move.uci);
  if (line && mates(line.eval)) {
    const wanted = mateCount(claim.said);
    const n = line.eval.mate;
    if (wanted !== null && n > wanted) {
      return verdict("partly", say(bare(move.san), ` forces mate, but in ${numberWord(n)}, not ${numberWord(wanted)}.`), marks, [arrow(move.from, move.to, tone)]);
    }
    return verdict("right", say(bare(move.san), ` forces mate in ${numberWord(n)}.`), marks, [arrow(move.from, move.to, tone)]);
  }
  const escape = line ? followFactLine(ctx, pos, line, color).played[1] : null;
  const strong = line && (bandOf(line.eval) === "winning" || (pos === ctx.P && GOOD_GRADES.includes(gradeOfLine(ctx, line))));
  if (move.check) {
    const after = pos.after(move);
    const way = (escape && after.byUci(escape.uci)) ?? after.legal[0];
    const kind = escape && strong ? "partly" : "wrong";
    const lead = kind === "partly" ? say(bare(move.san), " is strong, but it isn't mate: ") : say(bare(move.san), " isn't mate: ");
    const moveTone = kind === "partly" ? tone : "info";
    return verdict(kind, say(lead, ...escapeWords(after, way, move)), [...marks, way.from, way.to], [arrow(move.from, move.to, moveTone), arrow(way.from, way.to, "bad")]);
  }
  return verdict("wrong", say(bare(move.san), " isn't checkmate."), marks);
}

/** How a check is answered, in words: "the queen on e7 takes it", "Kd8 gets the king out", "Be7 blocks it". */
function escapeWords(after, answer, checkMove) {
  if (answer.toIndex === checkMove.toIndex && answer.isCapture) return [`${pieceAt(after.cells, answer.fromIndex)} takes it.`];
  if (answer.piece === "k") return [mv(answer.san), " gets the king out."];
  return [mv(answer.san), " blocks it."];
}

/** "Qh7+ Kf8 Qh8#": a line said to end in mate. */
function mateLine(ctx, claim, pos, color) {
  const walk = walkSan(ctx, pos, claim.moves);
  if (walk.failed) return walk.failed;
  const sans = walk.moves.map((move) => move.san);
  const first = walk.moves[0];
  const marks = walk.moves.slice(0, 3).flatMap((move) => [move.from, move.to]);
  const arrows = walk.moves.slice(0, 3).map((move) => arrow(move.from, move.to, move.color === ctx.player ? "good" : "bad"));
  if (!walk.end.isCheckmate) {
    const escape = walk.end.inCheck ? walk.end.legal[0] : null;
    const tail = escape ? say(", and ", mv(escape.san), " gets out.") : say(walk.end.inCheck ? "." : ": it isn't even check.");
    return verdict("wrong", say("After ", lineSay(sans), " it isn't mate", tail), marks, arrows);
  }
  const line = lineAt(ctx, pos, first.uci);
  if (!line || mates(line.eval)) {
    return verdict("right", say(lineSay(sans), ` ends in checkmate.`), marks, arrows);
  }
  const escape = followFactLine(ctx, pos, line, color).played[1];
  if (!escape) return verdict("right", say(lineSay(sans), " ends in checkmate."), marks, arrows);
  return verdict(
    "partly",
    say(lineSay(sans), " is mate, but they don't have to go along: ", mv(escape.san), " gets out."),
    [...marks, escape.from, escape.to],
    [...arrows, arrow(escape.from, escape.to, "bad")],
  );
}

/** "I have mate" / "he threatens mate" / "mate in two", with no move named. */
function mateAnywhere(ctx, claim, pos, color) {
  const lines = linesAt(ctx, pos);
  const mating = lines.find((line) => mates(line.eval));
  const wanted = mateCount(claim.said);
  const theirs = color !== ctx.player;
  const name = (move) => (theirs || ctx.reveal ? [": ", mv(move.san)] : []);
  if (mating) {
    const n = mating.eval.mate;
    const marks = theirs || ctx.reveal ? [mating.move.from, mating.move.to] : [];
    const arrows = theirs || ctx.reveal ? [arrow(mating.move.from, mating.move.to, theirs ? "bad" : "good")] : [];
    const who = theirs ? "They have" : "You have";
    if (wanted !== null && n > wanted) {
      return verdict("partly", say(`${who} a forced mate, but in ${numberWord(n)}, not ${numberWord(wanted)}`, ...name(mating.move), "."), marks, arrows);
    }
    return verdict("right", say(`${who} ${mateIn(n)}`, ...name(mating.move), "."), marks, arrows);
  }
  const mateInOne = pos.mateInOne();
  if (mateInOne) {
    const marks = theirs || ctx.reveal ? [mateInOne.from, mateInOne.to] : [];
    return verdict("right", say(theirs ? "They have mate in one" : "You have mate in one", ...name(mateInOne), "."), marks);
  }
  if (lines.length || pos === ctx.P2 || pos === ctx.P2?.nullMove()) {
    const whose = theirs ? "They don't" : "You don't";
    const after = pos === ctx.P ? "" : pos === ctx.N ? "" : " after that move";
    return verdict("wrong", say(`${whose} have a mate${lines.length ? "" : " in one"}${after}.`));
  }
  return unclear(say("There's no mate in one, and Stockfish didn't look further."));
}

function judgeWins(ctx, claim, scene) {
  const color = colorOf(ctx, claim.side);
  const pos = turnAt(scene, color);
  if (!pos) return cantMove(ctx, color);
  const wanted = claim.gain ? GAINS[claim.gain] : 1;
  let move;
  if (claim.moves.length) {
    const found = resolveMove(pos, claim.moves[0], who(ctx, color));
    if (found.illegal) return impossible(claim.moves[0], found.illegal);
    move = found.move ?? bestOf(ctx, pos, found.ambiguous);
  } else {
    // "I'm winning a piece here": about the best move, whichever it is.
    move = linesAt(ctx, pos)[0]?.move;
    if (!move) return unclear(say("Which move wins it? Stockfish's numbers didn't come through."));
  }
  const outcome = moveOutcome(ctx, pos, move);
  if (!outcome) return notLooked(ctx, move.san);
  return winsVerdict(ctx, claim, pos, move, outcome, wanted, Boolean(claim.moves.length));
}

/** Of several readings of a written move, the one Stockfish rates best (or the first). */
function bestOf(ctx, pos, moves) {
  const lines = linesAt(ctx, pos);
  for (const line of lines) {
    if (moves.includes(line.move)) return line.move;
  }
  return moves[0];
}

function winsVerdict(ctx, claim, pos, move, outcome, wanted, named) {
  const color = move.color;
  const showMove = named || color !== ctx.player || ctx.reveal;
  const subject = showMove ? bare(move.san) : "It";
  const marks = showMove ? [move.from, move.to] : [];
  const tone = color === ctx.player ? "good" : "bad";
  const arrows = showMove ? [arrow(move.from, move.to, tone)] : [];
  const mateForSide = outcome.mateFor === color;
  const gain = outcome.gain;
  const what = outcome.trade ? `wins ${outcome.trade}` : gain >= 1 ? "wins material" : null;
  if (claim.gain === "mate") {
    if (mateForSide) return verdict("right", say(subject, " leads to mate."), marks, arrows);
    if (gain >= 1) return verdict("partly", say(subject, ` ${what ?? "wins material"}, but there's no mate.`), marks, arrows);
    return verdict("wrong", say(subject, " doesn't lead to mate."), marks);
  }
  if (claim.gain === "even") {
    if (Math.abs(gain) <= 0.5 && !outcome.mateFor) return verdict("right", say(subject, " is an even trade."), marks, arrows);
    if (gain > 0.5 || mateForSide) return verdict("partly", say(subject, ` does better than a trade: it ${what ?? "leads to mate"}.`), marks, arrows);
    return lossVerdict(ctx, pos, move, outcome, subject, marks);
  }
  if (mateForSide) return verdict("right", say(subject, " does better than that: it leads to mate."), marks, arrows);
  if (gain >= wanted - 0.5 || (gain >= 1 && tookWhatWasSaid(outcome.won, claim.gain))) {
    return verdict("right", say(subject, ` ${what}.`), marks, arrows);
  }
  if (gain >= 0.5) {
    return verdict("partly", say(subject, ` ${what ?? "wins something"}, not ${GAIN_WORDS[claim.gain] ?? "more"}.`), marks, arrows);
  }
  return lossVerdict(ctx, pos, move, outcome, subject, marks);
}

/** "Nc6+ wins the queen" holds when the queen falls, even if a knight goes back for it. */
function tookWhatWasSaid(won, gain) {
  if (!won) return false;
  switch (gain) {
    case "queen":
      return won.q >= 1;
    case "rook":
      return won.r >= 1;
    case "piece":
      return won.n + won.b >= 1 || won.r >= 1 || won.q >= 1;
    case "exchange":
      return won.r >= 1;
    case "two_pawns":
      return won.p >= 2;
    default:
      return false;
  }
}

function lossVerdict(ctx, pos, move, outcome, subject, marks) {
  const line = outcome.line;
  const effect = line ? replyEffect(ctx, pos, line) : null;
  if (effect) {
    const reply = effect.reply;
    const replyMarks = [...marks, reply.from, reply.to];
    const replyArrows = [arrow(reply.from, reply.to, "bad")];
    if (effect.mate) {
      const ending = effect.mateNow ? [plain(reply.san), " is mate."] : [mv(reply.san), " leads to mate."];
      return verdict("wrong", say(subject, " loses: after it, ", ...ending), replyMarks, replyArrows);
    }
    if (effect.gain >= 1 && effect.trade) {
      return verdict("wrong", say(subject, " loses material: after it, ", mv(reply.san), ` wins ${effect.trade}.`), replyMarks, replyArrows);
    }
    if (outcome.gain <= -1) return verdict("wrong", say(subject, " loses material."), marks);
    return verdict("wrong", say(subject, " doesn't win anything: ", mv(reply.san), " answers it."), replyMarks);
  }
  if (outcome.gain <= -1) return verdict("wrong", say(subject, " loses material."), marks);
  return verdict("wrong", say(subject, " doesn't win anything."), marks);
}

/** Plays SAN moves in turn: { moves, end } or { failed: verdict } at the first that can't be played. */
function walkSan(ctx, start, written) {
  let pos = start;
  const moves = [];
  for (const text of written) {
    const found = resolveMove(pos, text, who(ctx, pos.turn));
    const move = found.move ?? (found.ambiguous ? bestOf(ctx, pos, found.ambiguous) : null);
    if (!move) {
      if (!moves.length) return { failed: impossible(text, found.illegal) };
      const reason = found.illegal ? `: ${lowerFirst(found.illegal)}` : ".";
      return {
        failed: verdict(
          "wrong",
          say("After ", lineSay(moves.map((m) => m.san)), ", ", mv(text, { suffix: false }), ` isn't possible${reason}`),
          moves.flatMap((m) => [m.from, m.to]),
        ),
      };
    }
    moves.push(move);
    pos = pos.after(move);
    if (pos.legal.length === 0) break;
  }
  return { moves, end: pos };
}

/** A line of SAN as one sentence part: "Nxe5 dxe5 Qd4" on the screen, "…, then queen to d4" in speech. */
function lineSay(sans) {
  return { note: sans.join(" "), speech: lineWords(sans) };
}

function judgeLine(ctx, claim, scene) {
  if (!claim.moves.length) return unclear(say("I didn't catch the moves of that line."));
  const starts = lineStarts(ctx, claim, scene);
  let walk = null;
  let start = null;
  for (const candidate of starts) {
    const tried = walkSan(ctx, candidate, claim.moves);
    if (!tried.failed) {
      walk = tried;
      start = candidate;
      break;
    }
    if (!walk) walk = tried;
  }
  if (walk.failed) return walk.failed;
  return lineVerdict(ctx, start, walk);
}

/**
 * Where a line can start. Its first move is the side to move's in the claim's position (PROTOCOL.md):
 * after M, the opponent's reply in P′; now, the player's move in P, or for the opponent's line,
 * their move in N. The other places are tried after that, for a line placed loosely ("if he takes,
 * I take back" without afterMove).
 */
function lineStarts(ctx, claim, scene) {
  const out = [];
  const add = (pos) => {
    if (pos && !out.includes(pos)) out.push(pos);
  };
  if (scene === ctx.P2) {
    add(ctx.P2);
    add(ctx.P2.nullMove());
  } else if (claim.side === "opponent") {
    add(ctx.N);
    add(ctx.P2);
    add(ctx.P);
  } else {
    add(ctx.P);
    add(ctx.P2);
    add(ctx.N);
  }
  return out;
}

/**
 * A legal line is right when the opponent's first move in it is the one Stockfish expects, or one
 * that does about as well for them; partly when Stockfish's move is clearly better for them
 * (named); unclear when Stockfish didn't look there.
 */
function lineVerdict(ctx, start, walk) {
  const moves = walk.moves;
  const sans = moves.map((move) => move.san);
  const marks = moves.slice(0, 3).flatMap((move) => [move.from, move.to]);
  const arrows = moves.slice(0, 3).map((move) => arrow(move.from, move.to, move.color === ctx.player ? "good" : "bad"));
  if (walk.end.isCheckmate) return verdict("right", say(lineSay(sans), " ends in checkmate."), marks, arrows);
  const works = verdict("right", say("That line works: ", lineSay(sans), "."), marks, arrows);
  const at = moves.findIndex((move) => move.color === ctx.opponent);
  if (at < 0) return works;
  const expected = expectedAt(ctx, start, moves, at);
  if (!expected) return unclear(say("Every move there is legal, but Stockfish didn't look at that line."));
  const theirs = moves[at];
  const best = expected.line.move;
  if (best.uci === theirs.uci) return verdict("right", say(lineSay(sans), " is how Stockfish sees it too."), marks, arrows);
  if (!clearlyBetter(ctx, expected, moves.slice(at))) return works;
  return verdict(
    "partly",
    say("That works if they play ", mv(theirs.san), ", but ", mv(best.san), " is better for them."),
    [...marks, best.from, best.to],
    [...arrows, arrow(best.from, best.to, "bad")],
  );
}

/**
 * Stockfish's line for the opponent where the line has them move (its move `at`): their top threat
 * in N, the reply in P′, or the reply in the facts' line of the player's first move. { pos, line } or null.
 */
function expectedAt(ctx, start, moves, at) {
  if (at === 0) {
    const top = linesAt(ctx, start)[0];
    return top ? { pos: start, line: top } : null;
  }
  if (at !== 1) return null;
  const mine = lineAt(ctx, start, moves[0].uci);
  if (!mine || mine.pv.length < 2) return null;
  const pos = start.after(moves[0]);
  const reply = pos.byUci(mine.pv[1]);
  if (!reply) return null;
  return { pos, line: { uci: reply.uci, move: reply, eval: flip(mine.eval), pv: mine.pv.slice(1) } };
}

/**
 * Whether Stockfish's move for them does clearly better than the line's. With both in the facts,
 * by eval (a pawn or more). Otherwise only what material shows for sure: Stockfish's move mates, or
 * wins at least a pawn more than the line both at once (its own trades settled) and along its line.
 */
function clearlyBetter(ctx, expected, rest) {
  const { pos, line } = expected;
  const listed = lineAt(ctx, pos, rest[0].uci);
  if (listed) return score(line.eval) - score(listed.eval) >= THREAT_CP;
  const claimed = followLine(ctx, pos, rest.map((move) => move.uci), ctx.opponent);
  if (mates(line.eval)) return claimed.mateFor !== ctx.opponent;
  const soon = followLine(ctx, pos, [line.move.uci], ctx.opponent);
  const full = followFactLine(ctx, pos, line, ctx.opponent);
  return soon.gain - claimed.gain >= 1 && full.gain - claimed.gain >= 1;
}

function judgeEval(ctx, claim, scene) {
  if (!claim.eval) return unclear(say("I couldn't tell how you see the position."));
  const color = colorOf(ctx, claim.side);
  let evaluation = null;
  if (scene === ctx.P && ctx.best) evaluation = ctx.best.eval;
  if (scene === ctx.P2 && ctx.mLine) evaluation = ctx.mLine.eval;
  if (scene === ctx.P2 && !ctx.mLine && ctx.P2.isCheckmate) evaluation = { mate: 1 };
  if (!evaluation) return unclear(say("Stockfish's numbers didn't come through for that."));
  const view = color === ctx.player ? evaluation : flip(evaluation);
  const band = bandOf(view);
  const distance = Math.abs(BANDS.indexOf(band) - BANDS.indexOf(claim.eval));
  const subject = color === ctx.player ? "you're" : "they're";
  const actual = band === "equal" ? "it's about equal" : `${subject} ${BAND_WORDS[band]}`;
  const text = isMate(view)
    ? say(`Stockfish sees a forced mate${view.mate > 0 ? ` for ${color === ctx.player ? "you" : "them"}` : ` against ${color === ctx.player ? "you" : "them"}`}.`)
    : say(`Stockfish says ${actual}.`);
  if (distance === 0) return verdict("right", text);
  if (distance === 1) return verdict("partly", text);
  return verdict("wrong", text);
}

function judgeMaterial(ctx, claim, scene) {
  const color = colorOf(ctx, claim.side);
  if (!claim.gain || claim.gain === "mate") return unclear(say("I couldn't tell what material you mean."));
  const diff = balance(scene.cells, color);
  const wanted = GAINS[claim.gain];
  const text = say(materialWords(ctx, color, diff));
  if (claim.gain === "exchange") {
    const counts = pieceCounts(scene.cells);
    const them = other(color);
    const rookUp = counts[color].r - counts[them].r === 1;
    const minorDown = counts[them].n + counts[them].b - counts[color].n - counts[color].b === 1;
    if (diff === 2 && rookUp && minorDown) return verdict("right", say(`${color === ctx.player ? "You're" : "They're"} up the exchange.`));
    return verdict(diff === 2 ? "partly" : "wrong", text);
  }
  if (diff === wanted) return verdict("right", text);
  if (wanted !== 0 && diff !== 0 && Math.sign(diff) === Math.sign(wanted)) return verdict("partly", text);
  return verdict("wrong", text);
}

/** "You're a pawn up.", "They're down three points of material.", "Material is even." */
function materialWords(ctx, color, diff) {
  const subject = color === ctx.player ? "You're" : "They're";
  if (diff === 0) return "Material is even.";
  const way = diff > 0 ? "up" : "down";
  const amount = Math.abs(diff);
  if (amount === 1) return `${subject} a pawn ${way}.`;
  return `${subject} ${way} ${numberWord(amount)} points of material.`;
}

function judgePlan(ctx, claim, scene) {
  if (!claim.moves.length) return unclear(say("That's a plan, not a move I can check."));
  const color = colorOf(ctx, claim.side);
  const found = claimMove(ctx, claim, scene, color);
  if (!found.pos) return cantMove(ctx, color);
  if (found.illegal) return impossible(found.written, found.illegal);
  const move = found.move ?? bestOf(ctx, found.pos, found.ambiguous);
  const grade = planGrade(ctx, found.pos, move);
  const marks = [move.from, move.to];
  if (!grade) {
    if (scene === ctx.P2 && color === ctx.player && ctx.mLine?.pv[2] === move.uci) {
      return verdict("right", say(bare(move.san), " is Stockfish's plan too."), marks, [arrow(move.from, move.to, "good")]);
    }
    return notLooked(ctx, move.san);
  }
  const tone = color === ctx.player ? "good" : "bad";
  if (GOOD_GRADES.includes(grade)) return verdict("right", say(bare(move.san), ` is a good ${color === ctx.player ? "plan" : "idea for them"}.`), marks, [arrow(move.from, move.to, tone)]);
  if (grade === "inaccuracy") return verdict("partly", say(bare(move.san), " is playable, but not the best."), marks, [arrow(move.from, move.to, "info")]);
  const refutation = refutationOf(ctx, found.pos, move);
  return verdict("wrong", refutation ?? say(bare(move.san), ` is a ${grade}.`), marks, [arrow(move.from, move.to, "bad")]);
}

/** A plan's first move graded like M: in P against facts.moves, in N against the threats, or null. */
function planGrade(ctx, pos, move) {
  if (pos.after(move).isCheckmate) return "checkmate";
  const lines = linesAt(ctx, pos);
  const line = lineAt(ctx, pos, move.uci);
  if (!line || pos === ctx.P2) return line ? "best" : null;
  return gradeMove(lines[0].eval, line.eval, line === lines[0]);
}

/**
 * "After h6, Bxh6 wins a pawn." for a move with a line in the facts at `pos`: the engine's reply
 * and what it does, from the material along the line. Null when the reply wins nothing: then the
 * move lost ground in a way Leo can't put in words, so he only says a stronger move existed.
 */
function refutationOf(ctx, pos, move) {
  const line = lineAt(ctx, pos, move.uci);
  if (!line) return null;
  const effect = replyEffect(ctx, pos, line);
  return effect ? replySentence("After ", move, effect) : null;
}

function judgeThreat(ctx, claim, scene) {
  const color = colorOf(ctx, claim.side);
  const pos = turnAt(scene, color);
  if (!pos) {
    return unclear(say(color === ctx.opponent ? "You're in check, so that's their threat already made." : "They're in check, so they must answer that first."));
  }
  const options = threatOptions(ctx, claim, scene, pos, color);
  if (options.failed) return options.failed;
  if (!options.moves.length) return options.none;
  const judged = options.moves.map((move) => ({ move, value: threatValue(ctx, pos, move) }));
  const pick = judged.find((entry) => entry.value.real === true)
    ?? judged.find((entry) => entry.value.real === null)
    ?? judged[0];
  return threatVerdict(ctx, pos, pick.move, pick.value, color);
}

/**
 * The moves a threat claim could mean: its written move; else the captures of the named target;
 * else the named piece's captures; else the side's top threat. { moves } or { failed } / { none }.
 */
function threatOptions(ctx, claim, scene, pos, color) {
  const cells = pos.cells;
  if (claim.moves.length) {
    const found = resolveMove(pos, claim.moves[0], who(ctx, color));
    if (found.illegal) return { failed: impossible(claim.moves[0], found.illegal), moves: [] };
    return { moves: found.move ? [found.move] : found.ambiguous };
  }
  let target = claim.target;
  let from = -1;
  if (claim.square >= 0 && cells[claim.square]) {
    if (cells[claim.square].color === color) from = claim.square;
    else if (target < 0) target = claim.square;
  }
  const people = color === ctx.player ? "yours" : "theirs";
  if (target >= 0) {
    let moves = pos.legal.filter((move) => move.toIndex === target || move.takenIndex === target);
    if (from >= 0) moves = moves.filter((move) => move.fromIndex === from);
    else if (claim.piece && cells[target]?.type !== claim.piece) {
      const byPiece = moves.filter((move) => move.piece === claim.piece);
      if (byPiece.length) moves = byPiece;
    }
    const none = cells[target]
      ? verdict("wrong", say(`Nothing of ${people} can take ${pieceAt(cells, target)}.`), [squareName(target)])
      : verdict("wrong", say(`Nothing of ${people} can go to ${squareName(target)}.`), [squareName(target)]);
    return { moves, none };
  }
  if (from < 0 && claim.piece) {
    const theirs = squaresOf(cells, color, claim.piece);
    const mine = squaresOf(cells, other(color), claim.piece);
    // "He wants to take my knight": the named piece is the one in danger, not the attacker.
    if (!theirs.length && mine.length) {
      const moves = pos.legal.filter((move) => mine.includes(move.takenIndex));
      return { moves, none: verdict("wrong", say(`Nothing of ${people} can take a ${pieceName(claim.piece)}.`)) };
    }
    const moves = pos.legal.filter((move) => theirs.includes(move.fromIndex) && (move.isCapture || move.check));
    const listed = linesAt(ctx, pos).map((line) => line.move).filter((move) => theirs.includes(move.fromIndex));
    return { moves: unique([...listed, ...moves]), none: verdict("wrong", say(`${capitalize(owner(ctx, color))} ${pieceName(claim.piece)} has no real threat.`)) };
  }
  if (from >= 0) {
    const moves = pos.legal.filter((move) => move.fromIndex === from && (move.isCapture || move.check));
    const listed = linesAt(ctx, pos).map((line) => line.move).filter((move) => move.fromIndex === from);
    return { moves: unique([...listed, ...moves]), none: verdict("wrong", say(`${pieceAt(cells, from)} has no real threat.`)) };
  }
  // "He's threatening something": their top threat, if it is real.
  const top = linesAt(ctx, pos)[0]?.move ?? pos.mateInOne();
  const noneText = color === ctx.opponent ? "They don't have a real threat right now." : "You don't have a real threat right now.";
  if (!top) return { moves: [], none: unclear(say(`Stockfish didn't look at ${color === ctx.opponent ? "their" : "your"} threats.`)) };
  return { moves: [top], none: verdict("wrong", say(noneText)) };
}

function threatVerdict(ctx, pos, move, value, color) {
  const marks = [move.from, move.to];
  const tone = color === ctx.player ? "good" : "bad";
  const arrows = [arrow(move.from, move.to, tone)];
  if (value.real === null) return notLooked(ctx, move.san);
  if (!value.real) {
    if (value.loses) return verdict("wrong", say(bare(move.san), " isn't a real threat: it loses material."), marks);
    return verdict("wrong", say(bare(move.san), ` isn't a real threat: it doesn't win anything for ${color === ctx.player ? "you" : "them"}.`), marks);
  }
  const effect = value.mate ? (move.mate ? null : "leads to mate") : value.outcome ? effectWords(value.outcome, color, false) : null;
  const what = effect ? ` It ${effect}.` : "";
  // A bigger threat than the one they named?
  const lines = linesAt(ctx, pos);
  const top = lines[0];
  if (pos === ctx.N && top && top.move !== move) {
    const topValue = threatValue(ctx, pos, top.move);
    const bigger = topValue.real && ((topValue.mate && !value.mate) || (topValue.gain ?? 0) >= (value.gain ?? 0) + MISSED_CP);
    if (bigger) {
      return verdict(
        "partly",
        say(bare(move.san), " is a threat, but ", mv(top.move.san), " is a bigger one."),
        [...marks, top.move.from, top.move.to],
        [...arrows, arrow(top.move.from, top.move.to, "bad")],
      );
    }
  }
  const lead = color === ctx.opponent ? "They do threaten " : "You do threaten ";
  return verdict("right", say(lead, mv(move.san), `.${what}`), marks, arrows);
}

const JUDGES = {
  threat: judgeThreat,
  attacks: judgeAttacks,
  defends: judgeDefends,
  safe: judgeSafe,
  hanging: judgeHanging,
  pinned: judgePinned,
  check: judgeCheck,
  mate: judgeMate,
  wins: judgeWins,
  line: judgeLine,
  eval: judgeEval,
  material: judgeMaterial,
  plan: judgePlan,
};

function judgeClaim(ctx, claim) {
  const scene = sceneOf(ctx, claim);
  if (!scene) return needMove();
  return JUDGES[claim.kind](ctx, claim, scene);
}

// ---------------------------------------------------------------------------
// The move they'll play

/** Reads M and judges it: the `move` of `checked`, with its spoken line. */
function judgeMove(ctx, parsedMove) {
  const said = typeof parsedMove.said === "string" ? parsedMove.said.trim() : "";
  const written = typeof parsedMove.san === "string" ? parsedMove.san.trim() : "";
  const unplayed = (grade, text, squares = []) => ({
    said, san: null, uci: null, grade, note: text.note, speech: text.speech, reply: null, squares, arrows: [],
  });
  if (!written) return unplayed("unknown", say("Which move do you mean?"));
  const found = resolveMove(ctx.P, written, "you");
  if (found.illegal) return unplayed("illegal", say(mv(written, { suffix: false }), ` isn't possible: ${lowerFirst(found.illegal)}`));
  if (found.ambiguous) {
    const sans = found.ambiguous.map((move) => move.san);
    const text = say(`Which ${pieceName(found.ambiguous[0].piece)}? `, mv(sans[0]), " and ", mv(sans[1]), " are both possible.");
    return unplayed("unknown", text, unique(found.ambiguous.flatMap((move) => [move.from, move.to])));
  }
  const move = found.move;
  ctx.M = move;
  ctx.P2 = ctx.P.after(move);
  ctx.mLine = ctx.lines.find((line) => line.move === move) ?? null;
  if (ctx.mLine) {
    const reply = ctx.mLine.pv.length > 1 ? ctx.P2.byUci(ctx.mLine.pv[1]) : null;
    if (reply) ctx.replyLines = [{ uci: reply.uci, move: reply, eval: flip(ctx.mLine.eval), pv: ctx.mLine.pv.slice(1) }];
  }
  const grade = moveGrade(ctx, move);
  ctx.mGrade = grade;
  const replyMove = ctx.replyLines[0]?.move ?? null;
  const text = moveNote(ctx, move, grade);
  const tone = GOOD_GRADES.includes(grade) ? "good" : grade === "mistake" || grade === "blunder" ? "bad" : "info";
  const squares = [move.from, move.to];
  const arrows = [arrow(move.from, move.to, tone)];
  // The reply is lit when the note names it: it is what goes wrong.
  if (BAD_GRADES.includes(grade) && replyMove && text.note.includes(strip(replyMove.san))) {
    squares.push(replyMove.from, replyMove.to);
    arrows.push(arrow(replyMove.from, replyMove.to, "bad"));
  }
  return {
    said,
    san: move.san,
    uci: move.uci,
    grade,
    note: text.note,
    speech: text.speech,
    reply: replyMove ? { san: replyMove.san, uci: replyMove.uci } : null,
    squares: unique(squares),
    arrows,
  };
}

function moveGrade(ctx, move) {
  if (ctx.P2.isCheckmate) return "checkmate";
  if (!ctx.mLine) return "unknown";
  return gradeOfLine(ctx, ctx.mLine);
}

function moveNote(ctx, move, grade) {
  const best = ctx.best;
  const stronger = ctx.reveal && best && best.move !== move ? [" ", mv(best.move.san), " was a little stronger."] : [];
  switch (grade) {
    case "checkmate":
      return say(bare(move.san), " is checkmate.");
    case "best":
      return say(bare(move.san), " is the best move.");
    case "excellent":
      return say(bare(move.san), " is an excellent move.", ...stronger);
    case "good":
      return say(bare(move.san), " is a good move.", ...stronger);
    case "unknown":
      return ctx.lines.length
        ? say(bare(move.san), " is legal, but Stockfish didn't look at it.")
        : say(bare(move.san), " is legal, but Stockfish's numbers didn't come through.");
    default: {
      const refutation = refutationOf(ctx, ctx.P, move);
      if (refutation) return refutation;
      const much = grade === "inaccuracy" ? "" : " much";
      const better = ctx.reveal && best ? [": ", mv(best.move.san), ` was${much} stronger.`] : [`: there was a${much} stronger move.`];
      return say(bare(move.san), ` is ${grade === "inaccuracy" ? "an" : "a"} ${grade}`, ...better);
    }
  }
}

// ---------------------------------------------------------------------------
// What they didn't say, and the Traffic Light

/** The squares where the player talked about taking something, and the moves they named. */
function mentionsOf(ctx, claims) {
  const taken = new Set();
  const moves = new Set();
  for (const claim of claims) {
    if (["hanging", "wins", "safe"].includes(claim.kind)) {
      for (const square of [claim.square, claim.target]) if (square >= 0) taken.add(square);
    }
    for (const text of claim.moves) {
      moves.add(strip(text));
      const match = /x([a-h][1-8])/.exec(text);
      if (match) taken.add(squareIndex(match[1]));
    }
  }
  if (ctx.M) {
    moves.add(strip(ctx.M.san));
    if (ctx.M.isCapture) taken.add(ctx.M.takenIndex);
  }
  return { taken, moves };
}

/** The opponent's real threats in N, best first, each with its gain and line. */
function realityOf(ctx, line) {
  let found = ctx.realities.get(line);
  if (!found) {
    found = { line, ...threatReality(ctx, line) };
    ctx.realities.set(line, found);
  }
  return found;
}

/** The opponent's first real threat in N, in Stockfish's order, or null. Later lines aren't played. */
function firstRealThreat(ctx) {
  if (!ctx.N) return null;
  for (const line of ctx.threats) {
    const threat = realityOf(ctx, line);
    if (threat.real) return threat;
  }
  return null;
}

/** Their top real threat when it matters enough to raise: it mates, or gains a pawn and a half. */
function topThreat(ctx) {
  const threat = firstRealThreat(ctx);
  if (!threat) return null;
  if (!threat.mate && threat.gain !== null && threat.gain < MISSED_CP) return null;
  return { line: threat.line, move: threat.line.move, gain: threat.gain, mate: threat.mate, outcome: threat.outcome };
}

/**
 * Whether a threat still works after M. With M in the facts, M's own line decides: its reply is
 * the threat (or takes on the same square), or for a mate threat, M's eval is mate against. Without
 * the facts, the rules decide what they can: the mate is still mate, the capture still wins.
 */
function threatStillWorks(ctx, threat) {
  if (!ctx.M) return true;
  if (ctx.P2.isCheckmate) return false;
  if (ctx.mLine) {
    if (GOOD_GRADES.includes(ctx.mGrade)) return false;
    if (threat.mate) return getsMated(ctx.mLine.eval);
    const reply = ctx.replyLines[0]?.move;
    return Boolean(reply) && (reply.uci === threat.move.uci || (threat.move.isCapture && reply.takenIndex === threat.move.takenIndex));
  }
  const again = ctx.P2.byUci(threat.move.uci);
  if (!again) return false;
  if (threat.mate) return again.mate;
  if (again.isCapture) return captureValue(ctx.P2.cells.slice(), again.fromIndex, again.toIndex, again.takenIndex) > 0;
  return false;
}

/** Whether a right or partly claim named this threat: its move, the piece it takes, or the mate. */
function threatNamed(ctx, claims, verdicts, threat) {
  return claims.some((claim, index) => {
    const result = verdicts[index].verdict;
    if (result !== "right" && result !== "partly") return false;
    const said = claim.moves.map(strip);
    if (claim.side === "opponent" && said.includes(strip(threat.move.san))) return true;
    const target = threat.move.isCapture ? threat.move.takenIndex : -1;
    switch (claim.kind) {
      case "threat":
        if (claim.side !== "opponent") return false;
        if (target >= 0 && (claim.target === target || claim.square === target)) return true;
        return !claim.moves.length && claim.target < 0 && claim.square < 0;
      case "attacks":
        return claim.side === "opponent" && target >= 0 && claim.target === target;
      case "mate":
        return claim.side === "opponent" && threat.mate;
      case "hanging":
        return claim.side === "me" && target >= 0 && (claim.square === target || claim.target === target);
      default:
        return false;
    }
  });
}

/** Whether a claim said the very thing the threat hits is safe, and was wrong. */
function threatMisjudged(claims, verdicts, threat) {
  const target = threat.move.isCapture ? threat.move.takenIndex : -1;
  return claims.some((claim, index) => {
    if (claim.kind !== "safe" || claim.side !== "me" || claim.afterMove || verdicts[index].verdict !== "wrong") return false;
    return (!claim.piece && claim.square < 0) || (target >= 0 && claim.square === target) || (threat.mate && claim.piece === "k");
  });
}

function missedThreat(ctx, threat) {
  const move = threat.move;
  const marks = [move.from, move.to];
  const arrows = [arrow(move.from, move.to, "bad")];
  if (threat.mate) {
    const text = move.mate ? say("They threaten ", mv(move.san), ".") : say("They threaten mate, starting with ", mv(move.san), ".");
    return { kind: "mate", ...text, squares: marks, arrows };
  }
  const cells = ctx.N.cells;
  if (move.isCapture && captureValue(cells.slice(), move.fromIndex, move.toIndex, move.takenIndex) > 0) {
    const piece = pieceAt(cells, move.takenIndex, "your");
    return { kind: "hanging", ...say(`${piece} is hanging: `, mv(move.san), " wins it."), squares: unique([...marks, squareName(move.takenIndex)]), arrows };
  }
  const effect = effectWords(threat.outcome, ctx.opponent, false);
  const text = effect ? say("They threaten ", mv(move.san), `, which ${effect}.`) : say("They threaten ", mv(move.san), ".");
  return { kind: "threat", ...text, squares: marks, arrows };
}

/** The player's own forced mate, when their move isn't one and they didn't talk about it. */
function missedMate(ctx, claims, verdicts) {
  const best = ctx.best;
  if (!best || !mates(best.eval)) return null;
  if (ctx.M && GOOD_GRADES.includes(ctx.mGrade)) return null;
  const said = claims.some((claim, index) => {
    if (claim.moves.map(strip).includes(strip(best.move.san))) return true;
    return claim.kind === "mate" && claim.side === "me" && verdicts[index].verdict !== "wrong";
  });
  if (said) return null;
  const move = best.move;
  if (!ctx.reveal) return { kind: "mate", ...say(`You have ${mateIn(best.eval.mate)}.`), squares: [], arrows: [] };
  return {
    kind: "mate",
    ...say(`You have ${mateIn(best.eval.mate)}: `, mv(move.san), "."),
    squares: [move.from, move.to],
    arrows: [arrow(move.from, move.to, "good")],
  };
}

/** Their piece the engine's best move wins by taking it, when the player didn't talk about taking it. */
function freePiece(ctx, mentions) {
  const best = ctx.best;
  if (!best || !best.move.isCapture || mates(best.eval)) return null;
  if (ctx.M && (ctx.M === best.move || ["best", "excellent", "checkmate"].includes(ctx.mGrade))) return null;
  const square = best.move.takenIndex;
  if (mentions.taken.has(square)) return null;
  const outcome = followFactLine(ctx, ctx.P, best, ctx.player);
  if (outcome.gain < 1) return null;
  const value = captureValue(ctx.P.cells.slice(), best.move.fromIndex, best.move.toIndex, square);
  if (value <= 0) return null;
  const piece = pieceAt(ctx.P.cells, square, "their");
  const where = squareName(square);
  if (ctx.reveal) {
    return {
      kind: "free",
      ...say(`${piece} is loose: `, mv(best.move.san), " wins it."),
      squares: [where, best.move.from],
      arrows: [arrow(best.move.from, best.move.to, "good")],
    };
  }
  return { kind: "free", ...say(`${piece} is loose.`), squares: [where], arrows: [] };
}

function findMissed(ctx, claims, verdicts, move) {
  const missed = [];
  const mentions = mentionsOf(ctx, claims);
  const threat = topThreat(ctx);
  if (threat && !threatNamed(ctx, claims, verdicts, threat) && !threatMisjudged(claims, verdicts, threat) && threatStillWorks(ctx, threat)) {
    // When M walks into it, the move's note already names the reply that carries it out.
    const inMoveNote = Boolean(ctx.M) && ctx.mLine !== null;
    const inClaims = verdicts.some((result) => result.note.includes(strip(threat.move.san)));
    if (!inMoveNote && !inClaims && !mentions.moves.has(strip(threat.move.san))) missed.push(missedThreat(ctx, threat));
  }
  const mine = missedMate(ctx, claims, verdicts) ?? freePiece(ctx, mentions);
  // With reveal, the move's note may already say that the best move was stronger.
  const repeats = mine && ctx.reveal && move && move.note.includes(strip(ctx.best.move.san));
  if (mine && !repeats) missed.push(mine);
  return missed.slice(0, 2);
}

/**
 * Leo's Traffic Light. threats: did they name the opponent's real threat? forcing: when the best
 * move is a check, capture or attack that wins something, did they look at it? safety: is their
 * move safe? Each "good", "missed" or "none"; "missed" only when it clearly mattered.
 */
function habitsOf(ctx, claims, verdicts) {
  return {
    threats: threatsHabit(ctx, claims, verdicts),
    forcing: forcingHabit(ctx, claims),
    safety: safetyHabit(ctx),
  };
}

function threatsHabit(ctx, claims, verdicts) {
  if (!ctx.N || !ctx.threats.length) return "none";
  if (!firstRealThreat(ctx)) {
    // No real threat: saying so, and being right, is the habit done well.
    const saidSafe = claims.some(
      (claim, index) => claim.kind === "safe" && !claim.afterMove && claim.side === "me" && verdicts[index].verdict === "right" && (!claim.piece || claim.piece === "k"),
    );
    return saidSafe ? "good" : "none";
  }
  // Cheap tests first: a line is only played out when a claim is about it.
  const asThreat = (line) => ({ move: line.move, mate: mates(line.eval) });
  const real = (line) => realityOf(ctx, line).real;
  if (ctx.threats.some((line) => threatNamed(ctx, claims, verdicts, asThreat(line)) && real(line))) return "good";
  if (ctx.threats.some((line) => threatMisjudged(claims, verdicts, asThreat(line)) && real(line))) return "missed";
  const top = topThreat(ctx);
  if (top && threatStillWorks(ctx, top)) return "missed";
  return "none";
}

function forcingHabit(ctx, claims) {
  const best = ctx.best;
  if (!best) return "none";
  const move = best.move;
  const forcing = move.check || move.isCapture || attacksSomething(ctx.P.after(move), move);
  if (!forcing) return "none";
  const outcome = followFactLine(ctx, ctx.P, best, ctx.player);
  if (outcome.mateFor !== ctx.player && outcome.gain < 1) return "none";
  if (ctx.M === move || ["best", "excellent", "checkmate"].includes(ctx.mGrade)) return "good";
  const taken = mentionsOf(ctx, claims).taken;
  const looked = claims.some((claim) => claim.moves.map(strip).includes(strip(move.san))) || (move.isCapture && taken.has(move.takenIndex));
  if (looked) return "good";
  if (ctx.M && !BAD_GRADES.includes(ctx.mGrade)) return "none";
  return "missed";
}

/** Whether a move leaves its piece hitting an enemy piece worth more than a pawn, or the king. */
function attacksSomething(after, move) {
  const cells = after.cells;
  for (let square = 0; square < 64; square += 1) {
    const piece = cells[square];
    if (!piece || piece.color === move.color || piece.type === "p") continue;
    if (hits(cells, move.toIndex, square)) return true;
  }
  return false;
}

function safetyHabit(ctx) {
  if (!ctx.M) return "none";
  if (ctx.mGrade === "checkmate") return "good";
  if (ctx.mLine) {
    const outcome = followFactLine(ctx, ctx.P, ctx.mLine, ctx.player);
    const drops = outcome.mateFor === ctx.opponent || outcome.gain <= -1;
    if (drops && BAD_GRADES.includes(ctx.mGrade)) return "missed";
    return "good";
  }
  // Not in the facts: the rules can still see the moved piece left hanging.
  const danger = dangerTo(ctx, ctx.P2, ctx.M.toIndex);
  if (danger.status === "wins" && danger.value > 0) return "missed";
  return "none";
}

const HABIT_LINES = {
  threats: {
    good: "You checked their threats before choosing your move.",
    missed: "Before you choose a move, ask what they're threatening.",
  },
  forcing: {
    good: "You looked at the forcing move first.",
    missed: "Look at checks, captures and attacks first: there was something to win.",
  },
  safety: {
    good: "Your move keeps your pieces safe.",
    missed: "Before you play a move, check that it doesn't drop anything.",
  },
};

/** The one Traffic Light sentence that most deserves saying: a missed habit first, then praise. */
function habitLine(habits) {
  for (const key of ["threats", "safety", "forcing"]) {
    if (habits[key] === "missed") return HABIT_LINES[key].missed;
  }
  for (const key of ["threats", "forcing", "safety"]) {
    if (habits[key] === "good") return HABIT_LINES[key].good;
  }
  return null;
}

/** "Look at your knight.": the piece that moves in the engine's best move, never its square. */
function nudgeOf(ctx) {
  if (ctx.reveal || !ctx.best) return null;
  if (ctx.M && ["checkmate", "best", "excellent"].includes(ctx.mGrade)) return null;
  const move = ctx.best.move;
  if (move.castle) return "Think about your king's safety.";
  if (move.piece === "p") return `Look at your ${move.from[0]}-pawn.`;
  return `Look at your ${pieceName(move.piece)}.`;
}

// ---------------------------------------------------------------------------
// Putting it together

function playerName(color) {
  return color === "w" ? "white" : "black";
}

function emptyResult(player, said, evaluation) {
  return {
    checked: {
      understood: false,
      player,
      move: null,
      claims: [],
      missed: [],
      habits: { threats: "none", forcing: "none", safety: "none" },
      eval: evaluation,
      best: null,
      nudge: null,
    },
    spoken: { player, said, right: [], wrong: [], partly: [], unclear: [], move: null, missed: [], habit: null, nudge: null },
  };
}

function saidOf(said, parsed) {
  if (typeof said === "string" && said.trim()) return said.trim();
  const parts = [parsed?.move?.said, ...(Array.isArray(parsed?.claims) ? parsed.claims.map((claim) => claim?.said) : [])];
  return parts.filter((part) => typeof part === "string" && part.trim()).join(", ");
}

/**
 * Checks what the player said about the position `fen` (they are to move).
 * - facts: Stockfish's numbers from the app (PROTOCOL.md), or null.
 * - parsed: what Claude heard: { about, move: { said, san } | null, claims: [...] }.
 * - reveal: whether Leo may name the best move.
 * - said (optional): the player's words, for `spoken.said`; otherwise rebuilt from `parsed`.
 * Returns { checked, spoken }: `checked` is the stream's "checked" line without its "type".
 */
export function verifyTalk({ fen, facts = null, parsed = null, reveal = false, said = undefined } = {}) {
  const P = new Position(fen);
  const player = playerName(P.turn);
  const words = saidOf(said, parsed);
  const claims = (Array.isArray(parsed?.claims) ? parsed.claims : []).map(readClaim).filter(Boolean).slice(0, MAX_CLAIMS);
  const named = parsed?.move && typeof parsed.move === "object" ? parsed.move : null;
  const ctx = contextFor(P, facts, reveal);
  const evaluation = ctx.best ? { ...ctx.best.eval } : null;
  if (parsed?.about === false || (!claims.length && !named)) return emptyResult(player, words, evaluation);

  const move = named ? judgeMove(ctx, named) : null;
  const verdicts = claims.map((claim) => judgeClaim(ctx, claim));
  const missed = findMissed(ctx, claims, verdicts, move);
  const habits = habitsOf(ctx, claims, verdicts);
  const nudge = nudgeOf(ctx);
  const best = ctx.reveal && ctx.best ? { san: ctx.best.move.san, uci: ctx.best.move.uci } : null;

  const checked = {
    understood: true,
    player,
    move: move ? withoutSpeech(move) : null,
    claims: claims.map((claim, index) => ({
      id: `c${index + 1}`,
      said: claim.said,
      kind: claim.kind,
      ...withoutSpeech(verdicts[index]),
    })),
    missed: missed.map(withoutSpeech),
    habits,
    eval: evaluation,
    best,
    nudge,
  };
  const spoken = {
    player,
    said: words,
    right: [],
    wrong: [],
    partly: [],
    unclear: [],
    move: move ? move.speech : null,
    missed: missed.map((entry) => entry.speech),
    habit: habitLine(habits),
    nudge,
  };
  for (const result of verdicts) spoken[result.verdict].push(result.speech);
  return { checked, spoken };
}

function withoutSpeech(entry) {
  const { speech, ...rest } = entry;
  return rest;
}
