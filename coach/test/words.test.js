// Moves and trades in words, for Leo's voice: no notation may come through.
import assert from "node:assert/strict";
import { test } from "node:test";
import { Position, pieceCounts } from "../src/board.js";
import { capitalize, countOf, lineWords, moveWords, numberWord, ownerWord, pieceOn, sideName, tradeWords } from "../src/words.js";

test("moves in words", () => {
  assert.equal(moveWords("Nf3"), "knight to f3");
  assert.equal(moveWords("Nbd2"), "knight to d2");
  assert.equal(moveWords("R1e2"), "rook to e2");
  assert.equal(moveWords("exd5"), "pawn takes d5");
  assert.equal(moveWords("e4"), "e4");
  assert.equal(moveWords("Bxh7+"), "bishop takes h7, check");
  assert.equal(moveWords("Qxf7#"), "queen takes f7, checkmate");
  assert.equal(moveWords("Qxf7#", { suffix: false }), "queen takes f7");
  assert.equal(moveWords("O-O"), "castles");
  assert.equal(moveWords("O-O", { noun: true }), "castling");
  assert.equal(moveWords("O-O-O+"), "castles long, check");
  assert.equal(moveWords("0-0-0", { noun: true }), "castling long");
  assert.equal(moveWords("e8=Q+"), "e8, promoting to a queen, check");
  assert.equal(moveWords("bxa8=N"), "pawn takes a8, promoting to a knight");
  assert.equal(moveWords("exf6", { enPassant: true }), "pawn takes f6, en passant");
  assert.equal(moveWords("Nf3!?"), "knight to f3");
});

test("anything that isn't a move never leaks notation", () => {
  assert.equal(moveWords("xyz"), "that move");
  assert.equal(moveWords("Zf9"), "that move");
  assert.equal(moveWords(""), "that move");
  assert.equal(moveWords(null), "that move");
});

test("lines in words", () => {
  assert.equal(lineWords(["Nxe5"]), "knight takes e5");
  assert.equal(lineWords(["Bxd2+", "Nbxd2"]), "bishop takes d2, check, then knight takes d2");
  assert.equal(lineWords(["Nxe5", "Nxe5", "d4"]), "knight takes e5, knight takes e5, then d4");
  assert.equal(lineWords([]), "");
});

test("pieces, owners and numbers", () => {
  assert.equal(pieceOn("b", "c5"), "the bishop on c5");
  assert.equal(pieceOn("n", "f3", "your"), "your knight on f3");
  assert.equal(ownerWord("w", "w"), "your");
  assert.equal(ownerWord("b", "w"), "their");
  assert.equal(sideName("b"), "Black");
  assert.equal(numberWord(2), "two");
  assert.equal(numberWord(12), "12");
  assert.equal(countOf(1, "pawn"), "a pawn");
  assert.equal(countOf(3, "piece"), "three pieces");
  assert.equal(capitalize("knight to f3"), "Knight to f3");
});

/** What `winner` gains between two FENs, in words. */
function trade(beforeFen, afterFen, winner) {
  return tradeWords(pieceCounts(new Position(beforeFen).cells), pieceCounts(new Position(afterFen).cells), winner);
}

test("trades in words, like for like taken out", () => {
  const start = "r1bqkbnr/pppppppp/2n5/8/8/2N5/PPPPPPPP/R1BQKBNR w KQkq - 0 1";
  // Black loses a pawn.
  assert.equal(trade(start, "r1bqkbnr/ppp1pppp/2n5/8/8/2N5/PPPPPPPP/R1BQKBNR w KQkq - 0 1", "w"), "a pawn");
  // Black loses a knight, White a pawn.
  assert.equal(trade(start, "r1bqkbnr/pppppppp/8/8/8/2N5/PPP1PPPP/R1BQKBNR w KQkq - 0 1", "w"), "a piece for a pawn");
  // A knight for a bishop is even: nothing won.
  assert.equal(trade(start, "r1bqkbnr/pppppppp/8/8/8/2N5/PPPPPPPP/R2QKBNR w KQkq - 0 1", "w"), null);
  // A rook for a knight is the exchange.
  assert.equal(trade(start, "2bqkbnr/pppppppp/2n5/8/8/8/PPPPPPPP/R1BQKBNR w KQkq - 0 1", "w"), "the exchange");
  // A rook and a knight for a knight is a rook.
  assert.equal(trade(start, "2bqkbnr/pppppppp/8/8/8/8/PPPPPPPP/R1BQKBNR w KQkq - 0 1", "w"), "a rook");
  // The queen for a rook.
  assert.equal(trade(start, "r1b1kbnr/pppppppp/2n5/8/8/2N5/PPPPPPPP/2BQKBNR w Kkq - 0 1", "w"), "the queen for a rook");
  // The loser can't be said to win anything.
  assert.equal(trade(start, "r1bqkbnr/ppp1pppp/2n5/8/8/2N5/PPPPPPPP/R1BQKBNR w KQkq - 0 1", "b"), null);
  // A pawn that queens is a new queen, not a pawn given away.
  assert.equal(trade("8/4P1k1/8/8/8/8/8/4K3 w - - 0 1", "4Q3/6k1/8/8/8/8/8/4K3 w - - 0 1", "w"), "a new queen");
});
