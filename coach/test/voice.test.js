import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { test } from "node:test";
import { VOICE_SETTINGS, speak, toBase64, voiceKey } from "../src/voice.js";

const env = { ELEVENLABS_API_KEY: " xi-test\n", VOICE_ID: "JBFqnCBsd6RMkjVDRZzb", VOICE_MODEL: "eleven_multilingual_v2" };
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

test("Leo's answer comes back as MP3 bytes, read by George with the lessons' settings", async () => {
  const { fetchImpl, calls } = fakeFetch();
  const audio = await speak(env, "  Right about the bishop.  ", fetchImpl);
  assert.deepEqual(audio, MP3);
  assert.equal(calls.length, 1);
  const [{ url, options, body }] = calls;
  assert.equal(url, "https://api.elevenlabs.io/v1/text-to-speech/JBFqnCBsd6RMkjVDRZzb?output_format=mp3_44100_64");
  assert.equal(options.method, "POST");
  assert.equal(options.headers["xi-api-key"], "xi-test");
  assert.equal(options.headers["content-type"], "application/json");
  assert.ok(options.signal instanceof AbortSignal);
  assert.deepEqual(body, { text: "Right about the bishop.", model_id: "eleven_multilingual_v2", voice_settings: VOICE_SETTINGS });
});

test("without VOICE_ID or VOICE_MODEL it's still George on the lessons' model", async () => {
  const { fetchImpl, calls } = fakeFetch();
  await speak({ ELEVENLABS_API_KEY: "k" }, "Hello.", fetchImpl);
  assert.match(calls[0].url, /\/text-to-speech\/JBFqnCBsd6RMkjVDRZzb\?/);
  assert.equal(calls[0].body.model_id, "eleven_multilingual_v2");
});

test("the voice settings, voice and model are the ones the recorded lessons use", () => {
  const script = readFileSync(new URL("../../scripts/training/make_narration.py", import.meta.url), "utf8");
  const settings = /^VOICE_SETTINGS = (\{.*\})$/m.exec(script)[1].replace(/True/g, "true").replace(/False/g, "false");
  assert.deepEqual(JSON.parse(settings), { ...VOICE_SETTINGS });
  assert.match(script, /^MODEL = "eleven_multilingual_v2"$/m);
  assert.match(script, /^OUTPUT_FORMAT = "mp3_44100_64"$/m);
  assert.match(script, /"JBFqnCBsd6RMkjVDRZzb"/);
  const toml = readFileSync(new URL("../wrangler.toml", import.meta.url), "utf8");
  assert.match(toml, /^VOICE_ID = "JBFqnCBsd6RMkjVDRZzb"$/m);
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
