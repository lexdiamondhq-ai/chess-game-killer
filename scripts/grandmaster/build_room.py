#!/usr/bin/env python3
"""Builds the Grandmaster Room's content and checks every move with python-chess.

  classic-games.json  famous games for Guess the Move (from classic_games.py)
  openings.tsv        named openings from lichess-org/chess-openings (CC0), passed
                      as files a.tsv..e.tsv; every line is checked and its UCI added

The endgame studies are built and checked separately, by build_endgames.py.

Usage:
  python3 scripts/grandmaster/build_room.py ChessGameKiller/GrandmasterRoom/Content a.tsv b.tsv c.tsv d.tsv e.tsv
"""
from __future__ import annotations

import csv
import json
import os
import re
import sys

import chess

sys.path.insert(0, os.path.dirname(__file__))
from classic_games import GAMES  # noqa: E402

def san_line(pgn: str) -> list[str]:
    return [t for t in re.sub(r"\d+\.(\.\.)?", " ", pgn).split() if t not in ("1-0", "0-1", "1/2-1/2", "*")]


def main() -> None:
    out, sources = sys.argv[1], sys.argv[2:]
    os.makedirs(out, exist_ok=True)

    games = []
    for g in GAMES:
        board = chess.Board()
        uci = []
        for san in san_line(g["pgn"]):
            move = board.parse_san(san)
            uci.append(move.uci())
            board.push(move)
        record = {k: g[k] for k in ("id", "white", "black", "event", "year", "result", "blurb")}
        record["moves"] = uci
        games.append(record)
    with open(os.path.join(out, "classic-games.json"), "w") as f:
        json.dump({"games": games}, f, indent=1, ensure_ascii=False)

    rows = []
    for path in sources:
        with open(path, newline="") as f:
            for row in csv.DictReader(f, delimiter="\t"):
                board = chess.Board()
                uci = []
                for san in san_line(row["pgn"]):
                    move = board.parse_san(san)
                    uci.append(move.uci())
                    board.push(move)
                rows.append((row["eco"], row["name"], " ".join(uci)))
    with open(os.path.join(out, "openings.tsv"), "w") as f:
        f.write("eco\tname\tuci\n")
        for eco, name, uci in rows:
            f.write(f"{eco}\t{name}\t{uci}\n")
    print(f"{len(games)} games, {len(rows)} openings")


if __name__ == "__main__":
    main()
