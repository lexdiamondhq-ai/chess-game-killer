#!/usr/bin/env python3
"""Records Coach Leo's voice for every line in the lessons, with ElevenLabs.

Runs in GitHub Actions (.github/workflows/narration.yml) with the
ELEVENLABS_API_KEY repository secret whenever a lesson changes. Each line is
saved as ChessGameKiller/Training/Narration/nar-<12 hex digits of its SHA-1>.mp3,
the same name CoachVoice.fileName(for:) looks for, so a line that's already
recorded is never paid for twice. Lines without a recording are read by the
device's own voice, so the app works before (or without) this step.

Usage:
  python3 scripts/training/make_narration.py            # record what's missing
  python3 scripts/training/make_narration.py --list     # just print the lines
  python3 scripts/training/make_narration.py --prune    # also delete recordings no lesson uses
"""
from __future__ import annotations

import argparse
import hashlib
import json
import os
import sys
import time
import urllib.error
import urllib.request
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
CONTENT = ROOT / "ChessGameKiller" / "Training" / "Content"
NARRATION = ROOT / "ChessGameKiller" / "Training" / "Narration"

# George: a warm, mature British storyteller. Override with ELEVENLABS_VOICE_ID.
VOICE_ID = os.environ.get("ELEVENLABS_VOICE_ID", "JBFqnCBsd6RMkjVDRZzb")
MODEL = "eleven_multilingual_v2"
OUTPUT_FORMAT = "mp3_44100_64"
VOICE_SETTINGS = {"stability": 0.45, "similarity_boost": 0.8, "style": 0.25, "use_speaker_boost": True, "speed": 0.97}
# What LessonPlayer says when a task has no wrong-answer line of its own.
DEFAULT_WRONG = "Not quite. Have another look."
API = "https://api.elevenlabs.io/v1"


def file_name(text: str) -> str:
    """Matches CoachVoice.fileName(for:)."""
    return "nar-" + hashlib.sha1(text.strip().encode("utf-8")).hexdigest()[:12] + ".mp3"


def spoken_lines(lesson: dict) -> list[str]:
    """Everything LessonPlayer can say in a lesson, in the order it's heard."""
    lines: list[str] = []

    def add(text: str | None) -> None:
        if text and text.strip() and text.strip() not in lines:
            lines.append(text.strip())

    for step in lesson["steps"]:
        task = step.get("task")
        add(step.get("say"))
        if not task:
            continue
        add(task["prompt"])
        options = task.get("options") or []
        right = next((o for o in options if o["correct"]), None)
        if right and right.get("why"):
            add(f"{task['success']} {right['why']}")
        else:
            add(task["success"])
        for option in options:
            if not option["correct"]:
                add(option.get("why") or task.get("wrong") or DEFAULT_WRONG)
        add(task.get("hint"))
        for text in (task.get("feedback") or {}).values():
            add(text)
        if task["type"] != "choice":
            add(task.get("wrong") or DEFAULT_WRONG)
    return lines


def all_lines() -> list[str]:
    course = json.loads((CONTENT / "course.json").read_text())
    order = [lesson for unit in course["units"] for lesson in unit["lessons"]]
    lines: list[str] = []
    for lesson_id in order:
        lesson = json.loads((CONTENT / f"lesson-{lesson_id}.json").read_text())
        for line in spoken_lines(lesson):
            if line not in lines:
                lines.append(line)
    return lines


def request(path: str, key: str, body: dict | None = None) -> bytes:
    req = urllib.request.Request(
        f"{API}{path}",
        data=json.dumps(body).encode() if body is not None else None,
        headers={"xi-api-key": key, "Content-Type": "application/json",
                 "Accept": "audio/mpeg" if body is not None else "application/json"},
        method="POST" if body is not None else "GET",
    )
    for attempt in range(4):
        try:
            with urllib.request.urlopen(req, timeout=120) as response:
                return response.read()
        except urllib.error.HTTPError as error:
            detail = error.read().decode(errors="replace")[:400]
            if error.code in (429, 500, 502, 503) and attempt < 3:
                time.sleep(2 ** (attempt + 1))
                continue
            raise RuntimeError(f"ElevenLabs returned {error.code}: {detail}") from None
    raise RuntimeError("ElevenLabs didn't answer")


def characters_left(key: str) -> int | None:
    try:
        info = json.loads(request("/user/subscription", key))
        return int(info["character_limit"]) - int(info["character_count"])
    except Exception as error:  # Keys limited to text-to-speech can't read this; carry on.
        print(f"Couldn't read the character quota ({error}); recording anyway.")
        return None


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--list", action="store_true", help="print the lines and their files, record nothing")
    parser.add_argument("--prune", action="store_true", help="delete recordings that no lesson uses")
    parser.add_argument("--max-chars", type=int, default=60000, help="stop after recording this many characters")
    args = parser.parse_args()

    lines = all_lines()
    wanted = {file_name(line): line for line in lines}
    NARRATION.mkdir(parents=True, exist_ok=True)
    missing = [line for line in lines if not (NARRATION / file_name(line)).exists()]
    print(f"{len(lines)} lines ({sum(map(len, lines))} characters); {len(missing)} not recorded yet "
          f"({sum(map(len, missing))} characters).")

    if args.list:
        for line in lines:
            mark = " " if (NARRATION / file_name(line)).exists() else "*"
            print(f"{mark} {file_name(line)}  {line}")
        return

    if args.prune:
        for path in NARRATION.glob("nar-*.mp3"):
            if path.name not in wanted:
                path.unlink()
                print(f"Removed {path.name}")

    if not missing:
        return
    key = os.environ.get("ELEVENLABS_API_KEY")
    if not key:
        sys.exit("ELEVENLABS_API_KEY is not set. Add it as a repository secret.")
    budget = args.max_chars
    left = characters_left(key)
    if left is not None:
        print(f"{left} characters left on the ElevenLabs plan.")
        budget = min(budget, left)

    recorded = 0
    failure = None
    for line in missing:
        if len(line) > budget:
            print(f"Stopping: {len(missing) - recorded} lines left for the next run (the device voice reads them meanwhile).")
            break
        try:
            audio = request(f"/text-to-speech/{VOICE_ID}?output_format={OUTPUT_FORMAT}", key,
                            {"text": line, "model_id": MODEL, "voice_settings": VOICE_SETTINGS})
        except RuntimeError as error:
            # Keep what's recorded so far (the workflow still commits it) and say why it stopped.
            failure = error
            break
        (NARRATION / file_name(line)).write_bytes(audio)
        budget -= len(line)
        recorded += 1
        print(f"{file_name(line)} {len(audio):6} bytes  {line[:70]}")
    print(f"Recorded {recorded} lines.")
    if failure:
        sys.exit(f"Stopped early, {len(missing) - recorded} lines not recorded: {failure}")


if __name__ == "__main__":
    main()
