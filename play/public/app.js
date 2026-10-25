// Chess Game Killer in the browser: the home page, the invite page and the game itself.
// No framework and no build step. The server's protocol is in play/PROTOCOL.md.

import { Chess } from '/vendor/chess.js';
import { Board, parseFen } from './board.js';
import { setLook } from './looks.js';

// ---- Small helpers ------------------------------------------------------------------------

const $ = (sel, root = document) => root.querySelector(sel);

/** Builds an element. Strings become text nodes, so names typed by people are never parsed as HTML. */
function h(tag, props, ...kids) {
  const e = document.createElement(tag);
  for (const [k, v] of Object.entries(props || {})) {
    if (v == null || v === false) continue;
    if (k === 'class') e.className = v;
    else if (k.startsWith('on')) e.addEventListener(k.slice(2), v);
    else if (k === 'dataset') Object.assign(e.dataset, v);
    else if (v === true) e.setAttribute(k, '');
    else e.setAttribute(k, v);
  }
  append(e, kids);
  return e;
}
function append(e, kids) {
  for (const k of kids.flat()) {
    if (k == null || k === false) continue;
    e.append(k instanceof Node ? k : document.createTextNode(String(k)));
  }
  return e;
}

const ICONS = {
  copy: '<rect x="8.5" y="8.5" width="11.5" height="11.5" rx="2.6"/><path d="M15.5 8.5V6.6A2.6 2.6 0 0 0 12.9 4H6.6A2.6 2.6 0 0 0 4 6.6v6.3a2.6 2.6 0 0 0 2.6 2.6h1.9"/>',
  check: '<path d="M5 12.5l4.4 4.4L19 7.4"/>',
  share: '<path d="M12 14.5V3.8M7.8 7.8 12 3.6l4.2 4.2"/><path d="M8.5 10.5H7a2.5 2.5 0 0 0-2.5 2.5v5.5A2.5 2.5 0 0 0 7 21h10a2.5 2.5 0 0 0 2.5-2.5V13a2.5 2.5 0 0 0-2.5-2.5h-1.5"/>',
  mail: '<rect x="3.5" y="5.5" width="17" height="13" rx="2.6"/><path d="m4.5 7.5 7.5 5.6 7.5-5.6"/>',
  clock: '<circle cx="12" cy="12.5" r="8"/><path d="M12 8.3v4.4l2.8 1.8M9.6 2.8h4.8"/>',
  draw: '<circle cx="12" cy="12" r="8.3"/><path d="M8.6 10.2h6.8M8.6 13.8h6.8"/>',
  flag: '<path d="M6 21V4.2"/><path d="M6 4.6c2.2-1.2 4.2-1.1 6 0s3.8 1.2 6 0v8.2c-2.2 1.2-4.2 1.1-6 0s-3.8-1.2-6 0"/>',
  soundOn: '<path d="M4.5 9.5h3l4.5-4v13l-4.5-4h-3z"/><path d="M15.5 9a4.2 4.2 0 0 1 0 6M18 6.5a7.8 7.8 0 0 1 0 11"/>',
  soundOff: '<path d="M4.5 9.5h3l4.5-4v13l-4.5-4h-3z"/><path d="m16 9.5 5 5m0-5-5 5"/>',
  app: '<rect x="6.5" y="2.8" width="11" height="18.4" rx="2.8"/><path d="M10.6 17.8h2.8"/>',
  rematch: '<path d="M19.5 12a7.5 7.5 0 0 1-13 5.1"/><path d="M4.5 12a7.5 7.5 0 0 1 13-5.1"/><path d="M17.8 3.5v3.6h-3.6M6.2 20.5v-3.6h3.6"/>',
  plus: '<path d="M12 5v14M5 12h14"/>',
  camera: '<path d="M4 8.5A2.5 2.5 0 0 1 6.5 6h1.3l1.4-2h5.6l1.4 2h1.3A2.5 2.5 0 0 1 20 8.5v8a2.5 2.5 0 0 1-2.5 2.5h-11A2.5 2.5 0 0 1 4 16.5z"/><circle cx="12" cy="12.5" r="3.4"/>',
  record: '<circle cx="12" cy="12" r="8"/><circle cx="12" cy="12" r="3.2" fill="currentColor" stroke="none"/>',
  person: '<circle cx="12" cy="8" r="3.6"/><path d="M5 20a7 7 0 0 1 14 0"/>',
  leave: '<path d="M14 4.5h3.5A2.5 2.5 0 0 1 20 7v10a2.5 2.5 0 0 1-2.5 2.5H14"/><path d="M10 16.5 5.5 12 10 7.5M5.8 12H15"/>',
  shield: '<path d="M12 3l7 3v5c0 4.6-3 8.3-7 10-4-1.7-7-5.4-7-10V6l7-3z"/><path d="M9 12l2 2 4-4"/>',
  report: '<path d="M12 3.5 21 19.5H3z"/><path d="M12 10v4.2"/><circle cx="12" cy="16.9" r=".9" fill="currentColor"/>',
  wifi: '<path d="M3.5 9.5a12 12 0 0 1 17 0M6.5 12.6a7.6 7.6 0 0 1 11 0M9.5 15.7a3.4 3.4 0 0 1 5 0"/><circle cx="12" cy="18.6" r=".9" fill="currentColor"/>',
};
function icon(name) {
  const svg = document.createElementNS('http://www.w3.org/2000/svg', 'svg');
  svg.setAttribute('viewBox', '0 0 24 24');
  svg.setAttribute('fill', 'none');
  svg.setAttribute('stroke', 'currentColor');
  svg.setAttribute('stroke-width', '1.8');
  svg.setAttribute('stroke-linecap', 'round');
  svg.setAttribute('stroke-linejoin', 'round');
  svg.setAttribute('aria-hidden', 'true');
  svg.innerHTML = ICONS[name] || '';
  return svg;
}

const store = {
  get(key) {
    try { return JSON.parse(localStorage.getItem(key)); } catch { return null; }
  },
  set(key, value) {
    try { localStorage.setItem(key, JSON.stringify(value)); } catch { /* private mode */ }
  },
};
const seatKey = (code) => `cgk.seat.${code}`;
const NAME_KEY = 'cgk.name';
const SOUND_KEY = 'cgk.sound';

const other = (side) => (side === 'white' ? 'black' : 'white');
const sideWord = (side) => (side === 'white' ? 'White' : 'Black');
const isIOS = /iPad|iPhone|iPod/.test(navigator.userAgent) || (navigator.platform === 'MacIntel' && navigator.maxTouchPoints > 1);
const reducedMotion = () => window.matchMedia?.('(prefers-reduced-motion: reduce)').matches;

function plural(n, word) {
  return `${n} ${word}${n === 1 ? '' : 's'}`;
}
function duration(seconds) {
  if (seconds % 60 === 0) return plural(seconds / 60, 'minute');
  if (seconds < 60) return plural(seconds, 'second');
  return `${plural(Math.floor(seconds / 60), 'minute')} ${plural(seconds % 60, 'second')}`;
}
function clockWords(clock) {
  if (!clock) return 'No clock, play at your own pace';
  if (!clock.increment) return `${duration(clock.initial)} each`;
  return `${duration(clock.initial)} + ${plural(clock.increment, 'second')} a move`;
}

// ---- Network -------------------------------------------------------------------------------

const MESSAGES = {
  network: "Can’t reach the game right now. Check your connection and try again.",
  not_found: "This challenge isn’t here anymore.",
  seat_taken: 'Someone else accepted this challenge first.',
  game_over: 'This game has already ended.',
  cannot_claim: 'Your friend came back, so the game goes on.',
  rate_limited: 'That was a lot of tries at once. Wait a moment, then try again.',
  unauthorized: "This browser doesn’t hold a seat in this game.",
  illegal_move: "That move isn’t allowed here.",
  not_your_turn: "It isn’t your turn yet.",
  stale: 'The game moved on. Here is the latest position.',
  bad_request: "That didn’t work. Try again.",
  server: 'Something went wrong on our side. Try again in a moment.',
  server_error: 'Something went wrong on our side. Try again in a moment.',
};
function messageFor(err) {
  if (err?.code === 'rate_limited' && err.retryAfter > 0) {
    return `That was a lot of tries at once. Try again in ${plural(Math.ceil(err.retryAfter), 'second')}.`;
  }
  return MESSAGES[err?.code] || MESSAGES.server;
}

async function api(path, { method = 'GET', body, token } = {}) {
  const headers = { accept: 'application/json' };
  if (body) headers['content-type'] = 'application/json';
  if (token) headers.authorization = `Bearer ${token}`;
  let res;
  try {
    res = await fetch(path, { method, headers, body: body ? JSON.stringify(body) : undefined, cache: 'no-store' });
  } catch {
    throw Object.assign(new Error('network'), { code: 'network' });
  }
  const receivedAt = Date.now();
  let data = null;
  try { data = await res.json(); } catch { /* not JSON */ }
  if (!res.ok) {
    const err = new Error(data?.message || `HTTP ${res.status}`);
    err.code = data?.error || (res.status === 404 ? 'not_found' : res.status === 429 ? 'rate_limited' : 'server');
    err.status = res.status;
    err.game = data?.game || null;
    err.receivedAt = receivedAt;
    err.retryAfter = Number(res.headers.get('retry-after')) || 0;
    throw err;
  }
  if (data && typeof data === 'object') Object.defineProperty(data, 'receivedAt', { value: receivedAt });
  return data;
}

// ---- Sound -------------------------------------------------------------------------------

const sound = {
  ctx: null,
  buffers: {},
  enabled: store.get(SOUND_KEY) !== false,
  // The app's wooden set, at the app's levels (SoundPlayer.swift).
  volume: { move: 0.75, capture: 0.9, check: 0.9, castle: 0.75 },
  unlock() {
    const AC = window.AudioContext || window.webkitAudioContext;
    if (!AC) return;
    if (!this.ctx) {
      try { this.ctx = new AC(); } catch { return; }
      this.load();
    }
    if (this.ctx.state === 'suspended') this.ctx.resume().catch(() => {});
  },
  load() {
    for (const name of Object.keys(this.volume)) {
      fetch(`/sounds/${name}.mp3`)
        .then((r) => r.arrayBuffer())
        .then((b) => new Promise((ok, fail) => this.ctx.decodeAudioData(b, ok, fail)))
        .then((buf) => { this.buffers[name] = buf; })
        .catch(() => {});
    }
  },
  play(name) {
    if (!this.enabled || !this.ctx || this.ctx.state !== 'running') return;
    const buf = this.buffers[name];
    if (!buf) return;
    const src = this.ctx.createBufferSource();
    src.buffer = buf;
    const gain = this.ctx.createGain();
    gain.gain.value = this.volume[name] ?? 1;
    src.connect(gain).connect(this.ctx.destination);
    src.start();
  },
  forSan(san) {
    if (/[+#]/.test(san)) return 'check';
    if (san.includes('x')) return 'capture';
    if (san.startsWith('O-O')) return 'castle';
    return 'move';
  },
};
for (const type of ['pointerdown', 'touchend', 'keydown', 'click']) {
  document.addEventListener(type, () => sound.unlock(), { capture: true, passive: true });
}

// ---- Toasts and announcements --------------------------------------------------------------

function toast(text, iconName) {
  const box = $('#toasts');
  if (!box) return;
  const t = h('div', { class: 'toast' }, iconName ? icon(iconName) : null, text);
  box.append(t);
  while (box.children.length > 2) box.firstChild.remove();
  setTimeout(() => {
    t.classList.add('out');
    setTimeout(() => t.remove(), 300);
  }, 3400);
}

function announce(text) {
  const live = $('#announce');
  if (!live) return;
  live.textContent = '';
  setTimeout(() => { live.textContent = text; }, 30);
}

const PIECE_WORDS = { K: 'King', Q: 'Queen', R: 'Rook', B: 'Bishop', N: 'Knight' };
/** "Nxf3+" → "Knight takes f3, check", for screen readers. */
function spoken(san) {
  const check = san.includes('#') ? ', checkmate' : san.includes('+') ? ', check' : '';
  if (san.startsWith('O-O-O')) return `Castles queenside${check}`;
  if (san.startsWith('O-O')) return `Castles kingside${check}`;
  const m = san.match(/^([KQRBN])?[a-h]?[1-8]?(x)?([a-h][1-8])(?:=([QRBN]))?/);
  if (!m) return san;
  const piece = m[1] ? PIECE_WORDS[m[1]] : 'Pawn';
  const promo = m[4] ? `, promotes to ${PIECE_WORDS[m[4]].toLowerCase()}` : '';
  return `${piece} ${m[2] ? 'takes' : 'to'} ${m[3]}${promo}${check}`;
}

// ---- Boot ----------------------------------------------------------------------------------

let boot = {};
try { boot = JSON.parse($('#boot')?.textContent || '{}'); } catch { boot = {}; }

// ---- Home ----------------------------------------------------------------------------------

const CLOCK_PRESETS = {
  '3+2': { initial: 180, increment: 2 },
  '5+0': { initial: 300, increment: 0 },
  '10+0': { initial: 600, increment: 0 },
  '15+10': { initial: 900, increment: 10 },
  none: null,
};

function initHome() {
  const form = $('#create-form');
  const nameInput = $('#name');
  const button = $('#create-btn');
  const error = $('#create-error');
  const saved = store.get(NAME_KEY);
  if (saved && nameInput) nameInput.value = saved;

  const boardHost = $('#home-board');
  if (boardHost) {
    const b = new Board(boardHost, { interactive: false, coords: true, orientation: 'white', label: 'A game in progress' });
    // The Italian Game, a few moves in: quiet, classical, every piece easy to read.
    b.setPosition('r1bqk2r/pppp1ppp/2n2n2/2b1p3/2B1P3/2P2N2/PP1P1PPP/RNBQK2R w KQkq - 1 5', { lastMove: ['g8', 'f6'], animate: false });
  }

  // The clock in plain words under the choices, so "3 + 2" never has to explain itself.
  const hint = $('#clock-hint');
  const showClock = () => {
    const chosen = form?.querySelector('input[name="clock"]:checked');
    if (hint && chosen) hint.textContent = clockWords(CLOCK_PRESETS[chosen.value] ?? null);
  };
  form?.addEventListener('change', showClock);
  showClock();

  // Coming back with the Back button can restore this page as it was left, mid "Creating…".
  const resetButton = () => {
    button.disabled = false;
    button.replaceChildren('Create challenge');
  };
  window.addEventListener('pageshow', (e) => { if (e.persisted) resetButton(); });

  form?.addEventListener('submit', async (e) => {
    e.preventDefault();
    if (button.disabled) return;
    const data = new FormData(form);
    const name = String(data.get('name') || '').trim();
    const clock = CLOCK_PRESETS[data.get('clock')] ?? null;
    const side = data.get('side') || 'random';
    store.set(NAME_KEY, name);
    error.hidden = true;
    button.disabled = true;
    button.replaceChildren(h('span', { class: 'spinner', 'aria-hidden': 'true' }), 'Creating…');
    try {
      const res = await api('/api/games', { method: 'POST', body: { name, side, clock } });
      store.set(seatKey(res.code), { token: res.token, seat: res.seat });
      location.assign(`/c/${res.code}`);
    } catch (err) {
      error.textContent = messageFor(err);
      error.hidden = false;
      resetButton();
    }
  });
}

// ---- The game page -------------------------------------------------------------------------

const S = {
  code: null,
  token: null,
  seat: null, // 'white' | 'black' | null for a visitor
  game: null,
  offset: 0, // server time minus local time
  pending: null, // { uci, ply, san, fen, at }
  view: null,
  board: null,
  ui: null,
  shownMoves: null,
  disp: null,
  confirm: null,
  busy: null,
  waitedFor: null, // the absence the player chose to wait out instead of claiming the win
  claimShown: false,
  ws: null,
  wsOpen: false,
  wsAttempts: 0,
  wsTimer: null,
  pingTimer: null,
  lastMessageAt: 0,
  pollTimer: null,
  tickTimer: null,
  flagRefreshAt: 0,
  switching: false,
  wsDownSince: Date.now(),
};

const serverNow = () => Date.now() + S.offset;

function initGame() {
  S.code = String(boot.code || '').toUpperCase();
  const saved = store.get(seatKey(S.code));
  if (saved?.token) {
    S.token = saved.token;
    S.seat = saved.seat === 'white' || saved.seat === 'black' ? saved.seat : null;
  }
  if (boot.game) {
    // The page's own response time is the closest local moment to the server's `now`.
    let receivedAt = Date.now();
    try {
      const nav = performance.getEntriesByType('navigation')[0];
      if (nav?.responseStart) receivedAt = performance.timeOrigin + nav.responseStart;
    } catch { /* older browsers */ }
    applyState(boot.game, { force: true, receivedAt, quiet: true });
  }
  render();
  connect();

  document.addEventListener('visibilitychange', () => {
    if (document.visibilityState === 'hidden') {
      reportPresence('away');
    } else {
      reportPresence('back');
      if (!S.wsOpen) reconnectNow();
      refresh();
    }
  });
  window.addEventListener('pagehide', () => reportPresence('away'));
  window.addEventListener('pageshow', (e) => {
    if (e.persisted) { reportPresence('back'); reconnectNow(); refresh(); }
  });
  window.addEventListener('online', () => { reconnectNow(); refresh(); });
}

/** Takes a GameState from the server. Older states than the one on screen are ignored. */
function applyState(game, { force = false, receivedAt = Date.now(), quiet = false } = {}) {
  if (!game || game.code !== S.code) return;
  if (!force && S.game && game.updatedAt < S.game.updatedAt) return;
  if (typeof game.now === 'number') S.offset = game.now - receivedAt;
  const prev = S.game;
  S.game = game;
  setLook(game.look); // the board the friend who sent the link plays on in the app
  if (S.joining) return; // the join's answer decides what this page shows
  if (S.pending && (game.moves.length > S.pending.ply || game.status !== 'active')) S.pending = null;
  if (S.confirm && game.status !== 'active' && game.status !== 'waiting') S.confirm = null;

  if (!quiet && prev) {
    if (prev.status === 'waiting' && game.status === 'active' && S.seat && game[other(S.seat)].seated) {
      toast(`${nameOf(other(S.seat))} accepted. You play ${sideWord(S.seat)}.`, 'person');
    }
    if (prev.status === 'waiting' && game.status === 'active' && !S.seat && S.view === 'invite') {
      toast('Someone else accepted first. You’re watching.', 'person');
    }
  }
  if (game.rematch?.code && !S.switching) {
    switchTo(game.rematch.code);
    return;
  }
  render();
  if (prev && prev.status !== 'over' && game.status === 'over') {
    const [title, detail] = resultWords();
    announce(detail ? `${title}. ${detail}.` : `${title}.`);
  }
}

async function refresh() {
  if (!S.code) return;
  try {
    const d = await api(`/api/games/${S.code}`);
    S.lastPollOkAt = Date.now();
    applyState(d.game, { receivedAt: d.receivedAt });
  } catch (err) {
    if (err.code === 'not_found') {
      S.game = null;
      render();
    }
  }
}

// ---- WebSocket, with polling as the fallback ---------------------------------------------

function connect() {
  if (!S.code || S.ws || !S.game || S.elsewhere || S.socketDone) return;
  if (S.game.status === 'over' && S.game.result && ['cancelled', 'expired'].includes(S.game.result.reason)) return;
  const proto = location.protocol === 'https:' ? 'wss' : 'ws';
  const url = `${proto}://${location.host}/api/games/${S.code}/live${S.token ? `?token=${encodeURIComponent(S.token)}` : ''}`;
  let ws;
  try { ws = new WebSocket(url); } catch { scheduleReconnect(); return; }
  S.ws = ws;
  const code = S.code;
  const openTimer = setTimeout(() => { if (!S.wsOpen && S.ws === ws) ws.close(); }, 8000);
  ws.addEventListener('open', () => {
    if (S.ws !== ws) return;
    clearTimeout(openTimer);
    S.wsOpen = true;
    S.wsFailedOpens = 0;
    S.wsDownSince = 0;
    S.wsAttempts = 0;
    S.lastMessageAt = Date.now();
    stopPolling();
    clearInterval(S.pingTimer);
    S.pingTimer = setInterval(() => {
      if (ws.readyState !== WebSocket.OPEN) return;
      if (Date.now() - S.lastMessageAt > 50000) { ws.close(); return; }
      try { ws.send('ping'); } catch { /* closing */ }
    }, 20000);
    renderPresenceOnly();
  });
  ws.addEventListener('message', (e) => {
    if (S.ws !== ws || S.code !== code) return;
    S.lastMessageAt = Date.now();
    if (e.data === 'pong') return;
    let msg;
    try { msg = JSON.parse(e.data); } catch { return; }
    if (msg.type === 'state') applyState(msg.game, { receivedAt: Date.now() });
    else if (msg.type === 'notice') onNotice(msg);
  });
  ws.addEventListener('close', (e) => {
    clearTimeout(openTimer);
    if (S.ws !== ws) return;
    const opened = S.wsOpen;
    S.ws = null;
    S.wsOpen = false;
    S.wsDownSince = S.wsDownSince || Date.now();
    clearInterval(S.pingTimer);
    renderPresenceOnly();
    if (e.code === 4001) {
      // This seat opened the game somewhere newer. Stay off the socket; polling keeps the page right.
      S.elsewhere = true;
      startPolling();
      if (S.view === 'game' && S.ui) { S.ui.barKey = null; updateBar(); }
      else toast('This game is open in another tab or device', 'app');
      return;
    }
    if (e.code >= 4000 && e.code < 5000) {
      // The server closed it on purpose (a spectator making room for a player): that is final.
      S.socketDone = true;
      startPolling();
      return;
    }
    if (!opened && S.token) {
      S.wsFailedOpens = (S.wsFailedOpens || 0) + 1;
      if (S.wsFailedOpens >= 2) checkSeat();
    }
    scheduleReconnect();
  });
  ws.addEventListener('error', () => { /* close follows */ });
}

function scheduleReconnect() {
  clearTimeout(S.wsTimer);
  if (document.visibilityState === 'hidden') return;
  S.wsAttempts++;
  if (S.wsAttempts >= 2) startPolling();
  const delay = Math.min(15000, 600 * 2 ** (S.wsAttempts - 1)) * (0.8 + Math.random() * 0.4);
  S.wsTimer = setTimeout(connect, delay);
}

/** A seat whose socket never opens may hold a token the server no longer takes (401 at upgrade). */
async function checkSeat() {
  if (!S.token || S.checkingSeat || Date.now() - (S.seatCheckedAt || 0) < 60000) return;
  S.checkingSeat = true;
  S.seatCheckedAt = Date.now();
  const code = S.code;
  try {
    await api(`/api/games/${code}/join`, { method: 'POST', token: S.token, body: { name: store.get(NAME_KEY) || '' } });
  } catch (err) {
    if (err.code === 'unauthorized' && S.code === code) {
      dropSeat();
      closeSocket();
      S.wsAttempts = 0;
      render();
      connect();
      toast(MESSAGES.unauthorized);
    }
  } finally {
    S.checkingSeat = false;
  }
}

function useHere() {
  S.elsewhere = false;
  S.wsAttempts = 0;
  stopPolling();
  reconnectNow();
  refresh();
  if (S.view === 'game' && S.ui) { S.ui.barKey = null; updateBar(); }
}

function reconnectNow() {
  clearTimeout(S.wsTimer);
  if (S.ws) return;
  S.wsAttempts = 0;
  connect();
}

function closeSocket() {
  clearTimeout(S.wsTimer);
  clearInterval(S.pingTimer);
  const ws = S.ws;
  S.ws = null;
  S.wsOpen = false;
  if (ws) try { ws.close(); } catch { /* already closed */ }
}

function startPolling() {
  if (S.pollTimer) return;
  S.pollTimer = setInterval(() => {
    if (document.visibilityState !== 'hidden') refresh();
  }, 3000);
}
function stopPolling() {
  clearInterval(S.pollTimer);
  S.pollTimer = null;
}

/** Tells the server this seat left the page or came back. Leaving forfeits a timed game after the grace. */
function reportPresence(type) {
  if (!S.token || !S.game || S.game.status !== 'active') return;
  const url = `/api/games/${S.code}/action`;
  const body = JSON.stringify({ type, token: S.token });
  if (type === 'away' && navigator.sendBeacon) {
    try {
      if (navigator.sendBeacon(url, new Blob([body], { type: 'text/plain;charset=UTF-8' }))) return;
    } catch { /* fall through */ }
  }
  fetch(url, {
    method: 'POST',
    body,
    keepalive: true,
    headers: { 'content-type': 'application/json', authorization: `Bearer ${S.token}` },
  }).catch(() => {});
}

function onNotice(n) {
  if (!S.game) return;
  const mine = S.seat && n.seat === S.seat;
  if (mine) return;
  const name = nameOf(n.seat);
  switch (n.kind) {
    case 'screenshot': toast(`${name} took a screenshot`, 'camera'); break;
    case 'recording': toast(`${name} started recording the screen`, 'record'); break;
    case 'away': toast(leaveRuleApplies() ? `${name} left the page` : `${name} stepped away`, 'leave'); break;
    case 'back': toast(`${name} is back`, 'person'); break;
    case 'draw_offer': if (!S.seat) toast(`${name} offers a draw`, 'draw'); break;
    case 'draw_declined': toast(`${name} declined the draw`, 'draw'); break;
    case 'rematch_offer': toast(`${name} wants a rematch`, 'rematch'); break;
    default: break;
  }
}

// ---- Game facts ----------------------------------------------------------------------------

function nameOf(side) {
  return S.game?.[side]?.name || sideWord(side);
}
const GRACE_MS = 60000;
/** "a minute", or "45 seconds" when the server says otherwise. */
function graceWords(g = S.game) {
  const seconds = Math.max(1, Math.round((g?.leaveGraceMs || GRACE_MS) / 1000));
  if (seconds === 60) return 'a minute';
  if (seconds % 60 === 0) return plural(seconds / 60, 'minute');
  return plural(seconds, 'second');
}
/** The fair-play rules, said before a game and on its first screen. */
function fairWords(g = S.game) {
  return `Fair play: no hints or engines. In a timed game, if you leave for over ${graceWords(g)}, your friend can claim the win. Screenshots in the app are shown to your friend.`;
}
/** When the other side may claim the win because `side` left, in server ms; null if they can't. */
function claimableAt(side, g = S.game) {
  const seat = g?.[side];
  if (!seat || seat.away == null || !leaveRuleApplies(g)) return null;
  if (seat.claimableAt != null) return seat.claimableAt;
  return seat.away + (g.leaveGraceMs || GRACE_MS);
}
/** I can claim the win right now: my friend has been away past the grace period. */
function canClaim(g = S.game) {
  if (!S.seat || !g || g.status !== 'active') return false;
  const at = claimableAt(other(S.seat), g);
  return at != null && serverNow() >= at;
}
function claimOffered(g = S.game) {
  return canClaim(g) && S.waitedFor !== g[other(S.seat)].away;
}
function leaveRuleApplies(g = S.game) {
  return !!(g && g.clock && g.status === 'active' && g.moves.length >= 2);
}

function kingSquare(fen, color) {
  for (const [sq, code] of parseFen(fen)) if (code === `${color}K`) return sq;
  return null;
}

/** The position on screen: the server's, plus my move while it is on its way. */
function display() {
  const g = S.game;
  let fen = g.fen;
  let moves = g.moves;
  let san = g.san;
  if (S.pending && g.status === 'active' && g.moves.length === S.pending.ply) {
    fen = S.pending.fen;
    moves = [...g.moves, S.pending.uci];
    san = [...g.san, S.pending.san];
  }
  let chess;
  try { chess = new Chess(fen); } catch { chess = new Chess(); }
  const turnColor = chess.turn();
  const inCheck = typeof chess.inCheck === 'function' ? chess.inCheck() : chess.isCheck();
  const lastUci = moves[moves.length - 1];
  return {
    fen,
    moves,
    san,
    chess,
    turn: turnColor === 'w' ? 'white' : 'black',
    check: inCheck ? kingSquare(fen, turnColor) : null,
    last: lastUci ? [lastUci.slice(0, 2), lastUci.slice(2, 4)] : null,
  };
}

function movableColor() {
  const g = S.game;
  if (!S.seat || !g || g.status !== 'active' || S.pending || !S.disp) return null;
  return S.disp.turn === S.seat ? S.seat[0] : null;
}

function destsFrom(square) {
  if (!movableColor() || !S.disp) return [];
  let moves = [];
  try { moves = S.disp.chess.moves({ square, verbose: true }); } catch { moves = []; }
  return moves.map((m) => ({ to: m.to, promotion: m.promotion || null, capture: /[ce]/.test(m.flags) }));
}

const START_COUNT = { p: 8, n: 2, b: 2, r: 2, q: 1 };
const VALUE = { p: 1, n: 3, b: 3, r: 5, q: 9 };
/** Pieces each side has taken, and who is ahead on material. */
function material(fen) {
  const count = { w: { p: 0, n: 0, b: 0, r: 0, q: 0 }, b: { p: 0, n: 0, b: 0, r: 0, q: 0 } };
  for (const ch of String(fen).split(' ')[0]) {
    const t = ch.toLowerCase();
    if (!(t in VALUE)) continue;
    count[ch === t ? 'b' : 'w'][t]++;
  }
  const score = (c) => Object.entries(count[c]).reduce((s, [t, n]) => s + VALUE[t] * n, 0);
  const missing = (c) => ['p', 'n', 'b', 'r', 'q'].map((t) => [t, Math.max(0, START_COUNT[t] - count[c][t])]).filter(([, n]) => n > 0);
  return { white: missing('b'), black: missing('w'), diff: score('w') - score('b') };
}

function clockMs(side) {
  const g = S.game;
  const c = g?.clocks;
  if (!c) return null;
  let ms = c[side];
  if (g.status === 'active' && c.running === side && c.since != null) {
    const until = S.pending ? S.pending.at + S.offset : serverNow();
    ms -= until - c.since;
  }
  return Math.max(0, ms);
}

function formatClock(ms) {
  // As the app shows it: rounded up, in tenths for the last ten seconds ("0:09.8").
  const tenths = Math.ceil(Math.max(0, ms) / 100);
  if (tenths <= 100) return `0:${String(Math.floor(tenths / 10)).padStart(2, '0')}.${tenths % 10}`;
  const total = Math.ceil(tenths / 10);
  const h = Math.floor(total / 3600);
  const m = Math.floor((total % 3600) / 60);
  const s = String(total % 60).padStart(2, '0');
  return h ? `${h}:${String(m).padStart(2, '0')}:${s}` : `${m}:${s}`;
}

/** The result in plain words, from the viewer's side. */
function resultWords() {
  const g = S.game;
  const r = g.result || {};
  const me = S.seat;
  const winner = r.winner;
  const loser = winner ? other(winner) : null;
  // Who won, then how, in a few words: "Sam won" over "You ran out of time".
  const who = (side) => (side === me ? 'You' : nameOf(side));
  const title = winner ? `${who(winner)} won` : r.reason === 'aborted' ? 'Game aborted' : 'Draw';
  const L = loser && who(loser);
  switch (r.reason) {
    case 'checkmate': return [title, 'By checkmate'];
    case 'resign': return [title, `${L} resigned`];
    case 'timeout': return [title, `${L} ran out of time`];
    case 'left': return [title, loser === me ? `You were away for over ${graceWords()}` : `${L} left the game`];
    case 'stalemate': return [title, 'By stalemate'];
    case 'repetition': return [title, 'The same position, three times'];
    case 'fifty_moves': return [title, 'By the fifty-move rule'];
    case 'insufficient': return [title, 'Not enough pieces left to mate'];
    case 'agreement': return [title, 'By agreement'];
    case 'timeout_insufficient': return [title, `${who(g.turn)} ran out of time, with no mate possible`];
    case 'aborted': return [title, 'It ended before both sides moved'];
    default: return ['Game over', ''];
  }
}

// ---- Rendering -----------------------------------------------------------------------------

function viewOf() {
  const g = S.game;
  if (!g) return { name: 'note', key: 'note:gone' };
  const reason = g.result?.reason;
  if (g.status === 'over' && (reason === 'cancelled' || reason === 'expired')) return { name: 'note', key: `note:${reason}` };
  if (g.status === 'waiting') return S.seat ? { name: 'wait', key: `wait:${g.code}` } : { name: 'invite', key: `invite:${g.code}` };
  return { name: 'game', key: `game:${g.code}:${S.seat || 'watch'}` };
}

function render() {
  const app = $('#app');
  if (!app) return;
  const v = viewOf();
  if (v.key !== S.viewKey) {
    S.viewKey = v.key;
    S.view = v.name;
    S.confirm = null;
    if (S.board) { S.board.destroy(); S.board = null; }
    S.ui = null;
    S.shownMoves = null;
    stopTicking();
    let node;
    if (v.name === 'invite') node = buildInvite();
    else if (v.name === 'wait') node = buildWait();
    else if (v.name === 'game') node = buildGame();
    else node = buildNote(v.key);
    const first = !app.firstElementChild || app.firstElementChild.tagName === 'NOSCRIPT';
    app.replaceChildren(node);
    document.documentElement.classList.toggle('in-game', v.name === 'game');
    if (!first && window.scrollY > 0) window.scrollTo(0, 0);
  }
  if (S.view === 'game') updateGame();
  renderTop();
  renderTitle();
}

function renderTitle() {
  const g = S.game;
  let t = 'Chess Game Killer';
  if (S.view === 'invite') t = `${nameOf(g.creator)} challenged you to chess · ${t}`;
  else if (S.view === 'wait') t = `Waiting for your friend · ${t}`;
  else if (S.view === 'game' && g) {
    if (g.status === 'over') t = `${resultWords()[0]} · ${t}`;
    else if (S.seat) t = `${S.disp?.turn === S.seat ? 'Your move' : `${nameOf(other(S.seat))} to move`} · ${t}`;
    else t = `${nameOf('white')} vs ${nameOf('black')} · ${t}`;
  } else if (S.view === 'note') t = `This challenge isn’t here anymore · ${t}`;
  if (document.title !== t) document.title = t;
}

function renderTop() {
  const end = $('#top-end');
  if (!end) return;
  const key = `${S.view}:${S.seat ? 'p' : 'w'}:${S.game?.status}:${sound.enabled}`;
  if (end.dataset.key === key) return;
  end.dataset.key = key;
  end.replaceChildren();
  if (S.view === 'game' && !S.seat && S.game?.status === 'active') end.append(h('span', { class: 'live-pill' }, 'Watching live'));
  if (S.view === 'game') {
    const btn = h('button', {
      class: 'icon-btn',
      type: 'button',
      'aria-pressed': String(sound.enabled),
      'aria-label': sound.enabled ? 'Sound on' : 'Sound off',
      title: sound.enabled ? 'Sound on' : 'Sound off',
      onclick: () => {
        sound.enabled = !sound.enabled;
        store.set(SOUND_KEY, sound.enabled);
        sound.unlock();
        renderTop();
      },
    }, icon(sound.enabled ? 'soundOn' : 'soundOff'));
    end.append(btn);
  }
}

function previewBoard(side) {
  const wrap = h('div', { class: 'preview-wrap' });
  const b = new Board(wrap, { interactive: false, coords: false, orientation: side, label: `Board, you play ${sideWord(side)}` });
  b.setPosition(S.game?.fen || 'rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1', { animate: false });
  return wrap;
}

function chip(iconNode, text) {
  return h('span', { class: 'chip' }, iconNode, text);
}
function sideChip(side) {
  return chip(h('span', { class: `chip-piece ${side[0]}K`, style: 'background-size:100% 100%', 'aria-hidden': 'true' }), `You play ${sideWord(side)}`);
}

// ---- Invite --------------------------------------------------------------------------------

function buildInvite() {
  const g = S.game;
  const mySide = other(g.creator);
  const creator = nameOf(g.creator);
  const input = h('input', {
    class: 'input',
    id: 'join-name',
    name: 'name',
    type: 'text',
    maxlength: '24',
    autocomplete: 'nickname',
    autocapitalize: 'words',
    spellcheck: 'false',
    enterkeyhint: 'go',
    placeholder: 'Your name',
  });
  input.value = store.get(NAME_KEY) || '';
  const button = h('button', { class: 'btn btn-primary btn-block', type: 'submit' }, 'Accept and play');
  const error = h('p', { class: 'form-error invite-error', role: 'alert', hidden: true });
  const form = h('form', { class: 'invite-form', novalidate: true },
    h('label', { class: 'sr-only', for: 'join-name' }, 'Your name'),
    input,
    button,
    isIOS ? h('a', { class: 'btn btn-secondary btn-block', href: `chessgamekiller://c/${g.code}` }, icon('app'), 'Open in the app') : null,
    error,
  );
  form.addEventListener('submit', async (e) => {
    e.preventDefault();
    const name = input.value.trim();
    store.set(NAME_KEY, name);
    error.hidden = true;
    button.disabled = true;
    button.replaceChildren(h('span', { class: 'spinner', 'aria-hidden': 'true' }), 'Joining…');
    // Until the join answers, the socket may already report the game as started; that
    // must not read as someone else taking the seat.
    S.joining = true;
    try {
      const res = await api(`/api/games/${S.code}/join`, { method: 'POST', body: { name } });
      S.joining = false;
      S.token = res.token;
      S.seat = res.seat;
      store.set(seatKey(S.code), { token: res.token, seat: res.seat });
      closeSocket();
      applyState(res.game, { receivedAt: res.receivedAt, quiet: true });
      render();
      connect();
    } catch (err) {
      S.joining = false;
      if (err.game) applyState(err.game, { force: true, receivedAt: err.receivedAt, quiet: true });
      else render();
      if (S.view === 'invite') {
        error.textContent = messageFor(err);
        error.hidden = false;
        button.disabled = false;
        button.replaceChildren('Accept and play');
      } else {
        toast(messageFor(err));
      }
    }
  });

  return h('section', { class: 'view view-invite' },
    previewBoard(mySide),
    h('h1', {}, `${creator} challenged you to chess`),
    h('div', { class: 'chips' }, chip(icon('clock'), clockWords(g.clock)), sideChip(mySide)),
    form,
    h('p', { class: 'fine fair' }, fairWords()),
  );
}

// ---- Waiting for the friend (the creator's view) --------------------------------------------

function buildWait() {
  const g = S.game;
  const url = `${location.origin}/c/${g.code}`;
  const host = url.replace(/^https?:\/\//, '').replace(/\/c\/.*$/, '');
  const copyBtn = h('button', { class: 'btn btn-secondary', type: 'button' }, icon('copy'), 'Copy');
  copyBtn.addEventListener('click', async () => {
    const ok = await copyText(url);
    copyBtn.replaceChildren(icon(ok ? 'check' : 'copy'), ok ? 'Copied' : 'Copy');
    if (!ok) toast('Select the link and copy it.');
    setTimeout(() => copyBtn.replaceChildren(icon('copy'), 'Copy'), 2200);
  });
  const myName = g[S.seat]?.name;
  const shareText = 'Play me at chess. Tap the link to accept.';
  const actions = h('div', { class: 'share-row' });
  if (navigator.share) {
    actions.append(h('button', {
      class: 'btn btn-primary btn-block',
      type: 'button',
      onclick: () => navigator.share({ title: 'Chess Game Killer', text: shareText, url }).catch(() => {}),
    }, icon('share'), 'Share link'));
  } else {
    const subject = `${myName && myName !== 'Player' ? myName : 'A friend'} challenged you to chess`;
    actions.append(h('a', {
      class: 'btn btn-primary btn-block',
      href: `mailto:?subject=${encodeURIComponent(subject)}&body=${encodeURIComponent(`${shareText}\n\n${url}`)}`,
    }, icon('mail'), 'Send by email'));
  }

  const cancelArea = h('div', { class: 'cancel-area' });
  const drawCancel = () => {
    cancelArea.replaceChildren(h('button', {
      class: 'btn btn-quiet',
      type: 'button',
      onclick: () => {
        cancelArea.replaceChildren(
          h('p', { class: 'fine' }, 'Withdraw this challenge? The link will stop working.'),
          h('div', { class: 'share-row two', style: 'margin-top:10px' },
            h('button', { class: 'btn btn-secondary btn-sm', type: 'button', onclick: drawCancel }, 'Keep it'),
            h('button', {
              class: 'btn btn-secondary btn-sm btn-danger',
              type: 'button',
              onclick: () => act('cancel'),
            }, 'Withdraw'),
          ),
        );
      },
    }, 'Withdraw challenge'));
  };
  drawCancel();

  return h('section', { class: 'view view-wait' },
    previewBoard(S.seat),
    h('h1', {}, 'Waiting for your friend'),
    h('p', { class: 'lede' }, 'Send this link by text or email. The game starts as soon as they accept.'),
    h('div', { class: 'link-box' },
      h('div', { class: 'link-text' },
        h('span', { class: 'link-host' }, `${host}/c/`),
        h('span', { class: 'link-code', 'aria-label': `Code ${g.code.split('').join(' ')}` }, g.code)),
      copyBtn),
    actions,
    h('div', { class: 'chips' }, chip(icon('clock'), clockWords(g.clock)), sideChip(S.seat)),
    cancelArea,
  );
}

async function copyText(text) {
  try {
    await navigator.clipboard.writeText(text);
    return true;
  } catch {
    const ta = h('textarea', { style: 'position:fixed;opacity:0;top:0;left:0', readonly: true });
    ta.value = text;
    document.body.append(ta);
    ta.select();
    let ok = false;
    try { ok = document.execCommand('copy'); } catch { ok = false; }
    ta.remove();
    return ok;
  }
}

// ---- Notes (gone, withdrawn, expired) ------------------------------------------------------

function buildNote(key) {
  const g = S.game;
  let title = "This challenge isn’t here anymore";
  let text = 'It may have expired, or the person who sent it withdrew it.';
  if (key === 'note:cancelled') {
    const creatorIsMe = S.seat && g.creator === S.seat;
    title = creatorIsMe ? 'You withdrew this challenge' : "This challenge isn’t here anymore";
    text = creatorIsMe ? 'The link no longer works. Start a new one any time.' : `${nameOf(g.creator)} withdrew this challenge.`;
  } else if (key === 'note:expired') {
    title = 'This challenge expired';
    text = 'Nobody played it in time. Start a fresh one.';
  }
  return h('section', { class: 'view view-note' },
    h('div', { class: 'note-mark', 'aria-hidden': 'true' }, h('img', { src: '/pieces/wK.svg', alt: '' }), h('img', { src: '/pieces/bK.svg', alt: '' })),
    h('h1', {}, title),
    h('p', { class: 'lede' }, text),
    h('a', { class: 'btn btn-primary', href: '/' }, 'Challenge a friend'),
  );
}

// ---- The game view -------------------------------------------------------------------------

function buildPlate(side, role) {
  const avatar = h('div', { class: `avatar ${side}`, 'aria-hidden': 'true' });
  const name = h('span', { class: 'pname' });
  const presence = h('span', { class: 'presence' });
  const caps = h('div', { class: 'caps', 'aria-hidden': 'true' });
  const clock = h('div', { class: 'clock', role: 'timer', 'aria-live': 'off' });
  const el = h('div', { class: `plate ${role}`, dataset: { side } },
    avatar,
    h('div', { class: 'who' }, h('div', { class: 'name-line' }, name, presence), caps),
    clock);
  return { el, side, role, avatar, name, presence, caps, clock, capsKey: null };
}

function buildGame() {
  const orientation = S.seat === 'black' ? 'black' : 'white';
  const opp = buildPlate(other(orientation), 'opp');
  const me = buildPlate(orientation, 'me');
  const slot = h('div', { class: 'board-slot' });
  S.board = new Board(slot, {
    orientation,
    coords: true,
    interactive: !!S.seat,
    label: S.seat ? `Chess board. You play ${sideWord(S.seat)}.` : 'Chess board',
    movable: movableColor,
    dests: destsFrom,
    onMove: onUserMove,
    onInteract: () => sound.unlock(),
  });
  if (S.seat) S.board.root.classList.add('interactive');
  const moves = h('div', { class: 'moves', role: 'log', 'aria-label': 'Moves', tabindex: '-1' });
  const bar = h('div', { class: 'bar' });
  const after = h('div', { class: 'after', hidden: true },
    h('a', { class: 'after-link', href: '/' }, icon('plus'), S.seat ? 'New game' : 'Challenge a friend'),
    h('p', { class: 'app-line' }, 'The iPhone app is coming soon to the App Store.'));
  const reportBtn = h('button', {
    class: 'report-link',
    type: 'button',
    hidden: true,
    onclick: () => { S.confirm = 'report'; updateBar(); },
  });
  // Under the game: the fair-play rules until both sides have moved, then a quiet Report.
  const fair = h('p', { class: 'fair-note', hidden: true }, icon('shield'), h('span', {}));
  const foot = h('div', { class: 'game-foot' }, fair, reportBtn);
  const view = h('section', { class: 'view view-game', 'aria-label': 'Game' }, opp.el, slot, me.el, moves, bar, after, foot);
  S.ui = { view, opp, me, moves, bar, after, fair, report: reportBtn, reportKey: null, barKey: null, movesKey: null };
  startTicking();
  return view;
}

function updateGame() {
  const g = S.game;
  const ui = S.ui;
  if (!g || !ui) return;
  S.disp = display();
  ui.view.classList.toggle('is-over', g.status === 'over');
  syncBoard();
  updatePlate(ui.opp);
  updatePlate(ui.me);
  updateMoves();
  updateBar();
  tick();
}

function syncBoard() {
  const d = S.disp;
  const prev = S.shownMoves;
  if (!movableColor()) S.board.cancelPromotion(); // the game ended while the picker was open
  const same = prev && prev.length === d.moves.length && prev.every((m, i) => m === d.moves[i]);
  if (same) {
    S.board.refreshMarks();
    return;
  }
  const oneMore = prev && d.moves.length === prev.length + 1 && prev.every((m, i) => m === d.moves[i]);
  const near = prev && Math.abs(d.moves.length - prev.length) <= 2;
  S.board.setPosition(d.fen, { lastMove: d.last, check: d.check, animate: !!near, dragged: S.droppedOn });
  S.droppedOn = null;
  S.shownMoves = d.moves;
  if (oneMore) {
    const san = d.san[d.san.length - 1] || '';
    sound.play(sound.forSan(san));
    const mover = d.moves.length % 2 === 1 ? 'white' : 'black';
    if (mover !== S.seat) announce(`${S.seat ? nameOf(mover) : sideWord(mover)}: ${spoken(san)}`);
  }
}

function initialOf(text) {
  const ch = String(text || '').trim()[0];
  return ch ? ch.toUpperCase() : '';
}

function updatePlate(p) {
  const g = S.game;
  const side = p.side;
  const seat = g[side];
  const isMe = S.seat === side;
  const name = isMe ? 'You' : seat.seated ? nameOf(side) : 'Waiting for a player';
  if (p.name.textContent !== name) p.name.textContent = name;
  const init = initialOf(seat.name || sideWord(side));
  if (p.avatar.textContent !== init) p.avatar.textContent = init;
  p.el.setAttribute('aria-label', `${isMe ? 'You' : nameOf(side)}, ${sideWord(side)}`);
  const toMove = g.status === 'active' && S.disp.turn === side;
  p.el.classList.toggle('to-move', toMove);

  // Captured pieces and the material lead.
  const mat = material(S.disp.fen);
  const taken = mat[side];
  const lead = side === 'white' ? mat.diff : -mat.diff;
  const capsKey = `${taken.map(([t, n]) => t + n).join('')}|${lead}`;
  if (capsKey !== p.capsKey) {
    p.capsKey = capsKey;
    const theirs = side === 'white' ? 'b' : 'w';
    const kids = taken.map(([t, n]) => h('span', { class: 'cap-group' }, ...Array.from({ length: n }, () => h('span', { class: `${theirs}${t.toUpperCase()}` }))));
    if (lead > 0) kids.push(h('span', { class: 'adv' }, `+${lead}`));
    p.caps.replaceChildren(...kids);
  }
  updatePresence(p);
  updateClock(p);
}

function updatePresence(p) {
  const g = S.game;
  const side = p.side;
  const seat = g[side];
  let text = '';
  let cls = 'presence';
  if (S.seat === side) {
    // Only when neither the socket nor polling has reached the server for a while.
    const down = !S.wsOpen && !S.elsewhere && S.wsDownSince && Date.now() - S.wsDownSince > 2500 && Date.now() - (S.lastPollOkAt || 0) > 7000;
    if (down && g.status !== 'over') text = 'Reconnecting…';
    else if (g.status === 'active' && g.clocks && S.disp.turn === side && !S.pending) { text = 'Your move'; cls += ' mine'; }
  } else if (seat.seated) {
    if (seat.away != null && g.status === 'active') {
      const at = claimableAt(side);
      if (at != null) {
        const left = at - serverNow();
        if (left > 0) {
          text = `left · ${Math.ceil(left / 1000)}s`;
          cls += left < 6000 ? ' away urgent' : ' away';
        } else {
          text = 'left';
          cls += ' away urgent';
        }
      } else {
        text = 'away';
        cls += ' away';
      }
    } else if (seat.online) {
      text = 'Online';
      cls += ' on';
    } else {
      text = 'Offline';
    }
  }
  if (p.presence.textContent !== text) p.presence.textContent = text;
  if (p.presence.className !== cls) p.presence.className = cls;
}

function updateClock(p) {
  const g = S.game;
  const side = p.side;
  if (!g.clocks) {
    const toMove = g.status === 'active' && S.disp.turn === side;
    p.clock.hidden = !toMove;
    p.clock.className = 'turn-tag';
    const t = S.seat === side ? 'Your move' : 'To move';
    if (p.clock.textContent !== t) p.clock.textContent = t;
    p.clock.removeAttribute('role');
    return;
  }
  p.clock.hidden = false;
  const ms = clockMs(side);
  const running = g.status === 'active' && g.clocks.running === side && !S.pending;
  const low = ms < Math.min(20000, g.clock.initial * 1000 * 0.1 + 10000) && g.status === 'active';
  const cls = `clock${running ? ' run' : ''}${low ? ' low' : ''}`;
  if (p.clock.className !== cls) p.clock.className = cls;
  const text = formatClock(ms);
  if (p.clock.textContent !== text) p.clock.textContent = text;
  p.clock.setAttribute('aria-label', `${sideWord(side)} clock, ${text}`);
}

function updateMoves() {
  const ui = S.ui;
  const d = S.disp;
  const key = d.san.join(' ');
  if (key === ui.movesKey) return;
  ui.movesKey = key;
  const g = S.game;
  if (!d.san.length) {
    const t = g.clock
      ? 'White moves first. The clocks start once both sides have moved.'
      : 'White moves first. No clock, so take your time.';
    ui.moves.replaceChildren(h('span', { class: 'moves-empty' }, t));
    return;
  }
  const kids = [];
  d.san.forEach((san, i) => {
    if (i % 2 === 0) kids.push(h('span', { class: 'mv-n' }, `${i / 2 + 1}.`));
    kids.push(h('span', { class: `mv${i === d.san.length - 1 ? ' cur' : ''}` }, san));
  });
  ui.moves.replaceChildren(...kids);
  requestAnimationFrame(() => {
    ui.moves.scrollLeft = ui.moves.scrollWidth;
    ui.moves.scrollTop = ui.moves.scrollHeight;
  });
}

function barButton(iconName, label, onclick, extra = {}) {
  return h('button', { class: 'bar-btn', type: 'button', onclick, ...extra }, icon(iconName), label);
}

function updateBar() {
  const g = S.game;
  const ui = S.ui;
  const me = S.seat;
  const opp = me ? other(me) : null;
  const early = g.moves.length < 2;
  const opponentHere = !!(me && g[opp]?.seated);
  let key;
  if (S.confirm === 'report' && opponentHere) key = `report:${S.busy}:${g.status}`;
  else if (g.status === 'over') key = `over:${g.result?.reason}:${g.result?.winner}:${JSON.stringify(g.rematch)}:${S.busy}`;
  else if (!me) key = 'watch';
  else if (S.elsewhere) key = 'elsewhere';
  else if (S.confirm === 'resign') key = `confirm:${early}:${S.busy}`;
  else if (claimOffered()) key = `claim:${S.busy}`;
  else if (g.drawOffer === opp) key = `offer:${S.busy}`;
  else key = `play:${g.drawOffer === me}:${early}:${S.busy}`;
  if (key === ui.barKey) return;
  ui.barKey = key;

  const replaceBar = (node) => {
    ui.bar.replaceWith(node);
    ui.bar = node;
  };

  ui.after.hidden = g.status !== 'over';
  updateReportLink();
  if (key.startsWith('report:')) {
    const bar = h('div', { class: 'bar' },
      h('div', { class: 'bar-text' }, h('strong', {}, `Report ${nameOf(opp)}`), h('small', {}, 'For their name, or for cheating?')),
      h('button', { class: 'btn btn-secondary btn-sm-bar', type: 'button', disabled: !!S.busy, onclick: () => report('report_name') }, 'Name'),
      h('button', { class: 'btn btn-secondary btn-sm-bar', type: 'button', disabled: !!S.busy, onclick: () => report('report_cheating') }, 'Cheating'),
      h('button', { class: 'icon-btn bar-close', type: 'button', 'aria-label': 'Cancel', onclick: () => { S.confirm = null; updateBar(); } }, icon('plus')),
    );
    replaceBar(bar);
    return;
  }
  if (g.status === 'over') {
    replaceBar(buildResult());
    return;
  }
  const bar = h('div', { class: 'bar' });
  if (!me) {
    bar.classList.add('watching');
    bar.append('Moves appear here as they’re played.');
  } else if (S.elsewhere) {
    bar.append(
      h('div', { class: 'bar-text' }, 'This game is open in another tab or device'),
      h('button', { class: 'btn btn-primary', type: 'button', onclick: useHere }, 'Use here'),
    );
  } else if (S.confirm === 'resign') {
    bar.append(
      h('div', { class: 'bar-text' }, h('strong', {}, early ? 'Abort the game?' : 'Resign?'), h('small', {}, early ? 'Nobody wins or loses' : `${nameOf(opp)} wins the game`)),
      h('button', { class: 'btn btn-secondary', type: 'button', onclick: () => { S.confirm = null; updateBar(); } }, 'Cancel'),
      h('button', { class: 'btn btn-secondary btn-danger', type: 'button', disabled: S.busy === 'resign', onclick: () => act('resign') }, early ? 'Abort' : 'Resign'),
    );
  } else if (key.startsWith('claim:')) {
    bar.append(
      h('div', { class: 'bar-text' }, h('strong', {}, `${nameOf(opp)} left the game`), h('small', {}, `Away for over ${graceWords()}`)),
      h('button', { class: 'btn btn-secondary', type: 'button', disabled: !!S.busy, onclick: () => { S.waitedFor = g[opp].away; updateBar(); } }, 'Wait'),
      h('button', { class: 'btn btn-primary', type: 'button', disabled: !!S.busy, onclick: () => act('claim_win') }, 'Claim win'),
    );
  } else if (g.drawOffer === opp) {
    bar.append(
      h('div', { class: 'bar-text' }, h('strong', {}, nameOf(opp)), h('small', {}, 'offers a draw')),
      h('button', { class: 'btn btn-secondary', type: 'button', disabled: !!S.busy, onclick: () => act('decline_draw') }, 'Decline'),
      h('button', { class: 'btn btn-primary', type: 'button', disabled: !!S.busy, onclick: () => act('accept_draw') }, 'Accept'),
    );
  } else {
    const offered = g.drawOffer === me;
    bar.append(
      barButton('draw', offered ? 'Draw offered' : 'Offer draw', () => act('offer_draw'), { disabled: offered || early || S.busy === 'offer_draw' }),
      h('span', { class: 'bar-sep', 'aria-hidden': 'true' }),
      barButton('flag', early ? 'Abort' : 'Resign', () => { S.confirm = 'resign'; updateBar(); }),
    );
  }
  replaceBar(bar);
}

/** The result in the bar's place: what happened, and Rematch. The board keeps its size. */
function buildResult() {
  const g = S.game;
  const [title, detail] = resultWords();
  const text = h('div', { class: 'bar-text' }, h('strong', {}, title));
  const bar = h('section', { class: 'bar result-bar', 'aria-live': 'polite', 'aria-label': 'Result' }, text);
  if (S.seat) {
    const opp = nameOf(other(S.seat));
    const r = g.rematch;
    if (r && r.by === S.seat && !r.code) {
      text.append(h('small', {}, `Waiting for ${opp}…`));
      bar.append(h('button', { class: 'btn btn-primary', type: 'button', disabled: true, 'aria-label': `Rematch asked. Waiting for ${opp}.` }, h('span', { class: 'spinner', 'aria-hidden': 'true' }), 'Asked'));
    } else if (r && r.by !== S.seat && !r.code) {
      text.append(h('small', { class: 'accent' }, `${opp} wants a rematch`));
      bar.append(h('button', { class: 'btn btn-primary', type: 'button', disabled: S.busy === 'rematch', onclick: () => act('rematch') }, icon('rematch'), 'Accept'));
    } else {
      if (detail) text.append(h('small', {}, detail));
      bar.append(h('button', { class: 'btn btn-primary', type: 'button', disabled: S.busy === 'rematch', onclick: () => act('rematch') }, icon('rematch'), 'Rematch'));
    }
  } else {
    if (detail) text.append(h('small', {}, detail));
  }
  return bar;
}

/** A quiet "Report" under the game, for a player once their friend has joined. */
function updateReportLink() {
  const ui = S.ui;
  const me = S.seat;
  const g = S.game;
  const early = !!(me && g.status === 'active' && g.moves.length < 2);
  const show = !!(me && !early && g[other(me)]?.seated && S.confirm !== 'report');
  const name = show ? nameOf(other(me)) : '';
  const key = `${early}:${show}:${name}`;
  if (ui.reportKey === key) return;
  ui.reportKey = key;
  ui.fair.hidden = !early;
  if (early) ui.fair.lastChild.textContent = fairWords();
  ui.report.hidden = !show;
  ui.report.replaceChildren(icon('report'), `Report ${name}`);
}

async function report(type) {
  await act(type);
  S.confirm = null;
  if (S.view === 'game' && S.ui) { S.ui.barKey = null; updateBar(); }
}

// ---- Moves and actions -------------------------------------------------------------------

function onUserMove({ from, to, promotion, dragged }) {
  const g = S.game;
  if (!movableColor()) { syncAfterRefusal(); return; }
  const chess = new Chess(g.fen);
  let mv = null;
  try { mv = chess.move({ from, to, promotion: promotion || undefined }); } catch { mv = null; }
  if (!mv) { syncAfterRefusal(); return; }
  const uci = mv.from + mv.to + (mv.promotion || '');
  const ply = g.moves.length;
  S.pending = { uci, ply, san: mv.san, fen: chess.fen(), at: Date.now() };
  if (dragged) S.droppedOn = to;
  render();
  api(`/api/games/${S.code}/move`, { method: 'POST', token: S.token, body: { uci, ply } })
    .then((res) => applyState(res.game, { receivedAt: res.receivedAt, force: true }))
    .catch((err) => {
      if (S.pending && S.pending.uci === uci && S.pending.ply === ply) S.pending = null;
      if (err.code === 'unauthorized') dropSeat();
      if (err.game) applyState(err.game, { force: true, receivedAt: err.receivedAt });
      else { render(); refresh(); }
      if (err.code !== 'stale' && err.code !== 'game_over') toast(err.code === 'network' ? "Your move didn’t reach the game. Try it again." : messageFor(err), err.code === 'network' ? 'wifi' : null);
    });
}

/** The board showed a move the game did not take: put it back as it was. */
function syncAfterRefusal() {
  S.shownMoves = null;
  if (S.board && S.disp) S.board.setPosition(S.disp.fen, { lastMove: S.disp.last, check: S.disp.check, animate: false });
  S.shownMoves = S.disp?.moves || null;
}

function dropSeat() {
  S.token = null;
  S.seat = null;
  store.set(seatKey(S.code), null);
}

async function act(type) {
  if (!S.token) return;
  sound.unlock();
  S.busy = type;
  if (S.view === 'game') updateBar();
  try {
    const res = await api(`/api/games/${S.code}/action`, { method: 'POST', token: S.token, body: { type } });
    S.busy = null;
    if (type === 'resign') S.confirm = null;
    applyState(res.game, { receivedAt: res.receivedAt, force: true });
    if (type === 'report_name') toast('Thanks. The name is hidden and we’ll take a look.', 'report');
    if (type === 'report_cheating') toast('Thanks. We’ll take a look at this game.', 'report');
  } catch (err) {
    S.busy = null;
    if (type === 'resign') S.confirm = null;
    if (err.code === 'unauthorized') dropSeat();
    if (err.game) applyState(err.game, { force: true, receivedAt: err.receivedAt });
    else render();
    if (err.code !== 'game_over') toast(messageFor(err), err.code === 'network' ? 'wifi' : null);
  }
  if (S.view === 'game' && S.ui) { S.ui.barKey = null; updateBar(); }
}

/** Both players asked for a rematch: the server made a new game with colors swapped. */
async function switchTo(code) {
  S.switching = true;
  const token = S.token;
  const seat = S.seat;
  closeSocket();
  stopPolling();
  if (token && seat) store.set(seatKey(code), { token, seat: other(seat) });
  try { history.replaceState(null, '', `/c/${code}`); } catch { /* file or sandbox */ }
  const oldCode = S.code;
  S.code = code;
  S.pending = null;
  S.confirm = null;
  S.busy = null;
  S.elsewhere = false; // a new game: every tab starts over on its own socket
  S.socketDone = false;
  S.wsFailedOpens = 0;
  S.wsAttempts = 0;
  try {
    let res;
    if (token) {
      res = await api(`/api/games/${code}/join`, { method: 'POST', token, body: { name: store.get(NAME_KEY) || '' } });
      S.seat = res.seat;
      S.token = res.token || token;
      store.set(seatKey(code), { token: S.token, seat: S.seat });
    } else {
      res = await api(`/api/games/${code}`);
    }
    S.game = null;
    S.switching = false;
    applyState(res.game, { force: true, receivedAt: res.receivedAt, quiet: true });
    toast(S.seat ? `Rematch. You play ${sideWord(S.seat)}.` : 'Rematch started', 'rematch');
  } catch (err) {
    S.switching = false;
    S.code = oldCode;
    toast(messageFor(err));
    try { history.replaceState(null, '', `/c/${oldCode}`); } catch { /* ignore */ }
    render();
  }
  connect();
}

// ---- Clocks ------------------------------------------------------------------------------

function startTicking() {
  stopTicking();
  S.tickTimer = setInterval(tick, 100);
}
function stopTicking() {
  clearInterval(S.tickTimer);
  S.tickTimer = null;
}

function tick() {
  const g = S.game;
  const ui = S.ui;
  if (!g || !ui || S.view !== 'game') return;
  if (g.status !== 'active' && !S.tickedOver) {
    S.tickedOver = true;
  } else if (g.status !== 'active') {
    return;
  } else {
    S.tickedOver = false;
  }
  updateClock(ui.opp);
  updateClock(ui.me);
  updatePresence(ui.opp);
  updatePresence(ui.me);
  // A flag fell on this screen: ask the server, which decides.
  if (g.status === 'active' && g.clocks?.running && clockMs(g.clocks.running) <= 0 && Date.now() - S.flagRefreshAt > 1500) {
    S.flagRefreshAt = Date.now();
    setTimeout(refresh, 400);
  }
  // An absence passed the grace period: offer the claim (leaving never ends the game by itself).
  const offered = claimOffered();
  if (offered !== S.claimShown) {
    S.claimShown = offered;
    updateBar();
  }
}

function renderPresenceOnly() {
  if (S.view === 'game' && S.ui) {
    updatePresence(S.ui.opp);
    updatePresence(S.ui.me);
  }
}

// ---- Start ---------------------------------------------------------------------------------

if (boot.page === 'home') initHome();
else if (boot.page === 'game') initGame();
