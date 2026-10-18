// Sends one test board straight to the Claude API, exactly as the scanner does,
// and prints the API's answer. The deploy workflow runs it when the scanner fails,
// because the Worker's own logs aren't visible there.
// Usage: ANTHROPIC_API_KEY=... node scanner/test/check_api.mjs <image.png> <model>
import { readFile } from "node:fs/promises";
import { apiKey, buildRequest } from "../src/index.js";

const [image, model] = process.argv.slice(2);
const raw = process.env.ANTHROPIC_API_KEY || "";
const key = apiKey({ ANTHROPIC_API_KEY: raw });
if (!key) {
  console.log("The ANTHROPIC_API_KEY secret is empty.");
  process.exit(1);
}
if (raw !== key) console.log("Note: the ANTHROPIC_API_KEY secret has spaces or a line break around it.");
if (!key.startsWith("sk-ant-")) console.log("Note: the ANTHROPIC_API_KEY secret doesn't look like an Anthropic API key (they start with sk-ant-).");

const bytes = new Uint8Array(await readFile(image));
const response = await fetch("https://api.anthropic.com/v1/messages", {
  method: "POST",
  headers: { "x-api-key": key, "anthropic-version": "2023-06-01", "content-type": "application/json" },
  body: JSON.stringify(buildRequest(bytes, "image/png", model)),
});
const body = await response.json().catch(() => ({}));
if (response.ok) {
  console.log(`Claude API answered fine with ${model}.`);
} else {
  const error = body.error || {};
  console.log(`Claude API said ${response.status} ${error.type || ""}: ${error.message || JSON.stringify(body).slice(0, 300)}`);
  process.exitCode = 1;
}
