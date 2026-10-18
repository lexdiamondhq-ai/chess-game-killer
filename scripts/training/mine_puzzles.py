#!/usr/bin/env python3
"""Mines practice positions for the training mode from beginner-style games.

Stockfish plays itself at a low skill level, with the odd random move thrown
in, which gives games full of the mistakes real beginners make. Every game is
then combed for teaching moments:

  puzzle  The last move handed the other side a clear win with one move.
          The mistake is shown first, then the player must punish it.
          Checked again deeper, extended while every move stays the only good
          one, tagged with its pattern (fork, pin, mate in 2, ...) and given a
          starting difficulty.
  red     "What does their last move attack?" Exactly one of the player's
          pieces just came under attack. The player taps it.
  green   "Is this move safe?" A quiet move is shown as an arrow; the engine
          confirms whether it simply loses the piece.
  count   "Is this capture good?" The target is defended; the engine confirms
          whether taking it wins or loses material.

Output is one JSON record per line; scripts/training/build_drills.py picks the
final set for the app.

Usage:
  python3 scripts/training/mine_puzzles.py --engine "node stockfish-18-single.js" \
      --games 100 --workers 4 --out mined.jsonl
"""
from __future__ import annotations

import argparse
import json
import multiprocessing as mp
import random
import sys
import time

import chess

from chesslib import (EXCHANGE, NAMES, SLIDERS, VALUE, Engine, Line, balance, danger_squares, flipped,
                      mate_in, win_chances)

MAX_SOLVER_MOVES = 3


# MARK: Games

def play_game(eng: Engine, rng: random.Random) -> list[chess.Move]:
    """One game between two weak engines that sometimes play a random move."""
    board = chess.Board()
    skills = (rng.choice([0, 0, 1, 1, 2, 3, 4, 5, 6]), rng.choice([0, 0, 1, 1, 2, 3, 4, 5, 6]))
    blunder_rate = rng.choice([0.05, 0.08, 0.1, 0.12])
    opening_plies = rng.randint(2, 9)
    while not board.is_game_over(claim_draw=True) and board.ply() < 150:
        if board.ply() < opening_plies:
            lines = eng.lines(board, 6, 5)
            move = rng.choice(lines[: max(1, len(lines))]).move
        elif rng.random() < blunder_rate:
            move = rng.choice(list(board.legal_moves))
        else:
            skill = skills[0] if board.turn == chess.WHITE else skills[1]
            move = eng.play(board, skill, rng.choice([0.02, 0.03, 0.05]))
        board.push(move)
    return list(board.move_stack)


def separated(best: "Line", other: "Line | None", solver: chess.Color, needed: float = 0.33) -> bool:
    """Whether `best` is clearly better than `other`: by winning chances, or by at
    least 2.5 pawns when both are already winning (the curve flattens out there)."""
    if other is None:
        return True
    gap = win_chances(best.score, solver) - win_chances(other.score, solver)
    if gap >= needed:
        return True
    a, b = best.score.pov(solver), other.score.pov(solver)
    if not a.is_mate() and not b.is_mate():
        return a.score() >= 300 and a.score() - b.score() >= 250
    return False


# MARK: Puzzles

def extend_solution(eng: Engine, board: chess.Board, first: chess.Move, first_alternatives: list[chess.Move],
                    solver: chess.Color, mate: int | None) -> tuple[list[chess.Move], list[list[chess.Move]]] | None:
    """The full solution from `first`: the opponent's best replies and the player's
    good moves, until the mate or until the win has been cashed in.

    Also returns, for each of the player's moves, other moves that are just as
    good there (two ways to take the same queen, any mate in one). Playing one
    of those ends the puzzle as solved."""
    b = board.copy()
    line = [first]
    alternatives = [first_alternatives]
    b.push(first)
    moves = 1
    while not b.is_game_over():
        if mate is None and moves >= MAX_SOLVER_MOVES:
            break
        if mate is not None and moves >= mate:
            break
        reply = eng.lines(b, 16, 1)
        if not reply:
            break
        b.push(reply[0].move)
        options = eng.lines(b, 16, 4)
        if not options:
            b.pop()
            break
        best = options[0]
        if mate is not None:
            left = mate_in(best.score, solver)
            if left is None:
                return None
            same = [o.move for o in options[1:] if (mate_in(o.score, solver) or 99) <= left]
            if left > 1 and same:
                return None  # two ways to keep mating: ambiguous
            line += [reply[0].move, best.move]
            alternatives.append(same)
            b.push(best.move)
            moves += 1
            continue

        def forcing(m: chess.Move) -> bool:
            return b.is_capture(m) or b.gives_check(m) or bool(m.promotion)

        top = win_chances(best.score, solver)
        close = [o.move for o in options[1:] if win_chances(o.score, solver) >= top - 0.06]
        others = [o for o in options[1:] if win_chances(o.score, solver) < top - 0.06]
        if not others and b.legal_moves.count() > len(options):
            b.pop()
            break
        if forcing(best.move) and separated(best, others[0] if others else None, solver) \
                and len(close) <= 2 and all(forcing(m) for m in close):
            line += [reply[0].move, best.move]
            alternatives.append(close)
            b.push(best.move)
            moves += 1
        else:
            b.pop()
            break
    if mate is not None and not b.is_checkmate():
        return None
    return line, alternatives


def captured_square(board: chess.Board, move: chess.Move) -> chess.Square | None:
    if not board.is_capture(move):
        return None
    if board.is_en_passant(move):
        return move.to_square + (-8 if board.turn == chess.WHITE else 8)
    return move.to_square


def ray_beyond(board: chess.Board, frm: chess.Square, step: tuple[int, int]) -> list[chess.Square]:
    """Occupied squares along a ray from `frm`, nearest first (first two only)."""
    found = []
    f, r = chess.square_file(frm), chess.square_rank(frm)
    while True:
        f += step[0]
        r += step[1]
        if not (0 <= f < 8 and 0 <= r < 8):
            break
        sq = chess.square(f, r)
        if board.piece_at(sq):
            found.append(sq)
            if len(found) == 2:
                break
    return found


def directions(piece_type: int) -> list[tuple[int, int]]:
    diagonal = [(1, 1), (1, -1), (-1, 1), (-1, -1)]
    straight = [(1, 0), (-1, 0), (0, 1), (0, -1)]
    return {chess.BISHOP: diagonal, chess.ROOK: straight, chess.QUEEN: diagonal + straight}.get(piece_type, [])


def tag_puzzle(board: chess.Board, line: list[chess.Move], solver: chess.Color, mate: int | None) -> list[str]:
    tags: set[str] = set()
    enemy = not solver
    b = board.copy()
    later_captures: list[tuple[int, chess.Square]] = []
    probe = board.copy()
    for i, mv in enumerate(line):
        sq = captured_square(probe, mv)
        if i % 2 == 0 and sq is not None:
            later_captures.append((i, sq))
        probe.push(mv)

    def captured_later(i: int, squares) -> bool:
        return any(j > i and sq in squares for j, sq in later_captures)

    for i, mv in enumerate(line):
        if i % 2 == 1:
            b.push(mv)
            continue
        before = b.copy(stack=False)
        mover = b.piece_at(mv.from_square)
        b.push(mv)
        if mv.promotion:
            tags.add("promotion")
        if len(b.checkers()) >= 2:
            tags.add("doubleCheck")
        moved = b.piece_at(mv.to_square)

        # Fork: the moved piece hits two targets worth hitting.
        targets = set()
        for t in b.attacks(mv.to_square):
            p = b.piece_at(t)
            if not p or p.color != enemy:
                continue
            if p.piece_type == chess.KING or VALUE[p.piece_type] > VALUE[moved.piece_type] or not b.attackers(enemy, t):
                targets.add(t)
        if len(targets) >= 2 and captured_later(i, targets):
            tags.add("fork")

        # Pin and skewer along the moved piece's lines.
        if moved.piece_type in SLIDERS:
            for step in directions(moved.piece_type):
                hit = ray_beyond(b, mv.to_square, step)
                if len(hit) < 2:
                    continue
                front, back = b.piece_at(hit[0]), b.piece_at(hit[1])
                if front.color != enemy or back.color != enemy:
                    continue
                if mv.to_square not in b.attackers(solver, hit[0]):
                    continue
                front_value = EXCHANGE[front.piece_type]
                back_value = EXCHANGE[back.piece_type]
                if back_value > front_value and captured_later(i, {hit[0]}):
                    tags.add("pin")
                elif front_value > back_value and back.piece_type != chess.PAWN and captured_later(i, {hit[1]}):
                    tags.add("skewer")

        # Discovered attack: moving away opened a line from another piece.
        for s in b.pieces(chess.BISHOP, solver) | b.pieces(chess.ROOK, solver) | b.pieces(chess.QUEEN, solver):
            if s == mv.to_square:
                continue
            for t in b.attacks(s):
                p = b.piece_at(t)
                if not p or p.color != enemy:
                    continue
                if mv.from_square in chess.SquareSet(chess.between(s, t)):
                    if p.piece_type == chess.KING:
                        tags.add("discoveredCheck")
                    elif VALUE[p.piece_type] >= 3 and captured_later(i, {t}):
                        tags.add("discoveredAttack")

        # Pieces that were already pinned and get picked off.
        for t in later_captures:
            if t[0] == i and before.is_pinned(enemy, t[1]):
                tags.add("pin")

    if mate is not None:
        tags.add(f"mateIn{mate}")
        king = b.king(enemy)
        checkers = list(b.checkers())
        back_rank = 0 if enemy == chess.WHITE else 7
        if king is not None and chess.square_rank(king) == back_rank and checkers:
            c = b.piece_at(checkers[0])
            if c.piece_type in (chess.ROOK, chess.QUEEN) and chess.square_rank(checkers[0]) == back_rank:
                tags.add("backRankMate")
        if king is not None and checkers and b.piece_at(checkers[0]).piece_type == chess.KNIGHT:
            around = chess.SquareSet(chess.BB_KING_ATTACKS[king])
            if all(b.piece_at(s) and b.piece_at(s).color == enemy for s in around):
                tags.add("smotheredMate")
    else:
        first = line[0]
        target = captured_square(board, first)
        if len(line) == 1 and target is not None:
            if not board.attackers(enemy, target):
                tags.add("hangingPiece")
            elif VALUE[board.piece_at(target).piece_type] > VALUE[board.piece_at(first.from_square).piece_type]:
                tags.add("tradeUp")
    return sorted(tags)


def estimate_rating(board: chess.Board, line: list[chess.Move], tags: list[str], found_depth: int) -> int:
    """A starting difficulty on the puzzle-rating scale (about 400 easy to 2000 hard).
    The app adjusts each player's level from how they actually do."""
    first = line[0]
    solver_moves = (len(line) + 1) // 2
    r = 470 + 250 * (solver_moves - 1)
    if not board.is_capture(first) and not board.gives_check(first):
        r += 180
    elif board.gives_check(first) and not board.is_capture(first):
        r += 50
    r += 35 * max(0, found_depth - 3)
    r += 5 * (len(board.piece_map()) - 12)
    bonus = {"fork": 70, "pin": 110, "skewer": 100, "discoveredAttack": 130, "discoveredCheck": 90,
             "doubleCheck": 60, "smotheredMate": 80, "hangingPiece": -140, "tradeUp": -60}
    r += sum(bonus.get(t, 0) for t in tags)
    piece = board.piece_at(first.from_square)
    forward = 1 if board.turn == chess.WHITE else -1
    if (chess.square_rank(first.to_square) - chess.square_rank(first.from_square)) * forward < 0 and piece.piece_type != chess.PAWN:
        r += 70  # backward moves are easy to miss
    if chess.square_distance(first.from_square, first.to_square) >= 4:
        r += 40
    return max(350, min(2000, r))


def make_puzzle(eng: Engine, before: chess.Board, setup: chess.Move, board: chess.Board, solver: chess.Color,
                game_id: str, ply: int) -> dict | None:
    if board.legal_moves.count() < 3:
        return None
    if abs(balance(board, solver)) > 6:
        return None
    deep = eng.lines(board, 18, 4)
    if len(deep) < 2:
        return None
    best = deep[0]
    mate = mate_in(best.score, solver)
    if mate is not None:
        if mate > 3:
            return None
        rivals = [l for l in deep[1:] if mate_in(l.score, solver) is not None]
        if mate == 1:
            first_alternatives = [l.move for l in rivals if mate_in(l.score, solver) == 1]  # any mate counts
        elif any(mate_in(l.score, solver) <= mate + 1 for l in rivals):
            return None  # another move mates just as fast: ambiguous
        else:
            first_alternatives = []
    else:
        wc1 = win_chances(best.score, solver)
        if wc1 < 0.45:
            return None
        close = [l for l in deep[1:] if win_chances(l.score, solver) >= wc1 - 0.06]
        rest = [l for l in deep[1:] if win_chances(l.score, solver) < wc1 - 0.06]
        if len(close) > 2 or not rest:
            return None
        if not separated(best, rest[0], solver):
            return None  # several good ways to win: not a puzzle
        first_alternatives = [l.move for l in close]
    found = extend_solution(eng, board, best.move, first_alternatives, solver, mate)
    if not found:
        return None
    line, alternatives = found

    end = board.copy()
    for mv in line:
        end.push(mv)
    if mate is None:
        # Material after the opponent's best answer, so a capture that gets
        # taken straight back doesn't count as a win.
        settled = end.copy()
        if not settled.is_game_over():
            reply = eng.lines(settled, 14, 1)
            if reply:
                settled.push(reply[0].move)
        gain = balance(settled, solver) - balance(board, solver)
        if gain < 2:
            return None
    else:
        gain = 0
    tags = tag_puzzle(board, line, solver, mate)
    depth = eng.found_depth(board, line[0])
    return {
        "kind": "puzzle",
        "game": game_id,
        "ply": ply,
        "fen": before.fen(),
        "setup": setup.uci(),
        "solution": [m.uci() for m in line],
        "alternatives": [[m.uci() for m in step] for step in alternatives],
        "mate": mate,
        "tags": tags,
        "gain": gain,
        "foundDepth": depth,
        "pieces": len(board.piece_map()),
        "rating": estimate_rating(board, line, tags, depth),
    }


# MARK: Board-vision drills

def red_light(eng: Engine, before: chess.Board, setup: chess.Move, board: chess.Board, solver: chess.Color) -> dict | None:
    """Exactly one of the player's pieces came under attack with the last move."""
    if board.is_check() or flipped(board) is None:
        return None
    now = danger_squares(board, solver)
    if len(now) != 1:
        return None
    sq = next(iter(now))
    if sq in danger_squares(before, solver):
        return None
    view = flipped(board)
    best = eng.lines(view, 12, 1)
    if not best or best[0].move.to_square != sq:
        return None
    attacker = best[0].move.from_square
    piece = board.piece_at(sq)
    hunter = board.piece_at(attacker)
    defended = bool(board.attackers(solver, sq))
    reason = (f"your {NAMES[piece.piece_type]} is worth more than their {NAMES[hunter.piece_type]}" if defended
              else "nothing defends it")
    explain = (f"Their {NAMES[hunter.piece_type]} on {chess.square_name(attacker)} attacks your "
               f"{NAMES[piece.piece_type]} on {chess.square_name(sq)}, and {reason}.")
    rating = 450
    if hunter.piece_type == chess.KNIGHT:
        rating += 90
    if hunter.piece_type in SLIDERS and chess.square_distance(attacker, sq) >= 3:
        rating += 110
    if attacker != setup.to_square:
        rating += 160  # a discovered threat: the piece that moved isn't the attacker
    rating += 5 * (len(board.piece_map()) - 12)
    return {"kind": "red", "fen": before.fen(), "setup": setup.uci(), "answer": [chess.square_name(sq)],
            "attacker": chess.square_name(attacker), "explain": explain, "rating": max(350, min(1600, rating))}


def green_light(eng: Engine, before: chess.Board, setup: chess.Move, board: chess.Board, solver: chess.Color,
                best_wc: float, want_safe: bool, rng: random.Random) -> dict | None:
    """A quiet piece move, and whether the piece would simply be lost there."""
    moves = [m for m in board.legal_moves
             if not board.is_capture(m) and not board.gives_check(m)
             and board.piece_at(m.from_square).piece_type in (chess.KNIGHT, chess.BISHOP, chess.ROOK, chess.QUEEN)]
    rng.shuffle(moves)
    for m in moves[:8]:
        b = board.copy(stack=False)
        b.push(m)
        hanging = m.to_square in danger_squares(b, solver)
        if hanging == want_safe:
            continue
        reply = eng.lines(b, 12, 1)
        if not reply:
            continue
        drop = best_wc - win_chances(reply[0].score, solver)
        piece = NAMES[board.piece_at(m.from_square).piece_type]
        if not want_safe and reply[0].move.to_square == m.to_square and drop >= 0.35:
            taker = b.piece_at(reply[0].move.from_square)
            explain = (f"Not safe. Their {NAMES[taker.piece_type]} on "
                       f"{chess.square_name(reply[0].move.from_square)} can take your {piece}.")
            rating = 480 + (90 if taker.piece_type == chess.KNIGHT else 0) + \
                (100 if taker.piece_type in SLIDERS and chess.square_distance(reply[0].move.from_square, m.to_square) >= 3 else 0)
            return {"kind": "green", "fen": before.fen(), "setup": setup.uci(), "move": m.uci(), "answer": False,
                    "explain": explain, "rating": rating + 5 * (len(board.piece_map()) - 12)}
        if want_safe and drop <= 0.06:
            explain = f"Safe. Nothing can take your {piece} for free there."
            return {"kind": "green", "fen": before.fen(), "setup": setup.uci(), "move": m.uci(), "answer": True,
                    "explain": explain, "rating": 520 + 5 * (len(board.piece_map()) - 12)}
    return None


def counting(eng: Engine, before: chess.Board, setup: chess.Move, board: chess.Board, solver: chess.Color,
             best_wc: float, want_good: bool, rng: random.Random) -> dict | None:
    """A capture of a defended piece, and whether it wins or loses material."""
    caps = [m for m in board.legal_moves
            if board.is_capture(m) and not board.is_en_passant(m) and board.attackers(not solver, m.to_square)]
    rng.shuffle(caps)
    for m in caps[:6]:
        mover = board.piece_at(m.from_square)
        target = board.piece_at(m.to_square)
        if mover.piece_type == chess.KING:
            continue
        b = board.copy(stack=False)
        b.push(m)
        reply = eng.lines(b, 12, 1)
        if not reply:
            continue
        drop = best_wc - win_chances(reply[0].score, solver)
        defender = min(board.attackers(not solver, m.to_square), key=lambda s: EXCHANGE[board.piece_at(s).piece_type])
        d = board.piece_at(defender)
        if not want_good and VALUE[mover.piece_type] > VALUE[target.piece_type] and drop >= 0.35 \
                and reply[0].move.to_square == m.to_square:
            explain = (f"Not a good capture. The {NAMES[target.piece_type]} is defended by the "
                       f"{NAMES[d.piece_type]} on {chess.square_name(defender)}, so you'd give your "
                       f"{NAMES[mover.piece_type]} ({VALUE[mover.piece_type]}) for a "
                       f"{NAMES[target.piece_type]} ({VALUE[target.piece_type]}).")
            return {"kind": "count", "fen": before.fen(), "setup": setup.uci(), "move": m.uci(), "answer": False,
                    "explain": explain, "rating": 560 + 5 * (len(board.piece_map()) - 12)}
        if want_good and drop <= 0.06 and VALUE[target.piece_type] >= VALUE[mover.piece_type]:
            if VALUE[target.piece_type] > VALUE[mover.piece_type]:
                explain = (f"Good capture. Even if they take back, you trade your {NAMES[mover.piece_type]} "
                           f"({VALUE[mover.piece_type]}) for their {NAMES[target.piece_type]} ({VALUE[target.piece_type]}).")
            else:
                explain = (f"Fine capture. It's an even trade: {NAMES[mover.piece_type]} for "
                           f"{NAMES[target.piece_type]}, and nothing is left hanging.")
            return {"kind": "count", "fen": before.fen(), "setup": setup.uci(), "move": m.uci(), "answer": True,
                    "explain": explain, "rating": 600 + 5 * (len(board.piece_map()) - 12)}
    return None


# MARK: Mining

def mine_game(eng: Engine, moves: list[chess.Move], rng: random.Random, game_id: str) -> list[dict]:
    board = chess.Board()
    prev = eng.lines(board, 10, 2)
    out: list[dict] = []
    counts = {"puzzle": 0, "red": 0, "green": 0, "count": 0}
    for ply, move in enumerate(moves):
        before = board.copy()
        mover = board.turn
        board.push(move)
        if board.is_game_over():
            break
        solver = board.turn
        lines = eng.lines(board, 10, 2)
        if not lines or not prev:
            prev = lines
            continue
        best_wc = win_chances(lines[0].score, solver)
        before_wc = -win_chances(prev[0].score, mover)

        if ply >= 6 and counts["puzzle"] < 4 and len(lines) >= 2 and best_wc >= 0.4 and best_wc - before_wc >= 0.25:
            rec = make_puzzle(eng, before, move, board, solver, game_id, ply)
            if rec:
                out.append(rec)
                counts["puzzle"] += 1

        if ply >= 8 and not board.is_check() and abs(balance(board, solver)) <= 4:
            if counts["red"] < 2:
                rec = red_light(eng, before, move, board, solver)
                if rec:
                    out.append(rec)
                    counts["red"] += 1
            if counts["green"] < 2 and rng.random() < 0.3 and abs(best_wc) < 0.5:
                rec = green_light(eng, before, move, board, solver, best_wc, rng.random() < 0.5, rng)
                if rec:
                    out.append(rec)
                    counts["green"] += 1
            if counts["count"] < 2 and rng.random() < 0.3 and abs(best_wc) < 0.5:
                rec = counting(eng, before, move, board, solver, best_wc, rng.random() < 0.5, rng)
                if rec:
                    out.append(rec)
                    counts["count"] += 1
        prev = lines
    for rec in out:
        rec.setdefault("game", game_id)
    return out


def worker(job: tuple[int, int, str, str]) -> int:
    seed, games, command, path = job
    rng = random.Random(seed)
    eng = Engine(command)
    found = 0
    try:
        for g in range(games):
            game_id = f"{seed}-{g}"
            try:
                moves = play_game(eng, rng)
                records = mine_game(eng, moves, rng, game_id)
            except Exception as error:  # a crashed engine shouldn't end the run
                print(f"game {game_id} failed: {error}", file=sys.stderr)
                eng.close()
                eng = Engine(command)
                continue
            with open(f"{path}.{seed}", "a") as f:
                for rec in records:
                    f.write(json.dumps(rec) + "\n")
            found += len(records)
            print(f"[{seed}] game {g + 1}/{games}: {len(records)} records", flush=True)
    finally:
        eng.close()
    return found


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--engine", required=True, help='UCI engine command, e.g. "stockfish"')
    parser.add_argument("--games", type=int, default=50, help="games per worker")
    parser.add_argument("--workers", type=int, default=4)
    parser.add_argument("--seed", type=int, default=int(time.time()))
    parser.add_argument("--out", required=True)
    args = parser.parse_args()
    jobs = [(args.seed + i, args.games, args.engine, args.out) for i in range(args.workers)]
    with mp.Pool(args.workers) as pool:
        total = sum(pool.map(worker, jobs))
    with open(args.out, "a") as out:
        for seed, *_ in jobs:
            try:
                with open(f"{args.out}.{seed}") as part:
                    out.write(part.read())
            except FileNotFoundError:
                pass
    print(f"done: {total} records in {args.out}")


if __name__ == "__main__":
    main()
