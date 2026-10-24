#!/usr/bin/env python3
"""Indexes every named opening by the position it ends in, so the app can name the
opening a player's game reached (even by another move order) without replaying
thousands of lines on the phone.

  opening-positions.tsv   key<TAB>line, where key is the piece placement and side to
                          move (as TrainingChess.key writes it) and line is the row of
                          the opening in openings.tsv (0 is the first line after the
                          header). When two lines end in the same position the shorter,
                          then the earlier, wins.

Run again whenever openings.tsv changes; OpeningIndexTests checks the two agree.

Usage:
  python3 scripts/grandmaster/build_opening_positions.py ChessGameKiller/GrandmasterRoom/Content
"""
from __future__ import annotations

import os
import sys

import chess


def main() -> None:
    folder = sys.argv[1]
    with open(os.path.join(folder, "openings.tsv"), encoding="utf-8") as f:
        rows = f.read().split("\n")[1:]
    best: dict[str, tuple[int, int]] = {}
    index = -1
    for row in rows:
        fields = row.split("\t")
        if len(fields) < 3 or not fields[2].strip():
            continue
        index += 1
        board = chess.Board()
        moves = fields[2].split()
        for uci in moves:
            board.push(chess.Move.from_uci(uci))
        key = board.board_fen() + " " + ("w" if board.turn else "b")
        ranked = (len(moves), index)
        if key not in best or ranked < best[key]:
            best[key] = ranked
    out = os.path.join(folder, "opening-positions.tsv")
    with open(out, "w", encoding="utf-8") as f:
        f.write("key\tline\n")
        for key, (_, line) in sorted(best.items(), key=lambda item: item[1][1]):
            f.write(f"{key}\t{line}\n")
    print(f"{len(best)} positions from {index + 1} lines -> {out}")


if __name__ == "__main__":
    main()
