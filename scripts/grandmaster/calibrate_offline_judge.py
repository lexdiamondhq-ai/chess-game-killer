#!/usr/bin/env python3
"""Tunes the offline judge of Perfect Endgames: the thresholds in EngineReferee
(ChessGameKiller/GrandmasterRoom/EndgameJudge.swift) that let Stockfish stand in for the
tablebase when the phone can't reach it.

collect   plays each study the way the app does offline. At every turn of the player, every
          legal move is scored by Stockfish (a bare FEN and a cold hash, like the app, at a node
          budget well below a phone's second of thought) and by Syzygy tables, which know whether
          it really kept the goal. Then a move the tables approve is played, and Stockfish's
          best reply. Rows are written as JSON lines.
evaluate  shows how the scores of sound moves and of slips spread, study by study, and how
          each setting of the thresholds would do: false alarms (sound moves called slips) and
          slips caught. A good setting has no false alarms and catches every slip, with room
          to spare on both sides.

Game over is judged the way the app's ChessKit does: mate, stalemate, too little material, a
third repetition, or fifty moves.

Usage:
  calibrate_offline_judge.py collect --syzygy DIR [--syzygy DIR] --stockfish CMD
      [--nodes 300000] [--lines 2] [--only id,id] OUT.jsonl
  calibrate_offline_judge.py evaluate DATA.jsonl [DATA.jsonl ...]
"""
from __future__ import annotations

import argparse
import json
import math
import os
import random
import shlex
import sys
from collections import defaultdict

import chess
import chess.engine
import chess.syzygy

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from endgames import STUDIES  # noqa: E402

MATE = 100_000
# What the app ships with (EngineReferee), shown first in the evaluation.
APP = dict(not_winning=90, losing=-180, drop=0.2)


# MARK: Collect

def is_over(board: chess.Board) -> bool:
    return (board.is_checkmate() or board.is_stalemate() or board.is_insufficient_material()
            or board.is_repetition(3) or board.halfmove_clock >= 100)


def truth(tables: chess.syzygy.Tablebase, board: chess.Board) -> int:
    """+1, 0 or -1 for the side to move; a cursed win or blessed loss is a draw."""
    if board.is_checkmate():
        return -1
    if is_over(board):
        return 0
    wdl = tables.probe_wdl(chess.Board(board.fen()))
    return 1 if wdl == 2 else -1 if wdl == -2 else 0


def score_of(info: dict, pov: chess.Color) -> dict:
    score = info["score"].pov(pov)
    return {"mate": score.mate()} if score.is_mate() else {"cp": score.score()}


def collect(args: argparse.Namespace) -> None:
    tables = chess.syzygy.Tablebase()
    for folder in args.syzygy:
        tables.add_directory(folder)
    engine = chess.engine.SimpleEngine.popen_uci(shlex.split(args.stockfish))
    engine.configure({"Hash": 64})
    limit = chess.engine.Limit(nodes=args.nodes)
    only = set(args.only.split(",")) if args.only else None
    rng = random.Random(7)

    def analyse(board: chess.Board) -> dict:
        # Like the app: no game history, and a fresh hash for every position.
        return engine.analyse(chess.Board(board.fen()), limit, game=object())

    with open(args.out, "a") as out:
        for study in STUDIES:
            if only is not None and study["id"] not in only:
                continue
            try:
                truth(tables, chess.Board(study["fen"]))
            except KeyError:
                print(study["id"], "skipped: the tables don't cover it", flush=True)
                continue
            goal = 1 if study["goal"] == "win" else 0
            for line in range(args.lines):
                board = chess.Board(study["fen"])
                player = board.turn
                reference = score_of(analyse(board), player)
                for step in range(args.steps):
                    if is_over(board):
                        break
                    rows = []
                    for move in list(board.legal_moves):
                        board.push(move)
                        row = dict(study=study["id"], goal=study["goal"], line=line, step=step, move=move.uci(),
                                   real=-truth(tables, board), reference=reference, terminal=is_over(board),
                                   nodes=args.nodes)
                        if not row["terminal"]:
                            info = analyse(board)
                            row["played"] = score_of(info, player)
                            row["reply"] = info["pv"][0].uci() if info.get("pv") else None
                        board.pop()
                        out.write(json.dumps(row) + "\n")
                        rows.append(row)
                    out.flush()
                    sound = [r for r in rows if r["real"] >= goal and not r["terminal"] and r["reply"]]
                    if not sound:
                        break
                    chosen = rng.choice(sound)
                    board.push(chess.Move.from_uci(chosen["move"]))
                    board.push(chess.Move.from_uci(chosen["reply"]))
                    reference = chosen["played"]
                print(study["id"], "line", line, "done", flush=True)
    engine.quit()


# MARK: Evaluate

def centipawns(score: dict | None) -> int | None:
    """A score in centipawns, with mates as huge values (nearer mates bigger)."""
    if score is None:
        return None
    if "mate" in score:
        return int(math.copysign(MATE - abs(score["mate"]), score["mate"]))
    return score["cp"]


def chances(cp: int) -> float:
    """Lichess's winning chances, from -1 to 1, as Evaluation.winningChances in the app."""
    if abs(cp) >= MATE // 2:
        return math.copysign(1.0, cp)
    cp = max(-1000, min(1000, cp))
    return 2 / (1 + math.exp(-0.00368208 * cp)) - 1


def is_slip(goal: str, played: int, reference: int | None, p: dict) -> bool:
    """EngineReferee.isSlip: scores in centipawns from the player's side."""
    if abs(played) >= MATE // 2:
        return played < 0
    before = chances(reference) if reference is not None else (1.0 if goal == "win" else 0.0)
    fell = before - chances(played) >= p["drop"]
    return fell and played <= (p["not_winning"] if goal == "win" else p["losing"])


def tally(rows: list[dict], p: dict) -> tuple[int, int, int, int, dict]:
    slips = caught = sound = alarms = 0
    missed = defaultdict(int)
    for r in rows:
        flagged = is_slip(r["goal"], centipawns(r["played"]), centipawns(r["reference"]), p)
        if r["real"] < (1 if r["goal"] == "win" else 0):
            slips += 1
            caught += flagged
            missed[r["study"]] += not flagged
        else:
            sound += 1
            alarms += flagged
    return slips, caught, sound, alarms, {k: v for k, v in missed.items() if v}


def show(cp: int) -> str:
    return f"#{int(math.copysign(MATE - abs(cp), cp))}" if abs(cp) >= MATE // 2 else str(cp)


def evaluate(args: argparse.Namespace) -> None:
    rows = []
    for path in args.data:
        with open(path) as f:
            rows += [json.loads(line) for line in f if line.strip()]
    rows = [r for r in rows if not r["terminal"]]
    print(f"{len(rows)} moves")

    spread = defaultdict(lambda: {"sound": [], "slips": []})
    for r in rows:
        kind = "slips" if r["real"] < (1 if r["goal"] == "win" else 0) else "sound"
        spread[(r["goal"], r["study"])][kind].append(centipawns(r["played"]))
    for (goal, study), d in sorted(spread.items()):
        sound, slips = sorted(d["sound"]), sorted(d["slips"])
        print(f"{study:16} {goal:4}  sound moves from {show(sound[0]) if sound else '-':>7}"
              f"   slips up to {show(slips[-1]) if slips else '-':>7}   ({len(sound)} sound, {len(slips)} slips)")
    edges = {}
    for goal in ("win", "draw"):
        sound = sorted(centipawns(r["played"]) for r in rows if r["goal"] == goal and r["real"] >= (goal == "win"))
        slips = sorted(centipawns(r["played"]) for r in rows if r["goal"] == goal and r["real"] < (goal == "win"))
        edges[goal] = (sound[0], slips[-1])
        print(f"{goal}: lowest sound moves {[show(x) for x in sound[:5]]}, highest slips {[show(x) for x in slips[-5:]]}")

    def room(p: dict) -> int:
        """How far, in centipawns, the score thresholds sit from the nearest sound move or slip."""
        (win_sound, win_slip), (draw_sound, draw_slip) = edges["win"], edges["draw"]
        return min(win_sound - p["not_winning"], p["not_winning"] - win_slip,
                   draw_sound - p["losing"], p["losing"] - draw_slip)

    results = []
    for not_winning in (0, 50, 80, 90, 100, 120, 150, 200):
        for losing in (-100, -150, -180, -200, -250, -300):
            for drop in (0.1, 0.15, 0.2, 0.25, 0.3, 0.4):
                p = dict(not_winning=not_winning, losing=losing, drop=drop)
                slips, caught, sound, alarms, missed = tally(rows, p)
                results.append((alarms, slips - caught, -room(p), p, missed))
    results.sort(key=lambda r: r[:3])
    print("\nfalse alarms, slips missed, room (cp), setting")
    app = next(r for r in results if r[3] == APP)
    for alarms, missed_count, negative_room, p, missed in [app] + [r for r in results if r is not app][:15]:
        mark = "  (the app)" if p == APP else ""
        print(f"{alarms:5} {missed_count:5} {-negative_room:5}   not_winning={p['not_winning']} losing={p['losing']}"
              f" drop={p['drop']}{mark} {missed or ''}")


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    commands = parser.add_subparsers(dest="command", required=True)
    c = commands.add_parser("collect")
    c.add_argument("--syzygy", action="append", required=True, metavar="DIR")
    c.add_argument("--stockfish", required=True, metavar="CMD")
    c.add_argument("--nodes", type=int, default=300_000)
    c.add_argument("--lines", type=int, default=2)
    c.add_argument("--steps", type=int, default=14)
    c.add_argument("--only")
    c.add_argument("out")
    e = commands.add_parser("evaluate")
    e.add_argument("data", nargs="+")
    args = parser.parse_args()
    collect(args) if args.command == "collect" else evaluate(args)


if __name__ == "__main__":
    main()
