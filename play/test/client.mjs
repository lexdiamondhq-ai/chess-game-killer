// A small client for the game server, used by integration.mjs (against
// `wrangler dev`) and smoke.mjs (against a deployed server). It needs
// Node 22 or later, which has fetch and WebSocket built in.

/** Calls the REST API. Returns { status, json, text, headers }; never throws for an HTTP error. */
export async function api(base, method, path, { body, token, headers = {} } = {}) {
  const sent = { ...headers };
  if (token) sent.authorization = `Bearer ${token}`;
  if (body !== undefined && !sent["content-type"]) sent["content-type"] = "application/json";
  const response = await fetch(base + path, {
    method,
    headers: sent,
    body: body === undefined ? undefined : typeof body === "string" ? body : JSON.stringify(body),
    signal: AbortSignal.timeout(15000),
  });
  const text = await response.text();
  let json = null;
  try {
    json = JSON.parse(text);
  } catch {
    // Not JSON (a page, for example).
  }
  return { status: response.status, json, text, headers: response.headers };
}

/**
 * A WebSocket to /api/games/{code}/live that records every message, so a
 * test can wait for the one it expects.
 */
export class LiveSocket {
  constructor(base, code, token) {
    const url = new URL(`/api/games/${code}/live`, base);
    url.protocol = url.protocol === "https:" ? "wss:" : "ws:";
    if (token) url.searchParams.set("token", token);
    this.messages = [];
    this.waiters = [];
    this.closed = null;
    this.ws = new WebSocket(url);
    this.opened = new Promise((resolve, reject) => {
      this.ws.addEventListener("open", () => resolve(this), { once: true });
      this.ws.addEventListener("error", () => reject(new Error(`WebSocket to ${code} failed to open`)), { once: true });
    });
    this.opened.catch(() => {});
    this.ws.addEventListener("message", (event) => {
      const data = typeof event.data === "string" ? event.data : String(event.data);
      let message = data;
      try {
        message = JSON.parse(data);
      } catch {
        // "pong" is plain text.
      }
      this.messages.push(message);
      this.wake();
    });
    this.ws.addEventListener("close", (event) => {
      this.closed = { code: event.code, reason: event.reason };
      this.wake();
    });
  }

  wake() {
    for (const waiter of [...this.waiters]) waiter();
  }

  /** The first message so far (or to come) that matches, or a rejection after timeoutMs. */
  waitFor(predicate, what = "a message", timeoutMs = 8000) {
    return new Promise((resolve, reject) => {
      const check = () => {
        const found = this.messages.find((message) => {
          try {
            return predicate(message);
          } catch {
            return false;
          }
        });
        if (found !== undefined) {
          done();
          resolve(found);
        }
      };
      const timer = setTimeout(() => {
        done();
        reject(new Error(`timed out waiting for ${what}; got ${JSON.stringify(this.messages.map(summary))}`));
      }, timeoutMs);
      const done = () => {
        clearTimeout(timer);
        this.waiters = this.waiters.filter((waiter) => waiter !== check);
      };
      this.waiters.push(check);
      check();
    });
  }

  /** Waits for a state message whose game matches. */
  state(predicate, what = "a state", timeoutMs) {
    return this.waitFor((m) => m && m.type === "state" && predicate(m.game), what, timeoutMs).then((m) => m.game);
  }

  /** Waits for a notice of this kind about this seat. */
  notice(kind, seat, timeoutMs) {
    return this.waitFor((m) => m && m.type === "notice" && m.kind === kind && m.seat === seat, `a ${kind} notice for ${seat}`, timeoutMs);
  }

  /**
   * Waits until the server has closed the socket: its close frame has
   * arrived (readyState CLOSING) or the socket is closed. Under `wrangler
   * dev` the connection stays open after a close the server starts, so Node
   * never fires "close" for it; the close frame is what tells.
   */
  async whenClosing(timeoutMs = 8000) {
    const deadline = Date.now() + timeoutMs;
    while (this.ws.readyState < 2 && !this.closed) {
      if (Date.now() > deadline) throw new Error("timed out waiting for the server to close the socket");
      await new Promise((resolve) => setTimeout(resolve, 25));
    }
    return this;
  }

  /** True once the server has closed this socket (see whenClosing). */
  get closing() {
    return this.ws.readyState >= 2 || this.closed !== null;
  }

  send(text) {
    this.ws.send(text);
  }

  close() {
    try {
      this.ws.close(1000, "done");
    } catch {
      // Already closed.
    }
  }
}

function summary(message) {
  if (typeof message === "string") return message;
  if (message.type === "notice") return `notice:${message.kind}:${message.seat}`;
  if (message.type === "state") {
    const game = message.game;
    return `state:${game.status}:${game.moves.length}${game.result ? `:${game.result.reason}` : ""}`;
  }
  return message.type;
}

/** Fails with a message naming what was being checked. */
export function check(condition, message) {
  if (!condition) throw new Error(message);
}
