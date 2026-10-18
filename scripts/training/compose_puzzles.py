#!/usr/bin/env python3
"""Composes pattern puzzles and endgame drills for the training mode.

The miner (mine_puzzles.py) finds realistic puzzles in beginner games, but the
patterns come in whatever mix those games produce. This script fills each
pattern lesson on purpose. Every motif has a few templates that place the
pieces of the tactic and then dress the position up the way real games look:
castled kings behind their pawns (sometimes with a luft pawn), a few more pawns
and pieces, material about level. Each candidate is then checked by Stockfish
with the miner's own rules: one clearly best first move, the line extended
while every move stays the only good one, material won after the opponent's
best reply (or a forced mate), and the pattern confirmed by tag_puzzle. About
half of every motif is mirrored so that Black is to move.

  mate-in-1   any mating move counts; most have one or two, and a few
              checks that don't mate
  back-rank   back-rank mates in one or two (doubled rooks, deflections,
              the Opera finish Qb8+ Nxb8 Rd8#)
  mate-in-2   queen sacrifices, smothered mates, Anastasia, kingside attacks
  forks       knight forks (royal forks too), pawn, bishop, rook, queen forks
  pins        a bishop, rook or queen pins a piece (the queen too) and wins it
  skewers     check the king or hit the queen, then take what is behind
  discovered  discovered attacks, discovered checks and double checks

Endgame playouts, where the player mates a lone king against the engine:

  queen-mate   K+Q vs K, mate in 5-10
  ladder-mate  K+R+R vs K, mate in 3-7
  rook-mate    K+R vs K, mate in 8-16

Their mate distances are exact (a small retrograde solver works them out;
Stockfish's own mate scores are often a few moves too long there), and the
engine confirms that each position is a forced win.

Output is one JSON record per line, in the miner's shape plus
"source": "composed" and "motif"; endgames are {"kind": "playout", ...}.

Usage:
  python3 scripts/training/compose_puzzles.py --engine "node stockfish-18-single.js" \
      --workers 2 --seed 1 --out composed.jsonl
  python3 scripts/training/compose_puzzles.py --engine stockfish --out forks.jsonl \
      --only forks --forks 20
  # after a crash: keep what composed.jsonl already has and make the rest
  python3 scripts/training/compose_puzzles.py --engine stockfish --out composed.jsonl --resume

Jobs are time-boxed, so a seed varies the output but doesn't reproduce it exactly.
"""
from __future__ import annotations

import argparse
import itertools
import json
import multiprocessing as mp
import os
import random
import sys
import time
import zlib
from collections import Counter
from typing import Callable

import chess

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from chesslib import VALUE, Engine, balance, danger_squares, mate_in, win_chances  # noqa: E402
from mine_puzzles import estimate_rating, extend_solution, separated, tag_puzzle  # noqa: E402

PUZZLES = {"mate-in-1": 70, "back-rank": 45, "mate-in-2": 60, "forks": 70, "pins": 50, "skewers": 45,
           "discovered": 45}
PLAYOUTS = {"queen-mate": 30, "ladder-mate": 30, "rook-mate": 20}

W, B = chess.WHITE, chess.BLACK
DIAGONAL = [(1, 1), (1, -1), (-1, 1), (-1, -1)]
STRAIGHT = [(1, 0), (-1, 0), (0, 1), (0, -1)]


# MARK: Squares and lines

def at(f: int, r: int) -> chess.Square | None:
    return chess.square(f, r) if 0 <= f < 8 and 0 <= r < 8 else None


def sq(name: str) -> chess.Square:
    return chess.parse_square(name)


def mv(a: str | int, b: str | int) -> chess.Move:
    return chess.Move(sq(a) if isinstance(a, str) else a, sq(b) if isinstance(b, str) else b)


def walk(start: chess.Square, step: tuple[int, int], limit: int = 7) -> list[chess.Square]:
    """Squares from `start` (not included) in one direction, up to the edge."""
    f, r = chess.square_file(start), chess.square_rank(start)
    out = []
    for i in range(1, limit + 1):
        s = at(f + step[0] * i, r + step[1] * i)
        if s is None:
            break
        out.append(s)
    return out


def between(a: chess.Square, b: chess.Square) -> set[chess.Square]:
    return set(chess.SquareSet(chess.between(a, b)))


def near(a: chess.Square, b: chess.Square) -> bool:
    return chess.square_distance(a, b) <= 1


# MARK: Sketches

class Sketch:
    """A position being composed, always with White to move (it may be mirrored later).

    Templates place the pieces of the tactic, mark the squares its lines need
    (`clear`) and the squares Black's extra pieces must not cover (`guard`),
    and name the intended first move (`key`). `dress` adds the rest."""

    def __init__(self, endgame: bool = False):
        self.pieces: dict[chess.Square, chess.Piece] = {}
        self.clear: set[chess.Square] = set()
        self.guard: set[chess.Square] = set()
        self.loose: set[chess.Square] = set()        # pieces allowed to stand en prise
        self.key: list[chess.Move] = []
        self.test: Callable[[chess.Board, list[chess.Move]], bool] | None = None
        self.endgame = endgame
        self.flippable = True                        # may be mirrored left to right
        self.white_shelter = True                    # give White a castled king if it has none
        self.balance = (-1, 2)                       # White's material edge to aim for
        self.extra = (1, 3)                          # filler pieces to add (both sides together)
        self.opening: chess.Board | None = None      # a real game position, used as it is

    def add(self, symbol: str, square: chess.Square | None) -> bool:
        if square is None or square in self.pieces or square in self.clear:
            return False
        self.pieces[square] = chess.Piece.from_symbol(symbol)
        return True

    def put(self, spec: str) -> bool:
        """Places pieces written like "Kg1 Rd1 kg8 pf7" (upper case is White)."""
        return all(self.add(t[0], sq(t[1:])) for t in spec.split())

    def keep(self, squares) -> bool:
        """Marks squares that must stay empty; False if one is taken."""
        squares = set(squares)
        if squares & set(self.pieces):
            return False
        self.clear |= squares
        return True

    def free(self, square: chess.Square | None) -> bool:
        return square is not None and square not in self.pieces and square not in self.clear

    def king(self, color: chess.Color) -> chess.Square | None:
        return next((s for s, p in self.pieces.items() if p.piece_type == chess.KING and p.color == color), None)

    def transform(self, f: Callable[[chess.Square], chess.Square]) -> None:
        self.pieces = {f(s): p for s, p in self.pieces.items()}
        self.clear = {f(s) for s in self.clear}
        self.guard = {f(s) for s in self.guard}
        self.loose = {f(s) for s in self.loose}
        self.key = [chess.Move(f(m.from_square), f(m.to_square), m.promotion) for m in self.key]

    def board(self) -> chess.Board:
        b = chess.Board(None)
        for s, p in self.pieces.items():
            b.set_piece_at(s, p)
        b.turn = W
        return b


def flip_files(s: chess.Square) -> chess.Square:
    return chess.square(7 - chess.square_file(s), chess.square_rank(s))


def edge_to_h_file(s: chess.Square) -> chess.Square:
    """Turns the board a quarter: the eighth rank becomes the h-file. Only for cores without pawns."""
    return chess.square(chess.square_rank(s), 7 - chess.square_file(s))


# MARK: Dressing the position

# Where extra pieces usually stand, from White's side (Black uses the mirror image).
HOMES = {
    chess.KNIGHT: "c3 f3 d2 b3 e2 d4 c4 g3 e3 a3",
    chess.BISHOP: "e2 d3 c4 b3 b2 g2 f4 e3 d2 c2 c1 f1",
    chess.ROOK: "a1 b1 c1 d1 e1 f1 c2 d2 e2 a2",
    chess.QUEEN: "d1 e2 d2 c2 b3 e3 f3 c3 d3",
}
# Ranks (0-based, White's side) a pawn usually stands on, per file; repeats are weights.
PAWN_RANKS = {0: (1, 1, 2, 3), 1: (1, 1, 2, 3), 2: (1, 2, 2, 3), 3: (2, 3, 3, 4), 4: (2, 3, 3, 4),
              5: (1, 2, 2, 3), 6: (1, 1, 2), 7: (1, 2, 2, 3)}
ENDGAME_PAWN_RANKS = (1, 2, 2, 3, 3, 4)
WHITE_HOMES = [("g1", "f2 g2 h3"), ("g1", "f2 g3 h2"), ("g1", "f2 g2 h3"), ("g1", "f2 g2 h2"), ("h1", "f2 g2 h3"),
               ("h1", "g2 h2"), ("g1", "f3 g2 h2"), ("c1", "a2 b2 c2"), ("b1", "a2 b2 c2"), ("b1", "a3 b2 c2"),
               ("c1", "a3 b2 c2")]
BLACK_HOMES = [("g8", "f7 g7 h7"), ("g8", "f7 g7 h6"), ("g8", "f7 g6 h7"), ("h8", "f7 g7 h7"), ("g8", "f7 g7 h7"),
               ("c8", "a7 b7 c7"), ("b8", "a7 b7 c7"), ("b8", "a6 b7 c7"), ("h8", "g7 h6 f7")]


def for_color(name_or_square, color: chess.Color) -> chess.Square:
    s = sq(name_or_square) if isinstance(name_or_square, str) else name_or_square
    return s if color == W else chess.square_mirror(s)


def covers(board: chess.Board, square: chess.Square, piece: chess.Piece) -> chess.SquareSet:
    """What `piece` would attack from `square` on this board."""
    b = board.copy(stack=False)
    b.set_piece_at(square, piece)
    return b.attacks(square)


def place_home(sk: Sketch, rng: random.Random, color: chess.Color, homes) -> bool:
    """Castles a king that the template didn't place: the king plus its pawns
    (`homes` name the squares as they are, for the colour being placed)."""
    enemy = sk.king(not color)
    for king, pawns in rng.sample(homes, len(homes)):
        squares = [sq(king)] + [sq(p) for p in pawns.split()]
        if not all(sk.free(s) for s in squares) or (enemy is not None and chess.square_distance(squares[0], enemy) < 2):
            continue
        sk.add("K" if color == W else "k", squares[0])
        for s in squares[1:]:
            sk.add("P" if color == W else "p", s)
        return True
    return False


def place_endgame_king(sk: Sketch, rng: random.Random, color: chess.Color) -> bool:
    enemy = sk.king(not color)
    for _ in range(40):
        s = at(rng.randint(1, 6), rng.choice([0, 1, 1, 2, 2]) if color == W else rng.choice([7, 6, 6, 5, 5]))
        if sk.free(s) and (enemy is None or chess.square_distance(s, enemy) >= 3):
            sk.add("K" if color == W else "k", s)
            return True
    return False


def filler_ok(sk: Sketch, board: chess.Board, square: chess.Square, piece: chess.Piece) -> bool:
    """An extra piece mustn't change the story: no checks, no new attacks on enemy
    pieces, and Black's extras keep off the squares the tactic depends on."""
    if not sk.free(square):
        return False
    hits = covers(board, square, piece)
    enemy_king = sk.king(not piece.color)
    if enemy_king is not None and (enemy_king in hits or hits & chess.SquareSet(chess.BB_KING_ATTACKS[enemy_king])):
        return False
    for t in hits:
        p = board.piece_at(t)
        if p and p.color != piece.color and p.piece_type != chess.PAWN:
            return False
    if piece.color == B and (hits & chess.SquareSet(sk.guard) or square in sk.guard):
        return False
    own_king = sk.king(piece.color)
    if piece.piece_type == chess.ROOK and own_king is not None and chess.square_rank(square) == chess.square_rank(own_king) \
            and chess.square_rank(square) in (0, 7):
        # A rook in the corner beside a castled king (Kb1 + Ra1, Kg1 + Rh1) never castled; it looks wrong.
        kf, f = chess.square_file(own_king), chess.square_file(square)
        if (kf >= 5 and f > kf) or (kf <= 2 and f < kf):
            return False
    if piece.piece_type == chess.PAWN:
        # Pawns never stand beyond an enemy pawn on the same file.
        f, r = chess.square_file(square), chess.square_rank(square)
        for s in board.pieces(chess.PAWN, not piece.color):
            if chess.square_file(s) == f and (chess.square_rank(s) < r if piece.color == W else chess.square_rank(s) > r):
                return False
    return True


def add_pawns(sk: Sketch, rng: random.Random, color: chess.Color, n: int) -> None:
    board = sk.board()
    used = {chess.square_file(s) for s, p in sk.pieces.items() if p.piece_type == chess.PAWN and p.color == color}
    files = [f for f in range(8) if f not in used]
    rng.shuffle(files)
    for f in files:
        if n <= 0:
            break
        rank = rng.choice(ENDGAME_PAWN_RANKS if sk.endgame else PAWN_RANKS[f])
        s = at(f, rank if color == W else 7 - rank)
        piece = chess.Piece(chess.PAWN, color)
        if filler_ok(sk, board, s, piece):
            sk.pieces[s] = piece
            board.set_piece_at(s, piece)
            n -= 1


def add_piece(sk: Sketch, rng: random.Random, color: chess.Color, piece_type: int) -> bool:
    board = sk.board()
    have = board.pieces(piece_type, color)
    if len(have) >= (1 if piece_type == chess.QUEEN else 2):
        return False
    homes = [for_color(s, color) for s in HOMES[piece_type].split()]
    if sk.endgame:
        homes += [at(rng.randint(0, 7), rng.randint(2, 5)) for _ in range(4)]
    rng.shuffle(homes)
    piece = chess.Piece(piece_type, color)
    for s in homes:
        if piece_type == chess.BISHOP and have and light(s) == light(next(iter(have))):
            continue  # a second bishop runs on the other colour
        if filler_ok(sk, board, s, piece):
            sk.pieces[s] = piece
            return True
    return False


def light(s: chess.Square) -> bool:
    return bool(chess.BB_SQUARES[s] & chess.BB_LIGHT_SQUARES)


def pieces_for(gap: int, rng: random.Random) -> list[int]:
    """Piece types worth about `gap`, best fit first."""
    minors = rng.sample([chess.KNIGHT, chess.BISHOP], 2)
    if gap >= 8:
        return [chess.QUEEN, chess.ROOK] + minors
    if gap >= 4:
        return [chess.ROOK] + minors
    return minors


def dress(sk: Sketch, rng: random.Random) -> chess.Board | None:
    """Adds the kings' homes, pawns and a few pieces around the tactic."""
    if sk.king(B) is None:
        if not (place_endgame_king(sk, rng, B) if sk.endgame else place_home(sk, rng, B, BLACK_HOMES)):
            return None
    if sk.king(W) is None:
        if sk.endgame or not sk.white_shelter:
            if not place_endgame_king(sk, rng, W):
                return None
        elif not place_home(sk, rng, W, WHITE_HOMES):
            return None
    for color in (W, B):
        have = sum(1 for p in sk.pieces.values() if p.piece_type == chess.PAWN and p.color == color)
        want = rng.randint(1, 4) if sk.endgame else rng.randint(4, 7)
        add_pawns(sk, rng, color, want - have)
    # Neutral filler first (a piece each), then even out the material.
    for _ in range(rng.randint(*sk.extra) // 2):
        t = rng.choice([chess.ROOK, chess.KNIGHT, chess.BISHOP, chess.ROOK])
        if add_piece(sk, rng, W, t):
            add_piece(sk, rng, B, t)
    lo, hi = sk.balance
    target = rng.randint(lo, hi)
    for _ in range(6):
        edge = balance(sk.board(), W)
        gap = edge - target
        if lo <= edge <= hi and abs(gap) <= 1:
            break
        poorer = B if gap > 0 else W
        if abs(gap) < 2 or not any(add_piece(sk, rng, poorer, t) for t in pieces_for(abs(gap), rng)):
            add_pawns(sk, rng, poorer, 1)
    board = sk.board()
    board.fullmove_number = max(12, 40 - len(board.piece_map()) + rng.randint(0, 10))
    return board


def plausible(board: chess.Board, max_balance: int = 4, pieces: tuple[int, int] = (8, 22)) -> bool:
    """Legal, not in check, no extra queens or same-coloured bishops, pawn
    structures that captures could explain, and roughly level material."""
    if not board.is_valid() or board.is_check():
        return False
    for color in (W, B):
        if len(board.pieces(chess.QUEEN, color)) > 1 or len(board.pieces(chess.ROOK, color)) > 2 \
                or len(board.pieces(chess.KNIGHT, color)) > 2:
            return False
        bishops = list(board.pieces(chess.BISHOP, color))
        if len(bishops) > 2 or (len(bishops) == 2 and (chess.square_file(bishops[0]) + chess.square_rank(bishops[0])) % 2
                                == (chess.square_file(bishops[1]) + chess.square_rank(bishops[1])) % 2):
            return False
        pawns = board.pieces(chess.PAWN, color)
        files = Counter(chess.square_file(s) for s in pawns)
        doubled = sum(n - 1 for n in files.values())
        if max(files.values(), default=0) > 2 or doubled > 16 - chess.popcount(board.occupied_co[not color]):
            return False
        # Few pawns far up the board, and no long walls of them away from home.
        ranks = [chess.square_rank(s) if color == W else 7 - chess.square_rank(s) for s in pawns]
        if sum(1 for r in ranks if r >= 3) > 3:
            return False
        for r in set(ranks) - {1}:
            row = "".join("P" if (at(f, r if color == W else 7 - r) in pawns) else "." for f in range(8))
            if "PPPP" in row:
                return False
    if abs(balance(board, W)) > max_balance:
        return False
    return pieces[0] <= len(board.piece_map()) <= pieces[1]


def compose(template: Callable[[random.Random], Sketch | None], rng: random.Random,
            mates: bool) -> tuple[chess.Board, list[chess.Move]] | None:
    """One candidate from a template: core, optional left-right flip, dressing,
    static checks, and a coin flip for which colour solves it."""
    sk = template(rng)
    if sk is None:
        return None
    if sk.opening is not None:
        return (sk.opening, sk.key) if sk.test is None or sk.test(sk.opening, sk.key) else None
    if sk.flippable and rng.random() < 0.5:
        sk.transform(flip_files)
    board = dress(sk, rng)
    if board is None or not plausible(board):
        return None
    if any(not board.is_legal(m) for m in sk.key):
        return None
    if danger_squares(board, W) - sk.loose:
        return None  # the solver's own pieces shouldn't be hanging
    if not mates and danger_squares(board, B) - sk.loose:
        return None  # no free material besides the tactic
    if sk.test and not sk.test(board, sk.key):
        return None
    key = sk.key
    if rng.random() < 0.5:
        board = board.mirror()
        key = [chess.Move(chess.square_mirror(m.from_square), chess.square_mirror(m.to_square), m.promotion) for m in key]
    return board, key


# MARK: Static checks used by the templates

def mating_moves(board: chess.Board) -> list[chess.Move]:
    out = []
    for m in board.legal_moves:
        if board.gives_check(m):
            board.push(m)
            if board.is_checkmate():
                out.append(m)
            board.pop()
    return out


def mate_test(board: chess.Board, key: list[chess.Move], min_checks: int | None = None) -> bool:
    """The key mates and at most one other move mates too. Most positions also
    need a check that doesn't mate, as a distraction (decided per position by
    a checksum of the board, so the same board always gets the same answer)."""
    mates = mating_moves(board)
    if not 1 <= len(mates) <= 2 or not any(k in mates for k in key):
        return False
    if min_checks is None:
        min_checks = 0 if zlib.crc32(board.board_fen().encode()) % 3 == 0 else 1
    return sum(1 for m in board.legal_moves if board.gives_check(m)) - len(mates) >= min_checks


def after(board: chess.Board, move: chess.Move) -> chess.Board:
    b = board.copy(stack=False)
    b.push(move)
    return b


def holds(b: chess.Board, square: chess.Square) -> bool:
    """Black can't take the White piece on `square` without losing material:
    nothing attacks it, or it is defended and every attacker is worth more."""
    attackers = b.attackers(B, square)
    if not attackers:
        return True
    mine = VALUE[b.piece_at(square).piece_type]
    return bool(b.attackers(W, square)) and all(worth(b.piece_at(a)) > mine for a in attackers)


def targets(b: chess.Board, square: chess.Square) -> list[chess.Square]:
    """What the piece on `square` hits that is worth hitting (as tag_puzzle counts it)."""
    me = b.piece_at(square)
    out = []
    for t in b.attacks(square):
        p = b.piece_at(t)
        if p and p.color == B and (p.piece_type == chess.KING or VALUE[p.piece_type] > VALUE[me.piece_type]
                                   or not b.attackers(B, t)):
            out.append(t)
    return out


def fork_test(board: chess.Board, key: list[chess.Move]) -> bool:
    """The piece lands where nothing takes it and hits two targets."""
    b = after(board, key[0])
    return holds(b, key[0].to_square) and len(targets(b, key[0].to_square)) >= 2


def line_behind(b: chess.Board, square: chess.Square) -> list[tuple[chess.Square, chess.Square]]:
    """For the slider on `square`: (front, back) pairs of Black pieces along its lines."""
    piece = b.piece_at(square)
    steps = {chess.BISHOP: DIAGONAL, chess.ROOK: STRAIGHT, chess.QUEEN: DIAGONAL + STRAIGHT}.get(piece.piece_type, [])
    out = []
    for step in steps:
        hit = [s for s in walk(square, step) if b.piece_at(s)][:2]
        if len(hit) == 2 and all(b.piece_at(s).color == B for s in hit):
            out.append((hit[0], hit[1]))
    return out


def worth(p: chess.Piece) -> int:
    return 100 if p.piece_type == chess.KING else VALUE[p.piece_type]


def pin_test(board: chess.Board, key: list[chess.Move]) -> bool:
    """The slider lands where Black can't take it for free and pins a piece to
    something worth more; the pinned piece has no defender, or is worth more than
    the slider (a pinned queen may take a defended pinner, but loses herself)."""
    b = after(board, key[0])
    to = key[0].to_square
    if not holds(b, to) or b.is_check():
        return False
    mine = VALUE[b.piece_at(to).piece_type]
    return any(worth(b.piece_at(back)) > worth(b.piece_at(front))
               and (not b.attackers(B, front) or VALUE[b.piece_at(front).piece_type] > mine)
               for front, back in line_behind(b, to))


def skewer_test(board: chess.Board, key: list[chess.Move]) -> bool:
    """The slider lands safely, attacking a big piece with a smaller one behind it."""
    b = after(board, key[0])
    if not holds(b, key[0].to_square):
        return False
    return any(worth(b.piece_at(front)) > worth(b.piece_at(back)) and b.piece_at(back).piece_type != chess.PAWN
               for front, back in line_behind(b, key[0].to_square))


def uncovers(board: chess.Board, move: chess.Move) -> list[chess.Square]:
    """Black pieces that a White slider attacks through the square `move` leaves."""
    b = after(board, move)
    out = []
    for s in b.pieces(chess.BISHOP, W) | b.pieces(chess.ROOK, W) | b.pieces(chess.QUEEN, W):
        if s == move.to_square:
            continue
        for t in b.attacks(s):
            p = b.piece_at(t)
            if p and p.color == B and move.from_square in between(s, t):
                out.append(t)
    return out


def discovered_check_test(board: chess.Board, key: list[chess.Move]) -> bool:
    """The move uncovers a check, and the king can't answer it by taking the piece that moved."""
    king = board.king(B)
    if king not in uncovers(board, key[0]):
        return False
    b = after(board, key[0])
    return not near(key[0].to_square, king) or bool(b.attackers(W, key[0].to_square))


def discovered_attack_test(board: chess.Board, key: list[chess.Move]) -> bool:
    """Moving the piece opens a line to the queen or a rook, and the piece itself
    checks or captures, so there's no time to save both."""
    hit = uncovers(board, key[0])
    return any(board.piece_at(t).piece_type in (chess.QUEEN, chess.ROOK) for t in hit) and \
        (board.gives_check(key[0]) or board.is_capture(key[0]))


def double_check_test(board: chess.Board, key: list[chess.Move]) -> bool:
    """Both pieces give check and the king has at most one square left."""
    b = after(board, key[0])
    return len(b.checkers()) == 2 and b.legal_moves.count() <= 1


# MARK: Mate-in-one templates

def m1_back_rank(rng: random.Random) -> Sketch | None:
    """A rook or queen drops onto the eighth rank in front of three unmoved pawns."""
    sk = Sketch()
    king = rng.choice(["g8", "g8", "g8", "h8"])
    sk.put(f"k{king} pg7 ph7" + ("" if king == "h8" and rng.random() < 0.5 else " pf7"))
    x = rng.randint(0, 4)
    heavy = "Q" if rng.random() < 0.3 else "R"
    origin, target = at(x, rng.randint(0, 2) if heavy == "R" else rng.randint(1, 4)), at(x, 7)
    if not sk.keep(between(origin, target) | between(target, sq(king))):
        return None
    if heavy == "R" and rng.random() < 0.35:
        sk.add("r", target)  # the rook takes the only guard, which nothing defends
    else:
        sk.keep({target})
    sk.add(heavy, origin)
    if rng.random() < 0.6:
        # Black's queen or rook is busy on the other wing instead of guarding the back rank.
        busy = rng.choice(["qa5", "qb6", "qb4", "qc5", "qa3", "rc7", "rd7", "rb7", "rc6", "rd6"])
        sk.add(busy[0], sq(busy[1:]))
    sk.key = [chess.Move(origin, target)]
    sk.guard = between(target, sq(king)) | {target}
    sk.test = mate_test
    return sk


def m1_queen_kiss(rng: random.Random) -> Sketch | None:
    """Endgame: the queen mates right in front of the king, guarded by her own king."""
    sk = Sketch(endgame=True)
    f = rng.randint(1, 6)
    bk, mate, wk = at(f, 7), at(f, 6), at(f + rng.choice([-1, 0, 1]), 5)
    origins = [s for step in [(1, 0), (-1, 0), (1, -1), (-1, -1), (0, -1)] for s in walk(mate, step)[1:]
               if wk not in between(s, mate) and s != wk]
    origin = rng.choice(origins)
    sk.add("k", bk), sk.add("K", wk), sk.add("Q", origin)
    sk.keep(between(origin, mate) | {mate})
    sk.key = [chess.Move(origin, mate)]
    sk.guard = {mate}
    if rng.random() < 0.4:
        sk.transform(edge_to_h_file)
    sk.add("r", at(rng.randint(0, 7), rng.randint(0, 3)))  # Black still has a rook
    sk.balance = (2, 4)
    sk.test = mate_test
    return sk


def m1_rook_box(rng: random.Random) -> Sketch | None:
    """Endgame: king facing king, the rook mates along the edge."""
    sk = Sketch(endgame=True)
    f = rng.randint(0, 7)
    bk = at(f, 7)
    wk = at(f, 5) if 0 < f < 7 else at(f + (1 if f == 0 else -1) * rng.choice([0, 1]), 5)
    x = rng.choice([c for c in range(8) if abs(c - f) >= 2])
    origin, target = at(x, rng.randint(0, 4)), at(x, 7)
    if origin == wk or wk in between(origin, target):
        return None
    sk.add("k", bk), sk.add("K", wk), sk.add("R", origin)
    sk.keep(between(origin, target) | {target} | between(target, bk))
    sk.key = [chess.Move(origin, target)]
    sk.guard = between(target, bk) | {target}
    if rng.random() < 0.4:
        sk.transform(edge_to_h_file)
    sk.add(rng.choice("bn"), at(rng.randint(0, 7), rng.randint(2, 5)))
    sk.balance = (1, 3)
    sk.test = mate_test
    return sk


def m1_two_rooks(rng: random.Random) -> Sketch | None:
    """One rook holds the seventh rank, the other mates on the eighth."""
    sk = Sketch(endgame=rng.random() < 0.5)
    f = rng.randint(1, 6)
    bk = at(f, 7)
    a = rng.choice([c for c in range(8) if abs(c - f) >= 2])
    b = rng.choice([c for c in range(8) if abs(c - f) >= 2 and c != a])
    cut, origin, target = at(a, 6), at(b, rng.randint(0, 4)), at(b, 7)
    sk.add("k", bk), sk.add("R", cut), sk.add("R", origin)
    if not sk.keep(between(origin, target) | {target} | between(target, bk) | between(cut, at(f, 6)) | {at(f, 6)}):
        return None
    sk.key = [chess.Move(origin, target)]
    sk.guard = between(target, bk) | {target}
    sk.add("q", at(rng.randint(0, 7), rng.randint(1, 4)))
    sk.white_shelter = False
    sk.balance = (0, 3)
    sk.test = mate_test
    return sk


def m1_battery_h7(rng: random.Random) -> Sketch | None:
    """Queen and bishop line up on h7: Qxh7#."""
    sk = Sketch()
    sk.put("kg8 rf8 pf7 pg7")
    pawn = rng.random() < 0.7
    if pawn:
        sk.put("ph7")
    bishop = sq(rng.choice(["d3", "c2", "b1", "d3"]))
    line = between(bishop, sq("h7"))
    queen = sq(rng.choice(["h5", "h4", "h3"] + [chess.square_name(s) for s in line if chess.square_rank(s) >= 3]))
    sk.add("B", bishop), sk.add("Q", queen)
    if not sk.keep((line - {queen}) | between(queen, sq("h7")) | ({sq("h7")} if not pawn else set())):
        return None
    sk.key = [mv(queen, "h7")]
    sk.guard = {sq("h7")}
    sk.test = mate_test
    return sk


def m1_long_diagonal(rng: random.Random) -> Sketch | None:
    """The bishop on the long diagonal guards g7 and the queen lands there."""
    sk = Sketch()
    wedge = rng.random() < 0.35
    if wedge:
        # A pawn on f6 does the bishop's job.
        sk.put("kg8 rf8 pf7 ph7 Pf6")
        queen = sq(rng.choice(["h6", "g4", "g3", "g5"]))
        sk.add("Q", queen)
        sk.keep(between(queen, sq("g7")) | {sq("g7")})
        sk.loose.add(sq("f6"))
    else:
        sk.put("kg8 rf8 pf7 pg6 ph7 Qh6")
        bishop = sq(rng.choice(["b2", "c3", "d4", "e5", "b2"]))
        sk.add("B", bishop)
        if not sk.keep(between(bishop, sq("g7")) | {sq("g7")}):
            return None
        queen = sq("h6")
    sk.key = [mv(queen, "g7")]
    sk.guard = {sq("g7")}
    sk.test = mate_test
    return sk


def m1_knight_and_queen(rng: random.Random) -> Sketch | None:
    """The knight guards the mating square: Qh7# next to Ng5 or Nf6, or Qg7# next to Nf5/Nh5."""
    sk = Sketch()
    kind = rng.choice(["g5", "f6", "g7"])
    if kind == "g5":
        sk.put("kg8 rf8 pf7 pg7 Ng5")
        mate = "h7"
        queens = ["h5", "h4", "h3", "d3", "c2", "e4"]
    elif kind == "f6":
        sk.put("kh8 pg7 ph7 Nf6" + rng.choice([" pf7", " rf8 pf7", " rg8"]))
        mate = "h7"
        queens = ["h5", "h4", "h3", "d3", "c2", "e4"]
        sk.loose.add(sq("f6"))
    else:
        sk.put(f"kg8 rf8 pf7 ph7 N{rng.choice(['f5', 'h5'])}")
        mate = "g7"
        queens = ["g3", "g4", "h6", "d4", "c3"]
    queen = sq(rng.choice(queens))
    if not sk.add("Q", queen) or not sk.keep(between(queen, sq(mate)) | ({sq(mate)} if kind != "f6" else set())):
        return None
    sk.key = [mv(queen, mate)]
    sk.guard = {sq(mate)}
    sk.loose.add(sq("g5"))
    sk.test = mate_test
    return sk


def m1_smothered(rng: random.Random) -> Sketch | None:
    """Smothered mate: the king is boxed in by its own pieces and Nf7 mates."""
    sk = Sketch()
    sk.put("kh8 rg8 pg7 ph7")
    if rng.random() < 0.4:
        sk.put("pf7")
    else:
        sk.keep({sq("f7")})
    origin = sq(rng.choice(["g5", "e5", "d6", "g5", "e5", "h6"]))
    sk.add("N", origin)
    sk.key = [mv(origin, "f7")]
    sk.guard = {sq("f7")}
    sk.loose.add(origin)
    sk.test = mate_test
    return sk


def m1_bishop_and_rook(rng: random.Random) -> Sketch | None:
    """Rook and bishop together: the Opera mate, Morphy's and Pillsbury's mates,
    or a back-rank mate where the bishop covers the luft."""
    sk = Sketch()
    kind = rng.choice(["opera", "morphy", "pillsbury", "luft"])
    if kind == "opera":
        sk.put(f"ke8 pf7 B{rng.choice(['g5', 'h4', 'g5'])}" + rng.choice(["", " bf8", " pg7 ph7", " bf8 pg7"]))
        rook = at(3, rng.randint(0, 3))
        sk.add("R", rook)
        if rng.random() < 0.3:
            sk.add("r", sq("d8"))
            sk.keep(between(rook, sq("d8")) | {sq("e7")})
        elif not sk.keep(between(rook, sq("d8")) | {sq("d8"), sq("e7")}):
            return None
        sk.key = [mv(rook, "d8")]
        sk.guard = {sq("d8"), sq("d7"), sq("e7")}
    elif kind == "morphy":
        sk.put("kh8 ph7" + rng.choice(["", " pf7"]))
        rook = sq(rng.choice(["g1", "g3", "g4"]))
        sk.add("R", rook)
        diag = sq(rng.choice(["c3", "d4", "e5", "f6"]))
        f, r = chess.square_file(diag), chess.square_rank(diag)
        origins = [s for s in walk(diag, (1, -1), 3) + walk(diag, (-1, 1), 2) if chess.square_rank(s) <= 6]
        origin = rng.choice(origins)
        sk.add("B", origin)
        if not sk.keep(between(rook, sq("g8")) | {sq("g8"), sq("g7")} | between(diag, sq("h8")) | {diag}
                       | between(origin, diag)):
            return None
        sk.key = [chess.Move(origin, diag)]
        sk.guard = {sq("g7"), sq("g8"), diag} | between(diag, sq("h8"))
        if rook == sq("g1"):
            sk.put("Kh1 Ph2")
    elif kind == "pillsbury":
        sk.put("kg8 rf8 pf7 ph7")
        bishop = sq(rng.choice(["b2", "c3", "d4"]))
        sk.add("B", bishop)
        rank = rng.choice([2, 3, 4])
        target = at(6, rank)
        origin = at(rng.randint(0, 4), rank)
        sk.add("R", origin)
        if not sk.keep(between(bishop, sq("h8")) | between(origin, target) | {target} | between(target, sq("g8"))):
            return None
        sk.key = [chess.Move(origin, target)]
        sk.guard = {sq("g7"), sq("h8")} | between(target, sq("g8"))
    else:
        sk.put("kg8 pf7 pg7 ph6")
        bishop = sq(rng.choice(["d3", "c2", "b1"]))
        sk.add("B", bishop)
        x = rng.randint(0, 4)
        origin, target = at(x, rng.randint(0, 2)), at(x, 7)
        sk.add("R", origin)
        if not sk.keep(between(bishop, sq("h7")) | {sq("h7")} | between(origin, target) | {target}
                       | between(target, sq("g8"))):
            return None
        sk.key = [chess.Move(origin, target)]
        sk.guard = {sq("h7"), target} | between(target, sq("g8"))
    sk.test = mate_test
    return sk


def m1_minor_patterns(rng: random.Random) -> Sketch | None:
    """Boden's mate (two bishops), the Arabian mate and Anastasia's mate (rook and knight)."""
    sk = Sketch()
    kind = rng.choice(["boden", "arabian", "anastasia"])
    if kind == "boden":
        sk.put(f"kc8 rd8 pa7 {rng.choice(['nd7', 'bd7', 'rd7'])}")
        dark = sq(rng.choice(["f4", "e5", "g3", "f4"]))
        light = sq(rng.choice(["b5", "c4", "d3", "e2"]))
        sk.add("B", dark), sk.add("B", light)
        if not sk.keep(between(dark, sq("b8")) | {sq("b7"), sq("c7"), sq("a6")} | between(light, sq("a6"))):
            return None
        sk.key = [mv(light, "a6")]
        sk.guard = {sq("b7"), sq("b8"), sq("c7"), sq("a6")}
    elif kind == "arabian":
        sk.put("kh8 Nf6" + rng.choice(["", " pf7"]))
        sk.loose.add(sq("f6"))
        if rng.random() < 0.5:
            sk.put("pg7")
            origin = at(7, rng.randint(0, 4))
        else:
            origin = at(rng.randint(0, 4), 6)
        sk.add("R", origin)
        if not sk.keep(between(origin, sq("h7")) | {sq("h7")}):
            return None
        sk.key = [mv(origin, "h7")]
        sk.guard = {sq("h7"), sq("g8")}
    else:
        sk.put("kh7 pg7 Ne7" + rng.choice(["", " pf7", " rf8"]))
        rank = rng.randint(0, 4)
        target = at(7, rank)
        origin = at(rng.randint(0, 4), rank)
        sk.add("R", origin)
        if not sk.keep(between(origin, target) | {target} | between(target, sq("h7"))):
            return None
        sk.key = [chess.Move(origin, target)]
        sk.guard = between(target, sq("h7")) | {target, sq("g8"), sq("g6")}
        sk.loose.add(sq("e7"))
    sk.test = mate_test
    return sk


OPENING_TRAPS = [
    "e4 e5 Qh5 Nc6 Bc4 Nf6",      # Scholar's mate, Qxf7#
    "e4 e5 Bc4 Nc6 Qh5 Nf6",
    "e4 e5 Bc4 Bc5 Qh5 Nf6",
    "e4 e5 Qf3 Nc6 Bc4 Nd4",
    "e4 e5 Bc4 Nc6 Qf3 Nd4",
    "f3 e5 g4",                    # Fool's mate, Qh4#
    "f4 e5 g4",
    "e4 g5 d4 f6",                 # Qh5#
]


def m1_opening_trap(rng: random.Random) -> Sketch | None:
    """A few famous early mates (Scholar's, Fool's) on a full board, played out from the start."""
    board = chess.Board()
    for san in rng.choice(OPENING_TRAPS).split():
        board.push_san(san)
    sk = Sketch()
    sk.opening = board
    sk.key = mating_moves(board)
    sk.test = lambda board, key: mate_test(board, key, min_checks=0)
    return sk


# MARK: Back-rank templates

def br_battery(rng: random.Random) -> Sketch | None:
    """Two heavy pieces on one file against a guarded back rank: Rxe8+ Rxe8 Rxe8#."""
    sk = Sketch()
    king = rng.choice(["g8", "g8", "h8"])
    sk.put(f"k{king} pg7 ph7" + (" pf7" if king == "g8" or rng.random() < 0.5 else ""))
    x = rng.randint(1, 4)
    front, back = rng.choice([("R", "R"), ("R", "R"), ("Q", "R"), ("R", "Q")])
    rf = rng.randint(1, 3)
    f_sq, b_sq, target = at(x, rf), at(x, rng.randint(0, rf - 1)), at(x, 7)
    sk.add(front, f_sq), sk.add(back, b_sq)
    if not sk.keep(between(b_sq, f_sq) | between(f_sq, target) | between(target, sq(king))):
        return None
    # Black guards the square: a rook on it backed up along the rank, or a rook from the side.
    side = at(rng.randint(0, x - 1), 7)
    if rng.random() < 0.6:
        sk.add("r", target)
        sk.add(rng.choice("rq") if chess.square_file(side) > 0 else "r", side)  # no queen in the corner
    else:
        sk.keep({target})
        sk.add("r", side)
    sk.keep(between(side, target))
    sk.key = [chess.Move(f_sq, target)]
    sk.guard = between(target, sq(king)) | {target}
    return sk


def br_open(rng: random.Random) -> Sketch | None:
    """Heavy pieces against an unmoved pawn shield; the engine keeps the ones that mate in one or two."""
    sk = Sketch()
    king = rng.choice(["g8", "g8", "h8"])
    sk.put(f"k{king} pg7 ph7" + (" pf7" if king == "g8" or rng.random() < 0.6 else ""))
    files = rng.sample(range(0, 5), 2)
    kinds = rng.choice([("R", "R"), ("Q", "R"), ("R", "Q"), ("Q", "R")])
    for x, kind in zip(files, kinds):
        s = at(x, rng.randint(1 if kind == "Q" else 0, 4))
        sk.add(kind, s)
        sk.keep(between(s, at(x, 6)))
    for kind in rng.choice([["r"], ["r", "r"], ["q"], ["r", "q"], ["r", "b"]]):
        for _ in range(10):
            s = at(rng.randint(1 if kind == "q" else 0, 5), rng.choice([7, 7, 6, 5, 3]))  # no queen in a corner
            if sk.add(kind, s):
                break
    sk.balance = (-1, 3)
    return sk


# MARK: Mate-in-two templates

def m2_smothered(rng: random.Random) -> Sketch | None:
    """Philidor's legacy: Qg8+! Rxg8 Nf7#."""
    sk = Sketch()
    sk.put("kh8 pg7 ph7 Nh6")
    rook = sq(rng.choice(["f8", "f8", "e8", "d8", "c8"]))
    queen = sq(rng.choice(["b3", "c4", "d5", "e6", "c4"]))
    sk.add("r", rook), sk.add("Q", queen)
    if not sk.keep(between(rook, sq("g8")) | {sq("g8"), sq("f7")} | between(queen, sq("g8"))):
        return None
    sk.key = [mv(queen, "g8")]
    sk.guard = {sq("f7"), sq("g8")}
    sk.loose |= {sq("h6"), queen}
    return sk


def m2_anastasia(rng: random.Random) -> Sketch | None:
    """Qxh7+! Kxh7 and the rook mates on the h-file, the knight on e7 covering g6 and g8."""
    sk = Sketch()
    sk.put("kh8 pg7 ph7 Ne7" + rng.choice(["", " pf7", " pf6"]))
    queen = sq(rng.choice(["d3", "c2", "e4", "f5", "b1"]))
    rank = rng.choice([2, 3, 4])
    target = at(7, rank)
    rook = at(rng.randint(0, 5), rank)
    sk.add("Q", queen), sk.add("R", rook)
    if not sk.keep(between(queen, sq("h7")) | between(rook, target) | {target} | between(target, sq("h7"))):
        return None
    sk.key = [mv(queen, "h7")]
    sk.guard = {sq("h7"), sq("g8"), sq("g6"), target} | between(target, sq("h7"))
    sk.loose |= {sq("e7")}
    return sk


def m2_opera(rng: random.Random) -> Sketch | None:
    """The Opera finish: Qb8+! Nxb8 Rd8#, the bishop on g5 covering d8 and e7."""
    sk = Sketch()
    sk.put("ke8 nd7 pf7 Bg5" + rng.choice(["", " pg7 ph7", " bf8 pg7"]))
    queen = sq(rng.choice(["b3", "b4", "b5"]))
    rook = at(3, rng.randint(0, 2))
    sk.add("Q", queen), sk.add("R", rook)
    if not sk.keep(between(queen, sq("b8")) | {sq("b8"), sq("c8"), sq("d8"), sq("e7"), sq("a8")}
                   | between(rook, sq("d7"))):
        return None
    sk.key = [mv(queen, "b8")]
    sk.guard = {sq("b8"), sq("c8"), sq("d8"), sq("e7")}
    return sk


ATTACK_SHELTERS = ["f7 g7 h7", "f7 g6 h7", "f7 g7 h6", "f7 g6 h5", "f6 g7 h7", "f7 h7", "f7 g7", "g7 h7", "f7 g6",
                   "f7 h6", "g6 h7", "f7 g7 h5"]


def m2_attack(rng: random.Random) -> Sketch | None:
    """A kingside attack built at random; the engine keeps those with a single mate in two."""
    sk = Sketch()
    king = rng.choice(["g8", "g8", "g8", "h8"])
    sk.put(f"k{king}")
    for p in rng.choice(ATTACK_SHELTERS).split():
        sk.add("p", sq(p))
    if rng.random() < 0.75:
        sk.add("r", sq("f8"))
    if rng.random() < 0.5:
        sk.add(rng.choice("nb"), sq(rng.choice(["f6", "e7", "d7", "g6", "e6", "c6", "d6"])))
    sk.add("q", sq(rng.choice(["d8", "e7", "c7", "d7", "b6", "a5", "c8", "e8"])))
    sk.add("Q", sq(rng.choice(["h5", "h6", "g4", "g5", "h4", "h3", "e4", "d3", "f3", "g3", "f4"])))
    zones = {"R": ["e1", "d1", "f1", "e3", "f3", "g3", "h3", "d3", "e7", "d7", "c7", "f1"],
             "B": ["d3", "c2", "b1", "c4", "b3", "b2", "c3", "d4", "e5"],
             "N": ["g5", "f5", "e5", "h5", "e4", "d5", "f6", "e6"],
             "P": ["f6", "h6", "g6", "e6"]}
    for kind in rng.sample(["R", "B", "N", "P", "R"], rng.choice([2, 2, 3])):
        for _ in range(6):
            if sk.add(kind, sq(rng.choice(zones[kind]))):
                break
    sk.loose = set(sk.pieces)  # attacking positions are tense; the engine judges them
    sk.extra = (0, 2)
    sk.balance = (-2, 3)
    return sk


def m2_heavy_endgame(rng: random.Random) -> Sketch | None:
    """Queen or rooks against a king in the open; the engine keeps the precise mates in two."""
    sk = Sketch(endgame=True)
    bk = at(rng.randint(0, 7), rng.choice([7, 7, 6, 5]))
    sk.add("k", bk)
    for kind in rng.choice([["Q", "R"], ["R", "R"], ["Q", "N"], ["Q", "B"], ["R", "R", "B"], ["Q"]]):
        for _ in range(10):
            s = at(rng.randint(0, 7), rng.randint(0, 6))
            if not near(s, bk) and sk.add(kind, s):
                break
    for kind in rng.choice([["r"], ["q"], ["r", "b"], ["r", "n"], ["b", "n"]]):
        for _ in range(10):
            s = at(rng.randint(0, 7), rng.randint(0, 7))
            if sk.add(kind, s):
                break
    sk.loose = set(sk.pieces)
    sk.white_shelter = False
    sk.extra = (0, 0)
    sk.balance = (-1, 4)
    return sk


# MARK: Fork templates

BLACK_SPOTS = {
    "k": "g8 h8 e8 c8 b8 f8 g7 e7 d8 f7 d7",
    "q": "d8 c7 e7 d7 b6 a5 c8 e8 b8 f6 g6 e6 d6 c6 a4 b4 h4 g5 f5",
    "r": "a8 b8 c8 d8 e8 f8 h8 c7 d7 e7 a7 b7 c6 d6 e6 f7 g7",
    "b": "c8 b7 e7 d6 c5 b4 e6 d7 f5 g4 g7 a6 c6",
    "n": "c6 f6 d7 e7 a6 b4 d5 e5 g6 h5 c5 b6",
}
KNIGHT_FORKS = "c7 d6 e7 f7 e6 d7 f6 c6 b6 g6 d5 e5 c5 f5"


def spot(kind: str, square: chess.Square) -> bool:
    return chess.square_name(square) in BLACK_SPOTS[kind].split()


def fork_knight(rng: random.Random) -> Sketch | None:
    """A knight lands on a safe square hitting king and queen, king and rook, queen and rook..."""
    pair = rng.choices(["kq", "kr", "qr", "rr", "kb", "qb"], weights=[5, 4, 3, 1, 1, 1])[0]
    x = sq(rng.choice(KNIGHT_FORKS.split()))
    hits = list(chess.SquareSet(chess.BB_KNIGHT_ATTACKS[x]))
    first = [s for s in hits if spot(pair[0], s)]
    second = [s for s in hits if spot(pair[1], s)]
    if not first or not second:
        return None
    a = rng.choice(first)
    rest = [s for s in second if s != a]
    if not rest:
        return None
    b = rng.choice(rest)
    origins = [s for s in hits if s not in (a, b) and chess.square_rank(s) <= 5]
    if not origins:
        return None
    origin = rng.choice(origins)
    sk = Sketch()
    sk.add(pair[0], a), sk.add(pair[1], b), sk.add("N", origin)
    sk.keep({x})
    if "k" not in pair:
        home = rng.choice([("g8", "f7 g7 h7"), ("h8", "g7 h7"), ("b8", "a7 b7"), ("g8", "f7 g6 h7")])
        if not sk.add("k", sq(home[0])):
            return None
        for p in home[1].split():
            sk.add("p", sq(p))
    sk.key = [chess.Move(origin, x)]
    sk.guard = {x}
    sk.test = fork_test
    sk.balance = (-2, 1)
    return sk


def fork_pawn(rng: random.Random) -> Sketch | None:
    """A pawn steps forward and attacks two pieces at once."""
    f = rng.randint(1, 6)
    rank = rng.choice([3, 3, 4, 4, 5])
    dest = at(f, rank)
    origin = at(f, 1) if rank == 3 and rng.random() < 0.4 else at(f, rank - 1)
    pair = rng.choice(["nb", "nr", "br", "nq", "bq", "rq", "nn", "bb", "kr", "kn"])
    left, right = at(f - 1, rank + 1), at(f + 1, rank + 1)
    if rng.random() < 0.5:
        left, right = right, left
    if pair[0] == "k" and rank < 4:
        return None
    sk = Sketch()
    sk.add(pair[0], left), sk.add(pair[1], right), sk.add("P", origin)
    sk.keep(between(origin, dest) | {dest})
    # A second pawn backs up the forking pawn.
    if rng.random() < 0.7:
        sk.add("P", at(f + rng.choice([-1, 1]), rank - 1))
    if "k" not in pair:
        home = rng.choice([("g8", "f7 g7 h7"), ("h8", "g7 h7"), ("c8", "a7 b7 c7"), ("g8", "f7 g6 h7"), ("b8", "a7 b7")])
        if not sk.add("k", sq(home[0])):
            return None
        for p in home[1].split():
            sk.add("p", sq(p))
    sk.key = [chess.Move(origin, dest)]
    sk.guard = {dest}
    sk.test = fork_test
    sk.balance = (-3, 0)
    return sk


def slider_fork(rng: random.Random, kind: str) -> Sketch | None:
    """A queen, bishop or rook checks the king (or hits two big pieces) and takes what's loose."""
    sk = Sketch(endgame=rng.random() < 0.4)
    king = sq(rng.choice(["g8", "g7", "h7", "e7", "f7", "e8", "h8", "d7", "c7", "f8", "e6", "f6"]))
    sk.add("k", king)
    loose_kind = rng.choice("rrbn" if kind == "Q" else "rrq" if kind == "B" else "bn")
    for _ in range(20):
        t = at(rng.randint(0, 7), rng.randint(2, 7))
        if t is not None and chess.square_distance(t, king) >= 3 and sk.add(loose_kind, t):
            break
    else:
        return None
    board = sk.board()
    piece = chess.Piece.from_symbol(kind)
    spots = []
    for x in chess.SQUARES:
        if x in sk.pieces or chess.square_rank(x) > 6:
            continue
        hits = covers(board, x, piece)
        if king in hits and t in hits and not near(x, king):
            spots.append(x)
    if not spots:
        return None
    x = rng.choice(spots)
    steps = {"Q": DIAGONAL + STRAIGHT, "B": DIAGONAL, "R": STRAIGHT}[kind]
    origins = [s for step in steps for s in walk(x, step, 4)
               if not (between(s, x) & set(sk.pieces)) and s not in sk.pieces and chess.square_rank(s) <= 5]
    origins = [s for s in origins if king not in covers(board, s, piece) and t not in covers(board, s, piece)]
    if not origins:
        return None
    origin = rng.choice(origins)
    sk.add(kind, origin)
    sk.keep(between(origin, x) | {x} | between(x, king) | between(x, t))
    if not sk.endgame:
        # Pawn cover for the king where it has some.
        for s in chess.SquareSet(chess.BB_KING_ATTACKS[king]):
            if chess.square_rank(s) < chess.square_rank(king) and rng.random() < 0.5 and s not in sk.clear:
                sk.add("p", s)
    sk.key = [chess.Move(origin, x)]
    sk.guard = {x, t} | between(x, king) | between(x, t)
    sk.test = fork_test
    sk.balance = (-3, 1)
    sk.white_shelter = not sk.endgame
    return sk


# MARK: Pin templates

def pin_slider(rng: random.Random) -> Sketch | None:
    """A bishop, rook or queen pins a piece to the king (or queen) and wins it:
    the pinned piece has no defender, or it is a rook caught by a bishop."""
    kind = rng.choice(["B", "B", "R", "Q"])
    steps = DIAGONAL if kind == "B" else STRAIGHT if kind == "R" else DIAGONAL + STRAIGHT
    step = rng.choice([s for s in steps if s[1] <= 0])
    back_kind = rng.choice("kkkq")
    back = sq(rng.choice(BLACK_SPOTS[back_kind].split()))
    queen_pinned = back_kind == "k" and kind != "Q" and rng.random() < 0.35
    ray = walk(back, step)
    if len(ray) < 3:
        return None
    d = rng.randint(1, min(3, len(ray) - 2))
    front = ray[d - 1]
    # The pinned piece must not be able to take the pinner along the line.
    front_kind = "q" if queen_pinned else rng.choice("rrn" if step in DIAGONAL else "bn")
    dest = rng.choice(ray[d: min(len(ray), d + 4)])
    if chess.square_rank(dest) > 5 and rng.random() < 0.7:
        return None
    sk = Sketch()
    sk.add(back_kind, back), sk.add(front_kind, front)
    other = [s for st in steps if st != step and st != (-step[0], -step[1]) for s in walk(dest, st, 4)]
    origins = [s for s in other if not between(s, dest) & set(sk.pieces) and s not in sk.pieces]
    if not origins:
        return None
    origin = rng.choice(origins)
    sk.add(kind, origin)
    if not sk.keep(between(back, front) | between(front, dest) | {dest} | between(origin, dest)):
        return None
    if queen_pinned:
        # A pawn guards the pinner, so the queen can only take it and be taken.
        guards = [s for s in chess.SquareSet(chess.BB_PAWN_ATTACKS[B][dest]) if sk.free(s) and chess.square_rank(s) >= 1]
        if not guards or not sk.add("P", rng.choice(guards)):
            return None
    if back_kind != "k":
        home = rng.choice([("g8", "f7 g7 h7"), ("h8", "g7 h7"), ("b8", "a7 b7"), ("g8", "f7 g6 h7")])
        if not sk.add("k", sq(home[0])):
            return None
        for p in home[1].split():
            sk.add("p", sq(p))
    sk.key = [chess.Move(origin, dest)]
    # Black's extra pieces keep away from the pinned piece and the line.
    sk.guard = {dest, front} | between(front, dest)
    sk.test = pin_test
    sk.balance = (0, 2)
    return sk


# MARK: Skewer templates

def skewer_check(rng: random.Random) -> Sketch | None:
    """Check the king; when it steps aside, take the piece behind it."""
    kind = rng.choice(["B", "R", "R", "Q"])
    steps = DIAGONAL if kind == "B" else STRAIGHT if kind == "R" else DIAGONAL + STRAIGHT
    sk = Sketch(endgame=rng.random() < 0.6)
    king = sq(rng.choice(["e6", "d6", "f6", "e7", "d7", "f7", "c6", "g6", "e5", "d5", "c7", "g7", "f5", "b7", "g8", "e8"]))
    step = rng.choice(steps)
    behind = walk(king, step)
    front_side = walk(king, (-step[0], -step[1]))
    if len(behind) < 1 or len(front_side) < 1:
        return None
    t = rng.choice(behind[:4])
    target_kind = rng.choice("rrq" if kind != "Q" else "rrbn")
    x = rng.choice(front_side[:4])
    sk.add("k", king), sk.add(target_kind, t)
    if not sk.keep(between(king, t) | between(x, king) | {x}):
        return None
    other = [s for st in steps if st != step and st != (-step[0], -step[1]) for s in walk(x, st, 5)]
    origins = [s for s in other if s not in sk.pieces and not between(s, x) & set(sk.pieces)]
    if not origins:
        return None
    origin = rng.choice(origins)
    sk.add(kind, origin)
    sk.keep(between(origin, x))
    if near(x, king):
        # Right next to the king the checking piece needs a guard: a pawn, or in endgames the king.
        guards = [("P", s) for s in chess.SquareSet(chess.BB_PAWN_ATTACKS[B][x]) if sk.free(s) and chess.square_rank(s) >= 1]
        if sk.endgame:
            guards += [("K", s) for s in chess.SquareSet(chess.BB_KING_ATTACKS[x]) if sk.free(s)
                       and chess.square_distance(s, king) >= 2]
        if not guards:
            return None
        sk.add(*rng.choice(guards))
    sk.key = [chess.Move(origin, x)]
    sk.guard = {x, t} | between(x, king)
    sk.test = skewer_test
    sk.balance = (-3, 0)
    sk.white_shelter = not sk.endgame
    return sk


def skewer_queen(rng: random.Random) -> Sketch | None:
    """A bishop or rook attacks the queen, and the rook (or loose piece) behind her falls."""
    kind = rng.choice(["B", "R"])
    steps = DIAGONAL if kind == "B" else STRAIGHT
    step = rng.choice([s for s in steps if s[1] <= 0 or kind == "R"])
    queen = sq(rng.choice(BLACK_SPOTS["q"].split()))
    behind = walk(queen, (-step[0], -step[1]))
    front_side = walk(queen, step)
    if not behind or len(front_side) < 2:
        return None
    t = rng.choice(behind[:3])
    x = rng.choice(front_side[1:5])
    sk = Sketch()
    sk.add("q", queen), sk.add(rng.choice("rrb" if kind == "R" else "rrn"), t)
    if not sk.keep(between(queen, t) | between(x, queen) | {x}):
        return None
    other = [s for st in steps if st != step and st != (-step[0], -step[1]) for s in walk(x, st, 4)]
    origins = [s for s in other if s not in sk.pieces and not between(s, x) & set(sk.pieces)]
    if not origins:
        return None
    origin = rng.choice(origins)
    sk.add(kind, origin)
    sk.keep(between(origin, x))
    # The attacker is defended, so the queen can't just take it.
    guards = [s for s in chess.SquareSet(chess.BB_PAWN_ATTACKS[B][x]) if sk.free(s) and chess.square_rank(s) >= 1]
    if not guards:
        return None
    sk.add("P", rng.choice(guards))
    sk.key = [chess.Move(origin, x)]
    sk.guard = {x, t} | between(x, queen)
    sk.test = skewer_test
    sk.balance = (-2, 1)
    return sk


# MARK: Discovered-attack templates

def discovered_check(rng: random.Random) -> Sketch | None:
    """A piece steps off the line to the king (check from behind) and hits the queen,
    or gives check itself as well: double check."""
    kind = rng.choice(["R", "R", "B", "Q"])
    steps = STRAIGHT if kind == "R" else DIAGONAL if kind == "B" else DIAGONAL + STRAIGHT
    sk = Sketch()
    king = sq(rng.choice(["g8", "e8", "h8", "g8", "e8", "f8", "c8", "e7", "g7"]))
    step = rng.choice([s for s in steps if s[1] <= 0 and (s[0] or s[1])])
    ray = walk(king, step)
    if len(ray) < 3:
        return None
    rider = rng.choice(ray[2:6]) if len(ray) > 2 else None
    front = rng.choice(ray[: ray.index(rider)])
    mover = rng.choice("NNBP" if kind == "R" else "NNRP" if kind == "B" else "NNP")
    if mover == "P" and (chess.square_rank(front) in (0, 6, 7) or step[0] == 0):
        return None
    sk.add("k", king), sk.add(kind, rider), sk.add(mover, front)
    sk.keep(between(king, front) | between(front, rider))
    piece = chess.Piece.from_symbol(mover)
    board = sk.board()
    double = rng.random() < 0.25
    choices = []
    for m in board.generate_pseudo_legal_moves(chess.BB_SQUARES[front]):
        if m.to_square in chess.SquareSet(chess.ray(king, rider)) or m.promotion:
            continue
        hits = covers(board, m.to_square, piece)
        if (king in hits) != double:
            continue
        choices.append(m)
    if not choices:
        return None
    move = rng.choice(choices)
    if not double:
        # The piece that steps aside attacks the queen (or takes something).
        hits = [s for s in covers(board, move.to_square, piece) if sk.free(s) and s != king
                and chess.square_rank(s) >= 3 and not near(s, king)]
        if not hits:
            return None
        sk.add("q", rng.choice(hits))
    else:
        sk.add("q", sq(rng.choice(BLACK_SPOTS["q"].split())))
    sk.keep({move.to_square})
    if king in (sq("g8"), sq("h8"), sq("c8")):
        for s in chess.SquareSet(chess.BB_KING_ATTACKS[king]):
            if chess.square_rank(s) == 6 and sk.free(s) and rng.random() < 0.7 and \
                    s not in chess.SquareSet(chess.ray(king, rider)):
                sk.add("p", s)
    sk.key = [move]
    sk.guard = {move.to_square, rider} | between(king, rider)
    sk.loose.add(front)
    sk.test = discovered_check_test
    sk.balance = (-3, 0)
    return sk


def discovered_attack(rng: random.Random) -> Sketch | None:
    """Moving a piece with check (or a capture) opens a line to the queen: Bxh7+ and Rxd8."""
    sk = Sketch()
    kind = rng.choice(["bxh7", "knight", "bishop"])
    if kind == "bxh7":
        sk.put("kg8 ph7 pg7 pf7" + rng.choice([" rf8", " rf8", ""]))
        # The bishop stands on the queen's file and on the b1-h7 diagonal: c2, d3 or e4.
        bishop = sq(rng.choice(["c2", "d3", "d3", "e4"]))
        x = chess.square_file(bishop)
        queen = at(x, rng.choice([7, 6]))
        rider = at(x, rng.randint(0, chess.square_rank(bishop) - 1))
        sk.add("q", queen), sk.add("B", bishop), sk.add(rng.choice("RRQ"), rider)
        if not sk.keep(between(rider, queen) - {bishop} | between(bishop, sq("h7"))):
            return None
        sk.key = [mv(bishop, "h7")]
        sk.guard = between(rider, queen) | {queen}
    else:
        # A knight or bishop jumps off the queen's file or diagonal with check.
        rider_kind = "R" if kind == "knight" else rng.choice(["R", "Q"])
        sk.put("kg8 pf7 pg7 ph7" + rng.choice([" rf8", ""]))
        queen = sq(rng.choice(["d8", "e8", "c8", "d7", "e7", "c7"]))
        rider = at(chess.square_file(queen), rng.randint(0, 1))
        sk.add("q", queen), sk.add(rider_kind, rider)
        line = [s for s in between(rider, queen) if 2 <= chess.square_rank(s) <= 5]
        if not line:
            return None
        front = rng.choice(line)
        mover = "N" if kind == "knight" else "B"
        sk.add(mover, front)
        sk.keep(between(rider, queen) - {front})
        board = sk.board()
        piece = chess.Piece.from_symbol(mover)
        checks = [m for m in board.generate_pseudo_legal_moves(chess.BB_SQUARES[front])
                  if sq("g8") in covers(board, m.to_square, piece) and m.to_square not in between(rider, queen)]
        if not checks:
            return None
        move = rng.choice(checks)
        sk.keep({move.to_square})
        sk.key = [move]
        sk.guard = between(rider, queen) | {queen}
        sk.loose.add(front)
    sk.test = discovered_attack_test
    sk.balance = (-3, 0)
    return sk


def double_check(rng: random.Random) -> Sketch | None:
    """Double check: the piece that steps off the line gives check too, and the
    king, hemmed in by its own men, has one square at most: mate in one or two."""
    kind = rng.choice(["R", "R", "B", "Q"])
    steps = STRAIGHT if kind == "R" else DIAGONAL if kind == "B" else DIAGONAL + STRAIGHT
    king = sq(rng.choice(["g8", "h8", "e8", "c8", "g8", "f8", "b8"]))
    step = rng.choice([s for s in steps if s[1] <= 0])
    ray = walk(king, step)
    if len(ray) < 3:
        return None
    rider = rng.choice(ray[2:6])
    front = rng.choice(ray[: ray.index(rider)])
    mover = rng.choice("NNB" if kind == "R" else "NNR" if kind == "B" else "NN")
    sk = Sketch()
    sk.add("k", king), sk.add(kind, rider), sk.add(mover, front)
    sk.keep(between(king, front) | between(front, rider))
    board = sk.board()
    piece = chess.Piece.from_symbol(mover)
    line = between(king, rider) | {rider}
    choices = [m for m in board.generate_pseudo_legal_moves(chess.BB_SQUARES[front])
               if m.to_square not in line and king in covers(board, m.to_square, piece)
               and not near(m.to_square, king)]
    if not choices:
        return None
    move = rng.choice(choices)
    sk.keep({move.to_square})
    # Black's own pieces box the king in; the checking lines stay open.
    after_move = board.copy(stack=False)
    after_move.push(move)
    covered = after_move.attacks(move.to_square) | after_move.attacks(rider)
    for s in chess.SquareSet(chess.BB_KING_ATTACKS[king]):
        if not sk.free(s) or s in covered or rng.random() < 0.15:
            continue
        if chess.square_rank(s) == 7:
            sk.add("r" if chess.square_file(s) in (0, 7) else rng.choice("rbnrq"), s)  # only rooks in corners
        else:
            sk.add("p" if chess.square_rank(s) == 6 else rng.choice("pbn"), s)
    sk.key = [move]
    sk.guard = {move.to_square} | line | set(chess.SquareSet(chess.BB_KING_ATTACKS[king]))
    sk.loose.add(front)
    sk.test = double_check_test
    sk.balance = (-3, 1)
    return sk


# MARK: Template table

def fork_queen(rng: random.Random) -> Sketch | None:
    return slider_fork(rng, "Q")


def fork_bishop(rng: random.Random) -> Sketch | None:
    return slider_fork(rng, "B")


def fork_rook(rng: random.Random) -> Sketch | None:
    return slider_fork(rng, "R")


# Templates per motif with their share of the motif. The scheduler favours
# templates that have produced fewer puzzles so far, so the mix stays varied.
TEMPLATES: dict[str, list[tuple[Callable[[random.Random], Sketch | None], float]]] = {
    "mate-in-1": [(m1_back_rank, 1), (m1_queen_kiss, 1.2), (m1_rook_box, 1), (m1_two_rooks, 1),
                  (m1_battery_h7, 1), (m1_long_diagonal, 1), (m1_knight_and_queen, 1.2), (m1_smothered, 0.8),
                  (m1_bishop_and_rook, 1.6), (m1_minor_patterns, 1.2), (m1_opening_trap, 0.25)],
    # Opera-style mates (Qb8+ Nxb8 Rd8#) end on the back rank, so they count as back-rank puzzles.
    "back-rank": [(m1_back_rank, 1), (br_battery, 1.4), (br_open, 1), (m2_opera, 0.6)],
    "mate-in-2": [(m2_smothered, 0.6), (m2_anastasia, 0.8), (m2_attack, 2.5), (m2_heavy_endgame, 1)],
    "forks": [(fork_knight, 3), (fork_pawn, 1.2), (fork_queen, 1.2), (fork_bishop, 0.8), (fork_rook, 0.4)],
    "pins": [(pin_slider, 1)],
    "skewers": [(skewer_check, 2.5), (skewer_queen, 0.7)],
    "discovered": [(discovered_check, 2), (discovered_attack, 1.5), (double_check, 0.5)],
}
MATES = {"mate-in-1": {1}, "back-rank": {1, 2}, "mate-in-2": {2}}  # mate lengths each mate motif takes


# MARK: Engine checks

def first_look(eng: Engine, board: chess.Board, key: list[chess.Move], motif: str) -> bool:
    """A cheap search that throws out most failures before the deep one."""
    lines = eng.lines(board, 10, 2)
    if not lines:
        return False
    solver = board.turn
    best = lines[0]
    mate = mate_in(best.score, solver)
    second = mate_in(lines[1].score, solver) if len(lines) > 1 else None
    if motif in MATES:
        return mate in MATES[motif] and (mate == 1 or (second or 99) > mate + 1)
    if mate is not None and motif != "discovered":
        return False
    if key and best.move not in key:
        return False
    if mate is not None:
        return mate <= 2 and (second or 99) > mate + 1
    return win_chances(best.score, solver) >= 0.4 and (len(lines) < 2 or separated(best, lines[1], solver))


def judge(eng: Engine, board: chess.Board, motif: str, key: list[chess.Move] | None = None) -> dict | None:
    """make_puzzle's acceptance rules for a position with no setup move: a deep
    multi-line search, one clearly best move (any mate in one counts), the line
    extended while it stays forced, and material won after the best reply."""
    solver = board.turn
    if board.legal_moves.count() < 3:
        return None
    deep = eng.lines(board, 18, 4)
    if len(deep) < 2:
        return None
    best = deep[0]
    mate = mate_in(best.score, solver)
    if mate is not None:
        if mate > 3:
            return None
        rivals = [line for line in deep[1:] if mate_in(line.score, solver) is not None]
        if mate == 1:
            first_alternatives = [m for m in mating_moves(board) if m != best.move]
        elif any(mate_in(line.score, solver) <= mate + 1 for line in rivals):
            return None  # another move mates just as fast: ambiguous
        else:
            first_alternatives = []
    else:
        wc1 = win_chances(best.score, solver)
        if wc1 < 0.45:
            return None
        close = [line for line in deep[1:] if win_chances(line.score, solver) >= wc1 - 0.06]
        rest = [line for line in deep[1:] if win_chances(line.score, solver) < wc1 - 0.06]
        if len(close) > 2 or not rest or not separated(best, rest[0], solver):
            return None
        first_alternatives = [line.move for line in close]
    found = extend_solution(eng, board, best.move, first_alternatives, solver, mate)
    if not found:
        return None
    line, alternatives = found
    end = board.copy()
    for m in line:
        end.push(m)
    if mate is None:
        settled = end.copy()
        if not settled.is_game_over():
            reply = eng.lines(settled, 14, 1)
            if reply:
                settled.push(reply[0].move)
        gain = balance(settled, solver) - balance(board, solver)
        if gain < 2:
            return None
    else:
        gain = 0
        # The app accepts any mate on the last move, so list every one of them.
        b = board.copy()
        for m in line[:-1]:
            b.push(m)
        alternatives[-1] = [m for m in mating_moves(b) if m != line[-1]]
    tags = tag_puzzle(board, line, solver, mate)
    if motif == "pins" and key and line[0] == key[0] and "pin" not in tags:
        # The template checked the pin; the tagger misses it when the pinned
        # piece (usually the queen) takes the pinner and is taken itself.
        tags = sorted(set(tags) | {"pin"})
    depth = eng.found_depth(board, line[0])
    return {
        "kind": "puzzle",
        "source": "composed",
        "motif": motif,
        "fen": board.fen(),
        "setup": None,
        "solution": [m.uci() for m in line],
        "alternatives": [[m.uci() for m in step] for step in alternatives],
        "mate": mate,
        "tags": tags,
        "gain": gain,
        "foundDepth": depth,
        "pieces": len(board.piece_map()),
        "rating": estimate_rating(board, line, tags, depth),
    }


def is_motif(motif: str, rec: dict, key: list[chess.Move]) -> bool:
    """Whether a verified puzzle teaches the motif it was built for."""
    tags, mate = set(rec["tags"]), rec["mate"]
    if motif == "mate-in-1":
        return mate == 1
    if motif == "back-rank":
        return mate in (1, 2) and "backRankMate" in tags
    if motif == "mate-in-2":
        return mate == 2 and "backRankMate" not in tags
    if key and rec["solution"][0] not in {m.uci() for m in key}:
        return False  # the tactic should be the first move, not something found along the way
    if motif == "discovered":
        return bool(tags & {"discoveredAttack", "discoveredCheck", "doubleCheck"}) and (mate is None or mate <= 2)
    want = {"forks": "fork", "pins": "pin", "skewers": "skewer"}[motif]
    return mate is None and want in tags


# MARK: Picking distinct positions

def symmetric(board: chess.Board, rotations: bool = False) -> list[chess.Board]:
    """The board and its mirror images (colours swapped, left-right). With
    `rotations`, all eight symmetries of a pawnless board instead."""
    if rotations:
        fs = [lambda x: x, chess.flip_vertical, chess.flip_horizontal, chess.flip_diagonal, chess.flip_anti_diagonal,
              lambda x: chess.flip_vertical(chess.flip_horizontal(x)),
              lambda x: chess.flip_vertical(chess.flip_diagonal(x)),
              lambda x: chess.flip_horizontal(chess.flip_diagonal(x))]
        return [board.transform(f) for f in fs]
    out = []
    for b in (board, board.mirror()):
        out += [b, b.transform(chess.flip_horizontal)]
    return out


def placement_key(board: chess.Board, rotations: bool = False) -> str:
    return min(b.board_fen() + (" w" if b.turn else " b") for b in symmetric(board, rotations))


def core_key(rec: dict) -> str:
    """The pieces the solution touches plus the enemy king: two puzzles with the
    same core are near-duplicates even if the filler differs."""
    board = chess.Board(rec["fen"])
    squares = {board.king(not board.turn)}
    for uci in rec["solution"]:
        m = chess.Move.from_uci(uci)
        squares |= {m.from_square, m.to_square}
    core = chess.Board(None)
    for s in squares:
        if board.piece_at(s):
            core.set_piece_at(s, board.piece_at(s))
    core.turn = board.turn
    return placement_key(core)


# MARK: Endgame playouts

FULL = chess.BB_ALL


def around(x: int) -> int:
    """Squares next to the squares of bitboard `x`."""
    e = (x << 1) & ~chess.BB_FILE_A & FULL
    w = (x >> 1) & ~chess.BB_FILE_H
    row = x | e | w
    return (e | w | (row << 8) | (row >> 8)) & FULL


def slides(kind: int, s: chess.Square, occupied: int) -> int:
    a = chess.BB_RANK_ATTACKS[s][occupied & chess.BB_RANK_MASKS[s]] | \
        chess.BB_FILE_ATTACKS[s][occupied & chess.BB_FILE_MASKS[s]]
    if kind == chess.QUEEN:
        a |= chess.BB_DIAG_ATTACKS[s][occupied & chess.BB_DIAG_MASKS[s]]
    return a


def mate_table(kinds: tuple[int, ...], smaller: dict | None = None) -> dict[tuple, bytearray]:
    """Exact moves-to-mate, White to move, for king and `kinds` (rooks or a
    queen) against a lone king, by retrograde analysis.

    One entry per placement of White's pieces, holding a bitmask of the Black
    king squares already known to be lost (Black to move) or won (White to
    move), grown one ply at a time from the mates. `smaller` is the table with
    one piece fewer, for positions where Black captures; without it a capture
    draws. Returns placement -> 64 bytes of moves to mate (0: no forced mate)."""
    placements = [(wk,) + ps for wk in range(64)
                  for ps in itertools.combinations([s for s in range(64) if s != wk], len(kinds))]
    facts = {}
    for p in placements:
        wk, ps = p[0], p[1:]
        occupied = chess.BB_SQUARES[wk]
        for s in ps:
            occupied |= chess.BB_SQUARES[s]
        attacked = chess.BB_KING_ATTACKS[wk]
        for kind, s in zip(kinds, ps):
            attacked |= slides(kind, s, occupied)  # the Black king doesn't block: it can't step along a line
        legal_b = FULL & ~occupied & ~chess.BB_KING_ATTACKS[wk]   # Black king squares, Black to move
        legal_w = legal_b & ~attacked                               # ... and with White to move
        takes = occupied & ~attacked & ~chess.BB_SQUARES[wk]       # pieces the king may capture
        stuck = legal_b & ~around(legal_w | takes)
        facts[p] = (occupied, legal_b, legal_w, takes, stuck & ~attacked, stuck & attacked)
    won = dict.fromkeys(placements, 0)
    lost = {p: facts[p][5] for p in placements}  # checkmated
    dtm = {p: bytearray(64) for p in placements}
    plies = 1
    while True:
        changed = False
        for p in placements:  # White to move: some move reaches a lost position
            occupied, legal_b, legal_w, takes, stalemate, _ = facts[p]
            todo = legal_w & ~won[p]
            if not todo:
                continue
            wk, ps = p[0], p[1:]
            reach = 0
            for k2 in chess.scan_forward(chess.BB_KING_ATTACKS[wk] & ~occupied):
                reach |= lost[(k2,) + ps] & ~(chess.BB_KING_ATTACKS[k2] | chess.BB_SQUARES[k2])
            for i, (kind, s) in enumerate(zip(kinds, ps)):
                for s2 in chess.scan_forward(slides(kind, s, occupied) & ~occupied):
                    child = (wk,) + tuple(sorted(ps[:i] + (s2,) + ps[i + 1:]))
                    reach |= lost[child] & ~(chess.between(s, s2) | chess.BB_SQUARES[s2])
            new = todo & reach
            if new:
                won[p] |= new
                for b in chess.scan_forward(new):
                    dtm[p][b] = (plies + 1) // 2
                changed = True
        for p in placements:  # Black to move: every move reaches a won position
            occupied, legal_b, legal_w, takes, stalemate, _ = facts[p]
            bad = legal_w & ~won[p]
            for i, s in enumerate(p[1:]):
                if (takes >> s) & 1:
                    rest = (p[0],) + tuple(sorted(p[1:i + 1] + p[i + 2:]))
                    m = smaller[rest][s] if smaller else 0
                    if not m or 2 * m - 1 > plies:
                        bad |= chess.BB_SQUARES[s]
            new = legal_b & ~stalemate & ~around(bad) & ~lost[p]
            if new:
                lost[p] |= new
                changed = True
        if not changed:
            return dtm
        plies += 2


PLAYOUT_SPECS = {  # motif: (White's pieces, mate distances, rating for mate in n)
    "queen-mate": ((chess.QUEEN,), (5, 10), lambda n: 600 + 35 * n),
    "ladder-mate": ((chess.ROOK, chess.ROOK), (3, 7), lambda n: 450 + 40 * n),
    "rook-mate": ((chess.ROOK,), (8, 16), lambda n: 750 + 25 * n),
}


def playout_job(job: tuple[str, int, int]) -> tuple[str, list[dict], Counter]:
    """Endgame positions spread evenly over the mate distances, each confirmed
    as a decisive win by the engine (the distance itself comes from the table)."""
    motif, seed, wanted = job
    rng = random.Random(seed)
    kinds, (lo, hi), rating = PLAYOUT_SPECS[motif]
    table = mate_table(kinds, mate_table((chess.ROOK,)) if len(kinds) == 2 else None)
    # A random sample of (placement, Black king) at each distance.
    order = list(table)
    rng.shuffle(order)
    pool: dict[int, list[tuple[tuple, int]]] = {n: [] for n in range(lo, hi + 1)}
    cap = 50 * wanted
    for p in order:
        for bk, n in enumerate(table[p]):
            if lo <= n <= hi and len(pool[n]) < cap:
                pool[n].append((p, bk))
        if all(len(v) >= cap for v in pool.values()):
            break
    stats: Counter = Counter()
    out, seen = [], set()
    distances = [lo + i % (hi - lo + 1) for i in range(wanted)]
    rng.shuffle(distances)
    for n in distances:
        candidates = pool[n]
        rng.shuffle(candidates)
        while candidates:
            p, bk = candidates.pop()
            board = chess.Board(None)
            board.set_piece_at(p[0], chess.Piece(chess.KING, W))
            for kind, s in zip(kinds, p[1:]):
                board.set_piece_at(s, chess.Piece(kind, W))
            board.set_piece_at(bk, chess.Piece(chess.KING, B))
            board.turn = W
            near_pieces = chess.BB_KING_ATTACKS[bk] & board.occupied_co[W]
            if any(not board.attackers(W, s) for s in chess.scan_forward(near_pieces)):
                stats["hanging"] += 1
                continue  # a piece left hanging next to the king
            view = board.copy(stack=False)
            view.turn = B
            if not any(view.generate_legal_moves()):
                stats["boxed"] += 1
                continue  # the king is already boxed in: too close to a stalemate trick
            key = placement_key(board, rotations=True)
            if key in seen:
                continue
            seen.add(key)
            stats["engine"] += 1
            lines = ENGINE.lines(board, 16, 1)
            score = lines[0].score.pov(W) if lines else None
            # Stockfish rates a won K+R vs K at about +4, short of a mate score at this depth.
            if score is None or not (score.is_mate() and score.mate() > 0 or (score.score() or 0) >= 300):
                stats["engine-doubts"] += 1
                continue
            out.append({"kind": "playout", "motif": motif, "fen": board.fen(), "mateIn": n, "rating": rating(n)})
            break
        else:
            stats[f"none-at-{n}"] += 1
    stats["accepted"] = len(out)
    return motif, out, stats


# MARK: Running

ENGINE: Engine | None = None
COMMAND = ""
JOB_SECONDS = 150


def start_engine(command: str) -> None:
    global ENGINE, COMMAND
    COMMAND = command
    ENGINE = Engine(command)


def pick(templates, counts: dict[str, int], rng: random.Random, stats: Counter):
    """A template, favouring the ones that have produced fewer puzzles so far,
    but backing off from one whose candidates keep failing at the engine."""
    weights = []
    for t, w in templates:
        name = t.__name__
        tried, ok = stats[f"{name}:engine"], stats[f"{name}:ok"]
        weights.append(w / (1 + counts.get(name, 0)) * min(1.0, (ok + 2) / (tried / 20 + 1)))
    return rng.choices(templates, weights=weights)[0][0]


def puzzle_job(job: tuple[str, int, int, dict[str, int]]) -> tuple[str, list[tuple[str, dict]], Counter]:
    """Composes and verifies candidates for one motif for a while."""
    global ENGINE
    motif, seed, wanted, counts = job
    rng = random.Random(seed)
    counts = dict(counts)
    found: list[tuple[str, dict]] = []
    stats: Counter = Counter()
    deadline = time.time() + JOB_SECONDS
    while len(found) < wanted and time.time() < deadline:
        template = pick(TEMPLATES[motif], counts, rng, stats)
        name = template.__name__
        stats[f"{name}:tried"] += 1
        candidate = compose(template, rng, motif in MATES)
        if candidate is None:
            continue
        board, key = candidate
        stats[f"{name}:engine"] += 1
        try:
            if not first_look(ENGINE, board, key, motif):
                continue
            stats[f"{name}:deep"] += 1
            rec = judge(ENGINE, board, motif, key)
        except Exception as error:  # a crashed engine shouldn't end the run
            print(f"{motif}: engine error {error}", file=sys.stderr, flush=True)
            ENGINE.close()
            ENGINE = Engine(COMMAND)
            continue
        if rec is None or not is_motif(motif, rec, key):
            continue
        stats[f"{name}:ok"] += 1
        counts[name] = counts.get(name, 0) + 1
        found.append((name, rec))
    return motif, found, stats


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--engine", required=True, help='UCI engine command, e.g. "stockfish"')
    parser.add_argument("--out", required=True, help="JSONL file to write")
    parser.add_argument("--workers", type=int, default=2)
    parser.add_argument("--seed", type=int, default=int(time.time()))
    parser.add_argument("--only", help="comma-separated motifs to make, e.g. forks,pins")
    parser.add_argument("--minutes", type=float, default=240, help="stop starting new work after this long")
    parser.add_argument("--resume", action="store_true",
                        help="keep the records already in --out (say, after a crash) and only make the rest")
    for name, n in {**PUZZLES, **PLAYOUTS}.items():
        parser.add_argument(f"--{name}", type=int, default=n, metavar="N", help=f"how many {name} (default {n})")
    args = parser.parse_args()
    only = set(args.only.split(",")) if args.only else None
    wanted = {m: getattr(args, m.replace("-", "_")) for m in {**PUZZLES, **PLAYOUTS}
              if (only is None or m in only) and getattr(args, m.replace("-", "_")) > 0}

    have: dict[str, list[dict]] = {m: [] for m in wanted}
    by_template: dict[str, Counter] = {m: Counter() for m in wanted}
    seen: set[str] = set()
    cores: set[str] = set()
    totals: Counter = Counter()
    seed = args.seed * 1000
    started = time.time()

    def accept(motif: str, name: str, rec: dict) -> bool:
        key = placement_key(chess.Board(rec["fen"]), rotations=rec["kind"] == "playout")
        core = core_key(rec) if rec["kind"] == "puzzle" else key
        if key in seen or core in cores or len(have[motif]) >= wanted[motif]:
            return False
        seen.add(key)
        cores.add(core)
        have[motif].append(rec)
        by_template[motif][name] += 1
        return True

    carried: list[dict] = []  # resumed records of motifs this run doesn't make; written back untouched
    if args.resume and os.path.exists(args.out):
        with open(args.out) as f:
            for line in f:
                if line.strip():
                    rec = json.loads(line)
                    if rec["motif"] in wanted:
                        accept(rec["motif"], "earlier run", rec)
                    else:
                        carried.append(rec)
        print("resuming with " + ", ".join(f"{m} {len(have[m])}/{wanted[m]}" for m in wanted), flush=True)

    def write_out() -> None:
        # Write a new file and swap it in, so a crash mid-write can't lose what's done.
        with open(args.out + ".tmp", "w") as f:
            for m in wanted:
                for rec in sorted(have[m], key=lambda r: r["rating"]):
                    f.write(json.dumps(rec) + "\n")
            for rec in carried:
                f.write(json.dumps(rec) + "\n")
        os.replace(args.out + ".tmp", args.out)

    with mp.Pool(args.workers, initializer=start_engine, initargs=(args.engine,)) as pool:
        pending = []
        playout_runs: Counter = Counter()

        def start_playouts(motif: str) -> None:
            nonlocal seed
            seed += 1
            playout_runs[motif] += 1
            job = (motif, seed, wanted[motif] - len(have[motif]))
            pending.append((motif, pool.apply_async(playout_job, (job,))))

        for motif in [m for m in wanted if m in PLAYOUTS and len(have[m]) < wanted[m]]:
            start_playouts(motif)
        while True:
            busy = Counter(m for m, _ in pending)
            needs = {m: wanted[m] - len(have[m]) for m in wanted if m in PUZZLES}
            late = time.time() - started > args.minutes * 60
            open_motifs = [m for m, n in needs.items() if n > 0 and busy[m] < max(1, n // 6) and not late]
            while len(pending) < args.workers + 1 and open_motifs:
                motif = max(open_motifs, key=lambda m: needs[m] / (1 + busy[m]))
                seed += 1
                job = (motif, seed, min(needs[motif], 6), dict(by_template[motif]))
                pending.append((motif, pool.apply_async(puzzle_job, (job,))))
                busy[motif] += 1
                open_motifs = [m for m in open_motifs if busy[m] < max(1, needs[m] // 6)]
            if not pending:
                break
            time.sleep(0.5)
            for item in [p for p in pending if p[1].ready()]:
                pending.remove(item)
                motif, found, stats = item[1].get()
                totals.update(stats)
                if motif in PLAYOUTS:
                    for rec in found:
                        accept(motif, motif, rec)
                    if len(have[motif]) < wanted[motif] and playout_runs[motif] < 3:
                        start_playouts(motif)  # duplicates of earlier finds were dropped: top up
                else:
                    for name, rec in found:
                        accept(motif, name, rec)
                done = ", ".join(f"{m} {len(have[m])}/{wanted[m]}" for m in wanted)
                print(f"[{(time.time() - started) / 60:5.1f} min] {done}", flush=True)
                write_out()

    print("\ntemplate          tried  engine   deep     ok")
    names = sorted({k.split(":")[0] for k in totals if ":" in k})
    for name in names:
        print(f"{name:16} {totals[name + ':tried']:6} {totals[name + ':engine']:7} {totals[name + ':deep']:6} "
              f"{totals[name + ':ok']:6}")
    for m in wanted:
        ratings = [r["rating"] for r in have[m]]
        spread = f"{min(ratings)}-{max(ratings)}" if ratings else "-"
        print(f"{m:12} {len(have[m]):3}/{wanted[m]:<3} rating {spread}  {dict(by_template[m])}")
    write_out()
    print(f"wrote {sum(len(v) for v in have.values()) + len(carried)} records to {args.out}")


if __name__ == "__main__":
    main()
