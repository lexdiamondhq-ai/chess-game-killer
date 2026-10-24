#!/usr/bin/env python3
"""Temporary: designs very deep, dark voices for Leo with ElevenLabs Voice Design,
saves them to the account, and records the same Leo lines in each."""
import base64, json, os, sys
from pathlib import Path
sys.path.insert(0, str(Path(__file__).parent))
from make_narration import request, MODEL, VOICE_SETTINGS, API
import urllib.request, urllib.error

KEY = os.environ["ELEVENLABS_API_KEY"]
OUT = Path(__file__).resolve().parents[2] / "design" / "leo-voices"
OUT.mkdir(parents=True, exist_ok=True)

DESIGNS = {
    "dark-lord": "An extremely deep, dark, commanding male voice with heavy resonant bass. Slow, deliberate, menacing authority, like an imposing armored villain from a space opera. American accent, calm and controlled, perfect studio quality.",
    "abyss": "A very low, gravelly bass male voice, dark and ominous, middle-aged, American accent. Speaks slowly with enormous gravitas, like a cinematic movie trailer narrator. Clean, close studio audio.",
    "monolith": "A deep bass male voice, cold and powerful, intimidating but composed, American accent. Rich chest resonance, slow measured delivery, every word heavy. Crisp professional studio recording.",
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
        result = post_json("/text-to-voice/design", {"voice_description": description, "model_id": "eleven_ttv_v3", "text": PREVIEW})
    except RuntimeError as e:
        print("design failed, trying create-previews:", e)
        try:
            result = post_json("/text-to-voice/create-previews", {"voice_description": description, "text": PREVIEW})
        except RuntimeError as e2:
            print(name, "failed:", e2); continue
    previews = result.get("previews") or []
    for i, p in enumerate(previews):
        (OUT / f"preview-{name}-{i + 1}.mp3").write_bytes(base64.b64decode(p["audio_base_64"]))
    if not previews:
        print(name, "no previews"); continue
    try:
        saved = post_json("/text-to-voice", {"voice_name": f"Leo {name}", "voice_description": description,
                                            "generated_voice_id": previews[0]["generated_voice_id"]})
    except RuntimeError as e:
        print(name, "save failed:", e); continue
    voice_id = saved["voice_id"]
    made[name] = voice_id
    audio = request(f"/text-to-speech/{voice_id}?output_format=mp3_44100_128", KEY,
                    {"text": TEXT, "model_id": MODEL, "voice_settings": VOICE_SETTINGS})
    (OUT / f"leo-{name}.mp3").write_bytes(audio)
    print(name, voice_id, len(audio))
(OUT / "designed-voices.json").write_text(json.dumps(made, indent=2))
