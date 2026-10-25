// The HTML pages the worker renders: the invite page for a game link and the home page.
// Owned by the browser client (play/public); the worker only calls these.
//
// Every string a person typed (player names) is escaped before it reaches the HTML, and the
// GameState inlined for the browser has every "<" escaped, so nothing can close the script tag.

const SITE = 'Chess Game Killer';
const THEME = '#0F0F10';

/** Escapes text for HTML element content and quoted attribute values. */
function esc(value) {
  return String(value ?? '').replace(/[&<>"']/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' })[c]);
}

/** JSON that is safe inside <script type="application/json">. */
function inlineJson(data) {
  return JSON.stringify(data)
    .replace(/</g, '\\u003c')
    .replace(/>/g, '\\u003e')
    .replace(/&/g, '\\u0026')
    .replace(/\u2028/g, '\\u2028')
    .replace(/\u2029/g, '\\u2029');
}

function trimOrigin(origin) {
  return String(origin || '').replace(/\/+$/, '');
}

function plural(n, word) {
  return `${n} ${word}${n === 1 ? '' : 's'}`;
}

function duration(seconds) {
  if (seconds % 60 === 0) return plural(seconds / 60, 'minute');
  if (seconds < 60) return plural(seconds, 'second');
  return `${plural(Math.floor(seconds / 60), 'minute')} ${plural(seconds % 60, 'second')}`;
}

/** The clock in plain words: "10 minutes each", "3 minutes + 2 seconds a move", "No clock, play at your own pace". */
function clockWords(clock) {
  if (!clock) return 'No clock, play at your own pace';
  if (!clock.increment) return `${duration(clock.initial)} each`;
  return `${duration(clock.initial)} + ${plural(clock.increment, 'second')} a move`;
}

function nameOf(game, side) {
  return (game && game[side] && game[side].name) || (side === 'white' ? 'White' : 'Black');
}

function resultWords(game) {
  const r = game.result;
  if (!r) return 'Game over';
  const w = r.winner ? nameOf(game, r.winner) : null;
  const l = r.winner ? nameOf(game, r.winner === 'white' ? 'black' : 'white') : null;
  switch (r.reason) {
    case 'checkmate': return `${w} won by checkmate`;
    case 'resign': return `${l} resigned, ${w} won`;
    case 'timeout': return `${w} won on time`;
    case 'left': return `${l} left the game, ${w} won`;
    case 'stalemate': return 'Draw by stalemate';
    case 'repetition': return 'Draw by repetition';
    case 'fifty_moves': return 'Draw by the fifty-move rule';
    case 'insufficient': return 'Draw, not enough pieces to mate';
    case 'agreement': return 'Draw agreed';
    case 'timeout_insufficient': return 'Draw on time';
    case 'aborted': return 'Game aborted';
    default: return 'Game over';
  }
}

function head({ title, ogTitle, description, url, origin, robots }) {
  const image = `${origin}/og-invite.png`;
  return `<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1, viewport-fit=cover">
<title>${esc(title)}</title>
<meta name="description" content="${esc(description)}">
<meta name="theme-color" content="${THEME}">
<meta name="color-scheme" content="dark">
<meta name="format-detection" content="telephone=no">
<meta name="apple-mobile-web-app-title" content="${SITE}">
${robots ? `<meta name="robots" content="${robots}">\n` : ''}<link rel="canonical" href="${esc(url)}">
<link rel="icon" href="/favicon.ico" sizes="any">
<link rel="icon" href="/favicon-32.png" type="image/png" sizes="32x32">
<link rel="apple-touch-icon" href="/apple-touch-icon.png">
<meta property="og:type" content="website">
<meta property="og:site_name" content="${SITE}">
<meta property="og:title" content="${esc(ogTitle)}">
<meta property="og:description" content="${esc(description)}">
<meta property="og:url" content="${esc(url)}">
<meta property="og:image" content="${esc(image)}">
<meta property="og:image:type" content="image/png">
<meta property="og:image:width" content="1200">
<meta property="og:image:height" content="630">
<meta property="og:image:alt" content="A chess board set for a game, with the words Your move">
<meta name="twitter:card" content="summary_large_image">
<meta name="twitter:title" content="${esc(ogTitle)}">
<meta name="twitter:description" content="${esc(description)}">
<meta name="twitter:image" content="${esc(image)}">
<link rel="stylesheet" href="/app.css">
<link rel="stylesheet" href="/looks.css">
<link rel="modulepreload" href="/board.js">
<link rel="modulepreload" href="/vendor/chess.js">
<script type="module" src="/app.js"></script>`;
}

const BRAND = `<header class="top">
  <a class="brand" href="/"><img class="brand-icon" src="/icon-78.png" alt="" width="26" height="26"><span>${SITE}</span></a>
  <div class="top-end" id="top-end"></div>
</header>`;

const CREDITS = `<footer class="credits">
  <p>Chess pieces by Colin M.L. Burnett (cburnett), GPLv2+. Chess Game Killer is open source under the GPL.</p>
</footer>`;

/** The page for /c/{code}. `game` is the public GameState, or null when there is no such game. */
export function renderInvitePage({ game, origin, code }) {
  origin = trimOrigin(origin);
  const safeCode = String(code || '').toUpperCase().replace(/[^0-9A-Z]/g, '').slice(0, 12);
  const url = `${origin}/c/${safeCode}`;

  const gone = !game || (game.status === 'over' && game.result && (game.result.reason === 'cancelled' || game.result.reason === 'expired'));
  if (gone) {
    const withdrawn = game && game.result && game.result.reason === 'cancelled';
    const line = withdrawn
      ? `${esc(nameOf(game, game.creator))} withdrew this challenge.`
      : 'It may have expired, or the person who sent it withdrew it.';
    return `<!doctype html>
<html lang="en" class="page-gone">
<head>
${head({ title: `This challenge isn’t here anymore · ${SITE}`, ogTitle: "This challenge isn’t here anymore", description: 'Start a new game of chess with a friend in your browser.', url, origin, robots: 'noindex' })}
</head>
<body>
<div class="backdrop" aria-hidden="true"></div>
${BRAND}
<main id="app" class="shell">
  <section class="view view-note">
    <div class="note-mark" aria-hidden="true"><img src="/pieces/wK.svg" alt=""><img src="/pieces/bK.svg" alt=""></div>
    <h1>This challenge isn’t here anymore</h1>
    <p class="lede">${line}</p>
    <a class="btn btn-primary" href="/">Challenge a friend</a>
  </section>
</main>
${CREDITS}
<script id="boot" type="application/json">${inlineJson({ page: 'gone', code: safeCode, game: game || null })}</script>
</body>
</html>`;
  }

  const creator = nameOf(game, game.creator);
  let ogTitle;
  let description;
  if (game.status === 'waiting') {
    ogTitle = `${creator} challenged you to chess`;
    description = `${clockWords(game.clock)} · Play in your browser or in the ${SITE} app`;
  } else if (game.status === 'active') {
    ogTitle = `${nameOf(game, 'white')} vs ${nameOf(game, 'black')}, live`;
    description = `${clockWords(game.clock)} · Watch the game live in your browser`;
  } else {
    ogTitle = `${nameOf(game, 'white')} vs ${nameOf(game, 'black')}`;
    description = `${resultWords(game)} · ${SITE}`;
  }

  const opener = game.creator === 'white' ? 'black' : 'white';
  return `<!doctype html>
<html lang="en" class="page-game"${game.look ? ` data-look="${esc(game.look)}"` : ''}>
<head>
${head({ title: `${ogTitle} · ${SITE}`, ogTitle, description, url, origin, robots: 'noindex' })}
</head>
<body>
<div class="backdrop" aria-hidden="true"></div>
${BRAND}
<main id="app" class="shell" aria-live="off">
  <noscript>
    <section class="view view-note">
      <h1>${esc(ogTitle)}</h1>
      <p class="lede">${esc(clockWords(game.clock))}${game.status === 'waiting' ? ` · You play ${opener === 'white' ? 'White' : 'Black'}` : ''}</p>
      <p class="lede">Turn on JavaScript to play in this browser, or open the challenge in the app.</p>
      <a class="btn btn-secondary" href="chessgamekiller://c/${safeCode}">Open in the app</a>
    </section>
  </noscript>
</main>
${CREDITS}
<div class="toasts" id="toasts" role="status" aria-live="polite"></div>
<div class="sr-only" id="announce" aria-live="polite"></div>
<script id="boot" type="application/json">${inlineJson({ page: 'game', code: safeCode, origin, game })}</script>
</body>
</html>`;
}

const CLOCKS = [
  { id: '3+2', label: '3 + 2' },
  { id: '5+0', label: '5 min' },
  { id: '10+0', label: '10 min' },
  { id: '15+10', label: '15 + 10' },
  { id: 'none', label: 'None' },
];

/** The page for /. */
export function renderHomePage({ origin }) {
  origin = trimOrigin(origin);
  const description = 'Challenge a friend to chess. Send a link by text or email, and play right in the browser or in the app.';
  const clockOptions = CLOCKS.map((c) => `<label class="seg-option"><input type="radio" name="clock" value="${c.id}"${c.id === '10+0' ? ' checked' : ''} aria-describedby="clock-hint"><span>${esc(c.label)}</span></label>`).join('');
  const side = (value, label, icon) => `<label class="seg-option"><input type="radio" name="side" value="${value}"${value === 'random' ? ' checked' : ''}><span>${icon}${label}</span></label>`;
  return `<!doctype html>
<html lang="en" class="page-home">
<head>
${head({ title: `${SITE} · Challenge a friend to chess`, ogTitle: `${SITE}`, description, url: `${origin}/`, origin })}
</head>
<body>
<div class="backdrop" aria-hidden="true"></div>
${BRAND}
<main id="app" class="shell home">
  <section class="home-main">
    <div class="home-copy">
      <h1>Challenge a friend to chess</h1>
      <p class="lede">Send a link by text or email. Your friend plays right in the browser, with nothing to install.</p>
    </div>

    <form class="card home-form" id="create-form" novalidate>
      <div class="field">
        <label class="field-label" for="name">Your name</label>
        <input class="input" id="name" name="name" type="text" maxlength="24" autocomplete="nickname" autocapitalize="words" spellcheck="false" placeholder="How your friend will see you" enterkeyhint="go">
      </div>
      <fieldset class="field">
        <legend class="field-label">Clock</legend>
        <div class="seg seg-5">${clockOptions}</div>
        <p class="field-hint" id="clock-hint">${esc(clockWords({ initial: 600, increment: 0 }))}</p>
      </fieldset>
      <fieldset class="field">
        <legend class="field-label">You play</legend>
        <div class="seg seg-3">
          ${side('white', 'White', '<img src="/pieces/wK.svg" alt="" width="22" height="22">')}
          ${side('random', 'Random', '<span class="dual" aria-hidden="true"><img src="/pieces/wK.svg" alt=""><img src="/pieces/bK.svg" alt=""></span>')}
          ${side('black', 'Black', '<img src="/pieces/bK.svg" alt="" width="22" height="22">')}
        </div>
      </fieldset>
      <button class="btn btn-primary btn-block" type="submit" id="create-btn">Create challenge</button>
      <p class="form-error" id="create-error" role="alert" hidden></p>
    </form>
  </section>

  <div class="home-board" id="home-board" aria-hidden="true"></div>

  <ul class="points">
    <li><span class="point-mark" aria-hidden="true"><svg viewBox="0 0 24 24"><path d="M12 3l7 3v5c0 4.6-3 8.3-7 10-4-1.7-7-5.4-7-10V6l7-3z"/><path d="M9 12l2 2 4-4"/></svg></span><div><h2>Fair play, built in</h2><p>No hints or engines. In a timed game, leave for over a minute and your friend can claim the win.</p></div></li>
    <li><span class="point-mark" aria-hidden="true"><svg viewBox="0 0 24 24"><circle cx="12" cy="13" r="8"/><path d="M12 9v4l2.5 2.5M9.5 2.5h5"/></svg></span><div><h2>Any pace</h2><p>Blitz, rapid, or no clock at all. Moves arrive the instant they’re made.</p></div></li>
    <li><span class="point-mark" aria-hidden="true"><svg viewBox="0 0 24 24"><rect x="7" y="2.5" width="10" height="19" rx="2.5"/><path d="M11 18.5h2"/></svg></span><div><h2>${SITE} for iPhone</h2><p>Lessons, puzzles and five rivals to beat. Coming soon to the App Store.</p></div></li>
  </ul>
  <noscript><p class="lede">Turn on JavaScript to create a challenge.</p></noscript>
</main>
${CREDITS}
<div class="toasts" id="toasts" role="status" aria-live="polite"></div>
<script id="boot" type="application/json">${inlineJson({ page: 'home', origin })}</script>
</body>
</html>`;
}
