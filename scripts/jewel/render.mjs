import { chromium } from 'playwright-core';
import fs from 'fs';
// usage: node render.mjs "<query>" out.png [more "<query>" out.png pairs]
const args = process.argv.slice(2);
const b = await chromium.launch({ executablePath: '/opt/pw-browsers/chromium-1194/chrome-linux/chrome',
  args: ['--use-angle=swiftshader', '--enable-unsafe-swiftshader', '--ignore-gpu-blocklist', '--enable-webgl', '--disable-gpu-watchdog'] });
for (let i = 0; i < args.length; i += 2) {
  const query = args[i], out = args[i + 1];
  const params = new URLSearchParams(query);
  const w = +(params.get('w') || 1600), h = +(params.get('h') || 900);
  const p = await b.newPage({ viewport: { width: w, height: h } });
  p.on('console', m => console.log('console:', m.text().slice(0, 300)));
  p.on('pageerror', e => console.log('pageerror:', e.message));
  const t0 = Date.now();
  await p.goto('http://localhost:8765/index.html?' + query, { waitUntil: 'commit', timeout: 0 });
  await p.waitForFunction('window.__done === true', null, { timeout: 0, polling: 500 });
  const data = await p.evaluate(() => window.__png || document.querySelector('canvas').toDataURL('image/png'));
  if (Array.isArray(data)) data.forEach(([name, d]) => fs.writeFileSync(out.replace('%s', name), Buffer.from(d.split(',')[1], 'base64')));
  else fs.writeFileSync(out, Buffer.from(data.split(',')[1], 'base64'));
  console.log('wrote', out, ((Date.now() - t0) / 1000).toFixed(1) + 's');
  await p.close();
}
await b.close();
