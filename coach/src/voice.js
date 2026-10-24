// The coach's voice: Leo's answer read aloud by Liam on ElevenLabs, Vera's by
// Sarah, with the same model and settings as their recorded lessons
// (scripts/training/make_narration.py), so the coach in a game sounds like the
// coach in the lessons. When there's no
// key, or ElevenLabs is slow or fails, the app reads the answer with the
// device's voice instead.

const API = "https://api.elevenlabs.io/v1/text-to-speech";
/** Liam: a young, articulate American man. */
const DEFAULT_VOICE_ID = "TX3LPaxmHKxFdv7VOQHJ";
/** Sarah: a confident, warm young American woman. Vera's voice. */
const DEFAULT_VERA_VOICE_ID = "EXAVITQu4vr4xnSDxMaL";
const DEFAULT_VOICE_MODEL = "eleven_multilingual_v2";
/** Leo's lessons are recorded at 128 kbps too (COACHES["leo"] in make_narration.py). */
const OUTPUT_FORMAT = "mp3_44100_128";
/** Exactly the lessons' settings (VOICE_SETTINGS in make_narration.py). */
export const VOICE_SETTINGS = Object.freeze({
  stability: 0.65,
  similarity_boost: 0.9,
  style: 0.0,
  use_speaker_boost: true,
  speed: 0.95,
});
/** Vera's lesson settings (COACHES["vera"] in make_narration.py): steady and clean, at 128 kbps. */
export const VERA_VOICE_SETTINGS = Object.freeze({
  stability: 0.7,
  similarity_boost: 0.85,
  style: 0.0,
  use_speaker_boost: true,
  speed: 0.98,
});
const VERA_OUTPUT_FORMAT = "mp3_44100_128";
/** A spoken answer takes ElevenLabs a second or two; past this, the device's voice is quicker. */
const DEFAULT_TIMEOUT_MS = 8000;
/** 320 characters of speech is about 20 seconds, about 160 KB at 64 kbps. Anything far bigger is wrong. */
const MAX_AUDIO_BYTES = 2 * 1024 * 1024;

/** The ElevenLabs key without stray spaces or line breaks from pasting it into a secret. */
export function voiceKey(env) {
  return String((env && env.ELEVENLABS_API_KEY) || "").trim();
}

/**
 * The coach ("leo" or "vera") saying `text`, as MP3 bytes. Null when there's no key, or when
 * ElevenLabs fails, answers with something that isn't audio, or takes longer
 * than VOICE_TIMEOUT_MS (8 s; tests shorten it).
 */
export async function speak(env, text, fetchImpl = fetch, coach = "leo") {
  const key = voiceKey(env);
  const words = String(text || "").trim();
  if (!key || !words) return null;
  const vera = coach === "vera";
  const voice = String(vera ? env.VERA_VOICE_ID || DEFAULT_VERA_VOICE_ID : env.VOICE_ID || DEFAULT_VOICE_ID).trim();
  // The voice goes into the address, so only a plain ID is used.
  if (!/^[A-Za-z0-9]{1,64}$/.test(voice)) {
    console.error("voice: VOICE_ID isn't a plain voice ID");
    return null;
  }
  const timeout = Number(env.VOICE_TIMEOUT_MS) > 0 ? Number(env.VOICE_TIMEOUT_MS) : DEFAULT_TIMEOUT_MS;
  try {
    const response = await fetchImpl(`${API}/${voice}?output_format=${vera ? VERA_OUTPUT_FORMAT : OUTPUT_FORMAT}`, {
      method: "POST",
      headers: { "xi-api-key": key, "content-type": "application/json", accept: "audio/mpeg" },
      body: JSON.stringify({
        text: words,
        model_id: String(env.VOICE_MODEL || DEFAULT_VOICE_MODEL).trim(),
        voice_settings: vera ? VERA_VOICE_SETTINGS : VOICE_SETTINGS,
      }),
      signal: AbortSignal.timeout(timeout),
    });
    const type = (response.headers.get("content-type") || "").toLowerCase();
    if (!response.ok || !type.startsWith("audio/")) {
      // Only the status: the body can echo the text.
      console.error(`voice: ElevenLabs answered ${response.status} ${type.split(";")[0]}`);
      await response.body?.cancel().catch(() => {});
      return null;
    }
    const bytes = new Uint8Array(await response.arrayBuffer());
    if (bytes.length === 0 || bytes.length > MAX_AUDIO_BYTES) {
      console.error(`voice: ElevenLabs sent ${bytes.length} bytes`);
      return null;
    }
    return bytes;
  } catch (error) {
    const timedOut = error && (error.name === "TimeoutError" || error.name === "AbortError");
    console.error(`voice: ${timedOut ? "timed out" : "failed"}`);
    return null;
  }
}

/** Base64 without Node's Buffer, in chunks so long recordings don't overflow the call stack. */
export function toBase64(bytes) {
  let binary = "";
  const chunk = 0x8000;
  for (let i = 0; i < bytes.length; i += chunk) {
    binary += String.fromCharCode.apply(null, bytes.subarray(i, i + chunk));
  }
  return btoa(binary);
}
