#!/usr/bin/env python3
"""Temporary: records Monolith (Leo's new voice) with a few tuned settings."""
import os, sys
from pathlib import Path
sys.path.insert(0, str(Path(__file__).parent))
from make_narration import request, MODEL

VOICE = "1b0g3hQZNdyIitkZW5BL"
VARIANTS = {
    "clean": {"stability": 0.65, "similarity_boost": 0.9, "style": 0.0, "use_speaker_boost": True, "speed": 0.95},
    "rich": {"stability": 0.5, "similarity_boost": 0.9, "style": 0.2, "use_speaker_boost": True, "speed": 0.93},
    "steady": {"stability": 0.8, "similarity_boost": 0.95, "style": 0.0, "use_speaker_boost": True, "speed": 0.97},
}
TEXT = ("Leo here. Let's get to work. "
        "Look at the knight on f3. If it moves, your queen is left hanging. "
        "Find the move that keeps everything safe. "
        "Brilliant move! Now that is a move. "
        "Not quite. Have another look.")
out = Path(__file__).resolve().parents[2] / "design" / "leo-voices"
key = os.environ["ELEVENLABS_API_KEY"]
for name, settings in VARIANTS.items():
    audio = request(f"/text-to-speech/{VOICE}?output_format=mp3_44100_192", key,
                    {"text": TEXT, "model_id": MODEL, "voice_settings": settings})
    (out / f"monolith-{name}.mp3").write_bytes(audio)
    print(name, len(audio))
