"""Generates the game's sound effects with the ElevenLabs Sound Effects API.

Runs in GitHub Actions (.github/workflows/sounds.yml) with the
ELEVENLABS_API_KEY repository secret. Edit SOUNDS to change a sound,
then push to the `generate-sounds` branch to regenerate.

Usage: python3 scripts/make_sounds.py <output-dir> [name ...]
With names, only those sounds are made; the rest are left as they are.
       python3 scripts/make_sounds.py --tidy <output-dir> [name ...]
tidies the files already there (see tidy) without calling ElevenLabs.
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
    "check": ("A heavy weighted wooden chess piece with a felt base set down firmly on a thick "
              "hardwood board, followed by two quick, warm, low bronze bell notes, the second a "
              "step lower, fading quickly. Elegant, serious, no music", 1.2),
    "castle": ("Two weighted wooden chess pieces with felt bases set down on a hardwood board one "
               "right after the other: two soft knocks a fraction of a second apart. Close-up, "
               "dry room, no music", 0.7),
    # Deeper, more vibrant (Alex, 2026-11-10): move, capture and castle in the app are these
    # takes made two semitones lower with more warmth and sparkle and a small wooden room:
    #   asetrate=44100*0.891,aresample=44100,atempo=1.122,bass=g=5:f=140,
    #   equalizer=f=2800:t=q:w=1:g=2.5,aecho=0.8:0.5:28|46:0.18|0.10
    # brought back to the old files' loudness, then tidied. check.mp3 is the take above with
    # bass=g=3:f=140, equalizer=f=2800:t=q:w=1:g=1.5 and the same small room. A fresh take of
    # any of them needs that chain again.
    # The endings: warm and acoustic like the pieces, never arcade synths.
    "win": ("A short, elegant success chime: three warm rising notes on a soft celesta and a "
            "felt piano, a gentle shimmer at the end. Clean, luxurious, understated, no synths, "
            "no drums", 2.2),
    "game-over": ("The end of a chess game: two soft, warm, descending notes on a felt piano with "
                  "a low cello underneath, calm and dignified, not sad, quickly fading. No synths, "
                  "no drums", 2.2),
    # defeat.mp3 (a loss) is not made here: it is two takes blended by hand, two distant
    # funeral bell tolls ("Two slow tolls of a huge low iron funeral bell, far away across a
    # misty valley...") over a short low requiem choir at 75% ("A brief dark choral requiem:
    # a low wordless choir sings one slow descending minor phrase over deep strings..."),
    # then tidied to CUE_LUFS. game-over.mp3 is kept for draws.
    "victory": ("A joyful video game level-complete victory fanfare: a bright rising "
                "melody on shimmering synths and bells, punchy drums, ending on a big "
                "triumphant major chord with sparkles, polished modern mobile game music", 6.0),
    "welcome": ("A short elegant welcoming chime for opening a premium game app: warm "
                "bell and soft synth pad, three gentle rising notes, clean and luxurious", 2.2),
    # Background music, in the family of Home's "The Long Winter" (cello, strings, choir):
    # quiet, even loops that sit under the screen without a climax.
    "music-puzzles": ("Calm, focused medieval fantasy orchestral underscore, seamless as a background "
                      "loop: soft pizzicato strings and a gentle harp ostinato, a low sustained cello "
                      "drone, sparse solo violin phrases in a minor key, no drums. Slow steady tempo "
                      "around 66 BPM, thoughtful and concentrated, very quiet and even with no climax",
                      90.0),
    "music-training": ("Warm, hopeful medieval fantasy orchestral underscore, seamless as a background "
                       "loop to sit under a spoken voice: soft string pads, a gentle solo cello melody "
                       "in a major-leaning mode, light celesta and harp touches, nothing in the "
                       "midrange that competes with speech, no drums. Slow tempo around 68 BPM, "
                       "encouraging and patient, very soft and even", 90.0),
    "music-analyze": ("Mysterious, contemplative medieval fantasy orchestral underscore, seamless as a "
                      "background loop: slow low strings, a distant french horn, a hushed wordless "
                      "choir pad, soft timpani rolls far in the background, a solo viola line in a "
                      "minor key. Very slow tempo around 60 BPM, deep and pondering, like studying an "
                      "old map by candlelight, quiet throughout", 90.0),
}

# Composed as music rather than as a sound effect: text and length come from SOUNDS.
MUSIC = {"victory", "music-puzzles", "music-training", "music-analyze"}

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


# The longer cues are all brought to this loudness, so GameSound.volume alone sets how they
# sit against each other and a regenerated file never comes out much louder or quieter.
CUE_LUFS = -16.0
# ...without their peaks going past this.
CUE_PEAK_DB = -1.0


def loudness(path: str) -> tuple[float, float] | None:
    """Integrated loudness (LUFS) and true peak (dBFS) of a file, by ffmpeg's EBU R128 meter."""
    ffmpeg = shutil.which("ffmpeg")
    if not ffmpeg:
        return None
    meter = subprocess.run([
        ffmpeg, "-hide_banner", "-nostats", "-i", path, "-af", "ebur128=peak=true", "-f", "null", "-",
    ], capture_output=True, text=True)
    summary = meter.stderr.rsplit("Summary:", 1)[-1]
    level = peak = None
    for line in summary.splitlines():
        words = line.split()
        if len(words) >= 2 and words[0] == "I:":
            level = float(words[1])
        if len(words) >= 2 and words[0] == "Peak:":
            peak = float(words[1])
    if level is None or peak is None:
        return None
    return level, peak


def tidy(audio: bytes, out: str, knock: bool) -> bytes:
    """Starts the sound on its first real sample, so a piece is heard the instant it lands
    (the generated files open with a few hundredths of a second of near silence, and the
    victory theme with a third of a second), with a 4 ms fade in and a short fade out so
    nothing clicks. A longer cue is also brought to CUE_LUFS. Unchanged without ffmpeg."""
    ffmpeg = shutil.which("ffmpeg")
    if not ffmpeg:
        return audio
    source = os.path.join(out, "tidy-in.mp3")
    target = os.path.join(out, "tidy-out.mp3")
    with open(source, "wb") as f:
        f.write(audio)
    tail = 0.03 if knock else 0.25
    gain = ""
    measured = None if knock else loudness(source)
    if measured:
        level, peak = measured
        change = min(CUE_LUFS - level, CUE_PEAK_DB - peak)
        if abs(change) >= 0.5:
            gain = f"volume={change:.1f}dB,"
    chain = (
        "silenceremove=start_periods=1:start_threshold=-52dB:start_silence=0.002,"
        f"{gain}"
        "afade=t=in:d=0.004,"
        # A fade out on the last stretch: reversed, it is a fade in.
        f"areverse,silenceremove=start_periods=1:start_threshold=-70dB,afade=t=in:d={tail},areverse"
    )
    subprocess.run([
        ffmpeg, "-hide_banner", "-loglevel", "error", "-y", "-i", source,
        "-af", chain, "-ar", "44100", "-b:a", "128k", target,
    ], check=True)
    with open(target, "rb") as f:
        audio = f.read()
    os.remove(source)
    os.remove(target)
    return audio


# The short knocks of the pieces; everything else is a longer cue.
KNOCKS = {"move", "select", "capture", "check", "castle"}


def tidy_files(out: str, only: set[str]) -> None:
    for name in SOUNDS:
        if only and name not in only:
            continue
        path = os.path.join(out, f"{name}.mp3")
        if not os.path.exists(path):
            continue
        with open(path, "rb") as f:
            audio = tidy(f.read(), out, name in KNOCKS)
        with open(path, "wb") as f:
            f.write(audio)
        print(f"{name}.mp3 tidied: {len(audio)} bytes")


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
    args = sys.argv[1:]
    tidy_only = bool(args) and args[0] == "--tidy"
    if tidy_only:
        args = args[1:]
    out = args[0]
    only = set(args[1:])
    unknown = only - set(SOUNDS)
    if unknown:
        sys.exit(f"Unknown sounds: {', '.join(sorted(unknown))}")
    if tidy_only:
        tidy_files(out, only)
        return
    key = os.environ.get("ELEVENLABS_API_KEY")
    if not key:
        sys.exit("ELEVENLABS_API_KEY is not set. Add it as a repository secret.")
    os.makedirs(out, exist_ok=True)
    for name, (text, seconds) in SOUNDS.items():
        if only and name not in only:
            continue
        audio = compose(text, seconds, key) if name in MUSIC else None
        if audio is None and name.startswith("music-"):
            # Skipped rather than stopping, so the pieces already composed still get committed.
            print(f"{name}: skipped, the Music API is needed for background music")
            continue
        if name == "castle":
            audio = castle_from_move(out)
        if audio is None:
            audio = generate(text, seconds, key)
        if name in GAIN_DB:
            audio = louder(audio, GAIN_DB[name], out)
        audio = tidy(audio, out, name in KNOCKS)
        with open(os.path.join(out, f"{name}.mp3"), "wb") as f:
            f.write(audio)
        print(f"{name}.mp3: {len(audio)} bytes")


if __name__ == "__main__":
    main()
