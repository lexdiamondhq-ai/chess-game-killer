// The browser knows every board look the app has, so a friend always sees the creator's board.
import { test } from "node:test";
import assert from "node:assert/strict";
import { readFileSync, existsSync } from "node:fs";

const theme = readFileSync(new URL("../../ChessGameKiller/Views/BoardTheme.swift", import.meta.url), "utf8");
const looksJs = readFileSync(new URL("../public/looks.js", import.meta.url), "utf8");
const looksCss = readFileSync(new URL("../public/looks.css", import.meta.url), "utf8");

const appLooks = theme
  .match(/enum ID: String, CaseIterable \{([\s\S]*?)\n    \}/)[1]
  .replace(/\/\/.*$/gm, "")
  .match(/case ([^\n]+)/g)
  .flatMap((line) => line.replace("case ", "").split(",").map((s) => s.trim()))
  .filter(Boolean);
const browserLooks = JSON.parse(looksJs.match(/LOOKS = (\[.*\]);/)[1]);
const browserDefault = JSON.parse(looksJs.match(/DEFAULT_LOOK = (".*");/)[1]);

test("the browser has every look in the app (run scripts/play/export_looks.py after changing one)", () => {
  assert.deepEqual([...browserLooks].sort(), [...appLooks].sort());
  for (const look of appLooks) assert.match(looksCss, new RegExp(`\\[data-look="${look}"\\] \\{`), look);
});

test("the browser's default look is the app's", () => {
  const first = theme.match(/static let all: \[BoardTheme\] = \[\s*\.(\w+)/)[1];
  assert.equal(browserDefault, first);
});

test("every picture looks.css asks for is there", () => {
  for (const [, path] of looksCss.matchAll(/url\((\/looks\/[^)]+)\)/g)) {
    assert.ok(existsSync(new URL(`../public${path}`, import.meta.url)), path);
  }
});
