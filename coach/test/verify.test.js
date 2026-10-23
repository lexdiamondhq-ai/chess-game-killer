// Leo's verdicts: the fixtures (real positions, Stockfish's numbers from make_facts.mjs, claims as
// Claude would hand them over), the contract of `checked` and `spoken`, the rules that work
// without the engine, and the speed.
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { test } from "node:test";
import { CLAIM_KINDS, bandOf, gradeMove, verifyTalk, winningChances } from "../src/verify.js";

const FIXTURES = JSON.parse(readFileSync(new URL("./fixtures/talks.json", import.meta.url), "utf8"));

function run(fixture, changes = {}) {
  return verifyTalk({
    fen: fixture.fen,
    facts: fixture.facts,
    parsed: fixture.parsed,
    reveal: fixture.reveal === true,
    said: fixture.said,
    ...changes,
  });
}

function fixture(name) {
  const found = FIXTURES.find((item) => item.name.startsWith(name));
  assert.ok(found, `no fixture "${name}"`);
  return found;
}

/** A claim as claims.js hands it over. */
function claim(kind, said, fields = {}) {
  return {
    said,
    kind,
    side: fields.side ?? "me",
    piece: fields.piece ?? "",
    square: fields.square ?? "",
    target: fields.target ?? "",
    moves: fields.moves ?? [],
    afterMove: fields.afterMove ?? false,
    negated: fields.negated ?? false,
    eval: fields.eval ?? "",
    gain: fields.gain ?? "",
  };
}

function notesOf(checked) {
  return [checked.move?.note, ...checked.claims.map((item) => item.note), ...checked.missed.map((item) => item.note)].filter(Boolean);
}

/** Every string Leo may say, which is every string in `spoken` but the player's own words. */
function spokenStrings(spoken) {
  return [...spoken.right, ...spoken.wrong, ...spoken.partly, ...spoken.unclear, spoken.move, ...spoken.missed, spoken.habit, spoken.nudge].filter(
    (text) => typeof text === "string",
  );
}

// The same patterns answer.js's guard rejects in Leo's answer.
const NOTATION = [
  /\b[KQRBN][a-h]?[1-8]?x?[a-h][1-8]/,
  /\b[a-h]x[a-h][1-8]/,
  /\b[O0]-[O0](?:-[O0])?/,
  /\b[a-h][18]=?[QRBN]\b/,
  /\b[a-h][1-8][+#]/,
  /\b[a-h][1-8]-?[a-h][1-8]\b/,
  /\b\d+\.(?:\.\.)?\s*[a-h][1-8]\b/,
];
const NOT_SPOKEN = [/(?:^|[\s(])[+\-−]\d/, /\d\.\d/];
const SQUARE = /^[a-h][1-8]$/;
const squaresIn = (text) => text.match(/[a-h][1-8]/g) ?? [];

/** The protocol's promises that hold for every talk. */
function assertContract({ checked, spoken }, label) {
  assert.deepEqual(Object.keys(checked), ["understood", "player", "move", "claims", "missed", "habits", "eval", "best", "nudge"], label);
  assert.ok(!("type" in checked), label);
  assert.ok(checked.player === "white" || checked.player === "black", label);
  assert.ok(checked.claims.length <= 6, label);
  assert.ok(checked.missed.length <= 2, label);
  checked.claims.forEach((item, index) => {
    assert.deepEqual(Object.keys(item), ["id", "said", "kind", "verdict", "note", "squares", "arrows"], label);
    assert.equal(item.id, `c${index + 1}`, label);
    assert.ok(CLAIM_KINDS.includes(item.kind), label);
    assert.ok(["right", "wrong", "partly", "unclear"].includes(item.verdict), label);
  });
  if (checked.move) {
    assert.deepEqual(Object.keys(checked.move), ["said", "san", "uci", "grade", "note", "reply", "squares", "arrows"], label);
    assert.ok(
      ["checkmate", "best", "excellent", "good", "inaccuracy", "mistake", "blunder", "illegal", "unknown"].includes(checked.move.grade),
      label,
    );
    if (checked.move.grade === "illegal") assert.equal(checked.move.san, null, label);
  }
  for (const item of checked.missed) {
    assert.deepEqual(Object.keys(item), ["kind", "note", "squares", "arrows"], label);
    assert.ok(["threat", "hanging", "mate", "free"].includes(item.kind), label);
  }
  for (const key of ["threats", "forcing", "safety"]) assert.ok(["good", "missed", "none"].includes(checked.habits[key]), label);
  assert.deepEqual(Object.keys(checked.habits), ["threats", "forcing", "safety"], label);
  for (const item of [checked.move, ...checked.claims, ...checked.missed].filter(Boolean)) {
    assert.equal(typeof item.note, "string", label);
    assert.ok(item.note.length > 0 && item.note.length <= 160 && !item.note.includes("\n"), `${label}: ${item.note}`);
    for (const square of item.squares) assert.match(square, SQUARE, label);
    for (const line of item.arrows) {
      assert.match(line.from, SQUARE, label);
      assert.match(line.to, SQUARE, label);
      assert.ok(["good", "bad", "info"].includes(line.tone), label);
    }
  }
  assert.deepEqual(Object.keys(spoken), ["player", "said", "right", "wrong", "partly", "unclear", "move", "missed", "habit", "nudge"], label);
  assert.equal(spoken.player, checked.player, label);
  const strings = spokenStrings(spoken);
  for (const text of strings) {
    for (const pattern of [...NOTATION, ...NOT_SPOKEN]) assert.doesNotMatch(text, pattern, `${label}: "${text}"`);
  }
  assert.equal(spoken.right.length + spoken.wrong.length + spoken.partly.length + spoken.unclear.length, checked.claims.length, label);
  // Every square the screen names is one Leo may say.
  const sayable = new Set(strings.flatMap(squaresIn));
  for (const note of notesOf(checked)) {
    for (const square of squaresIn(note)) assert.ok(sayable.has(square), `${label}: ${square} from "${note}" isn't in spoken`);
  }
}

// ---------------------------------------------------------------------------
// The fixtures: `expect` is a part of `checked` (arrays in full, objects by the keys given), and
// `notes` are phrases that must turn up in its notes.

/** The first path where `actual` lacks what `expected` has, or null. */
function difference(expected, actual, path = "checked") {
  if (Array.isArray(expected)) {
    if (!Array.isArray(actual) || actual.length !== expected.length) return `${path} (${JSON.stringify(actual)})`;
    for (let index = 0; index < expected.length; index += 1) {
      const found = difference(expected[index], actual[index], `${path}[${index}]`);
      if (found) return found;
    }
    return null;
  }
  if (expected !== null && typeof expected === "object") {
    if (actual === null || typeof actual !== "object") return `${path} (${JSON.stringify(actual)})`;
    for (const [key, value] of Object.entries(expected)) {
      const found = difference(value, actual[key], `${path}.${key}`);
      if (found) return found;
    }
    return null;
  }
  return Object.is(expected, actual) ? null : `${path} (${JSON.stringify(actual)})`;
}

for (const item of FIXTURES) {
  test(`fixture: ${item.name}`, () => {
    const result = run(item);
    const { checked, spoken } = result;
    assertContract(result, item.name);
    assert.equal(difference(item.expect, checked), null);
    const notes = notesOf(checked).join("\n");
    for (const phrase of item.notes) assert.ok(notes.includes(phrase), `"${phrase}" not in:\n${notes}`);
    assert.equal(spoken.said, item.said);
    if (!item.reveal) assert.equal(checked.best, null);
  });
}

test("the fixtures cover every claim kind, right and wrong, and the hard cases", () => {
  const seen = new Set();
  for (const item of FIXTURES) item.parsed.claims.forEach((entry, index) => seen.add(`${entry.kind} ${item.expect.claims[index].verdict}`));
  for (const kind of CLAIM_KINDS) {
    assert.ok(seen.has(`${kind} right`), `no right ${kind}`);
    assert.ok(seen.has(`${kind} wrong`), `no wrong ${kind}`);
  }
  assert.ok(FIXTURES.length >= 14);
  const grades = FIXTURES.map((item) => item.expect.move?.grade);
  assert.ok(grades.includes("illegal"));
  assert.ok(grades.includes("checkmate"));
  assert.ok(grades.includes("blunder"));
  assert.ok(FIXTURES.some((item) => item.expect.move?.san === "O-O"), "castling");
  assert.ok(FIXTURES.some((item) => item.expect.move?.san?.includes("=Q")), "promotion");
  assert.ok(FIXTURES.some((item) => item.fen.split(" ")[3] !== "-" && item.expect.move?.san === "exf6"), "en passant");
  assert.ok(FIXTURES.some((item) => item.fen.split(" ")[1] === "b"), "Black to move");
  assert.ok(FIXTURES.some((item) => item.facts.threats.length === 0 && item.name.startsWith("in check")), "in check");
  assert.ok(FIXTURES.some((item) => item.expect.missed.some((entry) => entry.kind === "mate")), "a missed mate threat");
  assert.ok(FIXTURES.some((item) => item.expect.missed.some((entry) => entry.kind === "free")), "a missed free piece");
  assert.ok(FIXTURES.some((item) => item.expect.understood === false), "nothing about the position");
});

// ---------------------------------------------------------------------------
// Understanding and the shape of the answer

test("nothing usable parsed: understood is false, and the eval still comes through", () => {
  const item = fixture("scholar's mate: Qxf7 is mate");
  for (const parsed of [null, { about: false, move: null, claims: [] }, { about: true, move: null, claims: [] }, { about: true, claims: [{ kind: "vibes" }, null, 7] }]) {
    const result = run(item, { parsed, said: "hello there" });
    assertContract(result, "empty");
    assert.equal(result.checked.understood, false);
    assert.equal(result.checked.move, null);
    assert.deepEqual(result.checked.claims, []);
    assert.deepEqual(result.checked.missed, []);
    assert.deepEqual(result.checked.eval, { mate: 1 });
    assert.equal(result.spoken.said, "hello there");
  }
});

test("at most six claims, numbered c1 to c6", () => {
  const item = fixture("scholar's mate: Qxf7 is mate");
  const claims = Array.from({ length: 8 }, (_, index) => claim("attacks", `claim ${index + 1}`, { piece: "Q", square: "h5", target: "f7" }));
  const result = run(item, { parsed: { about: true, move: null, claims } });
  assertContract(result, "six");
  assert.deepEqual(result.checked.claims.map((entry) => entry.id), ["c1", "c2", "c3", "c4", "c5", "c6"]);
  assert.equal(result.checked.claims[5].said, "claim 6");
  // Nobody said Qxf7 is mate, so Leo points out that there is one, without naming it.
  assert.deepEqual(result.checked.missed.map((entry) => entry.note), ["You have mate in one."]);
  assert.equal(result.checked.nudge, "Look at your queen.");
});

test("without `said`, spoken.said is rebuilt from what Claude heard", () => {
  const item = fixture("italian: names the bishop");
  const { spoken } = run(item, { said: undefined });
  assert.equal(spoken.said, "I'll castle, his bishop eyes f2, my knight on f3 is safe");
});

// ---------------------------------------------------------------------------
// Facts: missing, malformed, reveal

test("without the facts, the rules still answer and the engine's judgments are unclear", () => {
  const item = fixture("italian: Ng5 hangs");
  const result = run(item, { facts: null, reveal: true });
  assertContract(result, "no facts");
  const { checked } = result;
  assert.deepEqual(checked.move && [checked.move.san, checked.move.grade], ["Ng5", "unknown"]);
  assert.match(checked.move.note, /numbers didn't come through/);
  assert.deepEqual(checked.claims.map((entry) => entry.verdict), ["right", "unclear", "unclear"]);
  assert.equal(checked.eval, null);
  assert.equal(checked.best, null);
  assert.equal(checked.nudge, null);
  // The rules alone see the knight left hanging on g5.
  assert.equal(checked.habits.safety, "missed");
  const mate = run(fixture("scholar's mate: Qxf7 is mate"), { facts: null });
  assert.equal(mate.checked.move.grade, "checkmate");
  assert.deepEqual(mate.checked.claims.map((entry) => entry.verdict), ["right", "right"]);
});

test("facts the server can't use are dropped, and a pv is trusted only while it is legal", () => {
  const facts = {
    depth: 12,
    moves: [
      { uci: "zzzz", eval: { cp: 90 } },
      { uci: "e2e5", eval: { cp: 80 } },
      { uci: "d2d4", eval: "bad" },
      { uci: "g1f3", eval: { cp: 25 }, pv: ["g1f3", "a1a8", "e2e4"] },
      { uci: "e2e4", eval: { cp: 20.4 }, pv: ["e2e4", "e7e5"] },
      { uci: "e2e4", eval: { cp: 99 } },
    ],
    threats: "nope",
  };
  const parsed = { about: true, move: { said: "e4", san: "e4" }, claims: [claim("eval", "it's equal", { eval: "equal" })] };
  const result = verifyTalk({ fen: "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1", facts, parsed, reveal: true });
  assertContract(result, "malformed");
  assert.deepEqual(result.checked.eval, { cp: 25 });
  assert.deepEqual(result.checked.best, { san: "Nf3", uci: "g1f3" });
  assert.equal(result.checked.move.grade, "excellent");
  assert.equal(result.checked.move.note, "e4 is an excellent move. Nf3 was a little stronger.");
  assert.equal(result.checked.claims[0].verdict, "right");
});

test("reveal: the best move is named only when allowed; otherwise a nudge names the piece", () => {
  const item = fixture("italian: black misses the loose knight");
  const hidden = run(item, { reveal: false });
  assert.equal(hidden.checked.best, null);
  assert.equal(hidden.checked.nudge, "Look at your bishop.");
  assert.equal(hidden.checked.move.note, "Nh6 is a blunder: there was a much stronger move.");
  assert.deepEqual(hidden.checked.missed.map((entry) => entry.note), ["Their knight on g5 is loose."]);
  const shown = run(item, { reveal: true });
  assert.deepEqual(shown.checked.best, { san: "Bxg5", uci: "e7g5" });
  assert.equal(shown.checked.nudge, null);
  assert.equal(shown.checked.move.note, "Nh6 is a blunder: Bxg5 was much stronger.");
  // The move's note already says it: no second line about the knight.
  assert.deepEqual(shown.checked.missed, []);
  // With no move named, the free knight is pointed out, and with reveal, how to take it.
  const talk = { about: true, move: null, claims: [claim("attacks", "his knight hits f7", { side: "opponent", piece: "N", square: "g5", target: "f7" })] };
  assert.deepEqual(run(item, { parsed: talk, reveal: false }).checked.missed.map((entry) => entry.note), ["Their knight on g5 is loose."]);
  assert.deepEqual(run(item, { parsed: talk, reveal: true }).checked.missed.map((entry) => entry.note), ["Their knight on g5 is loose: Bxg5 wins it."]);
  // The best move itself gets no nudge.
  assert.equal(run(fixture("italian: black takes the hanging knight"), { reveal: false }).checked.nudge, null);
});

// ---------------------------------------------------------------------------
// Missed things and habits

test("a threat the player named isn't repeated in missed", () => {
  const item = fixture("black a pawn up misses the mate");
  assert.deepEqual(run(item).checked.missed.map((entry) => entry.note), ["They threaten Qxh7#."]);
  const parsed = {
    about: true,
    move: { said: "knight f6", san: "Nf6" },
    claims: [claim("mate", "he threatens mate on h7", { side: "opponent", target: "h7" })],
  };
  const { checked } = run(item, { parsed });
  assert.equal(checked.claims[0].verdict, "right");
  assert.equal(checked.claims[0].note, "They have mate in one: Qxh7#.");
  assert.deepEqual(checked.missed, []);
  assert.equal(checked.habits.threats, "good");
  assert.equal(checked.move.grade, "best");
});

test("a move into the threat: the move's note names the refutation, missed doesn't repeat it", () => {
  const { checked } = run(fixture("greedy bishop: the rook on a8 is poisoned"));
  assert.equal(checked.move.note, "After Bxa8, Qxh2 is mate.");
  assert.deepEqual(checked.move.reply, { san: "Qxh2#", uci: "h5h2" });
  assert.ok(checked.move.arrows.some((line) => line.from === "h5" && line.to === "h2" && line.tone === "bad"));
  assert.deepEqual(checked.missed, []);
  assert.equal(checked.habits.threats, "missed");
  assert.equal(checked.habits.safety, "missed");
});

// ---------------------------------------------------------------------------
// The rules alone

test("the player in check: there is no N, and threats are ignored", () => {
  const item = fixture("in check: block with the bishop");
  const facts = { ...item.facts, threats: [{ uci: "e7e5", eval: { cp: 500 }, pv: ["e7e5"] }] };
  const parsed = {
    about: true,
    move: { said: "bishop d2", san: "Bd2" },
    claims: [claim("threat", "he threatens to take my knight", { side: "opponent", piece: "N" }), claim("safe", "nothing is hanging")],
  };
  const result = run(item, { facts, parsed });
  assertContract(result, "in check");
  assert.deepEqual(result.checked.claims.map((entry) => entry.verdict), ["unclear", "unclear"]);
  assert.equal(result.checked.claims[0].note, "You're in check, so that's their threat already made.");
  assert.equal(result.checked.habits.threats, "none");
});

test("back-rank mate and check, from the rules alone", () => {
  const parsed = {
    about: true,
    move: { said: "rook e8", san: "Re8" },
    claims: [claim("mate", "rook e8 is mate", { moves: ["Re8"] }), claim("check", "it's check", { moves: ["Re8+"] })],
  };
  const result = verifyTalk({ fen: "6k1/5ppp/8/8/8/8/8/4R1K1 w - - 0 1", parsed });
  assertContract(result, "back rank");
  assert.deepEqual(result.checked.move && [result.checked.move.san, result.checked.move.grade], ["Re8#", "checkmate"]);
  assert.deepEqual(result.checked.claims.map((entry) => entry.note), ["Re8# is checkmate.", "Re8# is even checkmate."]);
  assert.deepEqual(result.spoken.right, ["Rook to e8 is checkmate.", "Rook to e8 is even checkmate."]);
});

test("castling through check is illegal, with the reason", () => {
  const parsed = { about: true, move: { said: "I castle", san: "O-O" }, claims: [] };
  const { checked, spoken } = verifyTalk({ fen: "r3k2r/8/8/8/2b5/8/8/R3K2R w KQkq - 0 1", parsed });
  assert.deepEqual([checked.move.san, checked.move.uci, checked.move.grade], [null, null, "illegal"]);
  assert.equal(checked.move.note, "O-O isn't possible: you can't castle through check: f1 is covered by the bishop on c4.");
  assert.equal(spoken.move, "Castling isn't possible: you can't castle through check: f1 is covered by the bishop on c4.");
});

test("a move that fits two pieces is graded unknown and asks which", () => {
  const item = fixture("queen's gambit declined");
  const { checked } = run(item, { parsed: { about: true, move: { said: "knight d7", san: "Nd7" }, claims: [] } });
  assert.deepEqual([checked.move.san, checked.move.grade], [null, "unknown"]);
  assert.equal(checked.move.note, "Which knight? Nbd7 and Nfd7 are both possible.");
  assert.deepEqual(checked.move.squares, ["b8", "d7", "f6"]);
});

test("a pinned defender doesn't defend: the protocol's example of a fake guard", () => {
  const { checked } = run(fixture("scotch four knights"));
  const [pinned, defends, safe] = checked.claims;
  assert.equal(pinned.verdict, "right");
  assert.equal(defends.verdict, "partly");
  assert.match(defends.note, /pinned to your king by the bishop on b4, so it can't take back/);
  assert.equal(safe.verdict, "wrong");
  assert.equal(safe.note, "The pawn on e4 isn't safe: your knight on c3 is pinned, so Nxe4 wins it.");
});

// ---------------------------------------------------------------------------
// Grades and bands

test("a claim said with a not is judged without it, then turned around", () => {
  const italian = fixture("italian: names the bishop on f2");
  const parsed = {
    about: true,
    move: null,
    claims: [
      claim("attacks", "his bishop doesn't eye f2", { side: "opponent", piece: "B", square: "c5", target: "f2", negated: true }),
      claim("attacks", "his bishop doesn't eye h7", { side: "opponent", piece: "B", square: "c5", target: "h7", negated: true }),
      claim("safe", "my knight on f3 isn't safe", { piece: "N", square: "f3", negated: true }),
      claim("attacks", "his bishop eyes f2", { side: "opponent", piece: "B", square: "c5", target: "f2" }),
    ],
  };
  const { checked, spoken } = run(italian, { parsed });
  assert.deepEqual(checked.claims.map((item) => item.verdict), ["wrong", "right", "wrong", "right"]);
  // The note says what is true, so it reads as the correction for a wrong "not" and as the agreement for a right one.
  assert.equal(checked.claims[0].note, checked.claims[3].note);
  assert.equal(checked.claims[0].note, "The bishop on c5 hits f2.");
  assert.equal(checked.claims[1].note, "The bishop on c5 doesn't hit h7.");
  // Leo's lines go to the turned-around verdict, in claim order: the bishop does hit f2 is the correction.
  assert.equal(spoken.wrong.length, 2);
  assert.equal(spoken.right.length, 2);
  assert.equal(spoken.wrong[0], spoken.right[1], "the correction of claim 1 is the agreement with claim 4");
  assert.equal(spoken.right[0], "The bishop on c5 doesn't hit h7.");
});

test("\"my king isn't safe\" against a real mate threat spots it; said when the king is fine, it's wrong", () => {
  const mate = fixture("black a pawn up misses the mate on h7");
  const unsafe = claim("safe", "my king isn't safe", { piece: "K", square: "g8", negated: true });
  const spotted = run(mate, { parsed: { about: true, move: null, claims: [unsafe] } }).checked;
  assert.equal(spotted.claims[0].verdict, "right");
  assert.equal(spotted.habits.threats, "good");
  assert.equal(spotted.missed.length, 0, "Leo agrees with the claim instead of calling the mate missed");

  const calm = fixture("queen's gambit declined: black is right that nothing is threatened");
  const wrong = run(calm, { parsed: { about: true, move: null, claims: [{ ...unsafe, square: "g8" }] } }).checked;
  assert.equal(wrong.claims[0].verdict, "wrong");
  assert.notEqual(wrong.habits.threats, "good", "saying the king is in danger when it isn't is not the habit done well");
});

test("denying a real threat is a missed threat habit, and the threat isn't repeated in missed", () => {
  const ruy = fixture("ruy lopez: black spots the threat on e5");
  const parsed = {
    about: true,
    move: { said: "d6", san: "d6" },
    claims: [claim("threat", "he isn't threatening to take on c6", { side: "opponent", moves: ["Bxc6"], negated: true })],
  };
  const { checked } = run(ruy, { parsed });
  assert.equal(checked.claims[0].verdict, "wrong");
  assert.equal(checked.habits.threats, "missed");
  assert.equal(checked.missed.filter((item) => item.kind === "threat").length, 0, "the claim's own note corrects it");
});

test("eval bands: ±40, ±100 and ±300, and mates", () => {
  const bands = [300, 299, 100, 99, 41, 40, 0, -40, -41, -99, -100, -299, -300].map((cp) => bandOf({ cp }));
  assert.deepEqual(bands, [
    "winning", "better", "better", "slightly_better", "slightly_better", "equal", "equal", "equal",
    "slightly_worse", "slightly_worse", "worse", "worse", "losing",
  ]);
  assert.equal(bandOf({ mate: 3 }), "winning");
  assert.equal(bandOf({ mate: -2 }), "losing");
  assert.equal(bandOf({ mate: 0 }), "losing");
});

test("grades use the app's winning chances", () => {
  assert.equal(winningChances({ cp: 0 }), 0);
  assert.equal(winningChances({ mate: 2 }), 1);
  assert.equal(winningChances({ mate: -1 }), -1);
  assert.equal(winningChances({ cp: 5000 }), winningChances({ cp: 1000 }));
  assert.ok(Math.abs(winningChances({ cp: 100 }) - (2 / (1 + Math.exp(-0.368208)) - 1)) < 1e-12);
  const grade = (cp) => gradeMove({ cp: 0 }, { cp }, false);
  assert.deepEqual([-10, -50, -100, -150, -200].map(grade), ["excellent", "good", "inaccuracy", "mistake", "blunder"]);
  assert.equal(gradeMove({ cp: 0 }, { cp: 0 }, true), "best");
  assert.equal(gradeMove({ mate: 3 }, { cp: 500 }, false), "mistake");
  assert.equal(gradeMove({ mate: 3 }, { mate: 5 }, false), "excellent");
});

test("odd claims, odd moves and broken facts never break the contract", () => {
  // A fixed pseudo-random walk, so a failure can be replayed.
  let seed = 7;
  const random = () => (seed = (seed * 1103515245 + 12345) % 2147483648) / 2147483648;
  const pick = (list) => list[Math.floor(random() * list.length)];
  const squares = ["", "a1", "e4", "f7", "h8", "c3", "g5", "d5", "zz"];
  for (let round = 0; round < 12; round += 1) {
    for (const item of FIXTURES) {
      const legal = item.parsed.claims.flatMap((entry) => entry.moves).concat(["Qxz9", "O-O-O", "e8", "Nd7", "nonsense", ""]);
      const claims = Array.from({ length: Math.floor(random() * 8) }, () => ({
        said: pick(["a claim", "", 5, null]),
        kind: pick([...CLAIM_KINDS, "bogus"]),
        side: pick(["me", "opponent", "them"]),
        piece: pick(["", "K", "Q", "R", "B", "N", "P", "X"]),
        square: pick(squares),
        target: pick(squares),
        moves: Array.from({ length: Math.floor(random() * 4) }, () => pick(legal)),
        afterMove: random() < 0.4,
        eval: pick(["", "winning", "equal", "losing", "great"]),
        gain: pick(["", "pawn", "piece", "queen", "mate", "even", "lots"]),
      }));
      const move = random() < 0.8 ? { said: "my move", san: pick(legal) } : pick([null, {}, { san: 5 }]);
      const facts = random() < 0.2 ? pick([null, {}, { moves: "x" }, { moves: [{ uci: 1 }], threats: [null] }]) : item.facts;
      assertContract(run(item, { facts, parsed: { about: true, move, claims }, reveal: random() < 0.5 }), `${item.name}, round ${round}`);
    }
  }
});

// ---------------------------------------------------------------------------
// Speed

test("benchmark: verifyTalk is fast (warm), well under the 25 ms budget", (t) => {
  for (const item of FIXTURES) run(item);
  const runs = 50;
  const started = performance.now();
  for (let round = 0; round < runs; round += 1) for (const item of FIXTURES) run(item);
  const average = (performance.now() - started) / (runs * FIXTURES.length);
  t.diagnostic(`verifyTalk: ${average.toFixed(2)} ms on average over ${runs} runs of ${FIXTURES.length} fixtures`);
  assert.ok(average < 25, `${average.toFixed(2)} ms`);
});
