// The online lobby lives in one Durable Object, named "lobby": everyone who
// wants a game with a player online right now waits here. The rules are in
// lobby.js; this file keeps them in storage, pairs players into new games
// (each one a GameRoom, as for friend games) and keeps the ratings.
//
// Calls come from the router (router.js) and get back { status, body }:
//   list, me, seek, check, cancel, take
// and from a GameRoom when a rated game ends: recordResult.
//
// About waiting: while this code awaits storage no other event runs, but
// while it awaits a GameRoom (making the game) others can. So a seek being
// paired is marked `pairing` before that wait, and nobody else can take it.

import { DurableObject } from "cloudflare:workers";
import * as lobby from "./lobby.js";
import * as daily from "./daily.js";
import { ERROR_STATUS, errorBody, hashToken, newCode, newToken, readConfig } from "./util.js";

function reply(status, body) {
  return { status, body };
}

function refuse(error, message) {
  return reply(ERROR_STATUS[error] ?? 500, errorBody(error, message));
}

const GONE = "That player isn't waiting any more. Pick someone else, or find a game.";

function seekId() {
  return newToken().slice(0, 12);
}

export class Lobby extends DurableObject {
  constructor(ctx, env) {
    super(ctx, env);
    this.config = readConfig(env);
    this.state = lobby.emptyLobby();
    ctx.blockConcurrencyWhile(async () => {
      this.state = (await ctx.storage.get("lobby")) ?? lobby.emptyLobby();
    });
  }

  async #save() {
    await this.ctx.storage.put("lobby", this.state);
  }

  async #sweep(now) {
    if (lobby.sweep(this.state, now)) await this.#save();
  }

  /** A player's rating, by the hash of their key: 1200 and no games for someone new. */
  async #rating(playerHash) {
    const saved = await this.ctx.storage.get(`r:${playerHash}`);
    return saved ?? { rating: lobby.START_RATING, games: 0 };
  }

  #you(record) {
    return { rating: record.rating, games: record.games, provisional: record.games < lobby.PROVISIONAL_GAMES };
  }

  // -------------------------------------------------------------------------
  // Calls from the router

  /**
   * Today's Move: counts a player's try once a day and answers the day's tally
   * for that puzzle, { players, found }. A second report the same day changes nothing.
   */
  async dailyReport({ day, puzzle, playerHash, found }) {
    const key = daily.tallyKey(day, puzzle);
    const mark = daily.playerKey(day, playerHash);
    const seen = (await this.ctx.storage.get(mark)) !== undefined;
    const tally = daily.counted(await this.ctx.storage.get(key), { found, seen });
    if (!seen) await this.ctx.storage.put({ [key]: tally, [mark]: 1 });
    return reply(200, tally);
  }

  async list() {
    const now = Date.now();
    await this.#sweep(now);
    return reply(200, lobby.listView(this.state, now));
  }

  async me({ playerHash }) {
    return reply(200, { you: this.#you(await this.#rating(playerHash)) });
  }

  /**
   * Waits for a game at a clock. With `pair`, first takes on the closest-rated
   * player already waiting at that clock, if there is one.
   */
  async seek({ tokenHash, playerHash, name, clock, look, pair = true }) {
    const record = await this.#rating(playerHash);
    const now = Date.now();
    await this.#sweep(now);
    if (pair) {
      const opponent = lobby.bestOpponent(this.state, { clock, playerHash, rating: record.rating }, now);
      if (opponent) {
        const paired = await this.#pair(opponent, { playerHash, name, look, record });
        if (paired) return reply(200, { match: paired, you: this.#you(record) });
        // That game couldn't be made: wait like anyone else instead.
      }
    }
    const id = seekId();
    const added = lobby.addSeek(
      this.state,
      { id, tokenHash, playerHash, name, rating: record.rating, games: record.games, clock, look },
      Date.now(),
    );
    if (!added.ok) return refuse(added.error, added.message);
    await this.#save();
    return reply(201, { seek: lobby.seekView(added.seek, Date.now()), you: this.#you(record) });
  }

  /** The waiting app checks in: still waiting (which keeps the seek alive), or here is the game. */
  async check({ id, tokenHash }) {
    const seek = this.state.seeks[id];
    if (!seek || seek.tokenHash !== tokenHash) return refuse("not_found", "You're not waiting in the lobby any more.");
    const now = Date.now();
    if (seek.match) return reply(200, { match: { code: seek.match.code, seat: seek.match.seat, token: seek.match.token } });
    seek.seenAt = now;
    // Saved now and then, not on every check-in: a seek lost with the object just waits again.
    await this.#sweep(now);
    return reply(200, { seek: lobby.seekView(seek, now), waiting: lobby.openSeeks(this.state, now).length });
  }

  /** Stops waiting. If someone took the seek on just before, the game is handed over instead. */
  async cancel({ id, tokenHash }) {
    const seek = this.state.seeks[id];
    if (!seek || seek.tokenHash !== tokenHash) return reply(200, { cancelled: true });
    if (seek.match) return reply(200, { match: { code: seek.match.code, seat: seek.match.seat, token: seek.match.token } });
    if (seek.pairing) {
      // Someone is taking this seek on right now: the game is a moment away.
      return refuse("pairing", "Someone just took you on. Your game is starting.");
    }
    delete this.state.seeks[id];
    await this.#save();
    return reply(200, { cancelled: true });
  }

  /** Takes on one waiting player by their seek's id: challenging the online player. */
  async take({ id, playerHash, name, look }) {
    const now = Date.now();
    await this.#sweep(now);
    const seek = this.state.seeks[id];
    if (!seek || seek.match || seek.pairing || now - seek.seenAt > lobby.SEEK_STALE_MS) return refuse("not_found", GONE);
    if (seek.playerHash === playerHash) return refuse("bad_request", "That's you. Pick someone else.");
    const record = await this.#rating(playerHash);
    // Looked up again after waiting for storage: someone else may have taken it meanwhile.
    const still = this.state.seeks[id];
    if (!still || still.match || still.pairing) return refuse("not_found", GONE);
    const paired = await this.#pair(still, { playerHash, name, look, record });
    if (!paired) return refuse("server_error", "The game couldn't be started. Please try again.");
    return reply(200, { match: paired, you: this.#you(record) });
  }

  // -------------------------------------------------------------------------
  // Pairing

  /**
   * Makes the game between a waiting player and the one taking them on.
   * Colors are drawn at random. Returns the taker's seat, token and game,
   * and leaves the waiting player's in their seek for their next check-in.
   * Null if the game couldn't be made (the seek is open again).
   */
  async #pair(seek, taker) {
    seek.pairing = true;
    try {
      const seekerToken = newToken();
      const takerToken = newToken();
      const [seekerHash, takerHash] = await Promise.all([hashToken(seekerToken), hashToken(takerToken)]);
      const seekerWhite = crypto.getRandomValues(new Uint8Array(1))[0] & 1;
      const seeker = { name: seek.name, tokenHash: seekerHash, player: seek.playerHash, rating: seek.rating, games: seek.games };
      const other = { name: taker.name, tokenHash: takerHash, player: taker.playerHash, rating: taker.record.rating, games: taker.record.games };
      const [white, black] = seekerWhite ? [seeker, other] : [other, seeker];
      for (let attempt = 0; attempt < 5; attempt += 1) {
        const code = newCode();
        const room = this.env.GAMES.get(this.env.GAMES.idFromName(code));
        const made = await room.createPaired({
          code,
          white: { name: white.name, tokenHash: white.tokenHash },
          black: { name: black.name, tokenHash: black.tokenHash },
          clock: seek.clock,
          look: seek.look,
          rated: {
            white: { player: white.player, rating: white.rating, games: white.games },
            black: { player: black.player, rating: black.rating, games: black.games },
          },
        });
        if (made && made.inUse) continue;
        const now = Date.now();
        seek.pairing = false;
        seek.match = { code, seat: seekerWhite ? "white" : "black", token: seekerToken, at: now };
        // The taker's own earlier seek, if any, is no longer needed.
        for (const [id, other] of Object.entries(this.state.seeks)) {
          if (other.playerHash === taker.playerHash && !other.match) delete this.state.seeks[id];
        }
        await this.#save();
        console.log(JSON.stringify({ event: "online_pairing", code, clock: seek.clock }));
        return { code, seat: seekerWhite ? "black" : "white", token: takerToken, game: made.game };
      }
      throw new Error("no free game code after 5 tries");
    } catch (error) {
      console.error("pairing failed:", error && error.message);
      seek.pairing = false;
      return null;
    }
  }

  // -------------------------------------------------------------------------
  // Ratings

  /**
   * A rated game ended: White's `score` is 1, 0.5 or 0. Returns both players'
   * new { rating, games }. A game is counted once, however often it is reported.
   */
  async recordResult({ code, white, black, score }) {
    const doneKey = `done:${code}`;
    const done = await this.ctx.storage.get(doneKey);
    if (done) return done;
    if (typeof score !== "number" || !white || !black) return null;
    const [w, b] = await Promise.all([this.#rating(white), this.#rating(black)]);
    const after = lobby.eloAfter(w, b, score);
    // One write for all three, so a game is never half counted.
    await this.ctx.storage.put({
      [`r:${white}`]: after.white,
      [`r:${black}`]: after.black,
      [doneKey]: after,
    });
    return after;
  }
}

