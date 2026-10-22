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
import sys
import urllib.error
import urllib.request

SOUNDS = {
    "move": ("A single crisp click of a glass chess piece set down on a glass board, "
             "clean and satisfying, with a faint electronic shimmer", 0.6),
    "select": ("A very soft, subtle glassy UI tick, minimal and quiet", 0.5),
    "capture": ("A short punchy neon energy explosion, glass shattering into sparkling "
                "synth particles, satisfying, cinematic but not too loud", 1.2),
    "check": ("A tense futuristic synth alert, two quick rising notes, clean", 0.8),
    "castle": ("Two quick glass chess piece clicks in a row with a soft synth whoosh", 0.9),
    "game-start": ("A short uplifting futuristic neon power-up swell, clean synthwave", 1.6),
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
        if audio is None:
            audio = generate(text, seconds, key)
        with open(os.path.join(out, f"{name}.mp3"), "wb") as f:
            f.write(audio)
        print(f"{name}.mp3: {len(audio)} bytes")


if __name__ == "__main__":
    main()
