import assert from "node:assert/strict";
import { readFileSync, readdirSync } from "node:fs";
import { test } from "node:test";
import { VERA_VOICE_SETTINGS, VOICE_SETTINGS, speak, toBase64, voiceKey } from "../src/voice.js";

const env = { ELEVENLABS_API_KEY: " xi-test\n", VOICE_ID: "69SAlwj2jajrSXUGnYAA", VOICE_MODEL: "eleven_v4" };
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

test("Leo's answer comes back as MP3 bytes, read by Trevor with the lessons' model and the voice's own settings", async () => {
  const { fetchImpl, calls } = fakeFetch();
  const audio = await speak(env, "  Right about the bishop.  ", fetchImpl);
  assert.deepEqual(audio, MP3);
  assert.equal(calls.length, 1);
  const [{ url, options, body }] = calls;
  assert.equal(url, "https://api.elevenlabs.io/v1/text-to-speech/69SAlwj2jajrSXUGnYAA?output_format=mp3_44100_128");
  assert.equal(options.method, "POST");
  assert.equal(options.headers["xi-api-key"], "xi-test");
  assert.equal(options.headers["content-type"], "application/json");
  assert.ok(options.signal instanceof AbortSignal);
  // No settings: the voice's own, as in the samples it was chosen from.
  assert.deepEqual(body, { text: "Right about the bishop.", model_id: "eleven_v4" });
});

test("without VOICE_ID or VOICE_MODEL it's still Trevor on the lessons' model", async () => {
  const { fetchImpl, calls } = fakeFetch();
  await speak({ ELEVENLABS_API_KEY: "k" }, "Hello.", fetchImpl);
  assert.match(calls[0].url, /\/text-to-speech\/69SAlwj2jajrSXUGnYAA\?/);
  assert.equal(calls[0].body.model_id, "eleven_v4");
  assert.equal("voice_settings" in calls[0].body, false);
});

test("the voice settings, voice and model are the ones the recorded lessons use", () => {
  const script = readFileSync(new URL("../../scripts/training/make_narration.py", import.meta.url), "utf8");
  assert.equal(VOICE_SETTINGS, null);
  assert.match(script, /^VOICE_SETTINGS = None$/m);
  assert.match(script, /^LEO_MODEL = "eleven_v4"$/m);
  assert.match(script, /"leo":.*\n.*"model": LEO_MODEL, "settings": VOICE_SETTINGS, "format": "mp3_44100_128"/);
  assert.match(script, /"69SAlwj2jajrSXUGnYAA"/);
  const toml = readFileSync(new URL("../wrangler.toml", import.meta.url), "utf8");
  assert.match(toml, /^VOICE_ID = "69SAlwj2jajrSXUGnYAA"$/m);
  assert.match(toml, /^VOICE_MODEL = "eleven_v4"$/m);
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
  assert.equal(sent[0].body.model_id, "eleven_multilingual_v2");
  // VERA_VOICE_ID swaps her voice; VOICE_ID and VOICE_MODEL stay Leo's.
  const both = { ELEVENLABS_API_KEY: "key", VOICE_ID: "leoVoice", VOICE_MODEL: "eleven_v4", VERA_VOICE_ID: "veraVoice" };
  await speak(both, "Hi.", fetchImpl, "vera");
  assert.match(sent[1].url, /\/veraVoice\?/);
  assert.equal(sent[1].body.model_id, "eleven_multilingual_v2");
  await speak(both, "Hi.", fetchImpl);
  assert.match(sent[2].url, /\/leoVoice\?/);
  assert.equal(sent[2].body.model_id, "eleven_v4");
});

test("the voices match the lesson recordings in make_narration.py", () => {
  const script = readFileSync(new URL("../../scripts/training/make_narration.py", import.meta.url), "utf8");
  assert.match(script, /ELEVENLABS_VERA_VOICE_ID", "EXAVITQu4vr4xnSDxMaL"/);
  assert.match(script, /^MODEL = "eleven_multilingual_v2"$/m);
  assert.match(script, /"model": MODEL, "settings": \{"stability": 0\.7/);
  assert.match(script, /"stability": 0\.7, "similarity_boost": 0\.85, "style": 0\.0, "use_speaker_boost": True, "speed": 0\.98/);
  assert.match(script, /"format": "mp3_44100_128"/);
});

test("every lesson recording is in the voice its coach speaks with now", () => {
  // scripts/training/narration-voices.json keeps the voice and model of each recording. A coach
  // given a new voice is recorded again by .github/workflows/narration.yml; until that run has
  // committed the new files, this fails, so a half-switched voice can't go unnoticed.
  const voices = JSON.parse(readFileSync(new URL("../../scripts/training/narration-voices.json", import.meta.url), "utf8"));
  const toml = readFileSync(new URL("../wrangler.toml", import.meta.url), "utf8");
  const leo = `${/^VOICE_ID = "(\w+)"$/m.exec(toml)[1]} ${/^VOICE_MODEL = "(\w+)"$/m.exec(toml)[1]}`;
  const vera = "EXAVITQu4vr4xnSDxMaL eleven_multilingual_v2";
  const files = readdirSync(new URL("../../ChessGameKiller/Training/Narration/", import.meta.url)).filter((name) => name.endsWith(".mp3"));
  assert.ok(files.length > 400, `only ${files.length} recordings`);
  for (const file of files) {
    const coach = file.startsWith("nar-") ? leo : file.startsWith("vera-") ? vera : null;
    assert.ok(coach, `${file} is neither Leo's nor Vera's`);
    assert.equal(voices[file], coach, `${file} was recorded in another voice`);
  }
});
