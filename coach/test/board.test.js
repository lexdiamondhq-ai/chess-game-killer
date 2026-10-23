// The rules Leo leans on: material, attacks, pins, exchanges with legal moves only, the null move,
// engine lines, and reading what the player wrote.
import assert from "node:assert/strict";
import { test } from "node:test";
import {
  Position,
  attackersOf,
  balance,
  blockersOnLine,
  canTakeBack,
  captureValue,
  capturesOf,
  describePosition,
  exchange,
  hits,
  materialOf,
  nullMoveFen,
  pieceCounts,
  pinOn,
  playLine,
  resolveMove,
  settleExchange,
  squareIndex,
  squareName,
} from "../src/board.js";

const sq = squareIndex;

// 1.e4 e5 2.Nf3 Nc6 3.Nc3 Nf6 4.d4 exd4 5.Nxd4 Bb4: the knight on c3 is pinned to the king.
const SCOTCH = "r1bqk2r/pppp1ppp/2n2n2/8/1b1NP3/2N5/PPP2PPP/R1BQKB1R w KQkq - 3 6";
// 1.d4 Nf6 2.c4 e6 3.Nc3 Bb4.
const NIMZO = "rnbqk2r/pppp1ppp/4pn2/8/1bPP4/2N5/PP2PPPP/R1BQKBNR w KQkq - 2 4";
// 1.d4 d5 2.c4 e6 3.Nc3 Nf6 4.Bg5: the knight on f6 is pinned to the queen until ...Be7.
const QGD_PIN = "rnbqkb1r/ppp2ppp/4pn2/3p2B1/2PP4/2N5/PP2PPPP/R2QKBNR b KQkq - 3 4";
// 1.d4 d5 2.c4 e6 3.Nf3 Bb4+: White is in check.
const IN_CHECK = "rnbqk1nr/ppp2ppp/4p3/3p4/1bPP4/5N2/PP2PPPP/RNBQKB1R w KQkq - 2 4";
// French advance after 6...f5: exf6 en passant is possible.
const FRENCH_EP = "r2qkbnr/pp1b2pp/2n1p3/2ppPp2/3P4/2P2N2/PP2BPPP/RNBQK2R w KQkq f6 0 7";
// 1.e4 e5 2.Bc4 Nc6 3.Qh5 Nf6: Qxf7 is mate.
const SCHOLAR = "r1bqkb1r/pppp1ppp/2n2n2/4p2Q/2B1P3/8/PPPP1PPP/RNB1K1NR w KQkq - 4 4";

test("squares are named from a1 = 0 to h8 = 63", () => {
  assert.equal(sq("a1"), 0);
  assert.equal(sq("h8"), 63);
  assert.equal(sq("e4"), 28);
  assert.equal(squareName(28), "e4");
  assert.equal(sq("i9"), -1);
  assert.equal(sq(""), -1);
  assert.equal(sq(undefined), -1);
});

test("material counts 1, 3, 3, 5, 9 and the balance is from one side's view", () => {
  const start = new Position("rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1");
  assert.deepEqual(materialOf(start.cells), { w: 39, b: 39 });
  const upAPawn = new Position("r2q1rk1/pb1nbppp/1p2p3/n1p5/3P4/2NQ1N2/PPB2PPP/R1B2RK1 b - - 3 12");
  assert.equal(balance(upAPawn.cells, "b"), 1);
  assert.equal(balance(upAPawn.cells, "w"), -1);
  assert.equal(pieceCounts(upAPawn.cells).b.p, 7);
});

test("attacks: pieces hit along open lines, and a blocker is named", () => {
  const position = new Position("r2q1rk1/pb1nbppp/1p2p3/n1p5/3P4/2NQ1N2/PPB2PPP/R1B2RK1 b - - 3 12");
  assert.equal(hits(position.cells, sq("b7"), sq("g2")), false);
  assert.deepEqual(blockersOnLine(position.cells, sq("b7"), sq("g2")), [sq("f3")]);
  assert.equal(blockersOnLine(position.cells, sq("b7"), sq("h5")), null);
  // The queen and bishop battery on h7.
  assert.equal(hits(position.cells, sq("d3"), sq("h7")), true);
  assert.deepEqual(attackersOf(position.cells, sq("h7"), "w").sort(), [sq("d3")]);
  const italian = new Position("r1bqk2r/pppp1ppp/2n2n2/2b1p3/2B1P3/3P1N2/PPP2PPP/RNBQK2R w KQkq - 1 5");
  assert.equal(hits(italian.cells, sq("c5"), sq("f2")), true);
  assert.equal(hits(italian.cells, sq("f3"), sq("g5")), true);
  assert.equal(hits(italian.cells, sq("f3"), sq("e5")), true);
  assert.equal(hits(italian.cells, sq("c5"), sq("f3")), false);
});

test("pins: absolute to the king, relative to a queen, none behind a pawn", () => {
  const nimzo = new Position(NIMZO);
  assert.deepEqual(pinOn(nimzo.cells, sq("c3")), { square: sq("c3"), by: sq("b4"), behind: sq("e1"), absolute: true });
  const qgd = new Position(QGD_PIN);
  assert.deepEqual(pinOn(qgd.cells, sq("f6")), { square: sq("f6"), by: sq("g5"), behind: sq("d8"), absolute: false });
  // Qa4 pins the d-pawn to the king.
  const pawnPinned = new Position("rnbqkbnr/pp1ppppp/8/2p5/Q7/8/PPPPPPPP/RNB1KBNR b KQkq - 1 2");
  assert.equal(pinOn(pawnPinned.cells, sq("d7")).absolute, true);
  // Ruy Lopez: the knight on c6 has a pawn behind it, not the king, so it isn't pinned.
  const ruy = new Position("r1bqkbnr/pppp1ppp/2n5/1B2p3/4P3/5N2/PPPP1PPP/RNBQK2R b KQkq - 3 3");
  assert.equal(pinOn(ruy.cells, sq("c6")), null);
  assert.equal(pinOn(nimzo.cells, sq("f6")), null);
});

test("exchanges use legal moves: a pinned defender doesn't take back", () => {
  const scotch = new Position(SCOTCH);
  const theirTurn = scotch.nullMove();
  assert.equal(exchange(theirTurn, sq("e4"), "b").value, 1);
  // Without the pin, Nxe4 Nxe4 would lose the knight for a pawn.
  assert.equal(exchange(theirTurn, sq("e4"), "b", { pins: false }).value, -2);
  const retake = canTakeBack(scotch.cells, sq("c3"), sq("e4"));
  assert.equal(retake.ok, false);
  assert.equal(retake.pin.by, sq("b4"));
  assert.equal(canTakeBack(scotch.cells, sq("d4"), sq("c6")).ok, true);
});

test("exchanges: en passant, promotion and a settled trade", () => {
  const french = new Position(FRENCH_EP);
  const captures = capturesOf(french, sq("f5"), "w");
  assert.equal(captures.length, 1);
  assert.equal(captures[0].enPassant, true);
  // exf6 is taken back: no gain.
  assert.equal(exchange(french, sq("f5"), "w").value, 0);
  const promotion = new Position("r3k3/1P6/8/8/8/8/8/4K3 w - - 0 1");
  // A rook and a new queen (eight more than the pawn).
  assert.equal(captureValue(promotion.cells.slice(), sq("b7"), sq("a8")), 13);
  const loose = new Position("4k3/8/8/3n4/8/8/8/3RK3 w - - 0 1");
  const settled = settleExchange(loose.cells, sq("d5"), "w");
  assert.equal(settled.value, 3);
  assert.equal(settled.cells[sq("d5")].color, "w");
});

test("Position: FEN, check, mate, stalemate and legal moves", () => {
  const scholar = new Position(SCHOLAR);
  assert.equal(scholar.turn, "w");
  assert.equal(scholar.inCheck, false);
  const mate = scholar.mateInOne();
  assert.equal(mate.san, "Qxf7#");
  assert.equal(mate.mate, true);
  assert.equal(mate.check, true);
  assert.equal(scholar.after(mate).isCheckmate, true);
  assert.equal(new Position("7k/5Q2/6K1/8/8/8/8/8 b - - 0 1").isStalemate, true);
  const inCheck = new Position(IN_CHECK);
  assert.equal(inCheck.inCheck, true);
  assert.deepEqual(inCheck.legal.map((move) => move.san).sort(), ["Bd2", "Nbd2", "Nc3", "Nfd2", "Qd2"]);
  const castles = new Position("r3k2r/8/8/8/8/8/8/R3K2R w KQkq - 0 1").legal.filter((move) => move.castle);
  assert.deepEqual(castles.map((move) => [move.san, move.castle, move.uci]), [["O-O", "short", "e1g1"], ["O-O-O", "long", "e1c1"]]);
  const french = new Position(FRENCH_EP);
  const ep = french.byUci("e5f6");
  assert.equal(ep.enPassant, true);
  assert.equal(ep.takenIndex, sq("f5"));
  assert.equal(ep.san, "exf6");
  const promotion = new Position("6k1/4P3/3K4/8/8/8/1r6/8 w - - 0 50");
  assert.equal(promotion.byUci("e7e8").san, "e8=Q+");
  assert.equal(promotion.byUci("e7e8n").san, "e8=N");
  assert.equal(promotion.byUci("e7e6"), null);
  assert.throws(() => new Position("not a fen"));
});

test("Petroff trap: Nc6+ is a discovered check", () => {
  const position = new Position("rnbqkb1r/pppp1ppp/5n2/4N3/8/8/PPPPQPPP/RNB1KB1R w KQkq - 2 5");
  const move = position.byUci("e5c6");
  assert.equal(move.check, true);
  assert.equal(move.san, "Nc6+");
});

test("the null move flips the side, clears en passant, and is refused in check", () => {
  assert.equal(nullMoveFen(IN_CHECK), null);
  assert.equal(new Position(IN_CHECK).nullMove(), null);
  assert.equal(nullMoveFen(FRENCH_EP), "r2qkbnr/pp1b2pp/2n1p3/2ppPp2/3P4/2P2N2/PP2BPPP/RNBQK2R b KQkq - 0 7");
  assert.equal(
    nullMoveFen("r1bqkbnr/pppp1ppp/2n5/4p3/4P3/5N2/PPPP1PPP/RNBQKB1R b KQkq - 3 3"),
    "r1bqkbnr/pppp1ppp/2n5/4p3/4P3/5N2/PPPP1PPP/RNBQKB1R w KQkq - 3 4",
  );
  const scotch = new Position(SCOTCH);
  assert.equal(scotch.nullMove().turn, "b");
  assert.equal(scotch.nullMove(), scotch.nullMove());
});

test("engine lines are trusted only as far as they are legal", () => {
  const scholar = new Position(SCHOLAR);
  const line = playLine(scholar, ["h5f7", "e8f7", "d2d4"]);
  assert.deepEqual(line.played.map((move) => move.san), ["Qxf7#"]);
  assert.equal(line.mate, true);
  assert.equal(line.turn, "b");
  const italian = new Position("r1bqkbnr/pppp1ppp/2n5/4p3/2B1P3/5N2/PPPP1PPP/RNBQK2R b KQkq - 3 3");
  const walk = playLine(italian, ["g8f6", "f3g5", "d7d5", "e4d5", "f6d5", "g5f7"], { sanCount: 2 });
  assert.equal(walk.played.length, 6);
  assert.deepEqual(walk.played.slice(0, 2).map((move) => move.san), ["Nf6", "Ng5"]);
  assert.equal(walk.played[2].san, null);
  assert.equal(walk.played[5].captured, "p");
  assert.equal(playLine(italian, ["e1g1"]).played.length, 0);
  assert.equal(playLine(italian, ["zz", "g8f6"]).played.length, 0);
});

test("written moves are read leniently", () => {
  const position = new Position("rnbqkb1r/pppp1ppp/5n2/4p3/4P3/5N2/PPPP1PPP/RNBQKB1R w KQkq - 2 3");
  const san = (text) => resolveMove(position, text).move?.san ?? null;
  assert.equal(san("Nxe5"), "Nxe5");
  assert.equal(san("Ne5"), "Nxe5");
  assert.equal(san("N e5"), "Nxe5");
  assert.equal(san("Nf3-e5"), "Nxe5");
  assert.equal(san("f3e5"), "Nxe5");
  assert.equal(san("nxe5"), "Nxe5");
  assert.equal(san("Bc4+"), "Bc4");
  assert.equal(san("Bc4!?"), "Bc4");
  const castling = new Position("r3k2r/8/8/8/8/8/8/R3K2R w KQkq - 0 1");
  assert.equal(resolveMove(castling, "0-0").move.san, "O-O");
  assert.equal(resolveMove(castling, "o-o-o").move.san, "O-O-O");
  const promotion = new Position("6k1/4P3/3K4/8/8/8/1r6/8 w - - 0 50");
  assert.equal(resolveMove(promotion, "e8").move.san, "e8=Q+");
  assert.equal(resolveMove(promotion, "e8=N").move.san, "e8=N");
  assert.equal(resolveMove(new Position(FRENCH_EP), "exf6 e.p.").move.uci, "e5f6");
  const backRank = new Position("6k1/5ppp/8/8/8/8/8/4R1K1 w - - 0 1");
  assert.equal(resolveMove(backRank, "re8").move.san, "Re8#");
  const twoKnights = resolveMove(new Position(QGD_PIN), "Nd7");
  assert.deepEqual(twoKnights.ambiguous.map((move) => move.san), ["Nbd7", "Nfd7"]);
  assert.equal(resolveMove(new Position(QGD_PIN), "Nbd7").move.san, "Nbd7");
});

test("a move that can't be played comes with the reason", () => {
  const reason = (fen, text, who) => resolveMove(new Position(fen), text, who).illegal;
  const open = "rnbqkb1r/pppp1ppp/5n2/4p3/4P3/5N2/PPPP1PPP/RNBQKB1R w KQkq - 2 3";
  assert.equal(reason(NIMZO, "Nd5"), "The knight on c3 is pinned to your king.");
  assert.equal(reason(open, "Qh5"), "The queen on d1 can't get to h5: the knight on f3 is in the way.");
  assert.equal(reason(open, "e5"), "The pawn on e4 is blocked.");
  assert.equal(reason(open, "exd5"), "There's nothing to take on d5.");
  assert.equal(reason(open, "Nxf3"), "You can't take your own knight on f3.");
  assert.equal(reason(open, "Bxf7"), "No bishop of yours can reach f7.");
  assert.equal(reason(IN_CHECK, "e3"), "You're in check, and that doesn't get you out of it.");
  assert.equal(reason(IN_CHECK, "Kd2"), "Your king can't go to d2: it would be in check.");
  assert.equal(reason("r3k2r/8/8/8/2b5/8/8/R3K2R w KQkq - 0 1", "O-O"), "You can't castle through check: f1 is covered by the bishop on c4.");
  assert.equal(reason("r3k2r/8/8/8/4r3/8/8/R3K2R w KQkq - 0 1", "O-O"), "You can't castle out of check.");
  assert.equal(reason("r3k2r/8/8/8/8/8/8/R3K2R w Qkq - 0 1", "O-O"), "You can't castle that way any more: your king or rook has moved.");
  assert.equal(reason("r3k2r/8/8/8/8/8/8/RN2K2R w KQkq - 0 1", "O-O-O"), "You can't castle yet: the knight on b1 is in the way.");
  assert.equal(reason("4k3/8/8/8/8/8/8/4K3 w - - 0 1", "Bb5"), "You don't have a bishop.");
  assert.equal(reason(open, "hello"), "I couldn't read that move.");
  // The opponent's moves are worded for them.
  assert.equal(reason("r1bqkbnr/pppp1ppp/2n5/4p3/4P3/5N2/PPPP1PPP/RNBQKB1R b KQkq - 3 3", "Nxe4", "they"), "No knight of theirs can reach e4.");
});

test("describePosition: what Claude is told about the board", () => {
  const described = describePosition("r1bqk2r/pppp1ppp/2n2n2/2b1p3/2B1P3/3P1N2/PPP2PPP/RNBQK2R w KQkq - 1 5");
  assert.deepEqual(Object.keys(described), ["side", "inCheck", "pieces", "legal", "theirs"]);
  assert.equal(described.side, "white");
  assert.equal(described.inCheck, false);
  assert.deepEqual(described.pieces.white.slice(0, 4), ["Ke1", "Qd1", "Ra1", "Rh1"]);
  assert.deepEqual(described.pieces.black.slice(0, 2), ["Ke8", "Qd8"]);
  assert.equal(described.pieces.white.length, 16);
  assert.ok(described.legal.includes("O-O"));
  assert.ok(described.legal.includes("Bxf7+"));
  assert.ok(described.theirs.includes("Bxf2+"));
  assert.ok(described.theirs.includes("Nxe4"));
  const checked = describePosition(IN_CHECK);
  assert.equal(checked.inCheck, true);
  assert.deepEqual(checked.theirs, []);
  assert.equal(describePosition(QGD_PIN).side, "black");
});
