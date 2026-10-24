#!/usr/bin/env python3
"""Temporary: designs three more deep male voices for Leo and records the same lines in each."""
import base64, json, os, sys, urllib.request, urllib.error
from pathlib import Path
sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "training"))
from make_narration import request, MODEL, VOICE_SETTINGS, API

KEY = os.environ["ELEVENLABS_API_KEY"]
OUT = Path(__file__).resolve().parents[2] / "design" / "leo-voices"
OUT.mkdir(parents=True, exist_ok=True)
DESIGNS = {
    "titan": "A deep, smooth, powerful baritone male voice in his thirties, American accent. Confident and warm, like a heroic leading man. Rich low tones, clear diction, polished studio quality.",
    "sage": "A deep, calm, wise older male voice in his sixties, American accent. Warm, gravelly bass with gentle authority, unhurried and reassuring, like a legendary mentor. Clean studio recording.",
    "warlord": "A deep, rough, commanding male voice, American accent, forties. Gritty bass with a hard edge, intense and focused like a battlefield general giving orders. Clear, close studio audio.",
}
PREVIEW = ("Leo here. Sit down. We have work to do. Every piece on this board answers to you, "
           "and every mistake will be punished. Look closely. Find the move. Then strike.")
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

made = {}
for name, description in DESIGNS.items():
    try:
        previews = post_json("/text-to-voice/design", {"voice_description": description, "model_id": "eleven_ttv_v3", "text": PREVIEW})["previews"]
        saved = post_json("/text-to-voice", {"voice_name": f"Leo {name}", "voice_description": description,
                                            "generated_voice_id": previews[0]["generated_voice_id"]})
        voice_id = saved["voice_id"]
        audio = request(f"/text-to-speech/{voice_id}?output_format=mp3_44100_128", KEY,
                        {"text": TEXT, "model_id": MODEL, "voice_settings": VOICE_SETTINGS})
    except Exception as e:
        print(name, "failed:", e); continue
    made[name] = voice_id
    (OUT / f"leo-{name}.mp3").write_bytes(audio)
    print(name, voice_id, len(audio))
(OUT / "designed-voices-2.json").write_text(json.dumps(made, indent=2))
