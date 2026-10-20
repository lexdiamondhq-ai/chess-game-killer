#!/usr/bin/env python3
"""Builds the Grandmaster Room's content and checks every move with python-chess.

  classic-games.json  famous games for Guess the Move (from classic_games.py)
  endgames.json       endgame positions for Perfect Endgames (from ENDGAMES below)
  openings.tsv        named openings from lichess-org/chess-openings (CC0), passed
                      as files a.tsv..e.tsv; every line is checked and its UCI added

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

# Seven pieces at most, so the Lichess tablebase knows every position.
ENDGAMES = [
    dict(id="kq-k", title="Queen mate", level=1, fen="8/8/8/4k3/8/8/8/4K2Q w - - 0 1",
         idea="Box the king in with your queen a knight's jump away, bring your king up, then mate on the edge."),
    dict(id="kr-k", title="Rook mate", level=1, fen="8/8/8/4k3/8/8/8/R3K3 w - - 0 1",
         idea="Cut the king off with the rook, walk your king opposite theirs, and push them back one rank at a time."),
    dict(id="kp-k-6th", title="King in front of the pawn", level=1, fen="4k3/8/4K3/4P3/8/8/8/8 w - - 0 1",
         idea="Your king leads, the pawn follows. Take the opposition so their king has to step aside."),
    dict(id="kbb-k", title="Two bishops mate", level=2, fen="8/8/8/4k3/8/8/8/2B1KB2 w - - 0 1",
         idea="Side by side, the bishops make a wall. Shrink the box toward a corner and bring the king."),
    dict(id="kp-k-opposition", title="The opposition", level=2, fen="8/8/8/2k5/8/8/2KP4/8 w - - 0 1",
         idea="Get your king in front of the pawn first. Then win the opposition before pushing."),
    dict(id="lucena", title="Lucena position", level=2, fen="1K1k4/1P6/8/8/8/8/r7/2R5 w - - 0 1",
         idea="Build a bridge: bring your rook to the fourth rank so it can block checks later."),
    dict(id="philidor", title="Philidor defence", level=2, fen="4k3/8/r7/3KP3/8/8/8/7R b - - 0 1",
         idea="Keep your rook on the sixth rank. When the pawn steps up, check from behind."),
    dict(id="kq-kr", title="Queen against rook", level=3, fen="8/8/3k4/8/2r5/8/8/4K2Q w - - 0 1",
         idea="Drive the king and rook to the edge together, then win the rook with a fork or a skewer."),
    dict(id="kbn-k", title="Bishop and knight mate", level=3, fen="8/8/8/4k3/8/8/8/2B1KN2 w - - 0 1",
         idea="Mate only comes in a corner your bishop covers. Use the W-manoeuvre with the knight."),
    dict(id="kr-kb", title="Rook against bishop", level=3, fen="8/8/8/2k5/8/8/1b6/3RK3 b - - 0 1",
         idea="Defend: keep your king in the corner that's the opposite colour of your bishop."),
]


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

    for e in ENDGAMES:
        board = chess.Board(e["fen"])
        assert board.is_valid(), e["id"]
        assert len(board.piece_map()) <= 7, e["id"]
    with open(os.path.join(out, "endgames.json"), "w") as f:
        json.dump({"endgames": ENDGAMES}, f, indent=1)

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
    print(f"{len(games)} games, {len(ENDGAMES)} endgames, {len(rows)} openings")


if __name__ == "__main__":
    main()
