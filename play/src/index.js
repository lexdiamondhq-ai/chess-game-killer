// The worker's entry point. Cloudflare sends it every request that isn't for
// a static file in ./public (see wrangler.toml), and finds the Durable Object
// class for the games here.
//
// - router.js: checks each request and passes it to the right game.
// - room.js: GameRoom, the Durable Object that holds one game.
// - game.js: the rules, with no Cloudflare in them (most tests are of this).

import { handleRequest } from "./router.js";

export { GameRoom } from "./room.js";

export default {
  fetch: handleRequest,
};
