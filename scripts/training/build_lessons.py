#!/usr/bin/env python3
"""Writes Coach Leo's narrated lessons to ChessGameKiller/Training/Content.

Lessons are written here in plain chess notation (SAN) so they're easy to
edit; this script checks every move and writes the engine notation the app
plays. Run it after editing a lesson, then run verify_training.py.

    python3 scripts/training/build_lessons.py
    python3 scripts/training/build_lessons.py --engine stockfish   # also checks tasks with Stockfish

Each step can show a position, animate moves, draw arrows, light up squares
and put labels on them while the coach talks. A step with a task waits for
the learner: play a move, tap squares, or pick an answer.
"""
from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path

import chess

ROOT = Path(__file__).resolve().parents[2]
CONTENT = ROOT / "ChessGameKiller" / "Training" / "Content"
START = chess.STARTING_FEN
COLORS = {"red", "yellow", "green", "blue", "violet", "teal", "orange", "pink"}


class LessonError(Exception):
    pass


def arrow(spec: str) -> dict:
    """"h5f7 red" or "h5f7 red dashed"."""
    parts = spec.split()
    squares, color = parts[0], parts[1] if len(parts) > 1 else None
    out = {"from": squares[:2], "to": squares[2:4]}
    if color:
        out["color"] = color
    if "dashed" in parts:
        out["dashed"] = True
    return out


def mark(spec: str) -> dict:
    """"f7 red"."""
    parts = spec.split()
    out = {"square": parts[0]}
    if len(parts) > 1:
        out["color"] = parts[1]
    return out


def label(square: str, text: str, color: str | None = None) -> dict:
    out = {"square": square, "text": text}
    if color:
        out["color"] = color
    return out


class Lesson:
    def __init__(self, id: str, title: str, subtitle: str, skill: str, orientation: str | None = None):
        self.id, self.title, self.subtitle, self.skill, self.orientation = id, title, subtitle, skill, orientation
        self.steps: list[dict] = []
        self.board: chess.Board | None = None
        # Positions where the learner has a task, for the engine check.
        self.tasks: list[tuple[str, dict, chess.Board]] = []

    # Positions

    @staticmethod
    def position(fen: str | None = None, pgn: str | None = None) -> chess.Board:
        board = chess.Board(fen or START)
        if not board.is_valid():
            raise LessonError(f"invalid FEN {fen}: {board.status()!r}")
        for san in (pgn or "").split():
            board.push_san(san)
        return board

    def _play_line(self, board: chess.Board, sans: list[str]) -> list[str]:
        ucis = []
        for san in sans:
            move = board.parse_san(san)
            ucis.append(move.uci())
            board.push(move)
        return ucis

    def step(self, say: str | None = None, *, fen: str | None = None, pgn: str | None = None,
             moves: str = "", arrows: list[str] = (), marks: list[str] = (), labels: list[dict] = (),
             pause: float | None = None, task: dict | None = None) -> "Lesson":
        out: dict = {}
        if fen is not None or pgn is not None:
            self.board = self.position(fen, pgn)
            out["fen"] = self.board.fen()
        if self.board is None:
            raise LessonError(f"{self.id}: the first step needs a position")
        if say:
            out["say"] = say
        if moves:
            out["moves"] = self._play_line(self.board, moves.split())
        for spec in arrows:
            a = arrow(spec)
            for sq in (a["from"], a["to"]):
                chess.parse_square(sq)
            if a.get("color") and a["color"] not in COLORS:
                raise LessonError(f"{self.id}: unknown color in {spec}")
        if arrows:
            out["arrows"] = [arrow(s) for s in arrows]
        if marks:
            out["marks"] = [mark(s) for s in marks]
            for m in out["marks"]:
                chess.parse_square(m["square"])
        if labels:
            out["labels"] = list(labels)
        if pause:
            out["pause"] = pause
        if task:
            out["task"] = self._task(task)
        self.steps.append(out)
        return self

    def _task(self, spec: dict) -> dict:
        board = self.board
        kind = spec["type"]
        task = {"type": kind, "prompt": spec["prompt"]}
        before = board.copy()
        if kind == "move":
            line = spec["solution"].split()
            accept_sans = spec.get("accept", [])
            accept = []
            probe = board.copy()
            ucis = []
            for i, san in enumerate(line):
                if i % 2 == 0:
                    others = accept_sans[i // 2].split() if i // 2 < len(accept_sans) else []
                    accept.append([probe.parse_san(s).uci() for s in others])
                move = probe.parse_san(san)
                ucis.append(move.uci())
                probe.push(move)
            if spec.get("mate") and not probe.is_checkmate():
                raise LessonError(f"{self.id}: {spec['solution']} doesn't end in checkmate")
            task["solution"] = ucis
            if any(accept):
                task["accept"] = accept
            if spec.get("mate"):
                task["mate"] = True
            feedback = {}
            for san, text in spec.get("feedback", {}).items():
                feedback[board.parse_san(san).uci()] = text
            if feedback:
                task["feedback"] = feedback
            self._play_line(board, line)
        elif kind == "tap":
            task["squares"] = spec["squares"]
            for sq in spec["squares"]:
                chess.parse_square(sq)
            if spec.get("feedback"):
                task["feedback"] = spec["feedback"]
        elif kind == "choice":
            options = []
            for text, correct, why, move in spec["options"]:
                option = {"text": text, "correct": correct}
                if move:
                    option["move"] = move if len(move) >= 4 and move[1].isdigit() and move[3].isdigit() \
                        else board.parse_san(move).uci()
                if why:
                    option["why"] = why
                options.append(option)
            if sum(o["correct"] for o in options) != 1:
                raise LessonError(f"{self.id}: a choice needs exactly one right answer")
            task["options"] = options
        else:
            raise LessonError(f"{self.id}: unknown task type {kind}")
        for key in ("hint", "success", "wrong"):
            if spec.get(key):
                task[key] = spec[key]
        if "success" not in task:
            raise LessonError(f"{self.id}: every task needs a success line")
        self.tasks.append((self.id, task, before))
        return task

    def json(self) -> dict:
        out = {"id": self.id, "title": self.title, "subtitle": self.subtitle, "skill": self.skill}
        if self.orientation:
            out["orientation"] = self.orientation
        out["steps"] = self.steps
        return out


def move_task(prompt, solution, *, accept=(), mate=False, hint=None, success, wrong=None, feedback=None):
    return {"type": "move", "prompt": prompt, "solution": solution, "accept": list(accept), "mate": mate,
            "hint": hint, "success": success, "wrong": wrong, "feedback": feedback or {}}


def tap_task(prompt, squares, *, hint=None, success, wrong=None, feedback=None):
    return {"type": "tap", "prompt": prompt, "squares": squares, "hint": hint, "success": success,
            "wrong": wrong, "feedback": feedback}


def choice_task(prompt, options, *, hint=None, success, wrong=None):
    return {"type": "choice", "prompt": prompt, "options": options, "hint": hint, "success": success, "wrong": wrong}


# ---------------------------------------------------------------------------
# The lessons, in journey order.

PIECE_LABELS = [label("a1", "5", "orange"), label("b1", "3", "blue"), label("c1", "3", "blue"),
                label("d1", "9", "pink"), label("d2", "1", "green")]


def welcome() -> Lesson:
    L = Lesson("welcome", "Meet Coach Leo", "The Traffic Light: three questions that win games", "threats", "black")
    L.step("Hi, I'm Leo, your coach. I've lost more games than I can count, and every loss taught me something. "
           "Let me save you a few.", pgn="")
    L.step("Strong players aren't magic. They ask the same three questions before every move. I call it the Traffic Light.")
    L.step("Red light: what is my opponent threatening? Yellow light: what can I attack? Green light: is my move safe?")
    L.step("Let's try it on a famous trap. White brings out the bishop and the queen, fast.",
           moves="e4 e5 Bc4 Nc6 Qh5")
    L.step("Red light. White's queen just came to h5. What is she after?",
           task=tap_task("Tap the square White is attacking twice.", ["f7"],
                         hint="Follow the queen's diagonal and the bishop's diagonal. Where do they meet?",
                         success="Yes, f7! Only your king guards it, and two attackers beat one defender.",
                         wrong="Trace the lines from the queen on h5 and the bishop on c4."))
    L.step("If Black forgets to look, watch what happens. Knight f6 attacks the queen, but...",
           arrows=["h5f7 red", "c4f7 red"], moves="Nf6 Qxf7#")
    L.step("Checkmate in four moves. It's called Scholar's Mate, and it catches thousands of players every day.",
           marks=["e8 red"])
    L.step("Let's rewind. You're Black, and this time your red light is on.",
           pgn="e4 e5 Bc4 Nc6 Qh5", arrows=["h5f7 red", "c4f7 red"],
           task=move_task("Stop the checkmate. Guard f7, or block the queen.", "g6",
                          accept=["Qe7 Qf6"],
                          hint="A pawn can step into the queen's path and attack her at the same time.",
                          success="That stops the mate. f7 is safe!",
                          wrong="Not quite. f7 needs another guard, or the queen's path needs blocking.",
                          feedback={"Nf6": "Careful! Knight f6 attacks the queen, but Queen takes f7 is still checkmate.",
                                    "Nh6": "That guards f7, but it puts your knight on the edge. There's a move that guards f7 and attacks the queen."}))
    L.step("Here's one strong way: pawn to g6 blocks the queen and kicks her. But White tries again, queen to f3, "
           "aiming at f7 once more.", moves="Qf3")
    L.step(arrows=["f3f7 red", "c4f7 red"],
           task=move_task("Red light again! Guard f7, and bring out a piece while you're at it.", "Nf6",
                          accept=["Qe7 Qf6"],
                          hint="A knight can block the queen's path to f7.",
                          success="That's the habit. You saw the threat and stopped it.",
                          wrong="Not that one. Find a move that guards f7 and brings a new piece into the game.",
                          feedback={"f5": "That blocks the queen too, but it doesn't bring out a piece. Can you do both?"}))
    L.step("Knight f6 is my favorite: it blocks the queen and brings a piece into the game. Two jobs, one move.")
    L.step("That's the Traffic Light. Red, yellow, green, every move. In your games, tap Think and I'll go through it with you.")
    L.step("And when something goes wrong in a game, I'll save the position for practice. "
           "Your mistakes become your puzzles. Let's get started!")
    return L


def piece_values() -> Lesson:
    L = Lesson("piece-values", "What Pieces Are Worth", "Count before you capture", "counting")
    L.step("Every piece has a value. A pawn is worth 1. Knights and bishops are worth 3.", pgn="", labels=PIECE_LABELS)
    L.step("A rook is worth 5. The queen is worth 9, because she moves like a rook and a bishop together.",
           labels=PIECE_LABELS)
    L.step("The king has no number. You can never trade it. If it's trapped, the game is over.", marks=["e1 yellow"])
    L.step("Before you capture, count. Here White's knight could take the pawn on e5.",
           pgn="e4 e5 Nf3 d6", arrows=["f3e5 yellow dashed"],
           task=choice_task("Is Knight takes e5 a good capture?", [
               ("Yes, I win a pawn", False, "You'd win a pawn, but the d6 pawn takes your knight. That's 1 for 3.", "f3e5"),
               ("No, I'd lose my knight", True, "The d6 pawn guards e5, so you'd win 1 and lose 3.", "d6e5"),
           ], success="Good counting."))
    L.step("See? One pawn in, one knight out. Down 2 points.", moves="Nxe5 dxe5")
    L.step("Now Black puts a knight on d5. It's guarded by the e6 pawn, so it looks safe.",
           pgn="e4 e6 d4 Nf6 Nc3", moves="Nd5")
    L.step(arrows=["e4d5 yellow dashed"],
           task=choice_task("Is pawn takes d5 a good capture?", [
               ("Yes, my pawn for their knight", True, "Even if they take back, you gave 1 and won 3. You're 2 points up.", "e4d5"),
               ("No, they can take back", False, "They can take back, but count it: your pawn is worth 1 and their knight is worth 3.", None),
           ], success="That's it."))
    L.step("Pawn takes knight, pawn takes pawn. You traded a 1 for a 3.", moves="exd5 exd5")
    L.step("So here's the rule: count what you win and what you lose. Come out ahead or even, and the capture is fine. "
           "Come out behind, and it isn't.")
    return L


def threats() -> Lesson:
    L = Lesson("threats", "Red Light: What Do They Want?", "Find the threat behind every move", "threats")
    L.step("Every move your opponent makes wants something. Black just pushed a pawn to h6. Why?",
           pgn="e4 e5 Nf3 Nc6 Bc4 Nf6 d3 Bc5 Nc3 d6 Bg5", moves="h6")
    L.step(task=tap_task("Tap the piece the pawn is attacking.", ["g5"],
                         hint="Pawns attack one square diagonally forward. Which of your pieces is there?",
                         success="Right! The pawn is after your bishop. Spotting that is the red light.",
                         wrong="Look at the squares the h6 pawn attacks."))
    L.step(arrows=["h6g5 red"],
           task=move_task("Save your bishop. Move it, or trade it for their knight.", "Bxf6",
                          accept=["Bh4 Be3 Bd2 Bc1"],
                          hint="Any safe square works, and so does taking the knight on f6.",
                          success="Good. You saw the threat, and you didn't lose a thing.",
                          wrong="Your bishop can still be taken for free. Check every square it could go to.",
                          feedback={"Bf4": "The e5 pawn would take it there.",
                                    "Bxh6": "That gives your bishop for a pawn. Count it: 3 for 1."}))
    L.step("Now a sneakier one. Black pushes a pawn. Looks harmless, right?",
           fen="r4rk1/pb1q1ppp/1p1b4/2pp4/5B2/2N2Q2/PPP2PPP/R4RK1 b - - 0 1", moves="d4")
    L.step(task=tap_task("That pawn move made two threats. Tap both of your pieces in danger.", ["c3", "f3"],
                         hint="One threat comes from the pawn itself. The other comes from a piece the pawn was hiding.",
                         success="Both! The pawn attacks your knight, and it opened the bishop's path to your queen.",
                         wrong="Look at what the pawn attacks, and at what was standing behind it."))
    L.step("When a piece moves, ask two things: what does it attack, and what did it uncover? That's the full red light.",
           arrows=["d4c3 red", "b7f3 red"])
    L.step("Every move, red light first. It takes two seconds, and it saves whole games.")
    return L


def safe_squares() -> Lesson:
    L = Lesson("safe-squares", "Green Light: Is It Safe?", "Check before you let go", "safety")
    L.step("The green light is the last check before you move. You've picked a move. Now picture the piece on its new square.",
           pgn="e4 e5 Nf3 Nc6 Bc4 h6")
    L.step(arrows=["f3g5 yellow dashed"],
           task=choice_task("You'd like to play Knight g5 and attack f7. Is it safe?", [
               ("Safe", False, "Look at the h6 pawn. Pawns capture one square diagonally forward.", None),
               ("Not safe", True, "The h6 pawn would take it for free.", "h6g5"),
           ], success="Green light working!"))
    L.step("Let's see what happens if you go anyway. Gone, for nothing. One look would have saved it.",
           moves="Ng5 hxg5")
    L.step("But attacked doesn't always mean unsafe. Here you'd like to play Knight d5, and Black's knight attacks that square.",
           pgn="e4 e5 Nf3 Nc6 Nc3 Nf6", arrows=["c3d5 yellow dashed", "f6d5 red"],
           task=choice_task("Is Knight d5 safe?", [
               ("Safe", True, "If their knight takes, your e4 pawn takes back. Knight for knight is a fair trade.", None),
               ("Not safe", False, "Count it. If they take, your pawn takes back. Knight for knight, nothing lost.", None),
           ], success="Exactly."))
    L.step("So the green light asks: if they take, can I take back? Is the trade fair? Count, just like before.")
    L.step("Your knight is attacked by the e5 pawn. Some squares are safe, some aren't.",
           pgn="e4 c5 Nf3 d6 d4 cxd4 Nxd4 a6 c4 e5", arrows=["e5d4 red"],
           task=move_task("Move your knight to a safe square.", "Nf3",
                          accept=["Nb3 Nc2 Ne2 Nf5"],
                          hint="Pawns on a6, b7 and f7 guard some of the knight's squares. Stay away from those.",
                          success="Safe and sound. Green light!",
                          wrong="That square isn't safe. Check what can take your knight there.",
                          feedback={"Nb5": "The a6 pawn would take it.", "Nc6": "The b7 pawn would take it.",
                                    "Ne6": "The f7 pawn would take it."}))
    L.step("Green light, every move: picture it, then check it. Can they take it? Can I take back? Is the trade fair?")
    return L


def free_pieces() -> Lesson:
    L = Lesson("free-pieces", "Yellow Light: Free Pieces", "Take what they leave unprotected", "free-pieces")
    L.step("Yellow light: look for captures. Black's queen just came out to h4. Who is guarding her?",
           pgn="e4 e5 Nf3", moves="Qh4")
    L.step(task=move_task("Take the free piece.", "Nxh4",
                          hint="Your knight on f3 can jump to h4.",
                          success="Free queen! Nothing guarded h4. That's 9 points for nothing."))
    L.step("A piece nobody guards is called hanging. Real games are full of them. Your job is to notice.")
    L.step("Two captures here. One wins a piece for free. The other is a trap.",
           fen="4r1k1/ppp2ppp/8/3n4/8/1P5P/PBP2PP1/3R2K1 w - - 0 1",
           task=move_task("Find the capture that wins a piece for free.", "Rxd5",
                          hint="Check what guards each piece. Count the defenders.",
                          success="Free knight! Nothing was guarding d5.",
                          feedback={"Bxg7": "The king guards g7. You'd give a bishop for a pawn."}))
    L.step("Before you grab, use the green light too: after you take, is your piece safe? "
           "Free pieces are only free if you get to keep them.")
    return L


def mate_in_one() -> Lesson:
    L = Lesson("mate-in-one", "Checkmate in One", "Look at every check", "mate-in-1")
    L.step("Checkmate means the king is attacked and has no way out: no escape square, no block, no capture.",
           fen="6k1/Q7/5K2/8/8/8/8/8 w - - 0 1")
    L.step("This one is called the kiss of death. The queen goes right up to the king, and your own king protects her.",
           task=move_task("Find the checkmate.", "Qg7#", mate=True,
                          hint="Put the queen right in front of their king, on a square your king guards.",
                          success="Kiss of death! The king can't take the queen, because your king protects her."))
    L.step("Rooks love edges. Your king takes away the squares in front, and the rook checks along the back row.",
           fen="6k1/8/6K1/8/8/8/8/R7 w - - 0 1",
           task=move_task("Checkmate with the rook.", "Ra8#", mate=True,
                          hint="Their king can't step forward. Check it along the back row.",
                          success="Back-row mate! Your king and rook make a perfect team."))
    L.step("Remember Scholar's Mate? Now you're White, and Black forgot the red light.",
           pgn="e4 e5 Bc4 Nc6 Qh5 Nf6",
           task=move_task("Punish it. Checkmate in one!", "Qxf7#", mate=True,
                          hint="Your queen and bishop both aim at f7.",
                          success="Checkmate! Now you know it from both sides."))
    L.step("To find a mate, look at every check you have, one by one. For each one ask: can the king run, block, or capture? "
           "If not, it's mate.")
    return L


def back_rank() -> Lesson:
    L = Lesson("back-rank", "The Back-Rank Mate", "When pawns become a prison", "back-rank")
    L.step("Look at Black's king. Its own pawns block every step forward. If a rook reaches the back row, it's over.",
           fen="6k1/pb3ppp/2n5/8/8/1P6/P1P2PPP/4R1K1 w - - 0 1", marks=["f7 red", "g7 red", "h7 red"],
           task=move_task("Find the back-rank mate.", "Re8#", mate=True,
                          hint="Your rook can go all the way up the e-file.",
                          success="Back-rank mate! The pawns that protected the king became its prison."))
    L.step("Here's a trick with two rooks on the same file. Black's rook guards the back row, but one guard can't stop two attackers.",
           fen="3r2k1/ppq2ppp/8/8/8/7P/3R1PP1/3R2K1 w - - 0 1",
           task=move_task("Checkmate in two moves.", "Rxd8+ Qxd8 Rxd8#", mate=True,
                          hint="Take their rook with check. Whatever takes back, your other rook is waiting.",
                          success="Two rooks, one file, checkmate. That's called doubling your rooks."))
    L.step("The cure is simple: give your king some air. With a pawn on h6, the king just steps out to h7.",
           fen="6k1/pb3pp1/2n4p/8/8/1P6/P1P2PPP/4R1K1 w - - 0 1", moves="Re8+ Kh7")
    L.step("So guard your own back row, and look for theirs. A king with no air is a king in danger.")
    return L


def mate_in_two() -> Lesson:
    L = Lesson("mate-in-two", "Mate in Two", "Force it, then finish it", "mate-in-2")
    L.step("In a mate in two, your first move forces their reply, and your second move is checkmate. "
           "Here's the most beautiful one in chess: the smothered mate.",
           fen="5r1k/pp4pp/1q5N/8/2Q5/8/PP3PPP/6K1 w - - 0 1")
    L.step("Black's king is boxed in by its own rook and pawns. Your knight would love to check from f7, "
           "but the rook guards it. For now.", arrows=["h6f7 yellow dashed"], marks=["f8 red", "g7 red", "h7 red"])
    L.step(task=move_task("Checkmate in two. Start by giving up your queen!", "Qg8+ Rxg8 Nf7#", mate=True,
                          hint="Check on g8. The king can't take, because your knight guards g8. So the rook has to.",
                          success="Smothered mate! The king was trapped by its own pieces."))
    L.step("The secret of mates in two: look for checks that leave them only one reply. Then look for mate after it.")
    return L


def opening_rules() -> Lesson:
    L = Lesson("opening-rules", "Start Strong", "Center, develop, castle", "opening")
    L.step("The opening has three simple rules. Rule one: take the center. These four squares are the best real estate on the board.",
           pgn="", marks=["d4 teal", "e4 teal", "d5 teal", "e5 teal"],
           task=move_task("Play a first move that fights for the center.", "e4",
                          accept=["d4 c4 Nf3 Nc3"],
                          hint="Push one of the middle pawns two squares.",
                          feedback={"e3": "That's playable, but push a center pawn two squares to really grab the middle.",
                                    "d3": "That's playable, but push a center pawn two squares to really grab the middle.",
                                    "g3": "That gets your bishop ready, but the center comes first.",
                                    "c3": "That's a quiet start. Grab the center with a pawn two squares forward.",
                                    "a4": "Edge pawns don't help in the middle. Try a center pawn.",
                                    "h4": "Edge pawns don't help in the middle. Try a center pawn.",
                                    "Nh3": "A knight on the edge reaches fewer squares. Head for the middle.",
                                    "Na3": "A knight on the edge reaches fewer squares. Head for the middle."},
                          success="Great start! You grab space and open lines for your pieces."))
    L.step("Rule two: bring out your knights and bishops. Every move, a new piece joins the game.",
           pgn="e4 e5",
           task=move_task("Bring out a knight or a bishop. Bonus points if it attacks something.", "Nf3",
                          accept=["Nc3 Bc4 Bb5"],
                          hint="Which knight can jump out and attack the e5 pawn?",
                          feedback={"Ne2": "That develops, but on e2 the knight blocks your bishop. f3 is a better home.",
                                    "Be2": "That works, but the bishop does more on c4 or b5.",
                                    "Bd3": "On d3 the bishop blocks your d-pawn. Find a square with open lines.",
                                    "Ba6": "The b7 pawn would take it. Green light!",
                                    "Nh3": "A knight on the edge reaches fewer squares. Head for the middle.",
                                    "Na3": "A knight on the edge reaches fewer squares. Head for the middle.",
                                    "Qh5": "That's the queen, not a knight or bishop. Early queens get chased."},
                          success="Nicely developed. Every piece you bring out makes your army stronger."))
    L.step("Rule three: castle early. It tucks your king into the corner and brings a rook toward the middle.",
           pgn="e4 e5 Nf3 Nc6 Bc4 Bc5",
           task=move_task("Castle!", "O-O",
                          hint="Move your king two squares toward the rook on h1.",
                          success="Castled! King safe, rook ready."))
    L.step("Why not bring the queen out early? Watch. Black's queen took on d5, and White's knight comes out with an attack.",
           pgn="e4 d5 exd5 Qxd5", moves="Nc3")
    L.step("Now Black has to spend a move running away, while White brings out another piece. Early queens get chased.",
           arrows=["c3d5 red"])
    L.step(pgn="e4 e5 Nf3 Nc6",
           task=choice_task("Which move follows the opening rules?", [
               ("Bishop to c4", True, "It develops a piece and aims at f7.", "Bc4"),
               ("Pawn to h3", False, "Edge pawn moves don't develop anything. Bring out a piece.", "h3"),
               ("Queen to e2", False, "Too early for the queen, and she blocks your bishop.", "Qe2"),
           ], success="Exactly."))
    L.step("Center, develop, castle. Follow those three, and you'll get a good game every time.")
    return L


def forks() -> Lesson:
    L = Lesson("forks", "Forks", "One piece, two targets", "forks")
    L.step("A fork is one piece attacking two things at once. They can only save one. Knights are the sneakiest forkers.",
           fen="r1b1k2r/pp3ppp/5n2/1N6/5B2/8/PPP2PPP/R4RK1 w - - 0 1",
           task=move_task("Find the knight fork.", "Nc7+",
                          hint="Find a square where your knight checks the king and hits a rook. Your bishop guards it.",
                          success="Fork! Check and attack at the same time."))
    L.step("The king has to step away, and the knight takes the rook.", moves="Kd7 Nxa8")
    L.step("Pawns can fork too. Watch: White gives a knight for a pawn, on purpose.",
           pgn="e4 e5 Nf3 Nc6 Nc3 Nf6 Bb5 Bc5", moves="Nxe5 Nxe5")
    L.step(task=move_task("Now find the pawn fork.", "d4",
                          hint="Which pawn can attack the bishop and the knight in one step?",
                          success="Pawn d4 hits the bishop and the knight. You'll win your piece back."))
    L.step("Forks work best against the king and against pieces nobody is guarding. "
           "When you see two loose targets, look for a fork.")
    return L


def pins() -> Lesson:
    L = Lesson("pins", "Pins", "Freeze a piece in front of a bigger one", "pins")
    L.step("A pin freezes a piece. Black's knight on c6 can't move, because then your bishop would be attacking the king.",
           pgn="e4 e5 Nf3 Nc6 Bb5 d6", arrows=["b5e8 yellow dashed"], marks=["c6 yellow"])
    L.step("When the piece behind is the king, moving is against the rules. When it's the queen or a rook, moving is allowed, "
           "but it costs them.")
    L.step("Here Black's queen went to c6. Look at the diagonal from the queen to the king.",
           pgn="e4 d5 exd5 Qxd5 Nc3 Qc6",
           task=move_task("Pin the queen to the king and win her.", "Bb5",
                          hint="Your bishop can attack the queen from b5, and your knight guards that square.",
                          success="Pinned! The queen can't step away without exposing the king."))
    L.step("The best Black can do is give the queen for your bishop.", moves="Qxb5 Nxb5")
    L.step("Look for their pieces lined up with their king or queen. If you can attack the front one, you might have a pin.")
    return L


def skewers() -> Lesson:
    L = Lesson("skewers", "Skewers", "Attack the big piece, win the one behind", "skewers")
    L.step("A skewer is a pin in reverse. You attack the big piece, it has to move, and you win what's behind it.",
           fen="8/3k3q/8/8/8/8/5PPP/R5K1 w - - 0 1",
           task=move_task("Find the skewer. Check the king and win the queen.", "Ra7+",
                          hint="Check the king along the 7th row. The queen is hiding behind it.",
                          success="Skewered!"))
    L.step("The king has to move, and the queen falls.", moves="Ke6 Rxh7")
    L.step("Bishops skewer on diagonals.", fen="6q1/8/4k3/8/8/8/PP6/2K2B2 w - - 0 1",
           task=move_task("Find the bishop skewer.", "Bc4+",
                          hint="Check the king on the long diagonal. Who's standing behind it?",
                          success="Another skewer!"))
    L.step("Lined-up pieces are a gift.", moves="Kd7 Bxg8")
    L.step("Whenever their king and queen, or king and rook, stand on the same line, look for a skewer.")
    return L


def discovered() -> Lesson:
    L = Lesson("discovered", "Discovered Attacks", "Move one piece, uncover another", "discovered")
    L.step("A discovered attack: one piece steps out of the way, and the piece behind it attacks. "
           "Here your bishop stands in front of your rook.",
           fen="4k2r/pp3ppp/8/q3B3/8/8/PP3PPP/4R1K1 w - - 0 1", arrows=["e1e8 yellow dashed"])
    L.step("Red light first: their queen attacks your rook on e1. But you have something much better than defending.",
           arrows=["a5e1 red"],
           task=move_task("Move the bishop with check from your rook, and attack the queen at the same time.",
                          "Bc3+",
                          hint="Find a square where the bishop attacks the queen. The rook does the checking.",
                          success="Discovered check!",
                          feedback={"Bxg7+": "Careful! That opens the diagonal, and their queen takes your rook. Checkmate, for them."}))
    L.step("They have to answer the rook's check, and your bishop takes the queen.", moves="Kd8 Bxa5+")
    L.step("Discovered checks are the strongest kind. They must answer the check first, so your other piece gets a free hit.")
    return L


def queen_mate() -> Lesson:
    L = Lesson("queen-mate", "Queen Checkmate", "Build a box, shrink it, finish it", "queen-mate")
    box = [f"{f}{r} teal" for f in "efgh" for r in "5678"]
    L.step("King and queen against a lone king is always a win, once you know the method. First, your queen builds a box.",
           fen="8/8/4k3/8/3Q4/8/8/4K3 b - - 0 1", marks=box)
    L.step("Keep your queen a knight's jump away from their king. Each time it moves, follow it, and the box gets smaller.",
           moves="Kf5 Qe3 Kg4 Qf2")
    L.step("The box is two files wide now. Once the king is on the edge, stop chasing and bring your own king closer. "
           "The queen can't checkmate alone.", marks=[f"{f}{r} teal" for f in "gh" for r in "345678"])
    L.step("Careful here! Queen f7 takes every square, but the king isn't in check. That's stalemate, and it's only a draw.",
           fen="7k/8/6K1/8/8/8/8/5Q2 w - - 0 1", moves="Qf7")
    L.step("Always leave the king a square until you can give checkmate. Let's do it right.",
           fen="7k/8/6K1/8/8/8/8/5Q2 w - - 0 1",
           task=move_task("Checkmate in one.", "Qf8#", mate=True,
                          hint="Check along the back row. Your king guards the squares in front.",
                          success="Checkmate! Box, shrink, bring the king, finish."))
    L.step("Practice it a few times and you'll never let a won game slip away again.")
    return L


def rook_mates() -> Lesson:
    L = Lesson("rook-mates", "Rook Checkmates", "The ladder, and king and rook", "ladder-mate")
    L.step("Two rooks can checkmate on their own. It's called the ladder: they take turns checking, "
           "and the king climbs to the edge.", fen="8/8/8/6k1/R7/8/8/1R2K3 w - - 0 1", arrows=["a4h4 teal dashed"])
    L.step("One rook guards a row, the other checks on the next one. Then they swap.", moves="Rb5+ Kg6 Ra6+ Kg7 Rb7+ Kg8")
    L.step(task=move_task("Finish the ladder. Checkmate!", "Ra8#", mate=True,
                          hint="One rook guards the 7th row. Use the other to check on the 8th.",
                          success="Up the ladder, and checkmate!"))
    L.step("With one rook, your king has to help. First, use the rook to cut their king off.",
           fen="8/8/8/3k4/8/8/8/R3K3 w - - 0 1", moves="Ra4", arrows=["a4h4 teal dashed"])
    L.step("Then walk your king up. When the kings stand face to face, check from the side, and their king has to step back.",
           fen="8/8/4k3/R7/4K3/8/8/8 w - - 0 1", moves="Ra6+ Ke7")
    L.step("Repeat until their king reaches the edge.", fen="4k3/8/4K3/8/8/8/8/R7 w - - 0 1",
           task=move_task("Kings face to face. Checkmate!", "Ra8#", mate=True,
                          hint="Check along the edge. Your king covers the squares in front.",
                          success="Checkmate with king and rook. That's a skill for life."))
    L.step("Ladder with two rooks, king and rook with one. Practice both until they feel easy.")
    return L


LESSONS = [welcome, piece_values, threats, safe_squares, free_pieces, mate_in_one, back_rank, mate_in_two,
           opening_rules, forks, pins, skewers, discovered, queen_mate, rook_mates]


# ---------------------------------------------------------------------------
# Engine check: are the answers right, and are other good moves accepted?

def check_with_engine(lessons: list[Lesson], command: str) -> int:
    sys.path.insert(0, str(Path(__file__).resolve().parent))
    from chesslib import Engine, win_chances  # noqa: E402

    eng = Engine(command)
    problems = 0
    try:
        for lesson in lessons:
            for lid, task, board in lesson.tasks:
                if task["type"] != "move":
                    continue
                probe = board.copy()
                accept = task.get("accept", [])
                for i, uci in enumerate(task["solution"]):
                    if i % 2 == 1:
                        probe.push(chess.Move.from_uci(uci))
                        continue
                    lines = eng.lines(probe, depth=18, multipv=8)
                    best = win_chances(lines[0].score, probe.turn)
                    by_move = {l.move.uci(): win_chances(l.score, probe.turn) for l in lines}
                    mine = by_move.get(uci)
                    if mine is None:
                        line = eng.engine.analyse(probe, chess.engine.Limit(depth=18), root_moves=[chess.Move.from_uci(uci)])
                        mine = win_chances(line["score"], probe.turn)
                    okay = set([uci] + (accept[i // 2] if i // 2 < len(accept) else []))
                    if task.get("mate") and i == len(task["solution"]) - 1:
                        okay |= {m.uci() for m in probe.legal_moves
                                 if probe.copy(stack=False).is_checkmate() or _mates(probe, m)}
                    status = "ok" if best - mine <= 0.08 else "WORSE"
                    if status != "ok":
                        problems += 1
                    good = [f"{probe.san(l.move)}({by_move[l.move.uci()]:+.2f})" for l in lines
                            if best - by_move[l.move.uci()] <= 0.08 and l.move.uci() not in okay]
                    print(f"{lid:14} {probe.san(chess.Move.from_uci(uci)):8} {status:5} best {best:+.2f} mine {mine:+.2f}"
                          + (f"  also good, not accepted: {' '.join(good)}" if good else ""))
                    for alt in (accept[i // 2] if i // 2 < len(accept) else []):
                        if alt in by_move:
                            score = by_move[alt]
                        else:
                            info = eng.engine.analyse(probe, chess.engine.Limit(depth=18), root_moves=[chess.Move.from_uci(alt)])
                            score = win_chances(info["score"], probe.turn)
                        flag = "ok" if best - score <= 0.15 else "WEAK"
                        if flag != "ok":
                            problems += 1
                        print(f"{'':14}   accept {probe.san(chess.Move.from_uci(alt)):8} {flag} {score:+.2f}")
                    probe.push(chess.Move.from_uci(uci))
    finally:
        eng.close()
    return problems


def _mates(board: chess.Board, move: chess.Move) -> bool:
    b = board.copy(stack=False)
    b.push(move)
    return b.is_checkmate()


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--engine", help="UCI engine command; checks every task with it")
    parser.add_argument("--out", default=str(CONTENT))
    args = parser.parse_args()

    lessons = [make() for make in LESSONS]
    out = Path(args.out)
    out.mkdir(parents=True, exist_ok=True)
    for lesson in lessons:
        path = out / f"lesson-{lesson.id}.json"
        path.write_text(json.dumps(lesson.json(), indent=2, ensure_ascii=False) + "\n")
    print(f"Wrote {len(lessons)} lessons to {out}")
    if args.engine:
        problems = check_with_engine(lessons, args.engine)
        print("Engine check:", "all good" if problems == 0 else f"{problems} problem(s)")
        sys.exit(1 if problems else 0)


if __name__ == "__main__":
    main()
