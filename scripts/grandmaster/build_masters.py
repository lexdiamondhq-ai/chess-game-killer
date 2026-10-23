#!/usr/bin/env python3
"""Builds the opening statistics and master games from the Lichess databases (CC0).

Two modes, each reading PGN on stdin:

  masters  Lichess broadcast games (top over-the-board events, https://database.lichess.org/#broadcasts).
           Writes masters-stats.tsv (how players rated 2500+ continue in every named
           opening position) and masters-games.json (recent decisive master games for
           Guess the Move and each opening's model games).
  club     Lichess rated games (https://database.lichess.org/#standard_games), the first
           --limit games of a month. Writes club-stats.tsv: the same statistics, split
           into five rating bands, so the app can show what players at your level play.

Statistics are only kept for positions on the named lines in openings.tsv (and the move
played from them), which is what the Openings door shows. That keeps the files small and
means no game has to be replayed move by move: the walk follows the named-opening tree
by notation and stops when a game leaves it.

Stats line: key<TAB>book<TAB>moves, where key is the piece placement and side to move
(TrainingChess.key in the app), book is "m" (masters) or a band 0-4, and moves is
"uci games whiteWins draws" joined by ",", most played first.

Usage:
  ... | python3 scripts/grandmaster/build_masters.py masters OUT_DIR
  ... | python3 scripts/grandmaster/build_masters.py club OUT_DIR --limit 4000000
"""
from __future__ import annotations

import argparse
import hashlib
import json
import os
import re
import sys
from collections import defaultdict

import chess

# Keep in step with OpeningStats.Band in ChessGameKiller/GrandmasterRoom/OpeningStats.swift.
BAND_FLOORS = [0, 1200, 1500, 1800, 2100]
MAX_PLY = 30
MASTER_ELO = 2500
GAME_ELO = 2550
MAX_GAMES = 1500
PER_OPENING = 6
SKIP_EVENTS = re.compile(r"blitz|bullet|rapid|armageddon|960|freestyle|fischer|blind|simul|speed|titled|bughouse|"
                         r"puzzle|online|chess\.com|lichess", re.I)

COMMENT = re.compile(r"\{[^}]*\}")
VARIATION = re.compile(r"\([^()]*\)")
NOISE = re.compile(r"\$\d+|\d+\.(\.\.)?|1-0|0-1|1/2-1/2|\*")
HEADER = re.compile(r'^\[(\w+)\s+"(.*)"\]\s*$')


def clean(san: str) -> str:
    return san.rstrip("+#!?")


class Node:
    __slots__ = ("key", "fen", "name", "eco", "children", "stats")

    def __init__(self, board: chess.Board):
        self.fen = board.fen()
        self.key = " ".join(self.fen.split()[:2])
        self.name: str | None = None
        self.eco: str | None = None
        self.children: dict[str, Node] = {}
        # book -> san -> [games, white wins, draws]
        self.stats: dict[str, dict[str, list[int]]] = defaultdict(lambda: defaultdict(lambda: [0, 0, 0]))


def opening_tree(path: str) -> Node:
    """Every named line from openings.tsv as a tree, keyed by notation."""
    root = Node(chess.Board())
    with open(path) as f:
        next(f)
        for line in f:
            eco, name, uci = line.rstrip("\n").split("\t")
            board = chess.Board()
            node = root
            for move in uci.split():
                m = chess.Move.from_uci(move)
                san = clean(board.san(m))
                board.push(m)
                child = node.children.get(san)
                if child is None:
                    child = node.children[san] = Node(board)
                node = child
            node.name, node.eco = name, eco
    return root


def games(stream):
    """(headers, movetext) for each game, without replaying anything."""
    headers: dict[str, str] = {}
    moves: list[str] = []
    for line in stream:
        if line.startswith("["):
            if moves:
                yield headers, " ".join(moves)
                headers, moves = {}, []
            m = HEADER.match(line)
            if m:
                headers[m.group(1)] = m.group(2)
        elif line.strip():
            moves.append(line.strip())
    if moves:
        yield headers, " ".join(moves)


def tokens(movetext: str, limit: int | None) -> list[str]:
    text = COMMENT.sub(" ", movetext if limit is None else movetext[:4000])
    while True:
        stripped = VARIATION.sub(" ", text)
        if stripped == text:
            break
        text = stripped
    out = [t for t in NOISE.sub(" ", text).split() if t]
    return out if limit is None else out[:limit]


def walk(root: Node, sans: list[str], book: str, result: str) -> Node | None:
    """Counts each move played from a position on the tree. Returns the deepest named node."""
    node, named = root, None
    win = 1 if result == "1-0" else 0
    draw = 1 if result == "1/2-1/2" else 0
    for san in sans[:MAX_PLY]:
        san = clean(san)
        cell = node.stats[book][san]
        cell[0] += 1
        cell[1] += win
        cell[2] += draw
        child = node.children.get(san)
        if child is None:
            break
        node = child
        if node.name:
            named = node
    return named


def write_stats(root: Node, path: str, min_games: int) -> int:
    # Positions reached by different move orders share one key: add them up.
    merged: dict[tuple[str, str], dict[str, list[int]]] = defaultdict(lambda: defaultdict(lambda: [0, 0, 0]))
    fens: dict[str, str] = {}
    stack = [root]
    while stack:
        node = stack.pop()
        stack.extend(node.children.values())
        fens.setdefault(node.key, node.fen)
        for book, moves in node.stats.items():
            for san, (n, w, d) in moves.items():
                cell = merged[(node.key, book)][san]
                cell[0] += n
                cell[1] += w
                cell[2] += d
    rows = []
    for (key, book), moves in merged.items():
        total = sum(c[0] for c in moves.values())
        if total < min_games:
            continue
        board = chess.Board(fens[key])
        kept = []
        for san, (n, w, d) in sorted(moves.items(), key=lambda kv: -kv[1][0]):
            if len(kept) == 6 or n < max(2, total * 0.02):
                break
            try:
                uci = board.parse_san(san).uci()
            except ValueError:
                continue
            kept.append(f"{uci} {n} {w} {d}")
        if kept:
            rows.append(f"{key}\t{book}\t{','.join(kept)}")
    rows.sort()
    with open(path, "w") as f:
        f.write("key\tbook\tmoves\n")
        f.write("\n".join(rows) + "\n")
    return len(rows)


def elo(headers: dict[str, str], side: str) -> int:
    try:
        return int(headers.get(f"{side}Elo", "0"))
    except ValueError:
        return 0


def person(name: str) -> str:
    """"Carlsen, Magnus" -> "Magnus Carlsen"."""
    if "," in name:
        last, first = name.split(",", 1)
        return f"{first.strip()} {last.strip()}".strip()
    return name.strip()


def is_standard(headers: dict[str, str]) -> bool:
    return (headers.get("Variant", "Standard").lower() in ("standard", "")
            and "FEN" not in headers and headers.get("SetUp", "0") != "1")


def masters(root: Node, out: str) -> None:
    seen = used = 0
    candidates = []
    for headers, movetext in games(sys.stdin):
        seen += 1
        result = headers.get("Result", "*")
        if result == "*" or not is_standard(headers):
            continue
        we, be = elo(headers, "White"), elo(headers, "Black")
        if min(we, be) < MASTER_ELO:
            continue
        used += 1
        sans = tokens(movetext, None)
        named = walk(root, sans, "m", result)
        event = headers.get("Event", "")
        if (result != "1/2-1/2" and min(we, be) >= GAME_ELO and 50 <= len(sans) <= 150
                and not SKIP_EVENTS.search(event) and not SKIP_EVENTS.search(headers.get("TimeControl", ""))):
            candidates.append((headers, sans, named))
    print(f"Read {seen} broadcast games, {used} between players rated {MASTER_ELO}+, "
          f"{len(candidates)} candidates for Guess the Move.", file=sys.stderr)

    rows = write_stats(root, os.path.join(out, "masters-stats.tsv"), min_games=8)
    print(f"masters-stats.tsv: {rows} positions", file=sys.stderr)

    # Best-rated, newest first; a few per opening so every family has examples.
    candidates.sort(key=lambda c: (-(elo(c[0], "White") + elo(c[0], "Black")), c[0].get("Date", "")), reverse=False)
    picked, per_opening, keys = [], defaultdict(int), set()
    for headers, sans, named in candidates:
        if len(picked) >= MAX_GAMES:
            break
        opening = named.name if named else None
        family = opening.split(":")[0] if opening else "Other"
        white, black = person(headers.get("White", "?")), person(headers.get("Black", "?"))
        dedupe = (white, black, headers.get("Event", ""), headers.get("Round", ""))
        if dedupe in keys or per_opening[family] >= PER_OPENING:
            continue
        board = chess.Board()
        uci = []
        try:
            for san in sans:
                move = board.parse_san(san)
                uci.append(move.uci())
                board.push(move)
        except ValueError:
            continue
        keys.add(dedupe)
        per_opening[family] += 1
        date = headers.get("Date", "????")
        year = int(date[:4]) if date[:4].isdigit() else 0
        result = headers["Result"]
        winner = white if result == "1-0" else black
        event = headers.get("Event", "").strip() or "Over the board"
        moves_count = (len(uci) + 1) // 2
        blurb = f"{winner} won in {moves_count} moves" + (f", from the {opening}." if opening else ".")
        gid = "m-" + hashlib.sha1(f"{white}|{black}|{event}|{headers.get('Round', '')}|{date}".encode()).hexdigest()[:10]
        picked.append({
            "id": gid, "white": white, "black": black, "event": event, "year": year, "result": result,
            "blurb": blurb, "opening": opening, "whiteElo": elo(headers, "White"), "blackElo": elo(headers, "Black"),
            "date": date.replace("?", "").strip(".") or None, "moves": " ".join(uci),
        })
    picked.sort(key=lambda g: (g["date"] or "", g["id"]), reverse=True)
    with open(os.path.join(out, "masters-games.json"), "w") as f:
        json.dump({"games": picked}, f, separators=(",", ":"), ensure_ascii=False)
    print(f"masters-games.json: {len(picked)} games across {len(per_opening)} openings", file=sys.stderr)


def club(root: Node, out: str, limit: int) -> None:
    seen = used = 0
    for headers, movetext in games(sys.stdin):
        seen += 1
        if seen > limit:
            break
        event = headers.get("Event", "")
        result = headers.get("Result", "*")
        if not event.startswith("Rated") or "Bullet" in event or result == "*" or not is_standard(headers):
            continue
        we, be = elo(headers, "White"), elo(headers, "Black")
        if not we or not be:
            continue
        average = (we + be) // 2
        band = max(i for i, floor in enumerate(BAND_FLOORS) if average >= floor)
        used += 1
        walk(root, tokens(movetext, MAX_PLY), str(band), result)
    print(f"Read {min(seen, limit)} rated games, used {used}.", file=sys.stderr)
    rows = write_stats(root, os.path.join(out, "club-stats.tsv"), min_games=40)
    print(f"club-stats.tsv: {rows} position rows", file=sys.stderr)


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("mode", choices=["masters", "club"])
    parser.add_argument("out")
    parser.add_argument("--openings", default="ChessGameKiller/GrandmasterRoom/Content/openings.tsv")
    parser.add_argument("--limit", type=int, default=4_000_000)
    args = parser.parse_args()
    os.makedirs(args.out, exist_ok=True)
    root = opening_tree(args.openings)
    if args.mode == "masters":
        masters(root, args.out)
    else:
        club(root, args.out, args.limit)


if __name__ == "__main__":
    main()
