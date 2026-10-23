// A quick end-to-end check of a deployed game server, run by the deploy
// workflow right after each deploy:
//
//   node play/test/smoke.mjs https://play.chess-game-killer.workers.dev
//
// It makes a game, opens its invite page, joins it, watches it over a
// WebSocket and plays fool's mate over REST. Exits with 1 on any failure.
// The game it leaves behind is over, and is deleted 30 days later.

import { LiveSocket, api, check } from "./client.mjs";

const base = String(process.argv[2] || "").replace(/\/+$/, "");
if (!/^https?:\/\/[^/]+$/.test(base)) {
  console.error("Usage: node smoke.mjs https://play.example.workers.dev");
  process.exit(2);
}

const pause = (ms) => new Promise((resolve) => setTimeout(resolve, ms));

/** A fresh deploy can take a few seconds to answer everywhere. */
async function waitUntilUp() {
  let last = "no answer";
  for (let attempt = 0; attempt < 30; attempt += 1) {
    try {
      const response = await fetch(`${base}/`, { signal: AbortSignal.timeout(10000) });
      if (response.status === 200) return;
      last = `HTTP ${response.status}`;
    } catch (error) {
      last = error.message;
    }
    await pause(2000);
  }
  throw new Error(`${base}/ didn't answer 200 within a minute (${last})`);
}

const steps = [];
function done(step) {
  steps.push(step);
  console.log(`- ${step}`);
}

let socket = null;
try {
  await waitUntilUp();
  done("the home page answers");

  const made = await api(base, "POST", "/api/games", { body: { name: "Smoke test", side: "white", clock: null } });
  check(made.status === 201, `making a game: HTTP ${made.status} ${made.text}`);
  const { code, token: white } = made.json;
  check(made.json.url === `${base}/c/${code}`, `the invite link is ${made.json.url}`);
  done(`made game ${code}`);

  const page = await api(base, "GET", `/c/${code}`);
  check(page.status === 200 && /^text\/html/.test(page.headers.get("content-type") || ""), `the invite page: HTTP ${page.status}`);
  done("the invite page is up");

  const joined = await api(base, "POST", `/api/games/${code}/join`, { body: { name: "Smoke friend" } });
  check(joined.status === 200 && joined.json.seat === "black", `joining: HTTP ${joined.status} ${joined.text}`);
  const black = joined.json.token;
  done("joined as Black");

  socket = new LiveSocket(base, code, black);
  await socket.opened;
  await socket.state((game) => game.code === code && game.black.online, "the state on connect", 15000);
  done("the WebSocket is live");

  const plies = [
    [white, "f2f3"],
    [black, "e7e5"],
    [white, "g2g4"],
    [black, "d8h4"],
  ];
  for (const [ply, [token, uci]] of plies.entries()) {
    const moved = await api(base, "POST", `/api/games/${code}/move`, { body: { uci, ply }, token });
    check(moved.status === 200, `move ${uci}: HTTP ${moved.status} ${moved.text}`);
  }
  const final = await socket.state((game) => game.result !== null, "the result", 15000);
  check(final.result.winner === "black" && final.result.reason === "checkmate", `the result was ${JSON.stringify(final.result)}`);
  done("fool's mate: Black wins by checkmate, seen over the WebSocket");

  console.log(`\nSmoke test passed (${steps.length} steps).`);
  socket.close();
  process.exit(0);
} catch (error) {
  console.log(`\nSmoke test FAILED: ${error.message}`);
  if (socket) socket.close();
  process.exit(1);
}
