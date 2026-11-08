#!/usr/bin/env python3
"""Records each coach's voice for every line in the lessons, and their short
reactions in puzzles and drills, with ElevenLabs.

Two coaches teach the same course: Leo (Trevor's voice) and Vera (Sarah's). The
course is written in Leo's words; for Vera his name becomes hers, exactly as
Coach.personalize does in the app. Reactions ("Nice move.", "Try again.") come
from Training/Content/reactions.json.

Runs in GitHub Actions (.github/workflows/narration.yml) with the
ELEVENLABS_API_KEY repository secret whenever a lesson or the reactions change.
Each line is saved as ChessGameKiller/Training/Narration/<prefix><12 hex digits
of its SHA-1>.mp3 (prefix "nar-" for Leo, "vera-" for Vera), the same name
CoachVoice.fileName(for:coach:) looks for, so a line that's already recorded is
never paid for twice. Lesson lines without a recording are read by the device's
own voice, so the app works before (or without) this step.

narration-voices.json, next to this script, keeps which voice and model made
each recording. To give a coach a new voice: change its "voice" (or "model") in
COACHES, and for Leo VOICE_ID and VOICE_MODEL in coach/wrangler.toml and
coach/src/voice.js, then push. The workflow records that coach's lines again in
the new voice, over the old files, so the app has a recording of every line
throughout.

Usage:
  python3 scripts/training/make_narration.py              # record what's missing
  python3 scripts/training/make_narration.py --list       # just print the lines
  python3 scripts/training/make_narration.py --prune      # also delete recordings nothing uses
  python3 scripts/training/make_narration.py --coach vera # only one coach
"""
from __future__ import annotations

import argparse
import hashlib
import json
import os
import re
import shutil
import subprocess
import sys
import time
import urllib.error
import urllib.request
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
CONTENT = ROOT / "ChessGameKiller" / "Training" / "Content"
NARRATION = ROOT / "ChessGameKiller" / "Training" / "Narration"

# Which voice and model made each recording, by file name. A line recorded in another voice than
# its coach's counts as not recorded; a recording with no entry is taken to be in the coach's voice.
VOICES = Path(__file__).resolve().parent / "narration-voices.json"

MODEL = "eleven_multilingual_v2"
OUTPUT_FORMAT = "mp3_44100_64"
# Leo's model: ElevenLabs' newest, the most natural. It paces itself (no speed setting).
LEO_MODEL = "eleven_v4"
# Leo's settings: none, so the voice's own, exactly as in the samples Alex chose him from
# (2026-11-06). Changing them doesn't re-record anything.
VOICE_SETTINGS = None
COACHES = {
    # Trevor ("TrevorT"): a natural, conversational American man, a professional voice from
    # ElevenLabs' voice library, picked by Alex from samples (2026-11-06). Should its owner ever
    # withdraw it, the recordings stay; give Leo another voice and push to record them again.
    # Override with ELEVENLABS_VOICE_ID. Recorded at 128 kbps, then levelled (MASTER).
    "leo": {"name": "Leo", "prefix": "nar-", "voice": os.environ.get("ELEVENLABS_VOICE_ID", "69SAlwj2jajrSXUGnYAA"),
            "model": LEO_MODEL, "settings": VOICE_SETTINGS, "format": "mp3_44100_128", "master": True},
    # Sarah: a confident, warm young American woman. Override with ELEVENLABS_VERA_VOICE_ID.
    # Steady and clean: high stability, no style exaggeration, recorded at 128 kbps.
    "vera": {"name": "Vera", "prefix": "vera-", "voice": os.environ.get("ELEVENLABS_VERA_VOICE_ID", "EXAVITQu4vr4xnSDxMaL"),
             "model": MODEL, "settings": {"stability": 0.7, "similarity_boost": 0.85, "style": 0.0, "use_speaker_boost": True, "speed": 0.98},
             "format": "mp3_44100_128"},
}
# What LessonPlayer says when a task has no wrong-answer line of its own.
DEFAULT_WRONG = "Not quite. Have another look."
API = "https://api.elevenlabs.io/v1"
# Leo's polish, with ffmpeg: nothing that colors the voice (no EQ or compression, which made it
# sound processed), only the silence trimmed off both ends, every line brought to the same
# loudness by one steady change of volume, a limiter that only catches the odd peak, and a
# breath of quiet after the line.
MASTER = ("silenceremove=start_periods=1:start_threshold=-50dB,areverse,"
          "silenceremove=start_periods=1:start_threshold=-50dB,areverse,"
          "volume={gain:.1f}dB,alimiter=limit={limit:.3f}:attack=5:release=50:level=disabled,apad=pad_dur=0.15")
# Every line of Leo's at this loudness (it comes out about half a decibel under), its peaks under
# MASTER_PEAK_DB.
MASTER_LUFS = -16.0
MASTER_PEAK_DB = -2.0


def loudness(audio: bytes) -> tuple[float, float] | None:
    """Integrated loudness (LUFS) and true peak (dBFS) of an MP3, by ffmpeg's EBU R128 meter."""
    meter = subprocess.run(["ffmpeg", "-hide_banner", "-nostats", "-f", "mp3", "-i", "pipe:0",
                            "-af", "ebur128=peak=true", "-f", "null", "-"], input=audio, capture_output=True)
    level = peak = None
    for line in meter.stderr.decode(errors="replace").rsplit("Summary:", 1)[-1].splitlines():
        words = line.split()
        if len(words) >= 2 and words[0] == "I:":
            level = float(words[1])
        if len(words) >= 2 and words[0] == "Peak:":
            peak = float(words[1])
    if level is None or peak is None or level <= -70:
        return None
    return level, peak


def master(audio: bytes) -> bytes:
    """Leo's recording through MASTER; the raw recording when ffmpeg isn't installed or fails."""
    if not shutil.which("ffmpeg"):
        return audio
    measured = loudness(audio)
    gain = max(-12.0, min(12.0, MASTER_LUFS - measured[0])) if measured else 0.0
    chain = MASTER.format(gain=gain, limit=10 ** (MASTER_PEAK_DB / 20))
    result = subprocess.run(["ffmpeg", "-loglevel", "error", "-f", "mp3", "-i", "pipe:0", "-af", chain,
                             "-ar", "44100", "-b:a", "128k", "-f", "mp3", "pipe:1"],
                            input=audio, capture_output=True)
    if result.returncode != 0 or not result.stdout:
        print(f"ffmpeg couldn't master a line, keeping it raw: {result.stderr.decode(errors='replace')[:200]}")
        return audio
    return result.stdout


def signature(coach: str) -> str:
    """The voice and model a coach's lines are recorded in, as narration-voices.json keeps them."""
    return f"{COACHES[coach]['voice']} {COACHES[coach].get('model', MODEL)}"


def load_voices() -> dict[str, str]:
    try:
        return json.loads(VOICES.read_text())
    except FileNotFoundError:
        return {}


def save_voices(voices: dict[str, str]) -> None:
    """Only the recordings there are, one to a line, so a change of voice reads well in a diff."""
    kept = {name: made for name, made in sorted(voices.items()) if (NARRATION / name).exists()}
    VOICES.write_text(json.dumps(kept, indent=1) + "\n")


def file_name(text: str, coach: str = "leo") -> str:
    """Matches CoachVoice.fileName(for:coach:)."""
    return COACHES[coach]["prefix"] + hashlib.sha1(text.strip().encode("utf-8")).hexdigest()[:12] + ".mp3"


def personalize(text: str, coach: str) -> str:
    """Matches Coach.personalize: the course is in Leo's words, and his name becomes the coach's."""
    if coach == "leo":
        return text
    return re.sub(r"\bLeo\b", COACHES[coach]["name"], text)


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


# What Leo says over a game's highlight reel. Keep in step with GameReel in
# ChessGameKiller/Reel/HighlightReel.swift (introLine, lines, endLines).
REEL_LINES = [
    "Here's how it went.",
    "What a move. This is the one I'd frame.",
    "And right here, the whole game turned.",
    "Ouch. This is the one to learn from.",
    "And that's how you finish a game.",
    "A win. Well played.",
    "Not this time. We'll get them next game.",
    "Honours even. A fair result.",
]


def lesson_lines() -> list[str]:
    """Every lesson and reel line, in Leo's words."""
    course = json.loads((CONTENT / "course.json").read_text())
    order = [lesson for unit in course["units"] for lesson in unit["lessons"]]
    lines: list[str] = []
    for lesson_id in order:
        lesson = json.loads((CONTENT / f"lesson-{lesson_id}.json").read_text())
        for line in spoken_lines(lesson):
            if line not in lines:
                lines.append(line)
    for line in REEL_LINES:
        if line not in lines:
            lines.append(line)
    return lines


def reaction_lines(coach: str) -> list[str]:
    """The coach's short reactions in puzzles and drills (Training/Content/reactions.json)."""
    reactions = json.loads((CONTENT / "reactions.json").read_text())["coaches"].get(coach, {})
    lines: list[str] = []
    for moment in reactions.values():
        for line in moment:
            if line.strip() and line.strip() not in lines:
                lines.append(line.strip())
    return lines


def all_lines(coach: str = "leo") -> list[str]:
    """Everything the coach says: reactions first (they're short and heard most), then the lessons."""
    lines: list[str] = []
    for line in reaction_lines(coach) + [personalize(line, coach) for line in lesson_lines()]:
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
    parser.add_argument("--prune", action="store_true", help="delete recordings that nothing uses")
    parser.add_argument("--coach", choices=sorted(COACHES), action="append", help="only this coach (default: all)")
    parser.add_argument("--max-chars", type=int, default=60000, help="stop after recording this many characters")
    args = parser.parse_args()

    coaches = args.coach or list(COACHES)
    # (coach, line) in recording order: each coach's reactions and lessons.
    work = [(coach, line) for coach in coaches for line in all_lines(coach)]
    NARRATION.mkdir(parents=True, exist_ok=True)
    voices = load_voices()
    for coach, line in work:
        if (NARRATION / file_name(line, coach)).exists():
            voices.setdefault(file_name(line, coach), signature(coach))

    def recorded(coach: str, line: str) -> bool:
        """Recorded, and in the coach's voice."""
        name = file_name(line, coach)
        return (NARRATION / name).exists() and voices.get(name) == signature(coach)

    missing = [(coach, line) for coach, line in work if not recorded(coach, line)]
    for coach in coaches:
        mine = [line for c, line in work if c == coach]
        todo = [line for c, line in missing if c == coach]
        again = sum((NARRATION / file_name(line, coach)).exists() for line in todo)
        print(f"{COACHES[coach]['name']}: {len(mine)} lines ({sum(map(len, mine))} characters); "
              f"{len(todo)} to record ({sum(map(len, todo))} characters)"
              + (f", {again} of them again in the new voice." if again else "."))

    if args.list:
        for coach, line in work:
            mark = " " if recorded(coach, line) else "*"
            print(f"{mark} {file_name(line, coach)}  {line}")
        return

    if args.prune:
        # Every coach's lines are wanted, even when recording only one of them.
        wanted = {file_name(line, coach) for coach in COACHES for line in all_lines(coach)}
        for prefix in {c["prefix"] for c in COACHES.values()}:
            for path in NARRATION.glob(f"{prefix}*.mp3"):
                if path.name not in wanted:
                    path.unlink()
                    print(f"Removed {path.name}")

    if not missing:
        save_voices(voices)
        return
    key = os.environ.get("ELEVENLABS_API_KEY")
    if not key:
        sys.exit("ELEVENLABS_API_KEY is not set. Add it as a repository secret.")
    budget = args.max_chars
    left = characters_left(key)
    if left is not None:
        print(f"{left} characters left on the ElevenLabs plan.")
        budget = min(budget, left)

    done = 0
    failure = None
    try:
        for coach, line in missing:
            if len(line) > budget:
                print(f"Stopping: {len(missing) - done} lines left for the next run "
                      "(meanwhile the app plays their old recording, or the device voice reads them).")
                break
            voice = COACHES[coach]
            body = {"text": line, "model_id": voice.get("model", MODEL)}
            if voice["settings"] is not None:
                body["voice_settings"] = voice["settings"]
            try:
                audio = request(f"/text-to-speech/{voice['voice']}?output_format={voice.get('format', OUTPUT_FORMAT)}",
                                key, body)
            except RuntimeError as error:
                # Keep what's recorded so far (the workflow still commits it) and say why it stopped.
                failure = error
                break
            if voice.get("master"):
                audio = master(audio)
            (NARRATION / file_name(line, coach)).write_bytes(audio)
            voices[file_name(line, coach)] = signature(coach)
            budget -= len(line)
            done += 1
            print(f"{file_name(line, coach)} {len(audio):6} bytes  {line[:70]}")
    finally:
        save_voices(voices)
    print(f"Recorded {done} lines.")
    if failure:
        sys.exit(f"Stopped early, {len(missing) - done} lines not recorded: {failure}")


if __name__ == "__main__":
    main()
