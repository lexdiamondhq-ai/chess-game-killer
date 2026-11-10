// An experiment, not part of the server: writes "Leo's deep review" of one finished
// game with each model in turn, so the reviews and what each cost can be read side by side.
// The game and Stockfish's grades are in fixtures/review-game.txt.
//
//   ANTHROPIC_API_KEY=... node test/review-compare.mjs
import Anthropic from "@anthropic-ai/sdk";
import { readFileSync } from "node:fs";

const FACTS = readFileSync(new URL("./fixtures/review-game.txt", import.meta.url), "utf8");

/** Dollars per million tokens: [input, output]. */
const PRICES = {
  "claude-fable-5-2": [8, 40],
  "claude-opus-5-5": [4, 20],
};
const RUNS = [
  { model: "claude-fable-5-2", effort: "medium" },
  { model: "claude-fable-5-2", effort: "high" },
  { model: "claude-opus-5-5", effort: "medium" },
  { model: "claude-opus-5-5", effort: "high" },
];

const SYSTEM = `You are Coach Leo in the chess app Beauty of Chess: a warm, direct coach who sits down with a player after their game and talks them through it once, the way a good human coach would across the table.

The player has just finished a game. You are given every move with Stockfish's grade and score, and for each costly move what the engine wanted instead. Those are your facts. Everything you say about the chess must follow from them or from the moves themselves: never state a tactic, a threat or a line that the facts and the position do not support. If you are not sure something is true on the board, leave it out.

Your review is spoken aloud by a voice, to a club player who is still learning, and the board on their screen moves to each move you mention. So:
- Find the story of this game: the one or two ideas that decided it, not a list of every mistake. If the same kind of mistake came back more than once, that pattern is the story.
- Name something they did well, and mean it.
- End with one habit to take into their next game, put so they will remember it at the board.
- Speak plainly. Say moves in words ("bishop to f4", "take back with the c-pawn"), give move numbers so the board can follow, and do not quote engine scores.
- About 200 to 260 words. No headings, no lists, no markdown: only what Leo says.`;

const client = new Anthropic();
let total = 0;
for (const run of RUNS) {
  const started = Date.now();
  try {
    const stream = client.messages.stream({
      model: run.model,
      max_tokens: 32000,
      output_config: { effort: run.effort },
      system: SYSTEM,
      messages: [{ role: "user", content: FACTS }],
    });
    const message = await stream.finalMessage();
    const seconds = ((Date.now() - started) / 1000).toFixed(1);
    const text = message.content
      .filter((block) => block.type === "text")
      .map((block) => block.text)
      .join("\n")
      .trim();
    const { input_tokens: input, output_tokens: output } = message.usage;
    const [inPrice, outPrice] = PRICES[run.model];
    const cost = (input * inPrice + output * outPrice) / 1e6;
    total += cost;
    console.log(`\n===== ${run.model} · ${run.effort} effort =====`);
    console.log(
      `served by ${message.model} · stop: ${message.stop_reason} · ${seconds} s · ${input} in, ${output} out (thinking included) · $${cost.toFixed(4)} · ${text.split(/\s+/).length} words, ${text.length} characters\n`,
    );
    console.log(text);
  } catch (error) {
    console.log(`\n===== ${run.model} · ${run.effort} effort =====`);
    console.log(`failed: ${error?.status ?? ""} ${error?.message ?? error}`);
  }
}
console.log(`\n===== total: $${total.toFixed(4)} =====`);
