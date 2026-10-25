// The chess board for Chess Game Killer in the browser.
// Squares are buttons (for keyboard and screen readers); pieces sit in their own layer and slide
// between squares. Tap a piece then a square, or drag it. Legal moves show as dots on empty
// squares and rings on captures.
//
// Piece artwork: the "cburnett" set by Colin M.L. Burnett, GPLv2+ (via Lichess), in /pieces, for the
// Classic look; every other look uses the app's own pictures in /looks (see looks.css).

import { setLook } from './looks.js';

// The app's default look until a game says which look the friend who sent the link plays with.
setLook(document.documentElement.dataset.look);

const FILES = 'abcdefgh';
const PIECE_NAMES = { k: 'king', q: 'queen', r: 'rook', b: 'bishop', n: 'knight', p: 'pawn' };
const reducedMotion = () => window.matchMedia?.('(prefers-reduced-motion: reduce)').matches;

/** Squares → piece codes ("wN") from a FEN's placement field. */
export function parseFen(fen) {
  const out = new Map();
  const rows = String(fen || '').split(' ')[0].split('/');
  rows.forEach((row, i) => {
    let file = 0;
    for (const ch of row) {
      if (/\d/.test(ch)) { file += +ch; continue; }
      const color = ch === ch.toUpperCase() ? 'w' : 'b';
      out.set(FILES[file] + (8 - i), color + ch.toUpperCase());
      file++;
    }
  });
  return out;
}

export function pieceName(code) {
  return `${code[0] === 'w' ? 'white' : 'black'} ${PIECE_NAMES[code[1].toLowerCase()]}`;
}

const el = (tag, cls) => {
  const e = document.createElement(tag);
  if (cls) e.className = cls;
  return e;
};

export class Board {
  /**
   * @param {HTMLElement} host
   * @param {object} opts
   *  orientation: 'white' | 'black'
   *  coords: show file and rank letters
   *  label: accessible name for the board
   *  movable: () => 'w' | 'b' | null, the color the viewer may move now
   *  dests: (square) => [{ to, promotion?, capture }], legal moves from a square
   *  onMove: ({ from, to, promotion, dragged }) => void
   */
  constructor(host, opts = {}) {
    this.opts = opts;
    this.orientation = opts.orientation || 'white';
    this.position = new Map(); // square → { code, el }
    this.selected = null;
    this.lastMove = null;
    this.checkSquare = null;
    this.cursor = null; // keyboard focus square
    this.drag = null;
    this.pointerUntil = 0;
    this.promo = null;

    this.root = el('div', 'board');
    this.root.classList.toggle('flipped', this.orientation === 'black');
    if (opts.className) this.root.classList.add(...opts.className.split(' '));
    this.root.setAttribute('role', 'group');
    this.squaresEl = el('div', 'squares');
    this.piecesEl = el('div', 'pieces');
    this.piecesEl.setAttribute('aria-hidden', 'true');
    this.root.append(this.squaresEl, this.piecesEl);
    host.append(this.root);

    this.squareEls = new Map();
    this.buildSquares();
    this.setLabel(opts.label || 'Chess board');

    if (opts.interactive !== false) this.bindInput();
  }

  setLabel(label) {
    this.root.setAttribute('aria-label', label);
  }

  /** Builds the 64 square buttons in reading order for the current orientation. */
  buildSquares() {
    this.squaresEl.textContent = '';
    this.squareEls.clear();
    const coords = this.opts.coords !== false;
    for (let row = 0; row < 8; row++) {
      for (let col = 0; col < 8; col++) {
        const sq = this.squareAt(col, row);
        const fileIdx = FILES.indexOf(sq[0]);
        const rank = +sq[1];
        const light = (fileIdx + rank) % 2 === 0; // a1 is dark, h1 is light
        const b = el(this.opts.interactive === false ? 'div' : 'button', `sq ${light ? 'l' : 'd'}`);
        if (b.tagName === 'BUTTON') {
          b.type = 'button';
          b.tabIndex = -1;
        }
        b.dataset.sq = sq;
        if (coords && col === 0) {
          const r = el('span', 'co co-r');
          r.textContent = sq[1];
          r.setAttribute('aria-hidden', 'true');
          b.append(r);
        }
        if (coords && row === 7) {
          const f = el('span', 'co co-f');
          f.textContent = sq[0];
          f.setAttribute('aria-hidden', 'true');
          b.append(f);
        }
        this.squaresEl.append(b);
        this.squareEls.set(sq, b);
      }
    }
    const start = this.orientation === 'white' ? 'e2' : 'e7';
    this.setCursor(this.cursor && this.squareEls.has(this.cursor) ? this.cursor : start, false);
  }

  /** The square shown at a column and row (0,0 is the top left from the viewer's side). */
  squareAt(col, row) {
    return this.orientation === 'white' ? FILES[col] + (8 - row) : FILES[7 - col] + (row + 1);
  }

  colRow(sq) {
    const f = FILES.indexOf(sq[0]);
    const r = +sq[1];
    return this.orientation === 'white' ? [f, 8 - r] : [7 - f, r - 1];
  }

  setOrientation(orientation) {
    if (orientation === this.orientation) return;
    this.orientation = orientation;
    this.root.classList.toggle('flipped', orientation === 'black');
    this.buildSquares();
    for (const [sq, p] of this.position) this.place(p.el, sq, false);
    this.refreshMarks();
  }

  place(pieceEl, sq, animate = true) {
    const [c, r] = this.colRow(sq);
    pieceEl.style.zIndex = r + 1; // the 3D pieces stand in front of the rank behind them
    if (!animate) {
      pieceEl.style.transition = 'none';
      pieceEl.style.transform = `translate(${c * 100}%, ${r * 100}%)`;
      void pieceEl.offsetWidth;
      pieceEl.style.transition = '';
    } else {
      pieceEl.style.transform = `translate(${c * 100}%, ${r * 100}%)`;
    }
  }

  makePiece(code, sq) {
    const p = el('div', `pc ${code[0]} ${code}`);
    this.place(p, sq, false);
    this.piecesEl.append(p);
    return p;
  }

  /**
   * Shows a position. Pieces that moved slide to their new squares; captured pieces fade out.
   * opts: lastMove [from, to], check (square of a king in check), animate, dragged (square the
   * piece was dropped on, which must not slide).
   */
  /** Closes the promotion picker, if it is open, and puts the pawn back. */
  cancelPromotion() {
    this.promo?.cancel();
  }

  setPosition(fen, opts = {}) {
    this.cancelPromotion();
    const next = parseFen(fen);
    const animate = opts.animate !== false && !reducedMotion() && this.position.size > 0;
    const prev = this.position;
    const keep = new Map();
    const spare = [];
    for (const [sq, p] of prev) {
      if (next.get(sq) === p.code) keep.set(sq, p);
      else spare.push({ sq, ...p });
    }
    const missing = [];
    for (const [sq, code] of next) if (!keep.has(sq)) missing.push({ sq, code });

    const lastMove = opts.lastMove || null;
    const dist = (a, b) => Math.hypot(FILES.indexOf(a[0]) - FILES.indexOf(b[0]), +a[1] - +b[1]);
    for (const m of missing) {
      let best = -1;
      let bestD = Infinity;
      spare.forEach((s, i) => {
        if (!s) return;
        const same = s.code === m.code;
        // A promotion: the pawn walks to the last rank and becomes the new piece.
        const promoted = lastMove && s.sq === lastMove[0] && m.sq === lastMove[1] && s.code[1] === 'P' && s.code[0] === m.code[0];
        if (!same && !promoted) return;
        const d = promoted ? -1 : dist(s.sq, m.sq);
        if (d < bestD) { bestD = d; best = i; }
      });
      if (best >= 0) {
        const s = spare[best];
        spare[best] = null;
        if (s.code !== m.code) s.el.className = `pc ${m.code[0]} ${m.code}`;
        const slide = animate && opts.dragged !== m.sq;
        this.place(s.el, m.sq, slide);
        if (slide) {
          s.el.classList.add('moving');
          clearTimeout(s.el._mt);
          s.el._mt = setTimeout(() => s.el.classList.remove('moving'), 260);
        }
        keep.set(m.sq, { code: m.code, el: s.el });
      } else {
        const p = this.makePiece(m.code, m.sq);
        if (animate) {
          p.classList.add('appear');
          requestAnimationFrame(() => requestAnimationFrame(() => p.classList.remove('appear')));
        }
        keep.set(m.sq, { code: m.code, el: p });
      }
    }
    for (const s of spare) {
      if (!s) continue;
      if (animate) {
        s.el.classList.add('gone');
        setTimeout(() => s.el.remove(), 260);
      } else {
        s.el.remove();
      }
    }
    this.position = keep;
    this.lastMove = lastMove;
    this.checkSquare = opts.check || null;
    if (this.selected && !this.canSelect(this.selected)) this.selected = null;
    this.refreshMarks();
  }

  pieceAt(sq) {
    return this.position.get(sq)?.code || null;
  }

  canSelect(sq) {
    const color = this.opts.movable?.();
    const code = this.pieceAt(sq);
    return !!(color && code && code[0] === color);
  }

  /** Redraws highlights, dots, rings and the accessible labels. */
  refreshMarks() {
    const dests = this.selected ? this.opts.dests?.(this.selected) || [] : [];
    const destMap = new Map();
    for (const d of dests) destMap.set(d.to, d);
    for (const [sq, b] of this.squareEls) {
      const isLast = !!this.lastMove && (this.lastMove[0] === sq || this.lastMove[1] === sq);
      b.classList.toggle('last', isLast);
      b.classList.toggle('sel', this.selected === sq);
      b.classList.toggle('check', this.checkSquare === sq);
      const d = destMap.get(sq);
      b.classList.toggle('dot', !!d && !d.capture);
      b.classList.toggle('cap', !!d && !!d.capture);
      if (b.tagName === 'BUTTON') {
        const code = this.pieceAt(sq);
        let label = code ? `${sq}, ${pieceName(code)}` : sq;
        if (this.selected === sq) label += ', selected';
        else if (d) label += d.capture ? ', capture' : ', move here';
        if (this.checkSquare === sq) label += ', in check';
        b.setAttribute('aria-label', label);
      }
    }
  }

  select(sq) {
    this.selected = sq;
    this.refreshMarks();
  }

  deselect() {
    if (!this.selected) return;
    this.selected = null;
    this.refreshMarks();
  }

  setCursor(sq, focus = true) {
    if (this.opts.interactive === false) return;
    const prev = this.cursor && this.squareEls.get(this.cursor);
    if (prev) prev.tabIndex = -1;
    this.cursor = sq;
    const b = this.squareEls.get(sq);
    if (b) {
      b.tabIndex = 0;
      if (focus) b.focus({ preventScroll: true });
    }
  }

  /** A tap or click on a square (also Enter or Space on the focused square). */
  tap(sq) {
    if (this.promo) return;
    if (this.selected && this.selected !== sq) {
      const moves = (this.opts.dests?.(this.selected) || []).filter((d) => d.to === sq);
      if (moves.length) {
        this.tryMove(this.selected, sq, false);
        return 'moved';
      }
    }
    if (this.canSelect(sq)) {
      if (this.selected === sq) return 'same';
      this.select(sq);
      return 'selected';
    }
    this.deselect();
    return 'none';
  }

  tryMove(from, to, dragged) {
    const moves = (this.opts.dests?.(from) || []).filter((d) => d.to === to);
    if (!moves.length) return false;
    if (moves.some((m) => m.promotion)) {
      this.askPromotion(from, to, dragged);
      return true;
    }
    this.selected = null;
    this.refreshMarks();
    this.opts.onMove?.({ from, to, dragged });
    return true;
  }

  // ---- Promotion ---------------------------------------------------------------------------

  askPromotion(from, to, dragged) {
    const color = this.pieceAt(from)?.[0] || 'w';
    // The picker stands in for the dots and rings while it is open.
    this.selected = null;
    this.refreshMarks();
    const [col, row] = this.colRow(to);
    const downward = row === 0;
    const overlay = el('div', 'promo');
    const box = el('div', 'promo-col');
    box.style.left = `${col * 12.5}%`;
    box.style[downward ? 'top' : 'bottom'] = '0';
    box.setAttribute('role', 'dialog');
    box.setAttribute('aria-label', 'Promote the pawn to');
    const choices = ['q', 'n', 'r', 'b'];
    const finish = (promotion) => {
      overlay.remove();
      this.promo = null;
      document.removeEventListener('keydown', onKey, true);
      if (!promotion) {
        const p = this.position.get(from);
        if (p) this.place(p.el, from, !dragged && !reducedMotion());
        this.refreshMarks();
        return;
      }
      this.selected = null;
      this.refreshMarks();
      this.opts.onMove?.({ from, to, promotion, dragged });
    };
    const onKey = (e) => {
      if (e.key === 'Escape') { e.preventDefault(); e.stopPropagation(); finish(null); }
    };
    for (const t of choices) {
      const b = el('button', `promo-opt pc-${color}${t.toUpperCase()}`);
      b.type = 'button';
      b.setAttribute('aria-label', PIECE_NAMES[t][0].toUpperCase() + PIECE_NAMES[t].slice(1));
      const img = el('span', `promo-piece ${color}${t.toUpperCase()}`);
      b.append(img);
      b.addEventListener('click', (e) => { e.stopPropagation(); finish(t); });
      box.append(b);
    }
    if (!downward) box.append(...[...box.children].reverse());
    overlay.addEventListener('pointerdown', (e) => {
      if (e.target === overlay) { e.preventDefault(); e.stopPropagation(); finish(null); }
    });
    overlay.append(box);
    this.root.append(overlay);
    this.promo = { from, to, cancel: () => finish(null) };
    document.addEventListener('keydown', onKey, true);
    // Show the pawn on the promotion square while choosing.
    const p = this.position.get(from);
    if (p) this.place(p.el, to, !dragged && !reducedMotion());
    (downward ? box.firstChild : box.lastChild).focus({ preventScroll: true });
  }

  // ---- Input -------------------------------------------------------------------------------

  squareFromPoint(x, y) {
    const r = this.squaresEl.getBoundingClientRect();
    const col = Math.floor(((x - r.left) / r.width) * 8);
    const row = Math.floor(((y - r.top) / r.height) * 8);
    if (col < 0 || col > 7 || row < 0 || row > 7) return null;
    return this.squareAt(col, row);
  }

  bindInput() {
    const root = this.root;
    root.addEventListener('pointerdown', (e) => this.onDown(e));
    root.addEventListener('pointermove', (e) => this.onMoveEvt(e));
    root.addEventListener('pointerup', (e) => this.onUp(e));
    root.addEventListener('pointercancel', () => this.cancelDrag());
    root.addEventListener('lostpointercapture', () => { if (this.drag?.active) this.cancelDrag(); else this.drag = null; });
    root.addEventListener('contextmenu', (e) => e.preventDefault());
    // Enter or Space on the focused square (or a screen reader's activation) acts as a tap.
    // Clicks that follow a pointer press were already handled on pointerdown and pointerup;
    // a click from the keyboard (detail 0) is always its own.
    root.addEventListener('click', (e) => {
      const b = e.target.closest?.('.sq');
      if (!b || (e.detail !== 0 && performance.now() < this.pointerUntil)) return;
      this.opts.onInteract?.();
      this.tap(b.dataset.sq);
    });
    root.addEventListener('keydown', (e) => {
      const b = e.target.closest?.('.sq');
      if (!b) return;
      const [c, r] = this.colRow(b.dataset.sq);
      const moves = { ArrowLeft: [-1, 0], ArrowRight: [1, 0], ArrowUp: [0, -1], ArrowDown: [0, 1] };
      if (moves[e.key]) {
        e.preventDefault();
        const nc = Math.min(7, Math.max(0, c + moves[e.key][0]));
        const nr = Math.min(7, Math.max(0, r + moves[e.key][1]));
        this.setCursor(this.squareAt(nc, nr));
      } else if (e.key === 'Escape') {
        this.deselect();
      }
    });
    root.addEventListener('focusin', (e) => {
      const b = e.target.closest?.('.sq');
      if (b && b.dataset.sq !== this.cursor) this.setCursor(b.dataset.sq, false);
    });
  }

  onDown(e) {
    if (this.promo || e.button > 0) return;
    const sq = this.squareFromPoint(e.clientX, e.clientY);
    if (!sq) return;
    this.pointerUntil = performance.now() + 800;
    this.opts.onInteract?.();
    const wasSelected = this.selected === sq;
    const result = this.tap(sq);
    if (result === 'moved') { e.preventDefault(); return; }
    if (result === 'selected' || result === 'same') {
      e.preventDefault();
      const p = this.position.get(sq);
      this.drag = { sq, wasSelected, x: e.clientX, y: e.clientY, id: e.pointerId, active: false, el: p?.el, type: e.pointerType };
      try { this.root.setPointerCapture(e.pointerId); } catch {}
      if (this.cursor !== sq) this.setCursor(sq, false);
    }
  }

  onMoveEvt(e) {
    const d = this.drag;
    if (!d || e.pointerId !== d.id) return;
    const sqSize = this.squaresEl.getBoundingClientRect().width / 8;
    if (!d.active) {
      if (Math.hypot(e.clientX - d.x, e.clientY - d.y) < Math.max(4, sqSize * 0.12)) return;
      d.active = true;
      const ghost = el('div', `drag-ghost ${this.pieceAt(d.sq)}`);
      const scale = d.type === 'touch' ? 1.35 : 1.1;
      ghost.style.width = ghost.style.height = `${sqSize}px`;
      ghost.style.setProperty('--s', scale);
      document.body.append(ghost);
      d.ghost = ghost;
      d.size = sqSize;
      d.lift = d.type === 'touch' ? sqSize * 0.35 : 0;
      d.el?.classList.add('lifted');
    }
    d.ghost.style.transform = `translate(${e.clientX - d.size / 2}px, ${e.clientY - d.size / 2 - d.lift}px) scale(var(--s))`;
    const over = this.squareFromPoint(e.clientX, e.clientY - d.lift);
    if (over !== d.over) {
      if (d.over) this.squareEls.get(d.over)?.classList.remove('over');
      d.over = over;
      if (over && over !== d.sq) this.squareEls.get(over)?.classList.add('over');
    }
  }

  onUp(e) {
    const d = this.drag;
    if (!d || e.pointerId !== d.id) return;
    this.drag = null;
    this.pointerUntil = performance.now() + 500;
    if (d.active) {
      const to = this.squareFromPoint(e.clientX, e.clientY - d.lift);
      this.endGhost(d);
      if (to && to !== d.sq) {
        // Show the piece where it was dropped right away, then let the move decide.
        const moved = (this.opts.dests?.(d.sq) || []).some((m) => m.to === to);
        if (moved) {
          const p = this.position.get(d.sq);
          if (p) this.place(p.el, to, false);
          this.tryMove(d.sq, to, true);
          return;
        }
      }
      // Dropped back or somewhere illegal: the piece returns, still selected.
      const p = this.position.get(d.sq);
      if (p) this.place(p.el, d.sq, false);
      return;
    }
    if (d.wasSelected) this.deselect();
  }

  endGhost(d) {
    d.ghost?.remove();
    d.el?.classList.remove('lifted');
    if (d.over) this.squareEls.get(d.over)?.classList.remove('over');
  }

  cancelDrag() {
    const d = this.drag;
    this.drag = null;
    if (!d) return;
    this.endGhost(d);
    const p = this.position.get(d.sq);
    if (p) this.place(p.el, d.sq, false);
  }

  destroy() {
    this.root.remove();
  }
}
