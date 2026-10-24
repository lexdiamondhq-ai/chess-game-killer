#!/usr/bin/env python3
"""Temporary: records the same few Leo lines in each candidate voice so Alex can pick one."""
import os, sys
from pathlib import Path
sys.path.insert(0, str(Path(__file__).parent))
from make_narration import request, MODEL, VOICE_SETTINGS

CANDIDATES = {
    "brian": "nPczCjzI2devNBz1zQrb",  # deep, resonant American narrator
    "adam": "pNInz6obpgDQGcFmaJgB",   # deep, firm American
    "bill": "pqHfZKP75CyOlxRVxLKf",   # older, wise American
}
TEXT = ("Leo here. Let's get to work. "
        "Look at the knight on f3. If it moves, your queen is left hanging. "
        "Find the move that keeps everything safe. "
        "Brilliant move! Now that is a move. "
        "Not quite. Have another look.")
out = Path(__file__).resolve().parents[2] / "design" / "leo-voices"
out.mkdir(parents=True, exist_ok=True)
key = os.environ["ELEVENLABS_API_KEY"]
for name, voice in CANDIDATES.items():
    audio = request(f"/text-to-speech/{voice}?output_format=mp3_44100_128", key,
                    {"text": TEXT, "model_id": MODEL, "voice_settings": VOICE_SETTINGS})
    (out / f"leo-{name}.mp3").write_bytes(audio)
    print(name, len(audio))
