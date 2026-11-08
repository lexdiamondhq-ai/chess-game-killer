// The Floating Cut-outs for the flat board: each piece a bold paper-cut shape, drawn as a picture
// the app lays on a plane just above its square (SculptedFlatSet), with its shadow as a second
// picture the app sets below and off to the side, so the piece seems to hover. White is warm
// paper with dark lines; Black is near-black with gold detail and a thin gold edge, so it reads on
// a dark square. Shapes from the cburnett pieces in play/public/pieces.
//
// The picture is SIZE px square, the 45-unit cburnett box, and the app spans it across
// SculptedFlatSet.span squares; the piece is centered in it.
//
// Usage: node cutouts.js <out dir, such as ChessGameKiller/Assets.xcassets/Cutouts>
const fs = require('fs');
const path = require('path');
const { chromium } = require('playwright');

const OUT = process.argv[2];
const SIZE = 512;
const PIECES = path.join(__dirname, '../../../play/public/pieces');
const GOLD = '#E2B85E';

function inner(svg) { return svg.match(/<svg[^>]*>([\s\S]*)<\/svg>/)[1]; }
function sub(s, map) { for (const [a, b] of Object.entries(map)) s = s.split(a).join(b); return s; }

function piece(color, kind) {
  const src = fs.readFileSync(path.join(PIECES, color + kind + '.svg'), 'utf8');
  if (color === 'w') {
    const body = sub(inner(src), { '"#fff"': '"#FBF6EA"', '"#000"': '"#2A1F16"' });
    return `<g fill="#FBF6EA">${body}</g>`;
  }
  const body = sub(inner(src), { 'fill="#000"': 'fill="#16110D"', 'stroke="#000"': 'stroke="#16110D"', '"#ececec"': `"${GOLD}"` });
  // A thin gold edge round the whole shape.
  return `<filter id="edge" x="-10%" y="-10%" width="120%" height="120%">
      <feMorphology in="SourceAlpha" operator="dilate" radius="0.45" result="grown"/>
      <feFlood flood-color="${GOLD}"/><feComposite in2="grown" operator="in" result="rim"/>
      <feMerge><feMergeNode in="rim"/><feMergeNode in="SourceGraphic"/></feMerge></filter>
    <g filter="url(#edge)"><g fill="#16110D">${body}</g></g>`;
}

function page(body) {
  return `<html><body style="margin:0;background:transparent">
    <svg xmlns="http://www.w3.org/2000/svg" width="${SIZE}" height="${SIZE}" viewBox="0 0 45 45">${body}</svg></body></html>`;
}

function writeSet(name, png) {
  const dir = path.join(OUT, name + '.imageset');
  fs.mkdirSync(dir, { recursive: true });
  fs.writeFileSync(path.join(dir, name + '.png'), png);
  fs.writeFileSync(path.join(dir, 'Contents.json'), JSON.stringify({
    images: [{ filename: name + '.png', idiom: 'universal' }], info: { author: 'xcode', version: 1 } }, null, 2) + '\n');
}

(async () => {
  fs.mkdirSync(OUT, { recursive: true });
  fs.writeFileSync(path.join(OUT, 'Contents.json'), JSON.stringify({ info: { author: 'xcode', version: 1 },
    properties: { 'provides-namespace': false } }, null, 2) + '\n');
  const browser = await chromium.launch();
  const tab = await browser.newPage({ viewport: { width: SIZE, height: SIZE }, deviceScaleFactor: 1 });
  for (const kind of ['K', 'Q', 'R', 'B', 'N', 'P']) {
    for (const color of ['w', 'b']) {
      await tab.setContent(page(piece(color, kind)));
      const png = await tab.screenshot({ omitBackground: true });
      writeSet(`cutout-${color}${kind}`, png);
      if (color === 'b') {
        // The shadow: the shape's silhouette, softened. The app sets it off to the side.
        const shadow = `<filter id="soft" x="-30%" y="-30%" width="160%" height="160%"><feGaussianBlur stdDeviation="1.1"/></filter>
          <g filter="url(#soft)"><g fill="#000" stroke="#000">${sub(inner(fs.readFileSync(path.join(PIECES, 'b' + kind + '.svg'), 'utf8')),
            { '"#ececec"': '"#000"', 'fill="none"': 'fill="#000"' })}</g></g>`;
        await tab.setContent(page(shadow));
        writeSet(`cutout-shadow-${kind}`, await tab.screenshot({ omitBackground: true }));
      }
    }
  }
  await browser.close();
})();
