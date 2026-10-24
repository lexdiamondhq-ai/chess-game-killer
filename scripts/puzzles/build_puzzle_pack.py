#!/usr/bin/env python3
"""Builds the app's puzzle pack from the Lichess puzzle database.

The Lichess database (https://database.lichess.org/#puzzles) is released under
CC0, so it can ship in the app. It holds millions of puzzles taken from real
games. This keeps a well-loved, well-rated slice of it: for every theme in the
app's theme picker and every 100 points of rating from 400 up, the most
popular puzzles that many people have played. About 100,000 in all.

Input: the CSV, plain or .zst, from a path or "-" for stdin. Columns:
  PuzzleId,FEN,Moves,Rating,RatingDeviation,Popularity,NbPlays,Themes,GameUrl,OpeningTags
The FEN is the position before the opponent's move; Moves starts with that
move and then alternates solution and reply, in UCI.

Output: one line per puzzle, "id,fen,moves,rating,themes", themes cut down to
the ones the picker knows. An output path ending in .pack is written as raw
DEFLATE (what Apple's NSData calls .zlib), which keeps the app about 60% smaller.

Usage:
  curl -sL https://database.lichess.org/lichess_db_puzzle.csv.zst | zstd -dc \
    | python3 scripts/puzzles/build_puzzle_pack.py - ChessGameKiller/Puzzles/lichess-puzzles.pack
"""
from __future__ import annotations

import csv
import sys
import zlib
from collections import defaultdict

# Keep in step with PuzzleTheme in ChessGameKiller/Puzzles/PuzzleLibrary.swift.
THEMES = [
    "mateIn1", "mateIn2", "mateIn3", "mateIn4", "mateIn5",
    "fork", "pin", "skewer", "discoveredAttack", "doubleCheck",
    "sacrifice", "deflection", "attraction", "clearance", "interference",
    "intermezzo", "xRayAttack", "zugzwang", "quietMove", "defensiveMove",
    "backRankMate", "smotheredMate", "hangingPiece", "trappedPiece",
    "promotion", "advancedPawn", "kingsideAttack", "queensideAttack",
    "opening", "middlegame", "endgame", "rookEndgame", "pawnEndgame",
    "bishopEndgame", "knightEndgame", "queenEndgame", "veryLong",
    # Added with the bigger pack.
    "anastasiaMate", "arabianMate", "hookMate", "bodenMate", "doubleBishopMate",
    "dovetailMate", "capturingDefender", "exposedKing", "attackingF2F7",
    "enPassant", "castling", "underPromotion", "equality", "masterVsMaster",
]
KNOWN = set(THEMES)
PER_BUCKET = 180
MIN_RATING, MAX_RATING, STEP = 400, 3100, 100
# Rare themes (castling, en passant...) are topped up from less-played puzzles to this many.
RARE_FLOOR = 300


def main() -> None:
    source, out = sys.argv[1], sys.argv[2]
    stream = sys.stdin if source == "-" else open(source, newline="")
    reader = csv.reader(stream)
    header = next(reader)
    assert header[0] == "PuzzleId", header

    # (theme, bucket) -> list of (score, id, row)
    buckets: dict[tuple[str, int], list[tuple[int, int, str, tuple]]] = defaultdict(list)
    # theme -> fairly good puzzles that missed the strict bar, for themes that come out thin
    spare: dict[str, list[tuple[int, int, str, tuple]]] = defaultdict(list)
    seen = 0
    for row in reader:
        seen += 1
        pid, fen, moves, rating, deviation, popularity, plays, themes = row[:8]
        rating, deviation, popularity, plays = int(rating), int(deviation), int(popularity), int(plays)
        if popularity < 50 or plays < 80 or deviation > 100:
            continue
        kept = [t for t in themes.split() if t in KNOWN]
        if not kept:
            continue
        if popularity < 80 or plays < 300 or deviation > 85:
            record = (pid, fen, moves, rating, " ".join(kept))
            for theme in kept:
                items = spare[theme]
                items.append((popularity, plays, pid, record))
                if len(items) > RARE_FLOOR * 8:
                    items.sort(key=lambda x: (-x[0], -x[1], x[2]))
                    del items[RARE_FLOOR:]
            continue
        bucket = max(MIN_RATING, min(MAX_RATING, rating)) // STEP
        record = (pid, fen, moves, rating, " ".join(kept))
        for theme in kept:
            items = buckets[(theme, bucket)]
            items.append((popularity, plays, pid, record))
            # Trim now and then so memory stays small on the full database.
            if len(items) > PER_BUCKET * 8:
                items.sort(key=lambda x: (-x[0], -x[1], x[2]))
                del items[PER_BUCKET:]

    chosen: dict[str, tuple] = {}
    for items in buckets.values():
        items.sort(key=lambda x: (-x[0], -x[1], x[2]))
        for _, _, pid, record in items[:PER_BUCKET]:
            chosen[pid] = record

    counts = {t: 0 for t in THEMES}
    for record in chosen.values():
        for t in record[4].split():
            counts[t] += 1
    for theme in THEMES:
        items = sorted(spare[theme], key=lambda x: (-x[0], -x[1], x[2]))
        for _, _, pid, record in items:
            if counts[theme] >= RARE_FLOOR:
                break
            if pid not in chosen:
                chosen[pid] = record
                counts[theme] += 1
    for theme in THEMES:
        print(f"  {theme}: {counts[theme]}", file=sys.stderr)

    lines = ["id,fen,moves,rating,themes"]
    for record in sorted(chosen.values(), key=lambda r: (r[3], r[0])):
        lines.append(",".join(str(x) for x in record))
    data = ("\n".join(lines) + "\n").encode()
    if out.endswith(".pack"):
        packer = zlib.compressobj(9, zlib.DEFLATED, -15)
        data = packer.compress(data) + packer.flush()
    with open(out, "wb") as f:
        f.write(data)
    print(f"Read {seen} puzzles, kept {len(chosen)}.", file=sys.stderr)


if __name__ == "__main__":
    main()
