"""Shared helpers for the training content scripts.

Needs python-chess (`pip install chess`) and any UCI Stockfish. On a Mac,
`brew install stockfish` and pass `--engine stockfish`; anywhere with Node,
the WASM build from npm works too: `--engine "node <path>/stockfish-18-single.js"`.
"""
from __future__ import annotations

import math
import shlex
from dataclasses import dataclass

import chess
import chess.engine

# Material values used for counting. The king never gets traded, so it is 0
# for material and 100 when we ask "is this attacker cheaper than its target".
VALUE = {chess.PAWN: 1, chess.KNIGHT: 3, chess.BISHOP: 3, chess.ROOK: 5, chess.QUEEN: 9, chess.KING: 0}
EXCHANGE = {**VALUE, chess.KING: 100}
SLIDERS = (chess.BISHOP, chess.ROOK, chess.QUEEN)
NAMES = {chess.PAWN: "pawn", chess.KNIGHT: "knight", chess.BISHOP: "bishop",
         chess.ROOK: "rook", chess.QUEEN: "queen", chess.KING: "king"}


def win_chances(score: chess.engine.PovScore, pov: chess.Color) -> float:
    """Chance of winning from -1 to 1, the same curve the app and Lichess use."""
    s = score.pov(pov)
    if s.is_mate():
        return 1.0 if s > chess.engine.Cp(0) else -1.0
    cp = max(-1000, min(1000, s.score()))
    return 2 / (1 + math.exp(-0.00368208 * cp)) - 1


def mate_in(score: chess.engine.PovScore, pov: chess.Color) -> int | None:
    """Moves to a forced mate for `pov`, or None when there is no mate for it."""
    s = score.pov(pov)
    if s.is_mate() and s > chess.engine.Cp(0):
        return s.mate()
    return None


def material(board: chess.Board, color: chess.Color) -> int:
    return sum(VALUE[p.piece_type] for p in board.piece_map().values() if p.color == color)


def balance(board: chess.Board, pov: chess.Color) -> int:
    return material(board, pov) - material(board, not pov)


def flipped(board: chess.Board) -> chess.Board | None:
    """The same position with the other side to move, or None if that is illegal
    (the side that would be waiting is in check)."""
    b = board.copy(stack=False)
    b.turn = not b.turn
    b.ep_square = None
    return b if b.is_valid() else None


def capture_move(board: chess.Board, frm: chess.Square, to: chess.Square) -> chess.Move:
    piece = board.piece_at(frm)
    promo = None
    if piece and piece.piece_type == chess.PAWN and chess.square_rank(to) in (0, 7):
        promo = chess.QUEEN
    return chess.Move(frm, to, promotion=promo)


def in_danger(board: chess.Board, color: chess.Color, sq: chess.Square) -> bool:
    """Whether the piece of `color` on `sq` could be won right away: attacked and
    undefended, or attacked by something cheaper. Checks the capture is legal."""
    piece = board.piece_at(sq)
    if not piece or piece.color != color or piece.piece_type == chess.KING:
        return False
    attackers = board.attackers(not color, sq)
    if not attackers:
        return False
    view = board if board.turn != color else flipped(board)
    if view is None:
        return False
    legal = [a for a in attackers if view.is_legal(capture_move(view, a, sq))]
    if not legal:
        return False
    if not board.attackers(color, sq):
        return True
    cheapest = min(EXCHANGE[board.piece_at(a).piece_type] for a in legal)
    return cheapest < VALUE[piece.piece_type]


def danger_squares(board: chess.Board, color: chess.Color) -> set[chess.Square]:
    return {sq for sq, p in board.piece_map().items() if p.color == color and in_danger(board, color, sq)}


@dataclass
class Line:
    score: chess.engine.PovScore
    pv: list[chess.Move]

    @property
    def move(self) -> chess.Move:
        return self.pv[0]


class Engine:
    """A UCI engine with the two things the scripts need: analysis and weak play."""

    def __init__(self, command: str, hash_mb: int = 64):
        self.engine = chess.engine.SimpleEngine.popen_uci(shlex.split(command))
        self.engine.configure({"Hash": hash_mb})
        self.skill = 20

    def _set_skill(self, skill: int) -> None:
        if skill != self.skill:
            self.engine.configure({"Skill Level": skill})
            self.skill = skill

    def lines(self, board: chess.Board, depth: int, multipv: int = 1) -> list[Line]:
        self._set_skill(20)
        infos = self.engine.analyse(board, chess.engine.Limit(depth=depth), multipv=multipv)
        out = []
        for info in infos:
            pv, score = info.get("pv"), info.get("score")
            if pv and score is not None:
                out.append(Line(score, list(pv)))
        return out

    def play(self, board: chess.Board, skill: int, seconds: float) -> chess.Move:
        self._set_skill(skill)
        return self.engine.play(board, chess.engine.Limit(time=seconds)).move

    def found_depth(self, board: chess.Board, move: chess.Move, max_depth: int = 10) -> int:
        """The shallowest search that already picks `move`: a rough measure of how
        hard the move is to see."""
        for depth in range(1, max_depth + 1):
            line = self.lines(board, depth, 1)
            if line and line[0].move == move:
                return depth
        return max_depth + 1

    def close(self) -> None:
        try:
            self.engine.quit()
        except Exception:
            pass


def describe_square(board: chess.Board, sq: chess.Square) -> str:
    p = board.piece_at(sq)
    return f"{NAMES[p.piece_type]} on {chess.square_name(sq)}" if p else chess.square_name(sq)
