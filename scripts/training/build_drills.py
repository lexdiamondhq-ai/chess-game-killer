#!/usr/bin/env python3
"""Builds ChessGameKiller/Training/Content/drills.json, the practice items.

Sources:
  * positions mined from engine games by mine_puzzles.py (threats, safe moves,
    good captures, free pieces and whatever tactics the games produced),
  * pattern puzzles and endgame playouts from compose_puzzles.py,
  * the opening-rules drills written below.

It keeps a balanced, varied set for every skill: answers split about evenly
between yes and no, at most a couple of positions from any one game, no
repeated positions, and a spread of difficulty from easy to hard.

    python3 scripts/training/build_drills.py --mined mined.jsonl --composed composed.jsonl \\
        --engine "node stockfish-18-single.js"
"""
from __future__ import annotations

import argparse
import json
import random
import re
import sys
from collections import Counter, defaultdict
from pathlib import Path

import chess

sys.path.insert(0, str(Path(__file__).resolve().parent))
from chesslib import EXCHANGE, NAMES, Engine, win_chances  # noqa: E402

ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT / "ChessGameKiller" / "Training" / "Content" / "drills.json"

# How many drills each skill gets, at most.
TARGETS = {
    "counting": 180, "threats": 220, "safety": 220, "free-pieces": 220,
    "mate-in-1": 120, "back-rank": 80, "mate-in-2": 90,
    "forks": 110, "pins": 80, "skewers": 70, "discovered": 70,
    "queen-mate": 30, "ladder-mate": 30, "rook-mate": 20,
}
PER_GAME = 2

# Which skill a mined or composed puzzle trains, by its tags, most specific first.
TAG_SKILLS = [
    ("backRankMate", "back-rank"), ("smotheredMate", "mate-in-2"),
    ("mateIn1", "mate-in-1"), ("mateIn2", "mate-in-2"),
    ("fork", "forks"), ("skewer", "skewers"), ("pin", "pins"),
    ("discoveredCheck", "discovered"), ("discoveredAttack", "discovered"), ("doubleCheck", "discovered"),
    ("hangingPiece", "free-pieces"), ("tradeUp", "free-pieces"),
]
MOTIF_SKILLS = {"mate-in-1": "mate-in-1", "back-rank": "back-rank", "mate-in-2": "mate-in-2", "forks": "forks",
                "pins": "pins", "skewers": "skewers", "discovered": "discovered"}
PLAYOUT_LIMITS = {"queen-mate": 4, "ladder-mate": 3, "rook-mate": 6}

# MARK: Opening rules
#
# Each: moves so far, then (move, right?, why). The right move follows the
# opening rules and is one of the engine's best; the wrong ones break a rule
# and the engine agrees they're worse.

OPENINGS = [
    ("", [("e4", True, "A center pawn, two squares. It grabs the middle and frees your queen and bishop."),
          ("a4", False, "Edge pawns don't fight for the center. Start in the middle."),
          ("Nh3", False, "A knight on the edge reaches fewer squares. Knights belong near the center.")], 400),
    ("e4", [("e5", True, "Meet the center with the center. Your pawn takes its share of the middle."),
            ("h5", False, "Edge pawns don't help in the opening. Fight for the center."),
            ("Na6", False, "A knight on the edge reaches fewer squares. Knights belong near the center.")], 420),
    ("e4 e5", [("Nf3", True, "It develops a knight and attacks the e5 pawn. A great opening move."),
               ("Qh5", False, "Out this early, the queen gets chased around while Black develops."),
               ("f3", False, "It takes your knight's best square and weakens your king.")], 460),
    ("e4 e5 Nf3", [("Nc6", True, "It develops a knight and guards the e5 pawn. Two jobs, one move."),
                   ("f6", False, "It guards e5, but it weakens your king and takes your knight's best square."),
                   ("Qe7", False, "The queen guards e5, but she blocks your bishop. Use a knight.")], 480),
    ("e4 e5 Nf3 Nc6", [("Bb5", True, "It develops a bishop and puts pressure on the knight that guards e5."),
                       ("Ng5", False, "Same piece twice, and it attacks nothing guarded. Bring out a new piece."),
                       ("Qe2", False, "Too early for the queen, and she blocks your bishop.")], 520),
    ("e4 e5 Nf3 Nc6 Bc4", [("Nf6", True, "It develops a knight and attacks the e4 pawn."),
                           ("Qf6", False, "Too early for the queen, and she takes your knight's best square."),
                           ("h6", False, "A pawn move that doesn't develop anything. Bring out a piece.")], 540),
    ("e4 e5 Nf3 Nc6 Bc4 Bc5", [("O-O", True, "Castle early: your king gets safe and your rook joins the game."),
                               ("Kf1", False, "Walking the king gives up castling. Castle instead."),
                               ("Bxf7+", False, "That gives a bishop for a pawn. Count it: 3 for 1.")], 560),
    ("d4", [("d5", True, "Meet the center with the center. Your pawn takes its share of the middle."),
            ("g5", False, "That pawn is simply taken by the bishop on c1, and your king gets weaker."),
            ("Nh6", False, "A knight on the edge reaches fewer squares. Knights belong near the center.")], 420),
    ("d4 d5", [("Nf3", True, "It develops a knight and controls the center."),
               ("Nh3", False, "A knight on the edge reaches fewer squares. f3 is a much better home."),
               ("Qd3", False, "Too early for the queen, and she blocks your bishop.")], 460),
    ("d4 d5 c4", [("e6", True, "It guards d5 and opens a path for your bishop."),
                  ("Qd6", False, "Too early for the queen. She'll get chased around."),
                  ("h5", False, "Edge pawns don't help in the opening. Develop or fight for the center.")], 520),
    ("e4 c5", [("Nf3", True, "It develops a knight and gets ready to play d4."),
               ("Qh5", False, "Out this early, the queen gets chased around while Black develops."),
               ("a4", False, "Edge pawns don't help in the opening. Develop a piece.")], 480),
    ("e4 e6", [("d4", True, "Two pawns side by side in the center. The ideal opening setup."),
               ("Qg4", False, "Too early for the queen. She'll be chased around."),
               ("h4", False, "Edge pawns don't fight for the center.")], 480),
    ("e4 c6", [("d4", True, "Two pawns side by side in the center. The ideal opening setup."),
               ("b4", False, "A loose pawn on the edge that doesn't help the center."),
               ("Qf3", False, "Too early for the queen, and she takes your knight's best square.")], 500),
    ("e4 d5", [("exd5", True, "Take it: their pawn attacks your center, and capturing wins time."),
               ("f3", False, "It guards e4, but it weakens your king and takes your knight's square."),
               ("Ke2", False, "Never walk your king out in the opening. Keep it home and castle.")], 500),
    ("e4 d5 exd5 Qxd5", [("Nc3", True, "It develops a knight and attacks the queen. Black has to move her again."),
                         ("Bc4", False, "Green light! The queen on d5 would just take the bishop."),
                         ("Nh3", False, "A knight on the edge. Nc3 develops and attacks the queen.")], 560),
    ("d4 Nf6 c4", [("e6", True, "It opens a path for your bishop and keeps an eye on the center."),
                   ("Ng4", False, "Same piece twice, and it does nothing there. Develop something new."),
                   ("a5", False, "Edge pawns don't help in the opening.")], 560),
    ("d4 Nf6 c4 e6 Nc3", [("Bb4", True, "It develops a bishop and pins the knight on c3."),
                          ("Qe7", False, "The queen blocks your bishop. Develop a minor piece."),
                          ("h5", False, "Edge pawns don't help in the opening.")], 620),
    ("e4 e5 Nf3 d6", [("d4", True, "It grabs the center and opens lines for your pieces."),
                      ("Ng5", False, "Same piece twice, and h6 or f6 will push it back."),
                      ("Rg1", False, "Rooks come out after you castle. Develop a minor piece or take the center.")], 560),
    ("e4 e5 Nf3 Nc6 d4 exd4", [("Nxd4", True, "Win the pawn back and put a knight in the center."),
                               ("Qxd4", False, "Green light! The knight on c6 would take your queen."),
                               ("Bd3", False, "It blocks your d-pawn, and you're still a pawn down.")], 600),
    ("e4 e5 Nc3", [("Nf6", True, "It develops a knight and attacks the e4 pawn."),
                   ("Qg5", False, "Too early for the queen. d4 or Nf3 will chase her."),
                   ("f5", False, "It weakens your king and loses a pawn. Develop instead.")], 560),
    ("Nf3", [("d5", True, "A center pawn, two squares. It grabs the middle."),
             ("e5", False, "Green light! The knight on f3 would take it for free."),
             ("Na6", False, "A knight on the edge reaches fewer squares.")], 440),
    ("c4", [("e5", True, "A center pawn, two squares. It grabs the middle."),
            ("b5", False, "Green light! The c4 pawn would take it for free."),
            ("Nh6", False, "A knight on the edge reaches fewer squares.")], 460),
    ("e4 e5 Nf3 Nc6 Bc4 Bc5 O-O", [("Nf6", True, "It develops your last minor piece on the kingside, ready to castle."),
                                   ("Qh4", False, "Green light! The knight on f3 would take her."),
                                   ("Bxf2+", False, "That gives a bishop for a pawn. Count it: 3 for 1.")], 600),
    ("e4 e5 Nf3 Nc6 Nc3", [("Nf6", True, "It develops a knight and attacks the e4 pawn."),
                           ("Bd6", False, "On d6 the bishop blocks your d-pawn and your other bishop."),
                           ("Qf6", False, "Too early for the queen, and she takes your knight's best square.")], 580),
    ("d4 d5 Bf4", [("Nf6", True, "It develops a knight and guards d5."),
                   ("e5", False, "Green light! That pawn just gets taken."),
                   ("h5", False, "Edge pawns don't help in the opening. Develop a piece.")], 560),
    ("e4 e5 Nf3 Nf6", [("Nxe5", True, "Free pawn! Nothing guards e5, so take it."),
                       ("Ng1", False, "Going backwards undoes your development."),
                       ("Ke2", False, "Never walk your king out in the opening.")], 600),
    ("d4 d5 c4 dxc4", [("e3", True, "It frees your bishop, and the bishop will win back the c4 pawn."),
                       ("Kd2", False, "Never walk your king out in the opening."),
                       ("h4", False, "Edge pawns don't help. Free your bishop instead.")], 600),
    ("e4 e5 Nf3 Nc6 Bb5 Nf6", [("O-O", True, "Castle early: your king gets safe and your rook joins the game."),
                               ("Kf1", False, "Walking the king gives up castling. Castle instead."),
                               ("Qe2", False, "Too early for the queen, and she blocks your bishop's retreat.")], 620),
    ("e4 c5 Nf3 d6 d4 cxd4", [("Nxd4", True, "Win the pawn back and put a knight in the center."),
                              ("g4", False, "That pawn move weakens your king and leaves you a pawn down."),
                              ("Ba6", False, "The b7 pawn would take your bishop for free.")], 640),
    ("e4 e5 Bc4", [("Nf6", True, "It develops a knight and attacks the e4 pawn."),
                   ("b5", False, "Green light! The bishop would take it for free."),
                   ("Qg5", False, "Too early for the queen. She'll be chased around.")], 540),
    ("e4 e5 Nf3 Nc6 Bc4 Nf6 d3 Be7 O-O O-O", [("Nc3", True, "Your last knight joins the game. Every piece is out and working."),
                                              ("Ng5", False, "Same piece twice, and h6 pushes it right back."),
                                              ("h4", False, "Pawns in front of your castled king are its shield. Finish developing first.")], 680),
    ("e4 e5 Nf3 Nc6 Bc4 Nf6 d3 Be7", [("O-O", True, "Castle early: your king gets safe and your rook joins the game."),
                                      ("Ng5", False, "Same piece twice. Castle and finish developing first."),
                                      ("Rg1", False, "Rooks come out after you castle.")], 640),
    ("d4 d5 c4 e6 Nc3 Nf6", [("Bg5", True, "It develops a bishop and pins the knight on f6."),
                             ("Qa4+", False, "Too early for the queen. A pawn or piece blocks, and she has to move again."),
                             ("h4", False, "Edge pawns don't help in the opening.")], 680),
    ("e4 e5 Nf3 Nc6 Bc4 Bc5 c3", [("Nf6", True, "It develops a knight and attacks the e4 pawn."),
                                  ("Qh4", False, "Green light! The knight on f3 would take her."),
                                  ("Bxf2+", False, "That gives a bishop for a pawn. Count it: 3 for 1.")], 620),
    ("e4 Nf6", [("e5", True, "Gain space and chase the knight: it has to move again."),
                ("Qe2", False, "The queen guards e4, but she blocks your bishop."),
                ("f3", False, "It guards e4, but it weakens your king and takes your knight's best square.")], 600),
]


def describe(board: chess.Board, move: chess.Move) -> str:
    """"Knight to f3", "Pawn takes d5", "Castle"."""
    if board.is_castling(move):
        return "Castle" if board.is_kingside_castling(move) else "Castle queenside"
    piece = NAMES[board.piece_at(move.from_square).piece_type].capitalize()
    verb = "takes" if board.is_capture(move) else "to"
    text = f"{piece} {verb} {chess.square_name(move.to_square)}"
    if board.gives_check(move):
        text += ", check"
    return text


def opening_drills(engine: Engine | None) -> list[dict]:
    out = []
    for n, (pgn, options, rating) in enumerate(OPENINGS):
        board = chess.Board()
        for san in pgn.split():
            board.push_san(san)
        opts = []
        scores = {}
        if engine:
            lines = engine.lines(board, 16, 10)
            best = win_chances(lines[0].score, board.turn)
            for san, _, _ in options:
                move = board.parse_san(san)
                info = engine.engine.analyse(board, chess.engine.Limit(depth=16), root_moves=[move])
                scores[san] = win_chances(info["score"], board.turn)
            right = next(san for san, ok, _ in options if ok)
            ok = best - scores[right] <= 0.06 and all(scores[right] - scores[san] >= 0.06
                                                       for san, good, _ in options if not good)
            note = " ".join(f"{san}={scores[san]:+.2f}" for san, _, _ in options)
            print(f"opening {n:2} {'ok ' if ok else 'BAD'} best {best:+.2f} {note}  [{pgn}]")
            if not ok:
                continue
        for san, correct, why in options:
            move = board.parse_san(san)
            opts.append({"text": describe(board, move), "move": move.uci(), "correct": correct, "why": why})
        out.append({"skill": "opening", "type": "choice", "rating": rating, "fen": board.fen(), "options": opts})
    return out


# MARK: Mined and composed positions

def reply_from(board: chess.Board, target: chess.Square, named: str | None) -> str | None:
    """The opponent's capture on `target`: by the piece the explanation names, else the cheapest."""
    caps = [m for m in board.legal_moves if m.to_square == target and board.is_capture(m)]
    if not caps:
        return None
    if named:
        for m in caps:
            if chess.square_name(m.from_square) == named:
                return m.uci()
    return min(caps, key=lambda m: EXCHANGE[board.piece_at(m.from_square).piece_type]).uci()


def safe_drill(rec: dict, skill: str) -> dict | None:
    board = chess.Board(rec["fen"])
    board.push_uci(rec["setup"])
    move = chess.Move.from_uci(rec["move"])
    if move not in board.legal_moves:
        return None
    board.push(move)
    # The explanation names the piece that takes ("Their pawn on g5 can take...").
    named = re.search(r"on ([a-h][1-8])", rec["explain"]) if not rec["answer"] else None
    reply = reply_from(board, move.to_square, named.group(1) if named else None)
    if not rec["answer"] and reply is None:
        return None
    if skill == "safety" and rec["answer"]:
        reply = None
    out = {"skill": skill, "type": "safe", "rating": rec["rating"], "fen": rec["fen"], "setup": rec["setup"],
           "move": rec["move"], "answer": rec["answer"], "explain": rec["explain"], "game": rec.get("game")}
    if reply:
        out["reply"] = reply
    return out


def tap_drill(rec: dict) -> dict | None:
    return {"skill": "threats", "type": "tap", "rating": rec["rating"], "fen": rec["fen"], "setup": rec["setup"],
            "squares": rec["answer"], "explain": rec["explain"], "game": rec.get("game")}


def puzzle_skill(rec: dict) -> str | None:
    if rec.get("source") == "composed" and rec.get("motif") in MOTIF_SKILLS:
        return MOTIF_SKILLS[rec["motif"]]
    tags = set(rec.get("tags", []))
    mate = rec.get("mate")
    for tag, skill in TAG_SKILLS:
        if tag in tags:
            if skill == "back-rank" and (mate or 0) > 2:
                continue
            return skill
    if mate == 1:
        return "mate-in-1"
    if mate == 2:
        return "mate-in-2"
    return None


def move_drill(rec: dict, skill: str) -> dict | None:
    board = chess.Board(rec["fen"])
    if rec.get("setup"):
        board.push_uci(rec["setup"])
    probe = board.copy()
    for uci in rec["solution"]:
        move = chess.Move.from_uci(uci)
        if move not in probe.legal_moves:
            return None
        probe.push(move)
    if rec.get("mate") and not probe.is_checkmate():
        return None
    out = {"skill": skill, "type": "move", "rating": rec["rating"], "fen": rec["fen"], "solution": rec["solution"],
           "game": rec.get("game") or rec.get("source")}
    if rec.get("setup"):
        out["setup"] = rec["setup"]
    alts = rec.get("alternatives") or rec.get("alts") or []
    if any(alts):
        out["alts"] = alts
    if rec.get("mate"):
        out["mate"] = rec["mate"]
    return out


def playout_drill(rec: dict) -> dict:
    n = rec["mateIn"]
    return {"skill": rec["motif"], "type": "playout", "rating": rec["rating"], "fen": rec["fen"],
            "limit": n + PLAYOUT_LIMITS[rec["motif"]], "game": "composed"}


def key(fen: str) -> str:
    return " ".join(fen.split()[:2])


def pick(drills: list[dict], target: int, rng: random.Random, balance: str | None = None) -> list[dict]:
    """A varied set: no repeated positions, a couple per game at most, a spread of ratings,
    and (for yes-or-no drills) about as many yes as no answers."""
    seen, per_game, kept = set(), Counter(), []
    rng.shuffle(drills)
    drills.sort(key=lambda d: d["rating"])
    if balance:
        groups = defaultdict(list)
        for d in drills:
            groups[d[balance]].append(d)
        quota = {k: target // len(groups) for k in groups}
    else:
        groups, quota = {None: drills}, {None: target}
    for k, group in groups.items():
        # Even spread across the rating range: take every n-th after filtering.
        fresh = []
        for d in group:
            if key(d["fen"]) in seen or (d.get("game") and per_game[d["game"]] >= PER_GAME and d["game"] != "composed"):
                continue
            fresh.append(d)
            seen.add(key(d["fen"]))
            if d.get("game"):
                per_game[d["game"]] += 1
        step = max(1.0, len(fresh) / max(1, quota[k]))
        kept += [fresh[int(i * step)] for i in range(min(quota[k], len(fresh)))]
    return kept


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--mined", nargs="*", default=[])
    parser.add_argument("--composed", nargs="*", default=[])
    parser.add_argument("--engine", help="UCI engine command, to check the opening drills")
    parser.add_argument("--seed", type=int, default=7)
    parser.add_argument("--out", default=str(OUT))
    args = parser.parse_args()
    rng = random.Random(args.seed)

    by_skill: dict[str, list[dict]] = defaultdict(list)
    for path in args.mined + args.composed:
        for line in open(path):
            rec = json.loads(line)
            kind = rec.get("kind")
            if kind == "red":
                d = tap_drill(rec)
            elif kind == "green":
                d = safe_drill(rec, "safety")
            elif kind == "count":
                d = safe_drill(rec, "counting")
            elif kind == "puzzle":
                skill = puzzle_skill(rec)
                d = move_drill(rec, skill) if skill else None
            elif kind == "playout":
                d = playout_drill(rec)
            else:
                d = None
            if d:
                by_skill[d["skill"]].append(d)

    drills: list[dict] = []
    for skill, target in TARGETS.items():
        pool = by_skill.get(skill, [])
        balance = "answer" if skill in ("counting", "safety") else None
        chosen = pick(pool, target, rng, balance)
        drills += chosen
        print(f"{skill:12} {len(chosen):4} of {len(pool):5}")

    engine = Engine(args.engine) if args.engine else None
    try:
        openings = opening_drills(engine)
    finally:
        if engine:
            engine.close()
    drills += openings
    print(f"{'opening':12} {len(openings):4} of {len(OPENINGS):5}")

    # Stable ids, easiest first within each skill.
    counters = Counter()
    final = []
    order = list(TARGETS) + ["opening"]
    drills.sort(key=lambda d: (order.index(d["skill"]), d["rating"], d["fen"]))
    for d in drills:
        counters[d["skill"]] += 1
        d.pop("game", None)
        final.append({"id": f"{d['skill']}-{counters[d['skill']]:03d}", **d})
    Path(args.out).write_text(json.dumps({"drills": final}, separators=(",", ":"), ensure_ascii=False) + "\n")
    print(f"Wrote {len(final)} drills to {args.out}")


if __name__ == "__main__":
    main()
