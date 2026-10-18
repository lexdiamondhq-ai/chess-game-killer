"""Generates the game's sound effects with the ElevenLabs Sound Effects API.

Runs in GitHub Actions (.github/workflows/sounds.yml) with the
ELEVENLABS_API_KEY repository secret. Edit SOUNDS to change a sound,
then push to the `generate-sounds` branch to regenerate.

Usage: python3 scripts/make_sounds.py <output-dir>
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
}


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


def main() -> None:
    out = sys.argv[1]
    key = os.environ.get("ELEVENLABS_API_KEY")
    if not key:
        sys.exit("ELEVENLABS_API_KEY is not set. Add it as a repository secret.")
    os.makedirs(out, exist_ok=True)
    for name, (text, seconds) in SOUNDS.items():
        audio = generate(text, seconds, key)
        with open(os.path.join(out, f"{name}.mp3"), "wb") as f:
            f.write(audio)
        print(f"{name}.mp3: {len(audio)} bytes")


if __name__ == "__main__":
    main()
