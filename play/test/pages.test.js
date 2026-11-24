// The invite page reads naturally even when the person who sent it left their name blank.
import { test } from "node:test";
import assert from "node:assert/strict";
import { renderInvitePage } from "../src/pages.js";

const waiting = (name) => ({
  status: "waiting",
  creator: "white",
  white: { name },
  black: null,
  clock: { initial: 600, increment: 0 },
});

test("an invite from someone with a name shows their name", () => {
  const html = renderInvitePage({ game: waiting("Alex"), origin: "https://example.com", code: "ABCDEF" });
  assert.match(html, /Alex challenged you to chess/);
});

test("an invite with the default name says A friend, never Player", () => {
  const html = renderInvitePage({ game: waiting("Player"), origin: "https://example.com", code: "ABCDEF" });
  assert.match(html, /A friend challenged you to chess/);
  assert.doesNotMatch(html, /Player challenged you/);
});
