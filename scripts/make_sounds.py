"""Generates the game's sound effects with the ElevenLabs Sound Effects API.

Runs in GitHub Actions (.github/workflows/sounds.yml) with the
ELEVENLABS_API_KEY repository secret. Edit SOUNDS to change a sound,
then push to the `generate-sounds` branch to regenerate.

Usage: python3 scripts/make_sounds.py <output-dir> [name ...]
With names, only those sounds are made; the rest are left as they are.
Sounds listed in MUSIC are composed with the ElevenLabs Music API, falling
back to the Sound Effects API if music isn't available on the account.
"""
import json
import os
import shutil
import subprocess
import sys
import urllib.error
import urllib.request

SOUNDS = {
    # The pieces: weighted, felt-based pieces on a hardwood board. Close and dry,
    # no glass, no synths, so a game sounds like a fine set on a table.
    "move": ("A single weighted wooden chess piece with a felt base set down on a hardwood "
             "chess board: one soft, clean, satisfying knock. Close-up, dry room, no reverb, "
             "no music", 0.5),
    "select": ("A very quiet, soft tap of a fingertip on a wooden chess piece, barely audible, "
               "close-up, dry, no music", 0.5),
    "capture": ("A wooden chess piece takes another on a hardwood board: one firm knock, then the "
                "taken piece tips over and settles with a soft wooden clatter. Close-up, dry room, "
                "elegant, no glass, no explosion, no music", 0.9),
    "check": ("A weighted wooden chess piece set down firmly on a hardwood board, followed by a "
              "single soft, clear, low bell tone that fades quickly. Elegant and understated, "
              "not alarming, no music", 0.9),
    "castle": ("Two weighted wooden chess pieces with felt bases set down on a hardwood board one "
               "right after the other: two soft knocks a fraction of a second apart. Close-up, "
               "dry room, no music", 0.7),
    "win": ("A triumphant short synthwave victory chime with sparkles", 2.5),
    "game-over": ("A calm descending synth chime signalling the end of a game", 2.2),
    "victory": ("A joyful video game level-complete victory fanfare: a bright rising "
                "melody on shimmering synths and bells, punchy drums, ending on a big "
                "triumphant major chord with sparkles, polished modern mobile game music", 6.0),
    "welcome": ("A short elegant welcoming chime for opening a premium game app: warm "
                "bell and soft synth pad, three gentle rising notes, clean and luxurious", 2.2),
}

# Composed as music rather than as a sound effect: text and length come from SOUNDS.
MUSIC = {"victory"}

# Raised after generating, in dB. The check's bell comes out quieter than a plain move,
# and check is the more important news.
GAIN_DB = {"check": 3.0}


def castle_from_move(out: str) -> bytes | None:
    """Castling is the move knock twice, king then rook, so it always matches the
    move sound. None without ffmpeg, and the castle prompt is used instead."""
    ffmpeg = shutil.which("ffmpeg")
    move = os.path.join(out, "move.mp3")
    if not ffmpeg or not os.path.exists(move):
        return None
    castle = os.path.join(out, "castle-made.mp3")
    subprocess.run([
        ffmpeg, "-hide_banner", "-loglevel", "error", "-y", "-i", move, "-i", move,
        "-filter_complex",
        "[1]adelay=delays=115:all=1,volume=0.8[rook];[0][rook]amix=inputs=2:normalize=0,atrim=0:0.5",
        "-b:a", "128k", castle,
    ], check=True)
    with open(castle, "rb") as f:
        audio = f.read()
    os.remove(castle)
    return audio


def louder(audio: bytes, decibels: float, out: str) -> bytes:
    """`audio` raised by `decibels`. Unchanged without ffmpeg."""
    ffmpeg = shutil.which("ffmpeg")
    if not ffmpeg:
        return audio
    source = os.path.join(out, "gain-in.mp3")
    target = os.path.join(out, "gain-out.mp3")
    with open(source, "wb") as f:
        f.write(audio)
    subprocess.run([
        ffmpeg, "-hide_banner", "-loglevel", "error", "-y", "-i", source,
        "-af", f"volume={decibels}dB", "-ar", "44100", "-b:a", "128k", target,
    ], check=True)
    with open(target, "rb") as f:
        audio = f.read()
    os.remove(source)
    os.remove(target)
    return audio


def generate(text: str, seconds: float, key: str) -> bytes:
    body = json.dumps({
        "text": text,
        "duration_seconds": seconds,
        "prompt_influence": 0.6,
    }).encode()
    request = urllib.request.Request(
        "https://api.elevenlabs.io/v1/sound-generation?output_format=mp3_44100_128",
        data=body,
        headers={"xi-api-key": key, "Content-Type": "application/json", "Accept": "audio/mpeg"},
        method="POST",
    )
    try:
        with urllib.request.urlopen(request, timeout=120) as response:
            return response.read()
    except urllib.error.HTTPError as error:
        detail = error.read().decode(errors="replace")[:500]
        sys.exit(f"ElevenLabs returned {error.code}: {detail}")


def compose(text: str, seconds: float, key: str) -> bytes | None:
    """Music API. None when the account or API can't do it, so the caller falls back."""
    body = json.dumps({
        "prompt": text + ". Instrumental, no vocals.",
        "music_length_ms": int(max(seconds, 3.0) * 1000),
    }).encode()
    request = urllib.request.Request(
        "https://api.elevenlabs.io/v1/music?output_format=mp3_44100_128",
        data=body,
        headers={"xi-api-key": key, "Content-Type": "application/json", "Accept": "audio/mpeg"},
        method="POST",
    )
    try:
        with urllib.request.urlopen(request, timeout=300) as response:
            return response.read()
    except urllib.error.HTTPError as error:
        detail = error.read().decode(errors="replace")[:300]
        print(f"Music API returned {error.code}: {detail}; using sound effects instead")
        return None


def main() -> None:
    out = sys.argv[1]
    only = set(sys.argv[2:])
    unknown = only - set(SOUNDS)
    if unknown:
        sys.exit(f"Unknown sounds: {', '.join(sorted(unknown))}")
    key = os.environ.get("ELEVENLABS_API_KEY")
    if not key:
        sys.exit("ELEVENLABS_API_KEY is not set. Add it as a repository secret.")
    os.makedirs(out, exist_ok=True)
    for name, (text, seconds) in SOUNDS.items():
        if only and name not in only:
            continue
        audio = compose(text, seconds, key) if name in MUSIC else None
        if name == "castle":
            audio = castle_from_move(out)
        if audio is None:
            audio = generate(text, seconds, key)
        if name in GAIN_DB:
            audio = louder(audio, GAIN_DB[name], out)
        with open(os.path.join(out, f"{name}.mp3"), "wb") as f:
            f.write(audio)
        print(f"{name}.mp3: {len(audio)} bytes")


if __name__ == "__main__":
    main()
