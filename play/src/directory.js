// Friends by @username: one Durable Object, named "directory", that keeps
// every player who picked a username, who they've played, and the challenges
// sent to them. The rules are in friends.js; the protocol is in PROTOCOL.md
// ("Friends by username").
//
// Calls come from the router and get back { status, body }:
//   me, claim, search, people, invite, inbox, dismiss, phone
// and from game rooms: notify (a phone alert to one player).
// Players are known only by the SHA-256 of their app's player key.
// Each player's phone (its Apple push token) is kept here too, for alerts
// (push.js); a player needs no username to have one.

import { DurableObject } from "cloudflare:workers";
import * as friends from "./friends.js";
import * as push from "./push.js";
import { ERROR_STATUS, cleanName, errorBody, newToken } from "./util.js";

function reply(status, body) {
  return { status, body };
}

function refuse(error, message) {
  return reply(ERROR_STATUS[error] ?? 500, errorBody(error, message));
}

const NEEDS_USERNAME = "Pick a username first.";

export class Directory extends DurableObject {
  constructor(ctx, env) {
    super(ctx, env);
    this.sql = ctx.storage.sql;
    this.sql.exec(`
      CREATE TABLE IF NOT EXISTS players (
        hash TEXT PRIMARY KEY,
        username TEXT UNIQUE,
        name TEXT,
        last_seen INTEGER,
        created INTEGER NOT NULL
      );
      CREATE TABLE IF NOT EXISTS people (
        owner TEXT NOT NULL,
        other TEXT NOT NULL,
        last_at INTEGER NOT NULL,
        PRIMARY KEY (owner, other)
      );
      CREATE TABLE IF NOT EXISTS invites (
        id TEXT PRIMARY KEY,
        to_hash TEXT NOT NULL,
        from_hash TEXT NOT NULL,
        code TEXT NOT NULL,
        clock TEXT,
        seat TEXT NOT NULL,
        created INTEGER NOT NULL
      );
      CREATE INDEX IF NOT EXISTS invites_to ON invites (to_hash, created);
      CREATE TABLE IF NOT EXISTS phones (
        hash TEXT PRIMARY KEY,
        token TEXT NOT NULL,
        sandbox INTEGER NOT NULL,
        updated INTEGER NOT NULL
      );
      CREATE INDEX IF NOT EXISTS phones_token ON phones (token);
    `);
  }

  #player(hash) {
    return this.sql.exec("SELECT * FROM players WHERE hash = ?", hash).toArray()[0] ?? null;
  }

  #byUsername(username) {
    return this.sql.exec("SELECT * FROM players WHERE username = ?", username).toArray()[0] ?? null;
  }

  /** Marks a player as here now, and keeps the name friends see up to date. */
  #seen(hash, now, name) {
    const clean = name === undefined ? undefined : cleanName(name);
    if (clean === undefined) {
      this.sql.exec("UPDATE players SET last_seen = ? WHERE hash = ?", now, hash);
    } else {
      this.sql.exec("UPDATE players SET last_seen = ?, name = ? WHERE hash = ?", now, clean, hash);
    }
  }

  #you(row) {
    return row && row.username ? { username: row.username, name: friends.displayName(row.name, row.username) } : null;
  }

  /** The player's own username, if they have one: { you: { username, name } | null }. */
  async me({ playerHash, name }) {
    const now = Date.now();
    const row = this.#player(playerHash);
    if (row) this.#seen(playerHash, now, name);
    return reply(200, { you: this.#you(this.#player(playerHash)) });
  }

  /** Takes a username, or changes it. */
  async claim({ playerHash, username, name }) {
    const now = Date.now();
    const holder = this.#byUsername(username);
    if (holder && holder.hash !== playerHash) return refuse("username_taken", "That username is taken. Try another.");
    const clean = cleanName(name ?? "");
    if (this.#player(playerHash)) {
      this.sql.exec("UPDATE players SET username = ?, name = ?, last_seen = ? WHERE hash = ?", username, clean, now, playerHash);
    } else {
      this.sql.exec(
        "INSERT INTO players (hash, username, name, last_seen, created) VALUES (?, ?, ?, ?, ?)",
        playerHash, username, clean, now, now,
      );
    }
    return reply(200, { you: this.#you(this.#player(playerHash)) });
  }

  /** Players whose username starts with the query, or whose name has a word that does. */
  async search({ playerHash, q }) {
    const now = Date.now();
    this.#seen(playerHash, now);
    const like = `${friends.likeEscape(q)}%`;
    const word = `% ${friends.likeEscape(q)}%`;
    const rows = this.sql.exec(
      `SELECT p.*, (SELECT last_at FROM people WHERE owner = ? AND other = p.hash) AS known
         FROM players p
        WHERE p.username IS NOT NULL AND p.hash != ?
          AND (p.username LIKE ? ESCAPE '\\' OR lower(p.name) LIKE ? ESCAPE '\\' OR lower(p.name) LIKE ? ESCAPE '\\')
        ORDER BY (p.username = ?) DESC, known IS NULL, known DESC, length(p.username)
        LIMIT ?`,
      playerHash, playerHash, like, like, word, q, friends.SEARCH_MAX,
    ).toArray();
    return reply(200, { players: rows.map((row) => friends.personView(row, now)) });
  }

  /** The people this player has challenged or been challenged by, the latest first. Also checks the player in. */
  async people({ playerHash }) {
    const now = Date.now();
    this.#seen(playerHash, now);
    const rows = this.sql.exec(
      `SELECT p.* FROM people k JOIN players p ON p.hash = k.other
        WHERE k.owner = ? AND p.username IS NOT NULL
        ORDER BY k.last_at DESC LIMIT ?`,
      playerHash, friends.PEOPLE_MAX,
    ).toArray();
    return reply(200, { people: rows.map((row) => friends.personView(row, now)) });
  }

  /** Sends a waiting game to another player by username. `game` is the game as it stands. */
  async invite({ playerHash, to, game }) {
    const now = Date.now();
    const me = this.#player(playerHash);
    if (!me || !me.username) return refuse("bad_request", NEEDS_USERNAME);
    const them = this.#byUsername(to);
    if (!them) return refuse("not_found", `There's no player called @${to}.`);
    if (them.hash === playerHash) return refuse("bad_request", "That's you. Pick a friend.");
    if (!friends.isInvitable(game)) return refuse("game_over", "That challenge can't be joined any more.");
    this.#sweep(now);
    const waiting = this.sql.exec(
      "SELECT COUNT(*) AS n FROM invites WHERE to_hash = ? AND from_hash = ?", them.hash, playerHash,
    ).one().n;
    if (waiting >= friends.INVITES_PER_PAIR) {
      return refuse("rate_limited", `@${them.username} already has your challenges waiting.`);
    }
    // The same game sent twice to the same player is one invite.
    this.sql.exec("DELETE FROM invites WHERE to_hash = ? AND code = ?", them.hash, game.code);
    this.sql.exec(
      "INSERT INTO invites (id, to_hash, from_hash, code, clock, seat, created) VALUES (?, ?, ?, ?, ?, ?, ?)",
      newToken().slice(0, 12), them.hash, playerHash, game.code, JSON.stringify(game.clock ?? null),
      friends.friendSeat(game), now,
    );
    for (const [owner, other] of [[playerHash, them.hash], [them.hash, playerHash]]) {
      this.sql.exec(
        "INSERT INTO people (owner, other, last_at) VALUES (?, ?, ?) ON CONFLICT (owner, other) DO UPDATE SET last_at = excluded.last_at",
        owner, other, now,
      );
    }
    this.#seen(playerHash, now);
    // A phone alert, so the friend hears of it even with the app closed.
    const alert = push.challengeAlert({ from: friends.displayName(me.name, me.username), clock: game.clock ?? null, days: game.days ?? null });
    this.#alert(them.hash, alert, { kind: "challenge", code: game.code });
    return reply(201, { sent: friends.personView(them, now) });
  }

  /** Challenges waiting for this player, the newest first. Also checks the player in. */
  async inbox({ playerHash }) {
    const now = Date.now();
    this.#seen(playerHash, now);
    this.#sweep(now);
    const rows = this.sql.exec(
      `SELECT i.*, p.username, p.name, p.last_seen FROM invites i JOIN players p ON p.hash = i.from_hash
        WHERE i.to_hash = ? ORDER BY i.created DESC LIMIT 10`,
      playerHash,
    ).toArray();
    return reply(200, {
      invites: rows.map((row) => ({
        id: row.id,
        code: row.code,
        clock: JSON.parse(row.clock),
        seat: row.seat,
        at: row.created,
        from: friends.personView(row, now),
      })),
    });
  }

  /** Clears one invite (opened or turned down). */
  async dismiss({ playerHash, id }) {
    this.sql.exec("DELETE FROM invites WHERE id = ? AND to_hash = ?", id, playerHash);
    return reply(200, { dismissed: true });
  }

  /** Keeps (or with no token, forgets) the phone that gets this player's alerts. */
  async phone({ playerHash, token, sandbox }) {
    if (!token) {
      this.sql.exec("DELETE FROM phones WHERE hash = ?", playerHash);
      return reply(200, { phone: false });
    }
    // One phone, one player: a phone that changed hands stops getting the old player's alerts.
    this.sql.exec("DELETE FROM phones WHERE token = ? AND hash != ?", token, playerHash);
    this.sql.exec(
      `INSERT INTO phones (hash, token, sandbox, updated) VALUES (?, ?, ?, ?)
       ON CONFLICT (hash) DO UPDATE SET token = excluded.token, sandbox = excluded.sandbox, updated = excluded.updated`,
      playerHash, token, sandbox ? 1 : 0, Date.now(),
    );
    return reply(200, { phone: true });
  }

  /** A phone alert to one player, from a game room. { alert: { title, body }, kind, code }. */
  async notify({ playerHash, alert, kind, code = null }) {
    await this.#alert(playerHash, alert, { kind, code });
    return { ok: true };
  }

  /** Sends an alert to a player's phone, if they have one. Never throws. */
  #alert(playerHash, alert, { kind, code = null }) {
    const row = this.sql.exec("SELECT * FROM phones WHERE hash = ?", playerHash).toArray()[0];
    if (!row || !push.canSend(this.env)) return Promise.resolve();
    const payload = push.apnsPayload(alert, { kind, code });
    // One alert of each kind per game: a newer one replaces the older on the lock screen.
    const collapseId = code ? `${kind}-${code}` : null;
    return push
      .sendAlert(this.env, { token: row.token, sandbox: row.sandbox === 1, payload, collapseId })
      .then((result) => {
        if (result.gone) this.sql.exec("DELETE FROM phones WHERE hash = ? AND token = ?", playerHash, row.token);
        else if (result.sent && result.sandbox !== (row.sandbox === 1)) {
          this.sql.exec("UPDATE phones SET sandbox = ? WHERE hash = ?", result.sandbox ? 1 : 0, playerHash);
        }
      })
      .catch((error) => console.error("push failed:", error && error.message));
  }

  #sweep(now) {
    this.sql.exec("DELETE FROM invites WHERE created < ?", now - friends.INVITE_TTL_MS);
  }
}
