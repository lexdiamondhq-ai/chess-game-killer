// The coach's voice: Leo's answer read aloud by Trevor on ElevenLabs, Vera's by
// Sarah, with the same model and settings as their recorded lessons
// (scripts/training/make_narration.py), so the coach in a game sounds like the
// coach in the lessons. When there's no
// key, or ElevenLabs is slow or fails, the app reads the answer with the
// device's voice instead.

const API = "https://api.elevenlabs.io/v1/text-to-speech";
/** Trevor ("TrevorT" in ElevenLabs' voice library): a natural, conversational American man. */
const DEFAULT_VOICE_ID = "69SAlwj2jajrSXUGnYAA";
/** Sarah: a confident, warm young American woman. Vera's voice. */
const DEFAULT_VERA_VOICE_ID = "EXAVITQu4vr4xnSDxMaL";
/** Leo's model, ElevenLabs' newest and most natural (LEO_MODEL in make_narration.py). */
const DEFAULT_VOICE_MODEL = "eleven_v4";
/** Vera's model, which her settings are made for (MODEL in make_narration.py). */
const DEFAULT_VERA_VOICE_MODEL = "eleven_multilingual_v2";
/** Leo's lessons are recorded at 128 kbps too (COACHES["leo"] in make_narration.py). */
const OUTPUT_FORMAT = "mp3_44100_128";
/**
 * Exactly the lessons' settings (VOICE_SETTINGS in make_narration.py): none, so ElevenLabs uses
 * the voice's own, as in the samples Leo's voice was chosen from.
 */
export const VOICE_SETTINGS = null;
/** Vera's lesson settings (COACHES["vera"] in make_narration.py): steady and clean, at 128 kbps. */
export const VERA_VOICE_SETTINGS = Object.freeze({
  stability: 0.7,
  similarity_boost: 0.85,
  style: 0.0,
  use_speaker_boost: true,
  speed: 0.98,
});
const VERA_OUTPUT_FORMAT = "mp3_44100_128";
/**
 * A spoken answer takes ElevenLabs a few seconds (the newest model a little longer); past this,
 * the device's voice is quicker. With Claude's two calls it stays inside the app's 35 s.
 */
const DEFAULT_TIMEOUT_MS = 10000;
/** 320 characters of speech is about 20 seconds, about 160 KB at 64 kbps. Anything far bigger is wrong. */
const MAX_AUDIO_BYTES = 2 * 1024 * 1024;

/** The ElevenLabs key without stray spaces or line breaks from pasting it into a secret. */
export function voiceKey(env) {
  return String((env && env.ELEVENLABS_API_KEY) || "").trim();
}

/**
 * The coach ("leo" or "vera") saying `text`, as MP3 bytes. Null when there's no key, or when
 * ElevenLabs fails, answers with something that isn't audio, or takes longer
 * than VOICE_TIMEOUT_MS (10 s; tests shorten it).
 */
export async function speak(env, text, fetchImpl = fetch, coach = "leo") {
  const key = voiceKey(env);
  const words = String(text || "").trim();
  if (!key || !words) return null;
  const { vera, voice, model } = voiceChoice(env, coach);
  // The voice goes into the address, so only a plain ID is used.
  if (!/^[A-Za-z0-9]{1,64}$/.test(voice)) {
    console.error("voice: VOICE_ID isn't a plain voice ID");
    return null;
  }
  const timeout = Number(env.VOICE_TIMEOUT_MS) > 0 ? Number(env.VOICE_TIMEOUT_MS) : DEFAULT_TIMEOUT_MS;
  const settings = vera ? VERA_VOICE_SETTINGS : VOICE_SETTINGS;
  const body = { text: words, model_id: model };
  if (settings) body.voice_settings = settings;
  try {
    const response = await fetchImpl(`${API}/${voice}?output_format=${vera ? VERA_OUTPUT_FORMAT : OUTPUT_FORMAT}`, {
      method: "POST",
      headers: { "xi-api-key": key, "content-type": "application/json", accept: "audio/mpeg" },
      body: JSON.stringify(body),
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

/** Which voice and model read for this coach. */
function voiceChoice(env, coach) {
  const vera = coach === "vera";
  const voice = String(vera ? env.VERA_VOICE_ID || DEFAULT_VERA_VOICE_ID : env.VOICE_ID || DEFAULT_VOICE_ID).trim();
  // VOICE_MODEL is Leo's; Vera keeps the model her settings are made for. TALK_VOICE_MODEL, when
  // set, reads every live answer with a cheaper model instead: the lessons are recorded once,
  // but Talk pays per character on every answer.
  const lessonModel = vera ? env.VERA_VOICE_MODEL || DEFAULT_VERA_VOICE_MODEL : env.VOICE_MODEL || DEFAULT_VOICE_MODEL;
  const model = String(env.TALK_VOICE_MODEL || lessonModel).trim();
  return { vera, voice, model };
}

/**
 * The name a recording of `text` is kept under: the voice, model and exact words, hashed. Any
 * change to the voice or model gives new names, so an old recording is never played by mistake.
 */
export async function recordingKey(env, text, coach = "leo") {
  const { vera, voice, model } = voiceChoice(env, coach);
  const settings = JSON.stringify(vera ? VERA_VOICE_SETTINGS : VOICE_SETTINGS);
  const words = String(text || "").trim();
  const digest = await crypto.subtle.digest("SHA-256", new TextEncoder().encode(`${voice}|${model}|${settings}|${words}`));
  return [...new Uint8Array(digest)].map((byte) => byte.toString(16).padStart(2, "0")).join("");
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

/**
 * The pass for hearing one answer later, with POST /speak: an HMAC of the coach and the exact
 * words, keyed by the ElevenLabs key itself. Only words this server answered can be read aloud,
 * so /speak is never a free voice for anyone who finds the address. Null without a key.
 */
export async function hearToken(env, text, coach = "leo") {
  const key = await hearKey(env);
  if (!key) return null;
  const signature = await crypto.subtle.sign("HMAC", key, hearMessage(text, coach));
  return toBase64(new Uint8Array(signature));
}

/** True when `token` is hearToken's pass for these words and this coach (compared in constant time). */
export async function checkHearToken(env, text, coach, token) {
  const key = await hearKey(env);
  if (!key || typeof token !== "string" || token.length === 0 || token.length > 100) return false;
  let signature;
  try {
    signature = Uint8Array.from(atob(token), (character) => character.charCodeAt(0));
  } catch {
    return false;
  }
  return crypto.subtle.verify("HMAC", key, signature, hearMessage(text, coach));
}

function hearMessage(text, coach) {
  return new TextEncoder().encode(`hear|v1|${coach === "vera" ? "vera" : "leo"}|${String(text || "").trim()}`);
}

async function hearKey(env) {
  const secret = voiceKey(env);
  if (!secret) return null;
  return crypto.subtle.importKey("raw", new TextEncoder().encode(secret), { name: "HMAC", hash: "SHA-256" }, false, [
    "sign",
    "verify",
  ]);
}
