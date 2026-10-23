// Chess helpers for Leo's checks, in two layers:
// - chess.js decides the rules: legal moves, SAN, check and mate (Position, playLine,
//   resolveMove).
// - A plain board of 64 cells answers the quick questions claims ask: which pieces hit a
//   square, pins, what stands in the way on a line, and what an exchange on a square comes to.
//
// Squares are numbered 0..63 here: a1 = 0, b1 = 1, ..., h1 = 7, a2 = 8, ..., h8 = 63.
// Colors are chess.js's "w" and "b", piece types its "p n b r q k".
//
// Why the library's internals: chess.js 1.4.0 works out the SAN of every move in
// `moves({ verbose: true })` by generating all the legal moves again, which takes milliseconds
// in a busy middlegame, and the Workers free plan allows about 10 ms of CPU per request. So
// this file calls its move generator (`_moves`, `_moveToSan`, `_makeMove`, `_undoMove`) once per
// position instead. The vendored file is pinned, so those names can't change under us.

import { Chess } from "./vendor/chess.js";

export const WHITE = "w";
export const BLACK = "b";
const FILES = "abcdefgh";

/** Material in pawns: 1, 3, 3, 5, 9. Kings are never won, so they count 0. */
export const VALUES = { p: 1, n: 3, b: 3, r: 5, q: 9, k: 0 };
// The order capturers are tried in an exchange: cheapest first, the king last.
const ORDER = { p: 1, n: 3, b: 3, r: 5, q: 9, k: 100 };
const TYPE_ORDER = "kqrbnp";

const BITS = { EP_CAPTURE: 8, KSIDE_CASTLE: 32, QSIDE_CASTLE: 64 };
const QUEENS = { w: { type: "q", color: "w" }, b: { type: "q", color: "b" } };
const UCI = /^[a-h][1-8][a-h][1-8][qrbn]?$/;

export function other(color) {
  return color === WHITE ? BLACK : WHITE;
}

/** "e4" → 28, or -1 for anything that isn't a square. */
export function squareIndex(name) {
  if (typeof name !== "string" || !/^[a-h][1-8]$/.test(name)) return -1;
  return FILES.indexOf(name[0]) + 8 * (Number(name[1]) - 1);
}

/** 28 → "e4". */
export function squareName(index) {
  return FILES[index & 7] + String((index >> 3) + 1);
}

export const fileOf = (index) => index & 7;
export const rankOf = (index) => index >> 3;

// chess.js numbers its board 0x88-style, from a8 (0) to h1 (119).
const to0x88 = (index) => (7 - rankOf(index)) * 16 + fileOf(index);
const from0x88 = (sq) => (sq & 7) + 8 * (7 - (sq >> 4));

// ---------------------------------------------------------------------------
// Lines and neighbours, worked out once

// The eight directions a line can run, in opposite pairs (d and d ^ 1 point opposite ways).
// The first four are straight (rooks), the last four diagonal (bishops).
const DIRECTIONS = [
  [0, 1], [0, -1], [1, 0], [-1, 0],
  [1, 1], [-1, -1], [1, -1], [-1, 1],
];
const KNIGHT_JUMPS = [[1, 2], [2, 1], [2, -1], [1, -2], [-1, -2], [-2, -1], [-2, 1], [-1, 2]];

function onBoard(file, rank) {
  return file >= 0 && file < 8 && rank >= 0 && rank < 8;
}

function stepsFrom(index, offsets) {
  const out = [];
  for (const [df, dr] of offsets) {
    const file = fileOf(index) + df;
    const rank = rankOf(index) + dr;
    if (onBoard(file, rank)) out.push(file + 8 * rank);
  }
  return out;
}

function rayFrom(index, [df, dr]) {
  const out = [];
  let file = fileOf(index) + df;
  let rank = rankOf(index) + dr;
  while (onBoard(file, rank)) {
    out.push(file + 8 * rank);
    file += df;
    rank += dr;
  }
  return out;
}

// RAYS[square][direction]: the squares from `square` outwards, nearest first.
const RAYS = [];
const KNIGHT = [];
const KING = [];
for (let index = 0; index < 64; index += 1) {
  RAYS.push(DIRECTIONS.map((direction) => rayFrom(index, direction)));
  KNIGHT.push(stepsFrom(index, KNIGHT_JUMPS));
  KING.push(stepsFrom(index, DIRECTIONS));
}

/** Whether a piece type moves along direction d: rooks straight, bishops diagonally, queens both. */
function slidesAlong(type, d) {
  if (type === "q") return true;
  return d < 4 ? type === "r" : type === "b";
}

/** The direction from a to b when they share a rank, file or diagonal; otherwise -1. */
export function directionBetween(a, b) {
  if (a === b) return -1;
  const df = fileOf(b) - fileOf(a);
  const dr = rankOf(b) - rankOf(a);
  if (df !== 0 && dr !== 0 && Math.abs(df) !== Math.abs(dr)) return -1;
  return DIRECTIONS.findIndex(([x, y]) => x === Math.sign(df) && y === Math.sign(dr));
}

/** The squares strictly between a and b on their shared line, or null when they share none. */
export function squaresBetween(a, b) {
  const d = directionBetween(a, b);
  if (d < 0) return null;
  const ray = RAYS[a][d];
  return ray.slice(0, ray.indexOf(b));
}

/** The first occupied square from `index` in direction d, or -1. */
function firstPiece(cells, index, d) {
  for (const square of RAYS[index][d]) {
    if (cells[square]) return square;
  }
  return -1;
}

// ---------------------------------------------------------------------------
// The 64 cells: null or { type, color }

function cellsOf(chess) {
  const cells = new Array(64).fill(null);
  for (let index = 0; index < 64; index += 1) cells[index] = chess._board[to0x88(index)] ?? null;
  return cells;
}

/** The squares of every piece of `color` (and `type`, when given), from a1 to h8. */
export function squaresOf(cells, color, type) {
  const out = [];
  for (let index = 0; index < 64; index += 1) {
    const piece = cells[index];
    if (piece && piece.color === color && (!type || piece.type === type)) out.push(index);
  }
  return out;
}

export function kingOf(cells, color) {
  for (let index = 0; index < 64; index += 1) {
    const piece = cells[index];
    if (piece && piece.type === "k" && piece.color === color) return index;
  }
  return -1;
}

/** Material in pawns for each side. */
export function materialOf(cells) {
  const total = { w: 0, b: 0 };
  for (const piece of cells) {
    if (piece) total[piece.color] += VALUES[piece.type];
  }
  return total;
}

/** How far `color` is ahead in material, in pawns (negative when behind). */
export function balance(cells, color) {
  const total = materialOf(cells);
  return total[color] - total[other(color)];
}

/** How many of each piece each side has: { w: { p, n, b, r, q, k }, b: {...} }. */
export function pieceCounts(cells) {
  const counts = { w: { p: 0, n: 0, b: 0, r: 0, q: 0, k: 0 }, b: { p: 0, n: 0, b: 0, r: 0, q: 0, k: 0 } };
  for (const piece of cells) {
    if (piece) counts[piece.color][piece.type] += 1;
  }
  return counts;
}

// ---------------------------------------------------------------------------
// Who hits what

/** Whether the piece on `from` hits `to`: it could capture there if an enemy stood on it. Pins are ignored. */
export function hits(cells, from, to) {
  const piece = cells[from];
  if (!piece || from === to) return false;
  const df = fileOf(to) - fileOf(from);
  const dr = rankOf(to) - rankOf(from);
  switch (piece.type) {
    case "p":
      return Math.abs(df) === 1 && dr === (piece.color === WHITE ? 1 : -1);
    case "n":
      return (Math.abs(df) === 1 && Math.abs(dr) === 2) || (Math.abs(df) === 2 && Math.abs(dr) === 1);
    case "k":
      return Math.max(Math.abs(df), Math.abs(dr)) === 1;
    default: {
      const d = directionBetween(from, to);
      if (d < 0 || !slidesAlong(piece.type, d)) return false;
      return squaresBetween(from, to).every((square) => !cells[square]);
    }
  }
}

/** The squares of every piece of `color` that hits `target` now (direct hits, pins ignored). */
export function attackersOf(cells, target, color) {
  const found = [];
  // A white pawn that hits the target stands one rank below it, a black one one rank above.
  const back = color === WHITE ? -1 : 1;
  for (const df of [-1, 1]) {
    const file = fileOf(target) + df;
    const rank = rankOf(target) + back;
    if (!onBoard(file, rank)) continue;
    const piece = cells[file + 8 * rank];
    if (piece && piece.color === color && piece.type === "p") found.push(file + 8 * rank);
  }
  for (const square of KNIGHT[target]) {
    const piece = cells[square];
    if (piece && piece.color === color && piece.type === "n") found.push(square);
  }
  for (const square of KING[target]) {
    const piece = cells[square];
    if (piece && piece.color === color && piece.type === "k") found.push(square);
  }
  for (let d = 0; d < 8; d += 1) {
    const square = firstPiece(cells, target, d);
    if (square < 0) continue;
    const piece = cells[square];
    if (piece.color === color && slidesAlong(piece.type, d)) found.push(square);
  }
  return found;
}

/** Whether any piece of `color` hits `target`. */
export function isAttacked(cells, target, color) {
  return attackersOf(cells, target, color).length > 0;
}

/**
 * When a rook, bishop or queen lines up with `target` but something stands in between: the
 * squares in the way, nearest first. Null when it isn't on such a line, or the line is open.
 */
export function blockersOnLine(cells, from, target) {
  const piece = cells[from];
  if (!piece) return null;
  const d = directionBetween(from, target);
  if (d < 0 || !slidesAlong(piece.type, d)) return null;
  const blockers = squaresBetween(from, target).filter((square) => cells[square]);
  return blockers.length ? blockers : null;
}

// ---------------------------------------------------------------------------
// Pins

function guardedWithout(cells, square, gone) {
  const saved = cells[gone];
  cells[gone] = null;
  const guarded = isAttacked(cells, square, cells[square].color);
  cells[gone] = saved;
  return guarded;
}

/**
 * The pin on the piece at `square`, or null: { square, by, behind, absolute }.
 * Absolute: moving off the line would expose its own king (it may not move off it).
 * Relative: it would expose a queen or rook of its side worth at least as much as itself, to
 * a pinner that is cheaper than that piece or finds it unguarded.
 */
export function pinOn(cells, square) {
  const piece = cells[square];
  if (!piece || piece.type === "k") return null;
  let relative = null;
  for (let d = 0; d < 8; d += 1) {
    const by = firstPiece(cells, square, d);
    if (by < 0) continue;
    const pinner = cells[by];
    if (pinner.color === piece.color || !slidesAlong(pinner.type, d)) continue;
    const behind = firstPiece(cells, square, d ^ 1);
    if (behind < 0) continue;
    const shield = cells[behind];
    if (shield.color !== piece.color) continue;
    if (shield.type === "k") return { square, by, behind, absolute: true };
    if (relative || (shield.type !== "q" && shield.type !== "r")) continue;
    if (VALUES[piece.type] > VALUES[shield.type]) continue;
    if (VALUES[pinner.type] < VALUES[shield.type] || !guardedWithout(cells, behind, square)) {
      relative = { square, by, behind, absolute: false };
    }
  }
  return relative;
}

/** Every pin on `color`'s pieces, absolute ones first. */
export function pinsOf(cells, color) {
  const pins = squaresOf(cells, color)
    .map((square) => pinOn(cells, square))
    .filter(Boolean);
  return pins.sort((a, b) => Number(b.absolute) - Number(a.absolute));
}

/** Whether a pinned piece moving to `to` stays on the pin's line (it may slide along it, or take the pinner). */
export function staysOnPinLine(pin, to) {
  if (to === pin.by) return true;
  const between = squaresBetween(pin.behind, pin.by);
  return Boolean(between && between.includes(to));
}

// ---------------------------------------------------------------------------
// Exchanges

/** Whether the piece on `from` may take on `to` without leaving its own king attacked. `taken` is `to` except for en passant. */
function captureIsLegal(cells, from, to, taken = to) {
  const mover = cells[from];
  const victim = cells[taken];
  const landing = cells[to];
  cells[taken] = null;
  cells[from] = null;
  cells[to] = mover;
  const king = mover.type === "k" ? to : kingOf(cells, mover.color);
  const legal = king < 0 || !isAttacked(cells, king, other(mover.color));
  cells[to] = landing;
  cells[taken] = victim;
  cells[from] = mover;
  return legal;
}

const promotes = (piece, to) => piece.type === "p" && (rankOf(to) === 0 || rankOf(to) === 7);

/** What a capture is worth by itself: the piece taken, plus 8 when a pawn becomes a queen. */
function captureGain(cells, from, to, taken = to) {
  const gain = VALUES[cells[taken].type];
  return promotes(cells[from], to) ? gain + VALUES.q - VALUES.p : gain;
}

/** Plays a capture on the cells. Returns the function that takes it back. */
function playCapture(cells, from, to, taken = to) {
  const mover = cells[from];
  const victim = cells[taken];
  const landing = cells[to];
  cells[taken] = null;
  cells[from] = null;
  cells[to] = promotes(mover, to) ? QUEENS[mover.color] : mover;
  return () => {
    cells[to] = landing;
    cells[taken] = victim;
    cells[from] = mover;
  };
}

/**
 * The pieces of `color` that may take on `square`, cheapest first. With `pins: false`, pins are
 * ignored (only the king still may not take a guarded piece), which shows when a pin is the
 * reason a piece can be won.
 */
function capturersOf(cells, square, color, { pins = true } = {}) {
  return attackersOf(cells, square, color)
    .filter((from) => (pins || cells[from].type === "k" ? captureIsLegal(cells, from, square) : true))
    .sort((a, b) => ORDER[cells[a].type] - ORDER[cells[b].type]);
}

/**
 * The best `color` can get from the trades on `square` when it is their turn there: each side
 * takes back with its cheapest capturer, and either side may stop. 0 when taking doesn't pay.
 */
export function exchangeOn(cells, square, color, options) {
  if (!cells[square] || cells[square].color === color) return 0;
  const capturers = capturersOf(cells, square, color, options);
  if (!capturers.length) return 0;
  const from = capturers[0];
  const gain = captureGain(cells, from, square);
  const undo = playCapture(cells, from, square);
  const reply = exchangeOn(cells, square, other(color), options);
  undo();
  return Math.max(0, gain - reply);
}

/** What one capture comes to once the trades on its square are done, for the side taking. */
export function captureValue(cells, from, to, taken = to, options) {
  const color = cells[from].color;
  const gain = captureGain(cells, from, to, taken);
  const undo = playCapture(cells, from, to, taken);
  const reply = exchangeOn(cells, to, other(color), options);
  undo();
  return gain - reply;
}

/**
 * Every legal way for `color` to take the piece on `square` in `position` (en passant too, when
 * it is `color`'s turn): [{ from, to, taken, enPassant }]. Legal means the capturer's king is
 * safe afterwards, so a pinned piece can't take off its line.
 */
export function capturesOf(position, square, color) {
  const cells = position.cells;
  const target = cells[square];
  if (!target || target.color === color) return [];
  const out = [];
  for (const from of attackersOf(cells, square, color)) {
    if (captureIsLegal(cells, from, square)) out.push({ from, to: square, taken: square, enPassant: false });
  }
  const ep = position.turn === color ? position.ep : -1;
  const behind = square + (color === WHITE ? 8 : -8);
  if (target.type === "p" && ep >= 0 && ep === behind) {
    for (const df of [-1, 1]) {
      const file = fileOf(square) + df;
      if (file < 0 || file > 7) continue;
      const from = file + 8 * rankOf(square);
      const piece = cells[from];
      if (piece && piece.color === color && piece.type === "p" && captureIsLegal(cells, from, ep, square)) {
        out.push({ from, to: ep, taken: square, enPassant: true });
      }
    }
  }
  return out;
}

/**
 * Static exchange: what `color` wins by taking the piece on `square`, trading off with legal
 * moves only, so a pinned defender can't take back. Returns the best first capture and its value
 * in pawns ({ value: 0, capture: null } when nothing can take it; the value is negative when every
 * capture loses). `pins: false` ignores pins, to show when a pin is what makes a piece fall.
 */
export function exchange(position, square, color, { pins = true } = {}) {
  let best = { value: 0, capture: null };
  const cells = position.cells.slice();
  for (const capture of capturesOf(position, square, color)) {
    const value = captureValue(cells, capture.from, capture.to, capture.taken, { pins });
    if (!best.capture || value > best.value) best = { value, capture };
  }
  return best;
}

/**
 * Whether the piece on `from` could take back on `target` once the other side takes there
 * (with its cheapest piece; when nothing of theirs can, as if something stood there).
 * Returns { ok: true }, or { ok: false, pin } when a pin holds it, or { ok: false, coveredBy }
 * when it is the king and the square is still covered.
 */
export function canTakeBack(cells, from, target) {
  const color = cells[from].color;
  const enemy = other(color);
  const board = cells.slice();
  const occupant = board[target];
  if (!occupant || occupant.color === color) {
    const takers = capturersOf(board, target, enemy);
    if (takers.length) playCapture(board, takers[0], target);
    else board[target] = { type: "p", color: enemy };
  }
  if (captureIsLegal(board, from, target)) return { ok: true };
  if (board[from].type === "k") {
    const undo = playCapture(board, from, target);
    const coveredBy = attackersOf(board, target, enemy)[0] ?? -1;
    undo();
    return { ok: false, coveredBy };
  }
  return { ok: false, pin: pinOn(board, from) };
}

/**
 * Plays out the trades on `square` that `color` would choose (see exchangeOn) on a copy of the
 * cells: { value, cells } with the value from `color`'s side.
 */
export function settleExchange(cells, square, color) {
  const board = cells.slice();
  let side = color;
  let sign = 1;
  let value = 0;
  for (let step = 0; step < 32; step += 1) {
    if (exchangeOn(board, square, side) <= 0) break;
    const from = capturersOf(board, square, side)[0];
    value += sign * captureGain(board, from, square);
    playCapture(board, from, square);
    side = other(side);
    sign = -sign;
  }
  return { value, cells: board };
}

// ---------------------------------------------------------------------------
// Positions: chess.js for the rules

/** A legal move, in the shapes Leo needs. SAN is worked out the first time it's asked for. */
class LegalMove {
  constructor(position, raw, all) {
    this.position = position;
    this.raw = raw;
    this.all = all;
    this.sanCache = null;
    this.color = raw.color;
    this.piece = raw.piece;
    this.fromIndex = from0x88(raw.from);
    this.toIndex = from0x88(raw.to);
    this.from = squareName(this.fromIndex);
    this.to = squareName(this.toIndex);
    this.captured = raw.captured ?? null;
    this.promotion = raw.promotion ?? null;
    this.enPassant = Boolean(raw.flags & BITS.EP_CAPTURE);
    this.castle = raw.flags & BITS.KSIDE_CASTLE ? "short" : raw.flags & BITS.QSIDE_CASTLE ? "long" : null;
    this.uci = this.from + this.to + (this.promotion ?? "");
  }

  get san() {
    if (this.sanCache === null) this.sanCache = this.position.chess._moveToSan(this.raw, this.all);
    return this.sanCache;
  }

  get check() {
    return /[+#]$/.test(this.san);
  }

  get mate() {
    return this.san.endsWith("#");
  }

  get isCapture() {
    return this.captured !== null;
  }

  /** Where the taken piece stands: `to`, except for en passant. */
  get takenIndex() {
    if (!this.enPassant) return this.toIndex;
    return this.toIndex + (this.color === WHITE ? -8 : 8);
  }
}

/**
 * A position. Positions made from one another share a cache keyed by FEN, so a position reached
 * twice in one check is worked out once.
 */
export class Position {
  /** `trusted`: the FEN came from chess.js itself, so it needn't be validated again. */
  constructor(fen, { cache = new Map(), trusted = false } = {}) {
    this.chess = new Chess(fen, { skipValidation: trusted });
    this.fen = this.chess.fen();
    this.turn = this.chess.turn();
    this.cells = cellsOf(this.chess);
    this.ep = this.chess._epSquare >= 0 ? from0x88(this.chess._epSquare) : -1;
    this.castling = this.fen.split(" ")[2];
    this.cache = cache;
    this.legalCache = null;
    this.uciCache = null;
    this.checkCache = null;
    this.nullCache = undefined;
    cache.set(this.fen, this);
  }

  get inCheck() {
    if (this.checkCache === null) this.checkCache = this.chess.inCheck();
    return this.checkCache;
  }

  /** Every legal move, in chess.js's order. */
  get legal() {
    if (!this.legalCache) {
      const raws = this.chess._moves({ legal: true });
      this.legalCache = raws.map((raw) => new LegalMove(this, raw, raws));
    }
    return this.legalCache;
  }

  /** The legal move with this engine notation ("e7e8q"), or null. A promotion without its letter is a queen. */
  byUci(uci) {
    if (!this.uciCache) this.uciCache = new Map(this.legal.map((move) => [move.uci, move]));
    if (typeof uci !== "string") return null;
    const key = uci.trim().toLowerCase();
    return this.uciCache.get(key) ?? this.uciCache.get(key + "q") ?? null;
  }

  get isCheckmate() {
    return this.inCheck && this.legal.length === 0;
  }

  get isStalemate() {
    return !this.inCheck && this.legal.length === 0;
  }

  /** A move that mates at once, or null. Only checking moves are looked at closely. */
  mateInOne() {
    return this.legal.find((move) => move.mate) ?? null;
  }

  /** The position after a legal move of this position. */
  after(move) {
    const chess = this.chess;
    chess._makeMove(move.raw);
    const fen = chess.fen();
    chess._undoMove();
    return this.cache.get(fen) ?? new Position(fen, { cache: this.cache, trusted: true });
  }

  /** This position with the other side to move (N), or null when the side to move is in check. */
  nullMove() {
    if (this.nullCache === undefined) {
      const fen = nullMoveFen(this);
      this.nullCache = fen ? (this.cache.get(fen) ?? new Position(fen, { cache: this.cache, trusted: true })) : null;
    }
    return this.nullCache;
  }
}

/**
 * The null-move FEN: the same board with the other side to move and no en passant, which answers
 * "what would they do if it were their turn?". Null when the side to move is in check, because
 * then the other side could take the king.
 */
export function nullMoveFen(fenOrPosition) {
  const position = fenOrPosition instanceof Position ? fenOrPosition : new Position(fenOrPosition);
  if (position.inCheck) return null;
  const [placement, turn, castling, , halfmoves, fullmoves] = position.fen.split(" ");
  const moveNumber = Number(fullmoves) + (turn === BLACK ? 1 : 0);
  return [placement, other(turn), castling, "-", halfmoves, moveNumber].join(" ");
}

// ---------------------------------------------------------------------------
// Engine lines

function pseudoMove(chess, uci) {
  const from = uci.slice(0, 2);
  const to = uci.slice(2, 4);
  const promotion = uci[4] ?? "q";
  const options = chess._moves({ legal: false, square: from });
  return options.find((raw) => squareName(from0x88(raw.to)) === to && (!raw.promotion || raw.promotion === promotion)) ?? null;
}

function leavesKingSafe(chess, raw) {
  chess._makeMove(raw);
  const safe = !chess._isKingAttacked(raw.color);
  chess._undoMove();
  return safe;
}

/**
 * Plays engine moves from a position for as long as they are legal (a `pv` is trusted only that
 * far). Returns the moves played (SAN for the first `sanCount`), and the cells, side to move and
 * FEN at the end, and whether the end is checkmate. One chess.js board checks each move by hand,
 * which costs far less than a full move list per ply.
 */
export function playLine(position, ucis, { sanCount = 4 } = {}) {
  const chess = new Chess(position.fen, { skipValidation: true });
  const played = [];
  for (const uci of Array.isArray(ucis) ? ucis : []) {
    if (typeof uci !== "string" || !UCI.test(uci)) break;
    const raw = pseudoMove(chess, uci);
    if (!raw || !leavesKingSafe(chess, raw)) break;
    const san = played.length < sanCount ? chess._moveToSan(raw, chess._moves({ legal: true, piece: raw.piece })) : null;
    const from = from0x88(raw.from);
    const to = from0x88(raw.to);
    const enPassant = Boolean(raw.flags & BITS.EP_CAPTURE);
    played.push({
      uci: squareName(from) + squareName(to) + (raw.promotion ?? ""),
      san,
      color: raw.color,
      piece: raw.piece,
      from: squareName(from),
      to: squareName(to),
      toIndex: to,
      captured: raw.captured ?? null,
      promotion: raw.promotion ?? null,
      enPassant,
    });
    chess._makeMove(raw);
  }
  const inCheck = chess.inCheck();
  return {
    played,
    cells: cellsOf(chess),
    turn: chess.turn(),
    fen: chess.fen(),
    mate: inCheck && chess._moves({ legal: true }).length === 0,
  };
}

// ---------------------------------------------------------------------------
// Reading a written move

const PIECE_NAMES = { k: "king", q: "queen", r: "rook", b: "bishop", n: "knight", p: "pawn" };

/** How a reason talks about the mover: the player ("you") or the opponent ("they"). */
function voiceOf(who) {
  return who === "they"
    ? { You: "They", you: "them", your: "their", yours: "theirs", Youre: "They're", have: "have" }
    : { You: "You", you: "you", your: "your", yours: "yours", Youre: "You're", have: "have" };
}

function cleanWritten(text) {
  if (typeof text !== "string") return "";
  let written = text.replace(/\s+/g, "").replace(/[!?]+$/, "").replace(/(e\.?p\.?)$/i, "");
  written = written.replace(/[+#]+$/, "");
  if (/^[0oO]-?[0oO](-?[0oO])?$/.test(written)) return written.replace(/-/g, "").length === 3 ? "O-O-O" : "O-O";
  // "Ng1-f3" and "e2-e4" are long forms; the dash adds nothing.
  return written.replace(/^([KQRBNP]?[a-h][1-8])-([a-h][1-8])/, "$1$2");
}

const SAN_FORM = /^([KQRBNP])?([a-h])?([1-8])?([x:])?([a-h][1-8])(?:=?([QRBNqrbn]))?$/;

function readSan(written) {
  const match = SAN_FORM.exec(written);
  if (!match) return null;
  return {
    piece: (match[1] ?? "P").toLowerCase(),
    fromFile: match[2] ? FILES.indexOf(match[2]) : null,
    fromRank: match[3] ? Number(match[3]) - 1 : null,
    capture: Boolean(match[4]),
    to: squareIndex(match[5]),
    promotion: match[6] ? match[6].toLowerCase() : null,
  };
}

function fitsSan(move, want) {
  if (move.piece !== want.piece || move.toIndex !== want.to) return false;
  if (want.fromFile !== null && fileOf(move.fromIndex) !== want.fromFile) return false;
  if (want.fromRank !== null && rankOf(move.fromIndex) !== want.fromRank) return false;
  if (move.promotion) return move.promotion === (want.promotion ?? "q");
  return want.promotion === null;
}

/** Readings of a written move to try in turn: as written, then with a lowercase piece letter read as a piece. */
function readings(written) {
  const out = [];
  const first = readSan(written);
  if (first) out.push(first);
  if (/^[kqrbn]/.test(written)) {
    const capital = readSan(written[0].toUpperCase() + written.slice(1));
    if (capital) out.push(capital);
  }
  return out;
}

/**
 * The legal move a written move means in `position`, read leniently: exact SAN, without +/#, a
 * missing "x", a missing promotion piece (a queen), "0-0", a from-square ("Ng1f3", "Ng1-f3"),
 * spaces ("N f3"), engine notation ("g1f3"). `who` words the reasons for the player ("you") or
 * the opponent ("they").
 * Returns { move }, { ambiguous: [moves] } when it fits more than one, or { illegal: reason }.
 */
export function resolveMove(position, text, who = "you") {
  const written = cleanWritten(text);
  if (!written) return { illegal: "I couldn't read that move." };
  if (written === "O-O" || written === "O-O-O") return resolveCastle(position, written === "O-O" ? "short" : "long", who);
  if (UCI.test(written.toLowerCase())) {
    const move = position.byUci(written.toLowerCase());
    if (move) return { move };
  }
  const options = readings(written);
  if (!options.length) return { illegal: "I couldn't read that move." };
  for (const want of options) {
    const matches = position.legal.filter((move) => fitsSan(move, want));
    if (matches.length === 1) return { move: matches[0] };
    if (matches.length > 1) return { ambiguous: matches };
  }
  return { illegal: whyIllegal(position, options[0], who) };
}

function resolveCastle(position, wing, who) {
  const move = position.legal.find((candidate) => candidate.castle === wing);
  return move ? { move } : { illegal: whyNoCastle(position, wing, who) };
}

function pieceAt(cells, index) {
  return `the ${PIECE_NAMES[cells[index].type]} on ${squareName(index)}`;
}

function whyNoCastle(position, wing, who) {
  const v = voiceOf(who);
  const color = position.turn;
  const cells = position.cells;
  const right = color === WHITE ? (wing === "short" ? "K" : "Q") : wing === "short" ? "k" : "q";
  const home = color === WHITE ? 0 : 56;
  const king = home + 4;
  if (!position.castling.includes(right) || cells[king]?.type !== "k") {
    return `${v.You} can't castle that way any more: ${v.your} king or rook has moved.`;
  }
  if (position.inCheck) return `${v.You} can't castle out of check.`;
  const between = wing === "short" ? [home + 5, home + 6] : [home + 3, home + 2, home + 1];
  const blocker = between.find((index) => cells[index]);
  if (blocker !== undefined) return `${v.You} can't castle yet: ${pieceAt(cells, blocker)} is in the way.`;
  const path = wing === "short" ? [home + 5, home + 6] : [home + 3, home + 2];
  for (const index of path) {
    const attackers = attackersOf(cells, index, other(color));
    if (!attackers.length) continue;
    const word = index === path[path.length - 1] ? "into" : "through";
    return `${v.You} can't castle ${word} check: ${squareName(index)} is covered by ${pieceAt(cells, attackers[0])}.`;
  }
  return `${v.You} can't castle here.`;
}

/** Why a move that fits no legal move isn't possible, in a short sentence. */
function whyIllegal(position, want, who) {
  const v = voiceOf(who);
  const cells = position.cells;
  const color = position.turn;
  const to = squareName(want.to);
  const name = PIECE_NAMES[want.piece];
  const own = squaresOf(cells, color, want.piece).filter(
    (index) => (want.fromFile === null || fileOf(index) === want.fromFile) && (want.fromRank === null || rankOf(index) === want.fromRank),
  );
  if (!squaresOf(cells, color, want.piece).length) return `${v.You} don't have a ${name}.`;
  const target = cells[want.to];
  if (target && target.color === color) return `${v.You} can't take ${v.your} own ${PIECE_NAMES[target.type]} on ${to}.`;
  if (want.piece === "p") return whyPawnCannot(position, want, v);
  const reaching = own.filter((index) => hits(cells, index, want.to));
  if (!reaching.length) {
    for (const index of own) {
      const blockers = blockersOnLine(cells, index, want.to);
      if (blockers) return `The ${name} on ${squareName(index)} can't get to ${to}: ${pieceAt(cells, blockers[0])} is in the way.`;
    }
    return `No ${name} of ${v.yours} can reach ${to}.`;
  }
  return whyKingForbids(position, reaching, want, v);
}

/** The piece could get there, so the king forbids it: in check, pinned, or walking into check. */
function whyKingForbids(position, reaching, want, v) {
  const cells = position.cells;
  if (want.piece === "k") return `${cap(v.your)} king can't go to ${squareName(want.to)}: it would be in check.`;
  if (position.inCheck) return `${v.Youre} in check, and that doesn't get ${v.you} out of it.`;
  for (const index of reaching) {
    const pin = pinOn(cells, index);
    if (pin && pin.absolute) return `${cap(pieceAt(cells, index))} is pinned to ${v.your} king.`;
  }
  return `That would leave ${v.your} king in check.`;
}

function whyPawnCannot(position, want, v) {
  const cells = position.cells;
  const color = position.turn;
  const forward = color === WHITE ? 8 : -8;
  const to = squareName(want.to);
  const pushing = !want.capture && (want.fromFile === null || want.fromFile === fileOf(want.to));
  const isOwnPawn = (index) => index >= 0 && index < 64 && cells[index]?.type === "p" && cells[index].color === color;
  let from = -1;
  if (pushing) {
    const one = want.to - forward;
    const two = want.to - 2 * forward;
    const startRank = color === WHITE ? 1 : 6;
    if (isOwnPawn(one)) {
      if (cells[want.to]) return `The pawn on ${squareName(one)} is blocked.`;
      from = one;
    } else if (isOwnPawn(two) && rankOf(two) === startRank && !cells[one]) {
      if (cells[want.to]) return `The pawn on ${squareName(two)} is blocked.`;
      from = two;
    } else if (isOwnPawn(two) && rankOf(two) === startRank) {
      return `The pawn on ${squareName(two)} is blocked.`;
    } else {
      return `No pawn of ${v.yours} can reach ${to}.`;
    }
  } else {
    const file = want.fromFile ?? -1;
    const candidates = [file, fileOf(want.to) - 1, fileOf(want.to) + 1]
      .filter((f) => f >= 0 && f < 8 && Math.abs(f - fileOf(want.to)) === 1)
      .map((f) => f + 8 * (rankOf(want.to) - forward / 8));
    from = candidates.find(isOwnPawn) ?? -1;
    if (from < 0) return `No pawn of ${v.yours} can take on ${to}.`;
    if (!cells[want.to] && position.ep !== want.to) return `There's nothing to take on ${to}.`;
  }
  return whyKingForbids(position, [from], want, v);
}

function cap(text) {
  return text ? text[0].toUpperCase() + text.slice(1) : text;
}

// ---------------------------------------------------------------------------
// For Claude's prompt

function pieceList(cells, color) {
  return squaresOf(cells, color)
    .sort((a, b) => TYPE_ORDER.indexOf(cells[a].type) - TYPE_ORDER.indexOf(cells[b].type) || a - b)
    .map((index) => cells[index].type.toUpperCase() + squareName(index));
}

/**
 * The position as Claude needs it to read what the player said: whose move, check, every piece
 * ("Kg1", "Pa2"), the legal moves, and the opponent's moves if it were their turn (empty in check).
 */
export function describePosition(fen) {
  const position = new Position(fen);
  const theirs = position.nullMove();
  return {
    side: position.turn === WHITE ? "white" : "black",
    inCheck: position.inCheck,
    pieces: { white: pieceList(position.cells, WHITE), black: pieceList(position.cells, BLACK) },
    legal: position.legal.map((move) => move.san),
    theirs: theirs ? theirs.legal.map((move) => move.san) : [],
  };
}
