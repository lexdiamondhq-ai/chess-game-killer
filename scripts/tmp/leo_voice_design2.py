#!/usr/bin/env python3
"""Temporary: a varied batch of male voices for Leo (premade + designed), same lines in each."""
import json, os, sys, urllib.request, urllib.error
from pathlib import Path
sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "training"))
from make_narration import request, MODEL, VOICE_SETTINGS, API

KEY = os.environ["ELEVENLABS_API_KEY"]
OUT = Path(__file__).resolve().parents[2] / "design" / "leo-voices"
OUT.mkdir(parents=True, exist_ok=True)
PREMADE = {
    "eric": "cjVigY5qzO86Huf0OWal",   # smooth, trustworthy American
    "liam": "TX3LPaxmHKxFdv7VOQHJ",   # young, articulate American
    "will": "bIHbv24MWmeRgasZH58o",   # friendly, relaxed American
    "chris": "iP95p4xoKVk53GoZ742B",  # casual, down-to-earth American
}
DESIGNS = {
    "spark": "An upbeat, energetic male voice in his late twenties, American accent. Bright and encouraging like a great sports coach who loves the game. Quick, clear, smiling delivery. Clean studio audio.",
    "southern": "A warm, friendly male voice in his forties with a light Southern American accent. Easygoing, charming and kind, like a favorite uncle teaching you a game on the porch. Clean studio audio.",
}
PREVIEW = ("Leo here. Pull up a chair, we have work to do. Every piece on this board has a job, "
           "and today you're going to learn exactly what it is. Look closely. Find the move.")
TEXT = ("Leo here. Let's get to work. "
        "Look at the knight on f3. If it moves, your queen is left hanging. "
        "Find the move that keeps everything safe. "
        "Brilliant move! Now that is a move. "
        "Not quite. Have another look.")

def post_json(path, body):
    req = urllib.request.Request(f"{API}{path}", data=json.dumps(body).encode(),
                                 headers={"xi-api-key": KEY, "Content-Type": "application/json"}, method="POST")
    try:
        with urllib.request.urlopen(req, timeout=180) as r:
            return json.loads(r.read())
    except urllib.error.HTTPError as e:
        raise RuntimeError(f"{path} {e.code}: {e.read().decode(errors='replace')[:400]}") from None

voices = dict(PREMADE)
for name, description in DESIGNS.items():
    try:
        previews = post_json("/text-to-voice/design", {"voice_description": description, "model_id": "eleven_ttv_v3", "text": PREVIEW})["previews"]
        voices[name] = post_json("/text-to-voice", {"voice_name": f"Leo {name}", "voice_description": description,
                                                   "generated_voice_id": previews[0]["generated_voice_id"]})["voice_id"]
    except Exception as e:
        print(name, "design failed:", e)
made = {}
for name, voice_id in voices.items():
    try:
        audio = request(f"/text-to-speech/{voice_id}?output_format=mp3_44100_128", KEY,
                        {"text": TEXT, "model_id": MODEL, "voice_settings": VOICE_SETTINGS})
    except Exception as e:
        print(name, "failed:", e); continue
    made[name] = voice_id
    (OUT / f"leo-{name}.mp3").write_bytes(audio)
    print(name, voice_id, len(audio))
(OUT / "voices-round4.json").write_text(json.dumps(made, indent=2))
