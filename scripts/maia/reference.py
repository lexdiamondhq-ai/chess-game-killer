#!/usr/bin/env python3
"""Maia's move probabilities from the app's own network files, worked out with numpy and
python-chess. MaiaTests compares the app's Swift copy against these numbers.

    python3 scripts/maia/reference.py        (needs numpy and python-chess)
"""
import os, struct, sys, json
import numpy as np
import chess

ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..")

def read(path):
    b = open(path, "rb").read()
    assert b[:4] == b"MAIA"
    version, blocks, F, S, P = struct.unpack("<5I", b[4:24]); i = 24
    def take(n, dt):
        nonlocal i
        size = n * (2 if dt == "<f2" else 4)
        a = np.frombuffer(b[i:i + size], dt).astype(np.float32); i += size; return a
    def conv(cin, cout): return dict(w=take(cout * cin * 9, "<f2"), scale=take(cout, "<f4"), shift=take(cout, "<f4"), cout=cout)
    net = dict(input=conv(112, F), res=[])
    for _ in range(blocks):
        c1 = conv(F, F); c2 = conv(F, F)
        se = [take(S * F, "<f2"), take(S, "<f4"), take(2 * F * S, "<f2"), take(2 * F, "<f4")]
        net["res"].append(dict(c1=c1, c2=c2, se=se))
    net["policy1"] = conv(F, F)
    net["policy"] = dict(w=take(P * F * 9, "<f2"), scale=np.ones(P, np.float32), shift=take(P, "<f4"), cout=P)
    assert i == len(b)
    return net

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import lc0net

PIECES = [chess.PAWN, chess.KNIGHT, chess.BISHOP, chess.ROOK, chess.QUEEN, chess.KING]

def planes(board):
    """lc0's classical 112 planes from the side to move's point of view, history from the move
    stack; before a game's first position the planes stay empty, unless it began from a set-up
    position, which then fills the rest (lc0's fen_only)."""
    us = board.turn
    out = np.zeros((112, 8, 8), np.float32)
    hist, b = [board.copy()], board.copy()
    while len(hist) < 8 and b.move_stack:
        b.pop(); hist.append(b.copy())
    from_start = not b.move_stack and b.board_fen() == chess.STARTING_BOARD_FEN and b.turn == chess.WHITE
    for i in range(8):
        if i >= len(hist) and from_start: break
        h = hist[min(i, len(hist) - 1)]
        for color, off in ((us, 0), (not us, 6)):
            for k, pt in enumerate(PIECES):
                for s in h.pieces(pt, color):
                    r, f = chess.square_rank(s), chess.square_file(s)
                    out[i * 13 + off + k, 7 - r if us == chess.BLACK else r, f] = 1
        if i < len(hist) and h.is_repetition(2): out[i * 13 + 12] = 1
    them = not us
    out[104] = board.has_queenside_castling_rights(us)
    out[105] = board.has_kingside_castling_rights(us)
    out[106] = board.has_queenside_castling_rights(them)
    out[107] = board.has_kingside_castling_rights(them)
    out[108] = us == chess.BLACK
    out[109] = board.halfmove_clock
    out[111] = 1
    return out

QUEEN_DIRS = [(0, 1), (1, 1), (1, 0), (1, -1), (0, -1), (-1, -1), (-1, 0), (-1, 1)]
KNIGHT_DIRS = [(1, 2), (2, 1), (2, -1), (1, -2), (-1, -2), (-2, -1), (-2, 1), (-1, 2)]

def policy_index(board, move):
    """Where the policy head scores a legal move: plane * 64 + from-square, from the mover's
    side, castling as the king taking its rook, a knight promotion as the plain pawn move."""
    fr, to = move.from_square, move.to_square
    if board.is_castling(move):
        to = chess.square(7 if board.is_kingside_castling(move) else 0, chess.square_rank(fr))
    ff, fr_r, tf, tr = chess.square_file(fr), chess.square_rank(fr), chess.square_file(to), chess.square_rank(to)
    if board.turn == chess.BLACK: fr_r, tr = 7 - fr_r, 7 - tr
    df, dr = tf - ff, tr - fr_r
    if move.promotion in (chess.QUEEN, chess.ROOK, chess.BISHOP):
        plane = 64 + (df + 1) * 3 + {chess.ROOK: 0, chess.BISHOP: 1, chess.QUEEN: 2}[move.promotion]
    elif (df, dr) in KNIGHT_DIRS:
        plane = 56 + KNIGHT_DIRS.index((df, dr))
    else:
        steps = max(abs(df), abs(dr))
        plane = QUEEN_DIRS.index((np.sign(df), np.sign(dr))) * 7 + steps - 1
    return plane * 64 + fr_r * 8 + ff

def probabilities(net, board):
    raw = lc0net.policy_conv(net, planes(board))
    moves = list(board.legal_moves)
    logits = np.array([raw[policy_index(board, m)] for m in moves], np.float64)
    p = np.exp(logits - logits.max()); p /= p.sum()
    return sorted(((m.uci(), float(q)) for m, q in zip(moves, p)), key=lambda t: -t[1])

# The positions MaiaTests checks: (name, start FEN or None for the standard start, moves).
CASES = [
    ("start", None, ""),
    ("after e4", None, "e4"),
    ("italian, castle or not", None, "e4 e5 Nf3 Nc6 Bc4 Bc5 c3 Nf6 d3 d6"),
    ("recapture on d5", None, "e4 d5 exd5"),
    ("fried liver", None, "e4 e5 Nf3 Nc6 Bc4 Nf6 Ng5 d5 exd5 Nxd5"),
    ("queen's gambit middlegame", None, "d4 d5 c4 e6 Nc3 Nf6 Bg5 Be7 e3 O-O Nf3 Nbd7 Qc2 c6 cxd5 exd5 Bd3 Re8 O-O Nf8"),
    ("set-up endgame, promotion", "8/1P4k1/8/8/8/8/6K1/8 w - - 0 1", ""),
    ("set-up, black to move", "r3k2r/pppq1ppp/2npbn2/4p3/2B1P3/2NP1N2/PPPQ1PPP/R3K2R b KQkq - 4 9", ""),
]

if __name__ == "__main__":
    out = {}
    for level in (1100, 1200, 1600, 1900):
        net = read(os.path.join(ROOT, "ChessGameKiller", "Maia", f"maia-{level}.bin"))
        rows = []
        for name, fen, moves in CASES:
            board = chess.Board(fen) if fen else chess.Board()
            for san in moves.split(): board.push_san(san)
            fens = []
            b = board.copy(stack=True); stack = []
            while b.move_stack: stack.append(b.fen()); b.pop()
            fens = [b.fen()] + list(reversed(stack))
            top = probabilities(net, board)[:5]
            rows.append(dict(name=name, fens=fens, top=[[u, round(p, 5)] for u, p in top]))
        out[level] = rows
    print(json.dumps(out, separators=(",", ":")))
