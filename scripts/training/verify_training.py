#!/usr/bin/env python3
"""Checks every position, move and square in the training content.

    python3 scripts/training/verify_training.py

Needs python-chess. Exits non-zero and lists the problems if anything is
off: an illegal move, a "checkmate" that isn't one, a square with nothing on
it, a lesson or skill that doesn't exist, a choice with no right answer.
"""
from __future__ import annotations

import json
import sys
from pathlib import Path

import chess

ROOT = Path(__file__).resolve().parents[2]
CONTENT = ROOT / "ChessGameKiller" / "Training" / "Content"
COLORS = {"red", "yellow", "green", "blue", "violet", "teal", "orange", "pink"}
PIECES = {"pawn", "knight", "bishop", "rook", "queen", "king"}
DRILL_TYPES = {"move", "tap", "safe", "choice", "playout"}

problems: list[str] = []


def problem(where: str, text: str) -> None:
    problems.append(f"{where}: {text}")


def board_from(fen: str, where: str) -> chess.Board | None:
    try:
        board = chess.Board(fen)
    except ValueError as error:
        problem(where, f"bad FEN {fen!r} ({error})")
        return None
    if not board.is_valid():
        problem(where, f"impossible position {fen!r} ({board.status()!r})")
        return None
    return board


def play(board: chess.Board, uci: str, where: str) -> bool:
    try:
        move = chess.Move.from_uci(uci)
    except ValueError:
        problem(where, f"{uci!r} isn't a move")
        return False
    if move not in board.legal_moves:
        problem(where, f"{uci} isn't legal in {board.fen()}")
        return False
    board.push(move)
    return True


def square(name: str, where: str) -> bool:
    try:
        chess.parse_square(name)
        return True
    except ValueError:
        problem(where, f"{name!r} isn't a square")
        return False


def color(value: str | None, where: str) -> None:
    if value is not None and value not in COLORS:
        problem(where, f"unknown color {value!r}")


# MARK: Course

def check_course() -> dict:
    course = json.loads((CONTENT / "course.json").read_text())
    for key in ("coach", "habit", "units", "skills", "ranks", "lines", "moments"):
        if key not in course:
            problem("course", f"missing {key}")
    skills = {s["id"]: s for s in course["skills"]}
    lessons = [l for u in course["units"] for l in u["lessons"]]
    if len(set(lessons)) != len(lessons):
        problem("course", "a lesson appears in two units")
    for unit in course["units"]:
        color(unit["color"], f"unit {unit['id']}")
        for s in unit["skills"]:
            if s not in skills:
                problem(f"unit {unit['id']}", f"unknown skill {s}")
        for l in unit["lessons"]:
            if not (CONTENT / f"lesson-{l}.json").exists():
                problem(f"unit {unit['id']}", f"missing lesson file lesson-{l}.json")
    for s in skills.values():
        if s["lesson"] not in lessons:
            problem(f"skill {s['id']}", f"lesson {s['lesson']} isn't in any unit")
        if "{move}" in s["prompt"] and not (s.get("yes") and s.get("no")):
            problem(f"skill {s['id']}", "yes-or-no prompts need yes and no answers")
    xp = [r["xp"] for r in course["ranks"]]
    if xp != sorted(xp) or xp[0] != 0:
        problem("ranks", "ranks must start at 0 XP and go up")
    for r in course["ranks"]:
        if r["piece"] not in PIECES:
            problem(f"rank {r['id']}", f"unknown piece {r['piece']}")
    for name, lines in course["lines"].items():
        if not lines:
            problem("lines", f"{name} is empty")
    return course


# MARK: Lessons

def check_lesson(lesson_id: str, skills: set[str]) -> None:
    where = f"lesson {lesson_id}"
    lesson = json.loads((CONTENT / f"lesson-{lesson_id}.json").read_text())
    if lesson["id"] != lesson_id:
        problem(where, f"id is {lesson['id']}")
    if lesson["skill"] not in skills:
        problem(where, f"unknown skill {lesson['skill']}")
    board = None
    for n, step in enumerate(lesson["steps"], 1):
        at = f"{where} step {n}"
        if "fen" in step:
            board = board_from(step["fen"], at)
        if board is None:
            problem(at, "no position to start from")
            return
        if not step.get("say") and not step.get("task"):
            problem(at, "says nothing and asks nothing")
        for uci in step.get("moves", []):
            if not play(board, uci, at):
                return
        for a in step.get("arrows", []):
            square(a["from"], at), square(a["to"], at)
            color(a.get("color"), at)
        for m in step.get("marks", []) + step.get("labels", []):
            square(m["square"], at)
            color(m.get("color"), at)
        task = step.get("task")
        if not task:
            continue
        if not task.get("success"):
            problem(at, "task has no success line")
        kind = task["type"]
        if kind == "move":
            solution = task.get("solution") or []
            if not solution:
                problem(at, "move task without a solution")
            probe = board.copy()
            accept = task.get("accept") or []
            for i, uci in enumerate(solution):
                if i % 2 == 0 and i // 2 < len(accept):
                    for alt in accept[i // 2]:
                        if chess.Move.from_uci(alt) not in probe.legal_moves:
                            problem(at, f"accepted move {alt} isn't legal")
                if not play(probe, uci, at):
                    break
            if task.get("mate") and not probe.is_checkmate():
                problem(at, "the solution doesn't end in checkmate")
            for uci in (task.get("feedback") or {}):
                if chess.Move.from_uci(uci) not in board.legal_moves:
                    problem(at, f"feedback for {uci}, which isn't legal here")
            board = probe
        elif kind == "tap":
            if not task.get("squares"):
                problem(at, "tap task without squares")
            for sq in task.get("squares", []):
                if square(sq, at) and board.piece_at(chess.parse_square(sq)) is None:
                    problem(at, f"nothing to tap on {sq}")
        elif kind == "choice":
            options = task.get("options") or []
            if sum(o["correct"] for o in options) != 1:
                problem(at, "a choice needs exactly one right answer")
            for o in options:
                if o.get("move"):
                    square(o["move"][:2], at), square(o["move"][2:4], at)
        else:
            problem(at, f"unknown task type {kind}")


# MARK: Drills

def check_drills(skills: set[str]) -> int:
    drills = json.loads((CONTENT / "drills.json").read_text())["drills"]
    ids = set()
    for d in drills:
        where = f"drill {d.get('id')}"
        if d["id"] in ids:
            problem(where, "duplicate id")
        ids.add(d["id"])
        if d["skill"] not in skills:
            problem(where, f"unknown skill {d['skill']}")
        if d["type"] not in DRILL_TYPES:
            problem(where, f"unknown type {d['type']}")
            continue
        board = board_from(d["fen"], where)
        if board is None:
            continue
        if d.get("setup") and not play(board, d["setup"], where):
            continue
        learner = board.turn
        kind = d["type"]
        if kind == "move":
            probe = board.copy()
            ok = True
            for uci in d.get("solution") or []:
                if not play(probe, uci, where):
                    ok = False
                    break
            if not d.get("solution"):
                problem(where, "no solution")
            if ok and d.get("mate") and not probe.is_checkmate():
                problem(where, "the solution doesn't end in checkmate")
        elif kind == "tap":
            for sq in d.get("squares") or []:
                if square(sq, where):
                    piece = board.piece_at(chess.parse_square(sq))
                    if piece is None or piece.color != learner:
                        problem(where, f"{sq} isn't one of the learner's pieces")
            if not d.get("squares"):
                problem(where, "no squares")
        elif kind == "safe":
            if d.get("answer") is None or not d.get("move"):
                problem(where, "needs a move and an answer")
                continue
            probe = board.copy()
            if play(probe, d["move"], where) and d.get("reply"):
                play(probe, d["reply"], where)
        elif kind == "choice":
            options = d.get("options") or []
            if sum(o["correct"] for o in options) != 1:
                problem(where, "a choice needs exactly one right answer")
            for o in options:
                if o.get("move") and chess.Move.from_uci(o["move"]) not in board.legal_moves:
                    problem(where, f"option {o['move']} isn't legal")
        elif kind == "playout":
            if not d.get("limit"):
                problem(where, "playouts need a move limit")
            pieces = board.piece_map().values()
            if sum(1 for p in pieces if p.color != learner) != 1:
                problem(where, "the defender should have a lone king")
    return len(drills)


def main() -> None:
    course = check_course()
    skills = {s["id"] for s in course["skills"]}
    lessons = [l for u in course["units"] for l in u["lessons"]]
    for lesson_id in lessons:
        if (CONTENT / f"lesson-{lesson_id}.json").exists():
            check_lesson(lesson_id, skills)
    count = check_drills(skills)
    if problems:
        print("\n".join(problems))
        sys.exit(f"{len(problems)} problem(s) in the training content.")
    print(f"Training content OK: {len(lessons)} lessons, {count} drills, {len(skills)} skills.")


if __name__ == "__main__":
    main()
