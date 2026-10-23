// One game lives in one Durable Object: a tiny server Cloudflare starts on
// demand for each game code. Every request for a code reaches the same
// object, and the object handles one event at a time, so two players' moves
// can never clash.
//
// The game is kept in memory and saved after every change. The rules are in
// game.js; this file connects them to storage, the alarm and the WebSockets.
//
// - Requests from the router (router.js) arrive as method calls (create,
//   read, join, move, action) and get back { status, body } for the router
//   to send. Only GET /api/games/{code}/live comes as a request, to fetch(),
//   because it becomes a WebSocket.
// - WebSockets use the Hibernation API: while nothing is happening, Cloudflare
//   may put the object to sleep and still keep the sockets open, and the
//   text "ping" is answered with "pong" without waking it.
// - One alarm wakes the object for the next thing that can happen on its own:
//   a flag falling, an absent player's grace running out, the game expiring,
//   or a finished game being deleted.
//
// About waiting: while this code awaits storage, Cloudflare delivers no other
// event to the object, but while it awaits another object (making a rematch)
// other events can run. So every change to the game happens in one stretch of
// code with no await in it, and is saved right after.

import { DurableObject } from "cloudflare:workers";
import * as rules from "./game.js";
import { ERROR_STATUS, errorBody, hashToken, isToken, newCode, newToken, readConfig } from "./util.js";

/** At most 8 WebSockets per game, and at most 3 for one seat (the oldest is closed when a 4th opens). */
const MAX_SOCKETS = 8;
const MAX_SOCKETS_PER_SEAT = 3;
/** The tag for sockets with no seat: people watching. */
const WATCHER = "watcher";
const OPEN = 1; // WebSocket.readyState for an open socket
const CLOSED = 3; // ... and for one whose closing handshake is done

function reply(status, body) {
  return { status, body };
}

function refuse(error, message, game) {
  return reply(ERROR_STATUS[error] ?? 500, errorBody(error, message, game));
}

const NO_GAME = "There's no game with that code. It may have ended long ago.";
const BAD_TOKEN = "That link or token isn't for a seat in this game.";

function infoOf(ws) {
  try {
    return ws.deserializeAttachment() || {};
  } catch {
    return {};
  }
}

function send(ws, text) {
  try {
    ws.send(text);
  } catch {
    // The socket is already closing; its close event will follow.
  }
}

function closeSocket(ws, code, reason) {
  try {
    ws.close(code, reason);
  } catch {
    // Already closed.
  }
}

export class GameRoom extends DurableObject {
  constructor(ctx, env) {
    super(ctx, env);
    /** The game record, or null when this code has no game. */
    this.game = null;
    /** The time the alarm is set for, or null. */
    this.alarmAt = null;
    /** The rematch being made, while another object is asked to hold it. */
    this.rematching = null;
    this.config = readConfig(env);
    // Answer the keepalive without waking the object.
    ctx.setWebSocketAutoResponse(new WebSocketRequestResponsePair("ping", "pong"));
    // Load the game before any event is handled, once each time the object starts.
    ctx.blockConcurrencyWhile(async () => {
      this.game = (await ctx.storage.get("game")) ?? null;
      this.alarmAt = await ctx.storage.getAlarm();
    });
  }

  // -------------------------------------------------------------------------
  // Calls from the router

  /** Starts a new game under this code. Returns { inUse: true } if the code already has one. */
  async create({ code, name, side, clock, tokenHash }) {
    if (this.game) return { inUse: true };
    const now = Date.now();
    this.game = rules.createGame({ code, name, side, clock, tokenHash, now, leaveGraceMs: this.config.leaveGraceMs });
    await this.#settle({ changed: true, notices: [] });
    return { seat: this.game.creator, game: this.#view() };
  }

  /** Holds a rematch made by another game's room. Returns { inUse: true } if the code already has a game. */
  async createRematch(record) {
    if (this.game) return { inUse: true };
    this.game = record;
    await this.#settle({ changed: true, notices: [] });
    return { ok: true };
  }

  async read() {
    if (!this.game) return refuse("not_found", NO_GAME);
    await this.#settle(rules.tick(this.game, Date.now()));
    return reply(200, { game: this.#view() });
  }

  /** Takes the open seat, or with a valid token for this game just returns that seat. */
  async join({ token = null, name = null } = {}) {
    // Hash before looking at the game, so nothing can change it in between.
    const tokenHash = token ? await hashToken(token) : null;
    const fresh = token ? null : newToken();
    const freshHash = fresh ? await hashToken(fresh) : null;
    if (!this.game) return refuse("not_found", NO_GAME);
    const now = Date.now();
    if (tokenHash) {
      const seat = rules.seatForToken(this.game, tokenHash);
      if (!seat) return refuse("unauthorized", BAD_TOKEN);
      await this.#settle(rules.tick(this.game, now));
      return reply(200, { seat, token, game: this.#view() });
    }
    const out = rules.join(this.game, { name, tokenHash: freshHash }, now);
    await this.#settle(out);
    if (!out.ok) return refuse(out.error, out.message, this.#view());
    return reply(200, { seat: out.seat, token: fresh, game: this.#view() });
  }

  async move({ token, uci, ply } = {}) {
    const seat = await this.#seatOf(token);
    if (!this.game) return refuse("not_found", NO_GAME);
    if (!seat) return refuse("unauthorized", BAD_TOKEN);
    const out = rules.move(this.game, seat, { uci, ply }, Date.now());
    await this.#settle(out);
    if (!out.ok) return refuse(out.error, out.message, this.#view());
    return reply(200, { game: this.#view() });
  }

  async action({ token, type } = {}) {
    const seat = await this.#seatOf(token);
    if (!this.game) return refuse("not_found", NO_GAME);
    if (!seat) return refuse("unauthorized", BAD_TOKEN);
    const out = rules.act(this.game, seat, type, Date.now());
    await this.#settle(out);
    if (!out.ok) return refuse(out.error, out.message, this.#view());
    if (out.rematchReady) {
      try {
        await this.#makeRematch();
      } catch (error) {
        console.error("making a rematch failed:", error && error.message);
        return refuse("server_error", "The rematch couldn't be started. Please try again.", this.#view());
      }
    }
    return reply(200, { game: this.#view() });
  }

  /** The seat a token holds in this game, or null. */
  async #seatOf(token) {
    if (!isToken(token)) return null;
    const tokenHash = await hashToken(token);
    return this.game ? rules.seatForToken(this.game, tokenHash) : null;
  }

  // -------------------------------------------------------------------------
  // Rematch

  /** Makes the rematch once, however many requests ask for it at the same moment. */
  #makeRematch() {
    if (!this.rematching) {
      this.rematching = this.#startRematch().finally(() => {
        this.rematching = null;
      });
    }
    return this.rematching;
  }

  async #startRematch() {
    for (let attempt = 0; attempt < 5; attempt += 1) {
      if (!this.game || (this.game.rematch && this.game.rematch.code)) return;
      const code = newCode();
      const record = rules.rematchRecord(this.game, code, Date.now(), this.config.leaveGraceMs);
      const room = this.env.GAMES.get(this.env.GAMES.idFromName(code));
      // While this waits, other events for this game may run (see the top).
      const made = await room.createRematch(record);
      if (made && made.inUse) continue; // that code is taken: draw another
      if (!this.game) return;
      await this.#settle(rules.setRematchCode(this.game, code, Date.now()));
      return;
    }
    throw new Error("no free code for the rematch");
  }

  // -------------------------------------------------------------------------
  // WebSockets

  /** GET /api/games/{code}/live: opens a WebSocket, for a seat with ?token= or else to watch. */
  async fetch(request) {
    if ((request.headers.get("upgrade") || "").toLowerCase() !== "websocket") {
      return Response.json(errorBody("bad_request", "Connect to this address with a WebSocket."), { status: 426 });
    }
    const token = new URL(request.url).searchParams.get("token");
    let seat = null;
    if (token) {
      seat = await this.#seatOf(token);
      if (this.game && !seat) return Response.json(errorBody("unauthorized", BAD_TOKEN), { status: 401 });
    }
    if (!this.game) return Response.json(errorBody("not_found", NO_GAME), { status: 404 });
    if (!this.#makeRoomFor(seat)) {
      return Response.json(errorBody("rate_limited", "Too many people are connected to this game."), { status: 429 });
    }

    const wasOnline = seat !== null && this.#openSockets(seat).length > 0;
    const pair = new WebSocketPair();
    const [client, server] = Object.values(pair);
    const now = Date.now();
    this.ctx.acceptWebSocket(server, [seat ?? WATCHER]);
    server.serializeAttachment({ seat, openedAt: now });

    // Opening a socket ends an absence. If this seat just came online,
    // everyone gets the new state; otherwise only the new socket needs it.
    const out = seat ? rules.setAway(this.game, seat, false, now) : rules.tick(this.game, now);
    const everyone = out.changed || (seat !== null && !wasOnline);
    await this.#settle(out, everyone);
    if (!everyone) send(server, this.#stateMessage());
    return new Response(null, { status: 101, webSocket: client });
  }

  /**
   * Makes space for one more socket. A seat keeps at most 3 (its oldest is
   * closed, usually a connection the phone already dropped), and a player
   * may take a watcher's place when the game is full. Returns false if a
   * watcher can't get in.
   */
  #makeRoomFor(seat) {
    const byAge = (a, b) => (infoOf(a).openedAt ?? 0) - (infoOf(b).openedAt ?? 0);
    const closed = new Set();
    const stillOpen = () => this.ctx.getWebSockets().filter((ws) => ws.readyState === OPEN && !closed.has(ws));
    if (seat) {
      const mine = stillOpen().filter((ws) => infoOf(ws).seat === seat).sort(byAge);
      while (mine.length >= MAX_SOCKETS_PER_SEAT) {
        const oldest = mine.shift();
        closed.add(oldest);
        closeSocket(oldest, 4001, "Replaced by a newer connection");
      }
    }
    let open = stillOpen();
    if (open.length < MAX_SOCKETS) return true;
    if (!seat) return false;
    const watchers = open.filter((ws) => !infoOf(ws).seat).sort(byAge);
    while (open.length >= MAX_SOCKETS && watchers.length > 0) {
      const oldest = watchers.shift();
      closed.add(oldest);
      closeSocket(oldest, 4002, "Making room for a player");
      open = stillOpen();
    }
    return open.length < MAX_SOCKETS;
  }

  /** The open sockets of a seat, leaving out `except` (a socket that is closing). */
  #openSockets(seat, except = null) {
    return this.ctx.getWebSockets(seat).filter((ws) => ws !== except && ws.readyState === OPEN);
  }

  async webSocketMessage() {
    // Clients only ever send "ping", which is answered without waking us.
    // Moves and actions go through the REST API, so anything else is ignored.
  }

  async webSocketClose(ws, code, reason) {
    // The client closed it: finish the closing handshake from our side.
    // (When we closed it, the handshake is already done.)
    if (ws.readyState !== CLOSED) {
      closeSocket(ws, code >= 3000 && code <= 4999 ? code : 1000, typeof reason === "string" ? reason.slice(0, 120) : "");
    }
    await this.#socketGone(ws);
  }

  async webSocketError(ws) {
    await this.#socketGone(ws);
  }

  /** When a seat's last socket goes, that seat is away. */
  async #socketGone(ws) {
    const { seat } = infoOf(ws);
    if (!seat || !this.game) return;
    if (this.#openSockets(seat, ws).length > 0) return;
    await this.#settle(rules.setAway(this.game, seat, true, Date.now()));
  }

  // -------------------------------------------------------------------------
  // The alarm

  async alarm() {
    this.alarmAt = null; // the alarm that woke us is used up
    if (!this.game) return;
    const now = Date.now();
    if (rules.shouldDelete(this.game, now, this.config.keepFinishedMs)) {
      for (const ws of this.ctx.getWebSockets()) closeSocket(ws, 1000, "This game has been cleared away");
      this.game = null;
      await this.ctx.storage.deleteAlarm();
      await this.ctx.storage.deleteAll();
      return;
    }
    await this.#settle(rules.tick(this.game, now));
  }

  /** Sets the alarm for the game's next deadline (no alarm if there is none). */
  async #syncAlarm() {
    const at = this.game ? rules.nextDeadline(this.game, this.config.keepFinishedMs) : null;
    if (at === this.alarmAt) return;
    // Noted before waiting, so a save that overlaps this one compares
    // against the alarm being set. Storage applies the two in order.
    this.alarmAt = at;
    if (at === null) await this.ctx.storage.deleteAlarm();
    else await this.ctx.storage.setAlarm(at);
  }

  // -------------------------------------------------------------------------
  // Saving and telling everyone

  /**
   * After every outcome: saves the game if it changed, moves the alarm to the
   * next deadline, and sends the new state and any notices to the sockets.
   * `visible` sends the state even when the record didn't change (a seat
   * coming online changes what players see without changing the record).
   */
  async #settle(out, visible = false) {
    if (out.changed) await this.ctx.storage.put("game", this.game);
    await this.#syncAlarm();
    if (out.changed || visible) {
      const message = this.#stateMessage();
      for (const ws of this.ctx.getWebSockets()) send(ws, message);
    }
    for (const notice of out.notices) {
      // A notice goes to the other side (and anyone watching), not to the seat it is about.
      const message = JSON.stringify({ type: "notice", kind: notice.kind, seat: notice.seat, at: notice.at });
      for (const ws of this.ctx.getWebSockets()) {
        if (infoOf(ws).seat !== notice.seat) send(ws, message);
      }
    }
  }

  /** The GameState as players see it right now. */
  #view() {
    return rules.view(this.game, Date.now(), {
      white: this.#openSockets("white").length > 0,
      black: this.#openSockets("black").length > 0,
    });
  }

  #stateMessage() {
    return JSON.stringify({ type: "state", game: this.#view() });
  }
}
