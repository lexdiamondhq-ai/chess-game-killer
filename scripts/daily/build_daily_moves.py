#!/usr/bin/env python3
"""Builds Shared/Daily/daily-moves.csv: Today's Move for every day, the same for every player.

Day 1 is 2026-10-01; the app counts days from there in the player's own calendar
(Shared/Daily/DailyMoves.swift) and starts over at the top once the list runs out.
Like a newspaper puzzle, the week climbs: Monday is the easiest, Sunday the hardest.

Picks come from the bundled Lichess puzzle pack (CC0), so the app can open each one in
the usual puzzle screen. Run from the repository root:

    pip install chess==1.10.0
    python3 scripts/daily/build_daily_moves.py

The output is fixed by the seed: running it again gives the same file, so a day's puzzle
never changes under a player once it has shipped. Only append to the list; never reorder.
"""
import csv
import datetime
import io
import random
import zlib
from pathlib import Path

import chess

ROOT = Path(__file__).resolve().parents[2]
PACK = ROOT / "ChessGameKiller/Puzzles/lichess-puzzles.pack"
OUT = ROOT / "Shared/Daily/daily-moves.csv"

EPOCH = datetime.date(2026, 10, 1)
DAYS = 1100
SEED = 20261001

# Puzzle rating by weekday, Monday first.
BANDS = [(1200, 1400), (1350, 1550), (1500, 1700), (1600, 1800), (1700, 1900), (1800, 2000), (1900, 2150)]

# Ideas a reader recognizes and enjoys; quiet "equality" positions and very long lines stay out.
LIKED = {
    "fork", "pin", "skewer", "sacrifice", "discoveredAttack", "deflection", "attraction",
    "doubleCheck", "backRankMate", "smotheredMate", "hangingPiece", "trappedPiece", "quietMove",
    "mateIn1", "mateIn2", "mateIn3", "clearance", "interference", "xRayAttack", "promotion",
    "underPromotion", "capturingDefender", "intermezzo", "anastasiaMate", "arabianMate",
    "bodenMate", "doubleBishopMate", "dovetailMate", "hookMate",
}
SKIP = {"equality", "veryLong", "long"}


def rows():
    text = zlib.decompress(PACK.read_bytes(), -15).decode()
    reader = csv.reader(io.StringIO(text))
    next(reader)
    for pid, fen, moves, rating, themes in reader:
        yield pid, fen, moves.split(), int(rating), themes.split()


def shown(fen, setup):
    """The position the solver sees: after the opponent's first move."""
    board = chess.Board(fen)
    board.push_uci(setup)
    return board.fen()


def main():
    pools = [[] for _ in BANDS]
    for pid, fen, moves, rating, themes in rows():
        tags = set(themes)
        if tags & SKIP or not tags & LIKED or not 2 <= len(moves) <= 6:
            continue
        for index, (low, high) in enumerate(BANDS):
            if low <= rating < high:
                pools[index].append((pid, fen, moves, rating, themes))
    rng = random.Random(SEED)
    for pool in pools:
        pool.sort()
        rng.shuffle(pool)
    used = set()
    picks = []
    cursor = [0] * len(BANDS)
    for day in range(DAYS):
        band = (EPOCH + datetime.timedelta(days=day)).weekday()
        pool = pools[band]
        while pool[cursor[band]][0] in used:
            cursor[band] += 1
        pick = pool[cursor[band]]
        cursor[band] += 1
        used.add(pick[0])
        picks.append(pick)

    OUT.parent.mkdir(parents=True, exist_ok=True)
    with OUT.open("w", newline="") as f:
        out = csv.writer(f, lineterminator="\n")
        out.writerow(["day", "id", "fen", "moves", "rating", "themes", "shown"])
        for day, (pid, fen, moves, rating, themes) in enumerate(picks, start=1):
            out.writerow([day, pid, fen, " ".join(moves), rating, " ".join(themes), shown(fen, moves[0])])
    print(f"{len(picks)} days written to {OUT.relative_to(ROOT)}; pools {[len(p) for p in pools]}")


if __name__ == "__main__":
    main()
