// Moves and pieces in plain words, for Leo's voice and for Claude: "Qxf7#" becomes
// "queen takes f7, checkmate". Squares stay as they are ("f7"), because they speak well and the
// answer's guard checks them. Leo talks to the player as "you"; the opponent is "they".

export const PIECE_NAMES = { k: "king", q: "queen", r: "rook", b: "bishop", n: "knight", p: "pawn" };

const LETTERS = { K: "k", Q: "q", R: "r", B: "b", N: "n" };
const SAN_FORM = /^([KQRBN])?([a-h])?([1-8])?(x)?([a-h][1-8])(?:=?([QRBN]))?$/;

/**
 * A move in words.
 * "Nf3" → "knight to f3", "Nbd2" → "knight to d2", "exd5" → "pawn takes d5", "e4" → "e4",
 * "O-O" → "castles", "O-O-O" → "castles long", "e8=Q+" → "e8, promoting to a queen, check",
 * "Qxf7#" → "queen takes f7, checkmate".
 * Options: `suffix: false` leaves out ", check" / ", checkmate" (for "… is checkmate");
 * `noun: true` says "castling" instead of "castles" (for "castling is the best move");
 * `enPassant: true` adds ", en passant".
 * Something that isn't a move comes back as "that move", so no notation can leak into speech.
 */
export function moveWords(san, { suffix = true, noun = false, enPassant = false } = {}) {
  if (typeof san !== "string") return "that move";
  let text = san.trim().replace(/[!?]+$/, "");
  const ending = text.endsWith("#") ? "checkmate" : text.endsWith("+") ? "check" : null;
  text = text.replace(/[+#]+$/, "");
  let words;
  if (/^[O0]-[O0]-[O0]$/.test(text)) {
    words = noun ? "castling long" : "castles long";
  } else if (/^[O0]-[O0]$/.test(text)) {
    words = noun ? "castling" : "castles";
  } else {
    const match = SAN_FORM.exec(text);
    if (!match) return "that move";
    const [, letter, , , takes, to, promotion] = match;
    const piece = letter ? PIECE_NAMES[LETTERS[letter]] : "pawn";
    if (takes) words = `${piece} takes ${to}`;
    else words = letter ? `${piece} to ${to}` : to;
    if (promotion) words += `, promoting to a ${PIECE_NAMES[LETTERS[promotion]]}`;
    if (enPassant) words += ", en passant";
  }
  if (suffix && ending) words += `, ${ending}`;
  return words;
}

/** A line of moves in words, joined for speech: "knight takes e5, pawn takes e5, then queen to d4". */
export function lineWords(sans) {
  const words = sans.map((san) => moveWords(san));
  if (words.length <= 1) return words.join("");
  return `${words.slice(0, -1).join(", ")}, then ${words[words.length - 1]}`;
}

export function pieceName(type) {
  return PIECE_NAMES[type] ?? "piece";
}

/** "your" for the player's pieces, "their" for the opponent's. */
export function ownerWord(color, player) {
  return color === player ? "your" : "their";
}

/** "the bishop on c5", or "your bishop on c5" / "their bishop on c5" with an owner. */
export function pieceOn(type, square, owner = "the") {
  return `${owner} ${pieceName(type)} on ${square}`;
}

export function sideName(color) {
  return color === "w" ? "White" : "Black";
}

/** What a `wins` or `material` claim's `gain` means in words: "a pawn", "the exchange", "mate". */
export const GAIN_WORDS = {
  pawn: "a pawn",
  two_pawns: "two pawns",
  exchange: "the exchange",
  piece: "a piece",
  rook: "a rook",
  queen: "the queen",
  mate: "mate",
  even: "nothing",
};

/** How the eval bands sound, from the side's own view. */
export const BAND_WORDS = {
  winning: "winning",
  better: "better",
  slightly_better: "a little better",
  equal: "about equal",
  slightly_worse: "a little worse",
  worse: "worse",
  losing: "losing",
};

const NUMBERS = ["no", "one", "two", "three", "four", "five", "six", "seven", "eight", "nine", "ten"];

/** 2 → "two"; larger numbers stay as digits. */
export function numberWord(n) {
  return NUMBERS[n] ?? String(n);
}

/** "a pawn", "two pawns", "a piece", "three pieces": a count of something. */
export function countOf(n, singular, plural = `${singular}s`) {
  if (n === 1) return `a ${singular}`;
  return `${numberWord(n)} ${plural}`;
}

/** The first letter in capitals. */
export function capitalize(text) {
  return text ? text[0].toUpperCase() + text.slice(1) : text;
}

function listLosses(lost) {
  const parts = [];
  if (lost.q) parts.push(lost.q === 1 ? "the queen" : countOf(lost.q, "queen"));
  if (lost.r) parts.push(countOf(lost.r, "rook"));
  const minors = lost.n + lost.b;
  if (minors) parts.push(countOf(minors, "piece"));
  if (lost.p) parts.push(countOf(lost.p, "pawn"));
  if (parts.length <= 1) return parts.join("");
  return `${parts.slice(0, -1).join(", ")} and ${parts[parts.length - 1]}`;
}

const WORTH = { q: 9, r: 5, b: 3, n: 3, p: 1 };

function worth(pieces) {
  return Object.keys(WORTH).reduce((sum, type) => sum + WORTH[type] * pieces[type], 0);
}

/** Takes out what both sides gave up alike: a rook for a rook, or a bishop for a knight. */
function cancelLikeForLike(lost, gave) {
  for (const type of ["q", "r", "p"]) {
    const both = Math.min(lost[type], gave[type]);
    lost[type] -= both;
    gave[type] -= both;
  }
  // Knights and bishops are both "pieces", so a bishop for a knight cancels too.
  let minors = Math.min(lost.n + lost.b, gave.n + gave.b);
  while (minors > 0) {
    if (lost.n) lost.n -= 1;
    else lost.b -= 1;
    if (gave.n) gave.n -= 1;
    else gave.b -= 1;
    minors -= 1;
  }
}

function isOnly(pieces, type, count = 1) {
  return Object.keys(WORTH).every((t) => (t === type ? pieces[t] === count : pieces[t] === 0));
}

/**
 * What one side won and gave over a line, like for like taken out, from how many pieces of each
 * kind each side had before and after (counts as board.js pieceCounts gives them):
 * { won: { q, r, b, n, p }, gave: {...}, promoted } with `promoted` the winner's new queens.
 */
export function tradeOf(before, after, winner) {
  const loser = winner === "w" ? "b" : "w";
  const won = {};
  const gave = {};
  for (const type of Object.keys(WORTH)) {
    won[type] = Math.max(0, before[loser][type] - after[loser][type]);
    gave[type] = Math.max(0, before[winner][type] - after[winner][type]);
  }
  // A pawn that became a queen isn't a pawn given away: it is the gain.
  const promoted = Math.max(0, after[winner].q - before[winner].q);
  gave.p = Math.max(0, gave.p - promoted);
  cancelLikeForLike(won, gave);
  return { won, gave, promoted };
}

/**
 * What one side wins over a line, in words: "a pawn", "two pawns", "a piece", "the exchange",
 * "a rook", "the queen", "a piece for a pawn", "the queen for a rook", "a new queen"; null when
 * the winner doesn't come out ahead.
 */
export function tradeWords(before, after, winner) {
  const { won, gave, promoted } = tradeOf(before, after, winner);
  if (worth(won) + 8 * promoted <= worth(gave)) return null;
  const wonWords = listLosses(won);
  const gaveWords = listLosses(gave);
  if (promoted) return wonWords ? `${wonWords} and a new queen` : "a new queen";
  if (!gaveWords) return wonWords;
  // A rook for a knight or bishop has its own name.
  if (isOnly(won, "r") && gave.r === 0 && gave.q === 0 && gave.p === 0 && gave.n + gave.b === 1) return "the exchange";
  return `${wonWords} for ${gaveWords}`;
}
