import assert from "node:assert/strict";
import { test } from "node:test";
import Anthropic from "@anthropic-ai/sdk";
import { MAX_ANSWER, buildAnswerRequest, coachPrompt, guardAnswer, templateAnswer, wordAnswer } from "../src/answer.js";

// The checked facts in plain words, as verify.js writes them. The player is
// Black: White's bishop on d3 aims at h7, and the knight on f6 isn't safe.
const spoken = {
  player: "black",
  said: "his bishop eyes h7 so h6, and my knight on g5 is safe",
  right: ["The bishop on d3 does aim at h7."],
  wrong: ["Your knight on f6 isn't safe: the pawn on e5 can take it."],
  partly: [],
  unclear: [],
  move: "Pushing to h6 is a good move.",
  missed: [],
  habit: "You named their threat before choosing your move.",
  nudge: null,
};
const checked = { understood: true, player: "black", claims: [], missed: [] };
const DIDNT_CATCH = "I didn't catch a plan there. Tell me what you see, and the move you want.";

/** Mutes the expected console.error lines of a test. */
function quiet(t) {
  t.mock.method(console, "error", () => {});
}

function message(text, extra = {}) {
  return {
    id: "msg_test",
    type: "message",
    role: "assistant",
    model: "claude-opus-5-5",
    stop_reason: "end_turn",
    content: [
      { type: "thinking", thinking: "", signature: "sig" },
      { type: "text", text },
    ],
    usage: { input_tokens: 400, output_tokens: 60 },
    ...extra,
  };
}

/** A stand-in for the Anthropic client: records each call and answers with `reply`. */
function fakeClient(reply) {
  const calls = [];
  return {
    calls,
    beta: {
      messages: {
        create: async (params, options) => {
          calls.push({ params, options });
          return typeof reply === "function" ? reply(params, options) : reply;
        },
      },
    },
  };
}

// ---------------------------------------------------------------------------
// guardAnswer

test("the guard passes plain spoken words that name only checked squares", () => {
  const answer = "Right about the bishop eyeing h7. But your knight on f6 isn't safe: the e5 pawn can take it.";
  assert.equal(guardAnswer(answer, spoken), answer);
  assert.equal(guardAnswer("Good eye on H7.", spoken), "Good eye on H7.");
  assert.equal(guardAnswer("Mate in 2 is coming, so look again.", spoken), "Mate in 2 is coming, so look again.");
});

test("the guard turns down move notation in every form", () => {
  for (const answer of [
    "Play Bxh7+ now.",
    "Nf3 keeps it simple.",
    "Knight Nbd2 is fine.",
    "Castle with O-O.",
    "Then 0-0-0 is safe.",
    "Then e8=Q wins.",
    "And e8Q wins.",
    "Then exd5 is strong.",
    "And h7# is mate.",
    "Look at h7+ first.",
    "Play e2e4 instead.",
    "Play e2-e4 instead.",
    "After 12. h6 you're fine.",
  ]) {
    assert.equal(guardAnswer(answer, spoken), null, answer);
  }
});

test("the guard turns down a square that no checked fact names, even one the player said", () => {
  assert.equal(guardAnswer("Your bishop on c4 is loose.", spoken), null);
  // g5 is only in the player's own words, which aren't checked facts.
  assert.equal(guardAnswer("Your knight on g5 is fine.", spoken), null);
  assert.equal(guardAnswer("Your knight on f6 is not safe.", spoken), "Your knight on f6 is not safe.");
  // Squares in any checked string count, nested ones too.
  assert.equal(guardAnswer("Watch b4.", { ...spoken, missed: [{ note: "They can check on b4." }] }), "Watch b4.");
});

test("the guard turns down what a coach never says aloud", () => {
  for (const answer of [
    "See https://example.com for more.",
    "Visit www.example.com.",
    "Write to leo@example.com.",
    "It's +1.5 for you.",
    "You're 0.8 better.",
    "That is <b>bold</b>.",
  ]) {
    assert.equal(guardAnswer(answer, spoken), null, answer);
  }
});

test("the guard tidies markdown, quotation marks and labels away, and keeps apostrophes", () => {
  assert.equal(guardAnswer('"**Right** about the bishop."', spoken), "Right about the bishop.");
  assert.equal(guardAnswer("Leo: Good move.", spoken), "Good move.");
  assert.equal(guardAnswer("- Good thinking.\n- Your knight on f6 isn't safe.", spoken), "Good thinking. Your knight on f6 isn't safe.");
  assert.equal(guardAnswer("You’re right, it’s `safe`.", spoken), "You're right, it's safe.");
  assert.equal(guardAnswer("“Nice.”  \n\n Well   seen.", spoken), "Nice. Well seen.");
  assert.equal(guardAnswer("Mate in 1. Then you win.", spoken), "Mate in 1. Then you win.");
});

test("the guard turns down nothing, too much and things that aren't text", () => {
  assert.equal(guardAnswer("", spoken), null);
  assert.equal(guardAnswer(" \n ** ", spoken), null);
  assert.equal(guardAnswer(null, spoken), null);
  assert.equal(guardAnswer(42, spoken), null);
  assert.equal(guardAnswer("a".repeat(MAX_ANSWER), spoken), "a".repeat(MAX_ANSWER));
  assert.equal(guardAnswer("a".repeat(MAX_ANSWER + 1), spoken), null);
  assert.equal(guardAnswer("Fine.", undefined), "Fine.");
  assert.equal(guardAnswer("Fine on h7.", undefined), null);
});

// ---------------------------------------------------------------------------
// templateAnswer

test("the template: what was right, the most important correction, then the move", () => {
  assert.equal(
    templateAnswer(checked, spoken),
    "You're right, the bishop on d3 does aim at h7. Your knight on f6 isn't safe: the pawn on e5 can take it. Pushing to h6 is a good move.",
  );
});

test("the template keeps the correction, the move and a missed threat when there's too much to say", () => {
  const busy = { ...spoken, missed: ["Watch out: they threaten queen takes h7, mate."] };
  assert.equal(
    templateAnswer(checked, busy),
    "Your knight on f6 isn't safe: the pawn on e5 can take it. Pushing to h6 is a good move. Watch out: they threaten queen takes h7, mate.",
  );
});

test("the template praises briefly when everything was right", () => {
  const allRight = { ...spoken, right: ["The bishop on d3 does aim at h7.", "Your knight on f6 is safe."], wrong: [], move: "Castling is the best move here." };
  assert.equal(templateAnswer(checked, allRight), "You're right on every point. Castling is the best move here. You named their threat before choosing your move.");
  const yes = { ...spoken, right: ["Yes, the bishop on d3 hits h7."], wrong: [], move: "" };
  assert.equal(templateAnswer(checked, yes), "Yes, the bishop on d3 hits h7. You named their threat before choosing your move.");
});

test("the template when nothing was understood, or nothing could be checked", () => {
  assert.equal(templateAnswer({ understood: false }, spoken), DIDNT_CATCH);
  assert.equal(templateAnswer(null, spoken), DIDNT_CATCH);
  const unclear = { said: "push the h-pawn", unclear: ["I can't tell yet whether pushing the h-pawn works"] };
  assert.equal(templateAnswer(checked, unclear), "I can't tell yet whether pushing the h-pawn works.");
  assert.equal(templateAnswer(checked, {}), "I couldn't check that. Tell me what you see, and the move you want.");
  assert.equal(templateAnswer(checked, null), "I couldn't check that. Tell me what you see, and the move you want.");
});

test("the template never runs past 320 characters", () => {
  const long = (word) => `${word} `.repeat(60).trim();
  const wordy = { right: [long("right")], wrong: [long("wrong")], move: long("move"), missed: [long("missed")], habit: long("habit") };
  const answer = templateAnswer(checked, wordy);
  assert.ok(answer.length <= MAX_ANSWER, `${answer.length} characters`);
  assert.ok(answer.length > 0);
  const huge = templateAnswer(checked, { wrong: [`${"Your knight is loose. ".repeat(30)}`] });
  assert.ok(huge.length <= MAX_ANSWER && huge.endsWith("."), huge);
});

// ---------------------------------------------------------------------------
// The request and the call

test("the answer request: Leo's persona, the checked facts, the fallback and no sampling settings", () => {
  const request = buildAnswerRequest(checked, { ...spoken, said: "is <b>this</b> safe?" }, {});
  assert.equal(request.model, "claude-opus-5-5");
  assert.equal(request.max_tokens, 3000);
  assert.deepEqual(request.betas, ["server-side-fallback-2026-07-01"]);
  assert.equal(request.fallbacks, "default");
  assert.deepEqual(request.output_config, { effort: "low" });
  for (const key of ["temperature", "top_p", "top_k", "thinking", "tool_choice"]) assert.equal(key in request, false, key);
  assert.match(request.system[0].text, /You are Leo/);
  assert.deepEqual(request.system[0].cache_control, { type: "ephemeral" });
  const content = request.messages[0].content;
  assert.equal(request.messages[0].role, "user");
  assert.match(content, /<words>is ‹b›this‹\/b› safe\?<\/words>/);
  assert.match(content, /Right:\n- The bishop on d3 does aim at h7\./);
  assert.match(content, /Wrong:\n- Your knight on f6 isn't safe/);
  assert.match(content, /Their move: Pushing to h6 is a good move\./);
  assert.match(content, /Habit: You named their threat/);
  assert.doesNotMatch(content, /Partly right|Couldn't check|Hint/);

  const tuned = buildAnswerRequest(checked, spoken, { MODEL: "claude-test", ANSWER_EFFORT: "medium" });
  assert.equal(tuned.model, "claude-test");
  assert.equal(tuned.output_config.effort, "medium");
  assert.equal(buildAnswerRequest(checked, spoken, { ANSWER_EFFORT: "extreme" }).output_config.effort, "low");
  assert.match(buildAnswerRequest(checked, {}, {}).messages[0].content, /Nothing they said could be checked/);
});

test("Claude's wording is Leo's answer when the guard lets it through", async () => {
  const client = fakeClient(message("Right about the bishop. But your knight on f6 isn't safe."));
  const answer = await wordAnswer(client, {}, { checked, spoken });
  assert.deepEqual(answer, { text: "Right about the bishop. But your knight on f6 isn't safe.", source: "leo" });
  assert.equal(client.calls.length, 1);
  assert.ok(client.calls[0].options.signal instanceof AbortSignal);
  assert.equal(client.calls[0].options.timeout, 12000);
});

test("after a server-side fallback, the answer is the text after the fallback block", async () => {
  const reply = message("ignored", {
    model: "claude-opus-5",
    content: [
      { type: "fallback", from: { model: "claude-opus-5-5" }, to: { model: "claude-opus-5" } },
      { type: "text", text: "Well seen on h7." },
    ],
  });
  assert.deepEqual(await wordAnswer(fakeClient(reply), {}, { checked, spoken }), { text: "Well seen on h7.", source: "leo" });
});

test("a refusal, a cut-off reply, an API error or a guarded answer falls back to the template", async (t) => {
  quiet(t);
  const template = { text: templateAnswer(checked, spoken), source: "template" };
  const replies = [
    message("", { stop_reason: "refusal", content: [], stop_details: { type: "refusal", category: null } }),
    message("Right about", { stop_reason: "max_tokens" }),
    message("   "),
    message("Play Bxh7+ and win."),
    message("Your bishop on c4 is loose."),
    () => {
      throw Anthropic.APIError.generate(529, { type: "error", error: { type: "overloaded_error", message: "Overloaded" } }, "Overloaded", new Headers());
    },
    () => {
      throw new Anthropic.APIConnectionError({ message: "Connection error." });
    },
    () => {
      throw new Anthropic.APIConnectionTimeoutError();
    },
    { content: "not a message" },
  ];
  for (const reply of replies) {
    assert.deepEqual(await wordAnswer(fakeClient(reply), {}, { checked, spoken }), template);
  }
});

test("a slow Claude is given up on after CLAUDE_TIMEOUT_MS, and the template answers", async (t) => {
  quiet(t);
  let signal;
  const client = fakeClient((params, options) => {
    signal = options.signal;
    return new Promise(() => {});
  });
  const started = Date.now();
  const answer = await wordAnswer(client, { CLAUDE_TIMEOUT_MS: "1000" }, { checked, spoken });
  assert.equal(answer.source, "template");
  assert.ok(Date.now() - started < 3000);
  assert.equal(signal.aborted, true);
});

test("when nothing was understood, Claude isn't asked", async () => {
  const client = fakeClient(message("Hello!"));
  assert.deepEqual(await wordAnswer(client, {}, { checked: { understood: false }, spoken: {} }), { text: DIDNT_CATCH, source: "template" });
  assert.deepEqual(await wordAnswer(null, {}, { checked, spoken }), { text: templateAnswer(checked, spoken), source: "template" });
  assert.equal(client.calls.length, 0);
});

test("Vera answers as Vera, by the same rules as Leo", () => {
  const leo = coachPrompt("leo");
  const vera = coachPrompt("vera");
  assert.match(leo, /^You are Leo,/);
  assert.match(vera, /^You are Vera,/);
  assert.doesNotMatch(vera, /\bLeo\b/);
  // Everything after the persona is the same rules, word for word.
  const rules = (prompt) => prompt.slice(prompt.indexOf("Before moving"));
  assert.equal(rules(vera), rules(leo));
  assert.equal(coachPrompt("someone"), leo);
  const request = buildAnswerRequest({ understood: true }, { said: "castle" }, {}, "vera");
  assert.equal(request.system[0].text, vera);
  assert.match(request.messages[0].content, /Say Vera's answer\.$/);
  assert.equal(guardAnswer("Vera: Castling is safe.", {}), "Castling is safe.");
});
