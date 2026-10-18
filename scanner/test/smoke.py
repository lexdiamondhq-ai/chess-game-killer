"""Sends the test boards to the deployed scanner and reports how many squares it read right.

Usage: python3 scanner/test/smoke.py <scanner-url> scanner/test/boards
Fails only if the server itself is broken; reading mistakes are reported, not fatal.
"""
import json
import os
import sys
import time
import urllib.error
import urllib.request

# Cloudflare turns away Python's default "Python-urllib" signature with a 403.
HEADERS = {"User-Agent": "ChessGameKiller-smoke/1.0"}


def grid(placement):
    rows = []
    for row in placement.split("/"):
        rows.append("".join("." * int(ch) if ch.isdigit() else ch for ch in row))
    return rows  # rows[0] is rank 8, files a to h


def to_white_view(rows, side):
    """Turns rows as seen in the picture into rank 8..1, files a..h."""
    board = [["."] * 8 for _ in range(8)]
    for r, text in enumerate(rows):
        for c, ch in enumerate(text):
            if side == "bottom":
                f, rank = c, 7 - r
            elif side == "top":
                f, rank = 7 - c, r
            elif side == "left":
                f, rank = r, c
            else:
                f, rank = 7 - r, 7 - c
            board[7 - rank][f] = ch
    return ["".join(row) for row in board]


def wait_until_up(url, minutes=5):
    """A brand-new workers.dev address can take a few minutes to start answering."""
    deadline = time.time() + minutes * 60
    while True:
        try:
            request = urllib.request.Request(url + "/", headers=HEADERS)
            with urllib.request.urlopen(request, timeout=15) as response:
                if json.load(response).get("ok"):
                    return True
        except urllib.error.HTTPError as error:
            if time.time() > deadline:
                print(f"Scanner never answered at {url}: {error} {error.read()[:300]!r}")
                return False
        except (urllib.error.URLError, OSError, ValueError) as error:
            if time.time() > deadline:
                print(f"Scanner never answered at {url}: {error}")
                return False
        time.sleep(10)


def main():
    url, folder = sys.argv[1].rstrip("/"), sys.argv[2]
    if not wait_until_up(url):
        sys.exit(1)
    with open(os.path.join(folder, "expected.json")) as f:
        expected = json.load(f)
    broken = False
    for name, want in expected.items():
        with open(os.path.join(folder, name), "rb") as f:
            image = f.read()
        request = urllib.request.Request(f"{url}/read", data=image, method="POST",
                                         headers={**HEADERS, "Content-Type": "image/png"})
        started = time.time()
        try:
            with urllib.request.urlopen(request, timeout=150) as response:
                answer = json.load(response)
        except urllib.error.HTTPError as error:
            print(f"{name}: server error {error.code}: {error.read()[:200]!r}")
            broken = True
            continue
        if not answer.get("found"):
            print(f"{name}: no board found")
            continue
        got = to_white_view(answer["rows"], answer.get("white_side", "bottom"))
        truth = grid(want["placement"])
        right = sum(1 for r in range(8) for c in range(8) if got[r][c] == truth[r][c])
        wrong = [f"{'abcdefgh'[c]}{8 - r}: {got[r][c]} (should be {truth[r][c]})"
                 for r in range(8) for c in range(8) if got[r][c] != truth[r][c]]
        side_ok = answer.get("white_side") == want["white_side"]
        print(f"{name}: {right}/64 squares right, white side {answer.get('white_side')}"
              f"{'' if side_ok else ' (wrong)'}, confidence {answer.get('confidence')},"
              f" {time.time() - started:.0f} s")
        for line in wrong:
            print(f"    {line}")
    sys.exit(1 if broken else 0)


if __name__ == "__main__":
    main()
