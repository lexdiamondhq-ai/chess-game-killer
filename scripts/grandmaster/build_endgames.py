#!/usr/bin/env python3
"""Checks every Perfect Endgames study (endgames.py) and writes endgames.json for the app.

Each study is checked with python-chess: a legal position, `side` matching the side to move, no
castling rights, a unique id, and texts short enough for a phone. Then its goal is checked
against the position's true result, by whichever judges are given:

  --syzygy DIR      Syzygy tables on disk (repeatable), for the studies they cover
  --lichess         the Lichess tablebase, for every study with seven pieces or fewer
  --stockfish CMD   a deep Stockfish search, to --depth (30 by default)

A tablebase has the last word, and any judge that disagrees with a goal fails the build.
Stockfish's depth and score are shown for every study. Where no tablebase can answer (more
than seven pieces), Stockfish has to find the win on its own: a mate, or at least +5.00.
Where a tablebase answers, Stockfish landing on the wrong side of the app's offline thresholds
(EngineReferee in EndgameJudge.swift) is only a warning: the offline judge measures each move
against the score before it, so a steady misjudgement does it no harm.

Usage:
  python3 scripts/grandmaster/build_endgames.py [--syzygy DIR] [--lichess]
      [--stockfish "stockfish"] [--depth 30] [--only id,id] [--check]

  --check  fail when the committed endgames.json is out of date, instead of writing it
"""
from __future__ import annotations

import argparse
import json
import os
import re
import shlex
import sys
import time
import urllib.error
import urllib.parse
import urllib.request

import chess
import chess.engine
import chess.syzygy

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
from endgames import STUDIES  # noqa: E402

OUT = os.path.join(HERE, "..", "..", "ChessGameKiller", "GrandmasterRoom", "Content", "endgames.json")
FIELDS = ("id", "title", "group", "level", "fen", "side", "goal", "idea", "tip", "hold")
GROUPS = ("Must know", "Rook endings", "Expert")
TABLEBASE_PIECES = 7
# Lengths that still fit Leo's card and the header on a 375-point-wide phone.
LIMITS = dict(title=25, idea=130, tip=110)
# The app's offline thresholds, in centipawns for the player (EngineReferee).
NOT_WINNING, LOSING = 90, -180
# What Stockfish must show to vouch for a win no tablebase can confirm.
DECISIVE = 500


def problems_with(study: dict, seen: set[str]) -> list[str]:
    """What is wrong with a study's data, as short sentences."""
    missing = [k for k in FIELDS if k != "hold" and k not in study]
    if missing:
        return [f"missing {', '.join(missing)}"]
    problems = []
    if set(study) - set(FIELDS):
        problems.append(f"unknown fields {sorted(set(study) - set(FIELDS))}")
    if not re.fullmatch(r"[a-z0-9]+(-[a-z0-9]+)*", study["id"]):
        problems.append("the id must be lower-case words joined by dashes")
    if study["id"] in seen:
        problems.append("the id is used twice")
    seen.add(study["id"])
    if study["group"] not in GROUPS:
        problems.append(f"group must be one of {GROUPS}")
    if study["level"] not in (1, 2, 3):
        problems.append("level must be 1, 2 or 3")
    if study["goal"] not in ("win", "draw"):
        problems.append("goal must be win or draw")
    if "hold" in study and (study["goal"] != "draw" or not 4 <= study["hold"] <= 30):
        problems.append("hold is for draws, from 4 to 30 moves")
    for field, limit in LIMITS.items():
        if not study[field].strip() or len(study[field]) > limit:
            problems.append(f"{field} must be 1 to {limit} characters (it is {len(study[field])})")
    try:
        board = chess.Board(study["fen"])
    except ValueError as error:
        return problems + [f"bad FEN: {error}"]
    if not board.is_valid():
        problems.append(f"illegal position ({board.status()!r})")
    if board.castling_rights or study["fen"].split()[3] != "-":
        problems.append("no castling or en passant rights: the tablebase can't judge them")
    side = "white" if board.turn == chess.WHITE else "black"
    if study["side"] != side:
        problems.append(f"side says {study['side']} but {side} is to move")
    if board.is_game_over():
        problems.append("the game is already over")
    return problems


def syzygy_says(tables: chess.syzygy.Tablebase, board: chess.Board) -> str | None:
    """The result for the side to move from local Syzygy tables, or None when they don't cover it."""
    try:
        wdl = tables.probe_wdl(board)
    except KeyError:  # MissingTableError
        return None
    return {2: "win", 0: "draw", -2: "loss", 1: "cursed win", -1: "blessed loss"}[wdl]


def lichess_says(fen: str) -> str:
    """The result for the side to move from the Lichess tablebase, gently rate limited."""
    url = "https://tablebase.lichess.ovh/standard?" + urllib.parse.urlencode({"fen": fen})
    request = urllib.request.Request(url, headers={"User-Agent": "chess-game-killer endgame check"})
    for attempt in range(6):
        try:
            with urllib.request.urlopen(request, timeout=30) as response:
                category = json.load(response)["category"]
            time.sleep(1)
            return category.replace("-", " ")
        except urllib.error.HTTPError as error:
            if error.code != 429 or attempt == 5:
                raise
            time.sleep(60)
    raise RuntimeError("unreachable")


def score_text(score: chess.engine.Score) -> str:
    if score.is_mate():
        return f"#{score.mate()}"
    return f"{score.score() / 100:+.2f}"


def stockfish_says(engine: chess.engine.SimpleEngine, board: chess.Board, depth: int) -> tuple:
    """Stockfish's score for the side to move, the depth it reached, and its best move."""
    info = engine.analyse(board, chess.engine.Limit(depth=depth))
    best = board.san(info["pv"][0]) if info.get("pv") else "-"
    return info["score"].pov(board.turn), info.get("depth", 0), best


def stockfish_agrees(goal: str, score: chess.engine.Score, strict: bool) -> bool:
    """Whether Stockfish's score fits the goal: strictly when no tablebase can vouch for it."""
    if score.is_mate():
        return goal == "win" and score.mate() > 0
    cp = score.score()
    if goal == "win":
        return cp >= DECISIVE if strict else cp > NOT_WINNING
    return not strict and LOSING < cp <= NOT_WINNING


def record(study: dict) -> dict:
    return {k: study[k] for k in FIELDS if k in study}


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--syzygy", action="append", default=[], metavar="DIR")
    parser.add_argument("--lichess", action="store_true")
    parser.add_argument("--stockfish", metavar="CMD")
    parser.add_argument("--depth", type=int, default=30)
    parser.add_argument("--only", help="check just these ids (the file is not written)")
    parser.add_argument("--check", action="store_true")
    args = parser.parse_args()

    tables = None
    if args.syzygy:
        tables = chess.syzygy.Tablebase()
        for folder in args.syzygy:
            tables.add_directory(folder)
    engine = None
    if args.stockfish:
        engine = chess.engine.SimpleEngine.popen_uci(shlex.split(args.stockfish))
        options = {"Hash": 256}
        if "Threads" in engine.options:
            options["Threads"] = max(1, min(os.cpu_count() or 1, engine.options["Threads"].max or 1))
        engine.configure(options)
    judged = bool(tables or args.lichess or engine)
    only = set(args.only.split(",")) if args.only else None

    failures, warnings, seen = [], [], set()
    for study in STUDIES:
        problems = problems_with(study, seen)
        if only is not None and study["id"] not in only:
            failures += [f"{study['id']}: {p}" for p in problems]
            continue
        if problems:
            failures += [f"{study['id']}: {p}" for p in problems]
            print(f"{study['id']:16} {'; '.join(problems)}")
            continue
        board = chess.Board(study["fen"])
        pieces = len(board.piece_map())
        goal = study["goal"]
        verdicts, notes = [], []
        if tables is not None:
            said = syzygy_says(tables, board)
            if said:
                verdicts.append(("Syzygy", said))
        if args.lichess and pieces <= TABLEBASE_PIECES:
            verdicts.append(("Lichess", lichess_says(study["fen"])))
        for judge, said in verdicts:
            notes.append(f"{judge} {said}")
            if said != goal:
                failures.append(f"{study['id']}: the goal is {goal}, but {judge} says {said}")
        if engine is not None:
            score, depth, best = stockfish_says(engine, board, args.depth)
            notes.append(f"Stockfish depth {depth} {score_text(score)} ({best})")
            if not stockfish_agrees(goal, score, strict=not verdicts):
                message = f"{study['id']}: the goal is {goal}, but Stockfish gives {score_text(score)}"
                (warnings if verdicts else failures).append(message)
        elif judged and not verdicts:
            failures.append(f"{study['id']}: no judge covers it; pass --stockfish")
        print(f"{study['id']:16} {goal:4} {pieces} pieces   {'   '.join(notes)}", flush=True)
    if engine is not None:
        engine.quit()

    for line in warnings:
        print("warning:", line)
    for line in failures:
        print("FAILED:", line)
    if failures:
        return 1
    if not judged:
        print("Goals not checked: pass --syzygy, --lichess or --stockfish.")
    if only is not None:
        return 0

    text = json.dumps({"endgames": [record(s) for s in STUDIES]}, indent=1, ensure_ascii=False) + "\n"
    if args.check:
        with open(OUT, encoding="utf-8") as f:
            if f.read() != text:
                print("FAILED: endgames.json is out of date; run build_endgames.py")
                return 1
        print(f"endgames.json is up to date ({len(STUDIES)} studies)")
    else:
        with open(OUT, "w", encoding="utf-8") as f:
            f.write(text)
        print(f"Wrote {len(STUDIES)} studies to {os.path.normpath(OUT)}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
