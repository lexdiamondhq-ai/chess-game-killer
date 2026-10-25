import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { test } from "node:test";
import { VERA_VOICE_SETTINGS, VOICE_SETTINGS, speak, toBase64, voiceKey } from "../src/voice.js";

const env = { ELEVENLABS_API_KEY: " xi-test\n", VOICE_ID: "TX3LPaxmHKxFdv7VOQHJ", VOICE_MODEL: "eleven_multilingual_v2" };
const MP3 = new Uint8Array([0xff, 0xfb, 0x90, 0x64, 1, 2, 3]);

/** A stand-in for fetch that records the call and answers with `reply`. */
function fakeFetch(reply = () => new Response(MP3, { headers: { "content-type": "audio/mpeg" } })) {
  const calls = [];
  const fetchImpl = async (url, options) => {
    calls.push({ url, options, body: JSON.parse(options.body) });
    return reply(url, options);
  };
  return { fetchImpl, calls };
}

test("Leo's answer comes back as MP3 bytes, read by Liam with the lessons' settings", async () => {
  const { fetchImpl, calls } = fakeFetch();
  const audio = await speak(env, "  Right about the bishop.  ", fetchImpl);
  assert.deepEqual(audio, MP3);
  assert.equal(calls.length, 1);
  const [{ url, options, body }] = calls;
  assert.equal(url, "https://api.elevenlabs.io/v1/text-to-speech/TX3LPaxmHKxFdv7VOQHJ?output_format=mp3_44100_128");
  assert.equal(options.method, "POST");
  assert.equal(options.headers["xi-api-key"], "xi-test");
  assert.equal(options.headers["content-type"], "application/json");
  assert.ok(options.signal instanceof AbortSignal);
  assert.deepEqual(body, { text: "Right about the bishop.", model_id: "eleven_multilingual_v2", voice_settings: VOICE_SETTINGS });
});

test("without VOICE_ID or VOICE_MODEL it's still Liam on the lessons' model", async () => {
  const { fetchImpl, calls } = fakeFetch();
  await speak({ ELEVENLABS_API_KEY: "k" }, "Hello.", fetchImpl);
  assert.match(calls[0].url, /\/text-to-speech\/TX3LPaxmHKxFdv7VOQHJ\?/);
  assert.equal(calls[0].body.model_id, "eleven_multilingual_v2");
});

test("the voice settings, voice and model are the ones the recorded lessons use", () => {
  const script = readFileSync(new URL("../../scripts/training/make_narration.py", import.meta.url), "utf8");
  const settings = /^VOICE_SETTINGS = (\{.*\})$/m.exec(script)[1].replace(/True/g, "true").replace(/False/g, "false");
  assert.deepEqual(JSON.parse(settings), { ...VOICE_SETTINGS });
  assert.match(script, /^MODEL = "eleven_multilingual_v2"$/m);
  assert.match(script, /"leo":.*\n.*"format": "mp3_44100_128"/);
  assert.match(script, /"TX3LPaxmHKxFdv7VOQHJ"/);
  const toml = readFileSync(new URL("../wrangler.toml", import.meta.url), "utf8");
  assert.match(toml, /^VOICE_ID = "TX3LPaxmHKxFdv7VOQHJ"$/m);
  assert.match(toml, /^VOICE_MODEL = "eleven_multilingual_v2"$/m);
});

test("no key, no text or an odd voice ID: nothing is sent", async () => {
  const { fetchImpl, calls } = fakeFetch();
  assert.equal(await speak({}, "Hello.", fetchImpl), null);
  assert.equal(await speak({ ELEVENLABS_API_KEY: "  " }, "Hello.", fetchImpl), null);
  assert.equal(await speak(env, "   ", fetchImpl), null);
  assert.equal(await speak({ ...env, VOICE_ID: "../../v1/user" }, "Hello.", fetchImpl), null);
  assert.equal(calls.length, 0);
  assert.equal(voiceKey({ ELEVENLABS_API_KEY: " k\n" }), "k");
});

test("a failing, wrong or empty answer from ElevenLabs is no voice, not a crash", async () => {
  const replies = [
    () => new Response(JSON.stringify({ detail: "quota_exceeded" }), { status: 401, headers: { "content-type": "application/json" } }),
    () => new Response("overloaded", { status: 503 }),
    () => new Response(JSON.stringify({ ok: true }), { status: 200, headers: { "content-type": "application/json" } }),
    () => new Response(new Uint8Array(0), { headers: { "content-type": "audio/mpeg" } }),
    () => {
      throw new TypeError("network down");
    },
  ];
  for (const reply of replies) {
    const { fetchImpl } = fakeFetch(reply);
    assert.equal(await speak(env, "Hello.", fetchImpl), null);
  }
});

test("a slow ElevenLabs is given up on", async () => {
  const hanging = (url, options) =>
    new Promise((resolve, reject) => {
      options.signal.addEventListener("abort", () => reject(options.signal.reason));
    });
  // Node doesn't wait for AbortSignal.timeout's timer by itself (Workers do).
  const keepAlive = setTimeout(() => {}, 5000);
  const started = Date.now();
  assert.equal(await speak({ ...env, VOICE_TIMEOUT_MS: "50" }, "Hello.", hanging), null);
  assert.ok(Date.now() - started < 2000);
  clearTimeout(keepAlive);
});

test("base64 matches Node's, also for recordings bigger than one chunk", () => {
  const bytes = new Uint8Array(200_000).map((_, i) => (i * 7) % 256);
  assert.equal(toBase64(bytes), Buffer.from(bytes).toString("base64"));
  assert.equal(toBase64(new Uint8Array(0)), "");
});

test("Vera's answer is read by Sarah, with her lessons' settings", async () => {
  const sent = [];
  const fetchImpl = async (url, init) => {
    sent.push({ url, body: JSON.parse(init.body) });
    return new Response(new Uint8Array([1, 2, 3]), { headers: { "content-type": "audio/mpeg" } });
  };
  const audio = await speak({ ELEVENLABS_API_KEY: "key" }, "Castling is safe.", fetchImpl, "vera");
  assert.deepEqual([...audio], [1, 2, 3]);
  assert.match(sent[0].url, /\/EXAVITQu4vr4xnSDxMaL\?output_format=mp3_44100_128$/);
  assert.deepEqual(sent[0].body.voice_settings, VERA_VOICE_SETTINGS);
  // VERA_VOICE_ID swaps her voice; VOICE_ID stays Leo's.
  await speak({ ELEVENLABS_API_KEY: "key", VOICE_ID: "leoVoice", VERA_VOICE_ID: "veraVoice" }, "Hi.", fetchImpl, "vera");
  assert.match(sent[1].url, /\/veraVoice\?/);
  await speak({ ELEVENLABS_API_KEY: "key", VOICE_ID: "leoVoice", VERA_VOICE_ID: "veraVoice" }, "Hi.", fetchImpl);
  assert.match(sent[2].url, /\/leoVoice\?/);
});

test("the voices match the lesson recordings in make_narration.py", () => {
  const script = readFileSync(new URL("../../scripts/training/make_narration.py", import.meta.url), "utf8");
  assert.match(script, /ELEVENLABS_VERA_VOICE_ID", "EXAVITQu4vr4xnSDxMaL"/);
  assert.match(script, /"stability": 0\.7, "similarity_boost": 0\.85, "style": 0\.0, "use_speaker_boost": True, "speed": 0\.98/);
  assert.match(script, /"format": "mp3_44100_128"/);
});
