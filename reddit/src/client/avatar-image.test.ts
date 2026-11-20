// Checks which avatar URLs the page loads, and the head crop of a snoovatar.

import assert from 'node:assert/strict';
import { test } from 'node:test';
import { avatarSource, cropOf } from './avatar-image.ts';

const PAGE = 'https://fourwd-abc.devvit.net/game.html';

test('Reddit-hosted https images and this page’s own host are loaded', () => {
  assert.equal(avatarSource('https://i.redd.it/snoovatar/avatars/a.png', PAGE)?.hostname, 'i.redd.it');
  assert.equal(avatarSource('https://styles.redditmedia.com/t5_1/x.png', PAGE)?.hostname, 'styles.redditmedia.com');
  assert.equal(avatarSource('/local-avatar/ann.svg', PAGE)?.href, 'https://fourwd-abc.devvit.net/local-avatar/ann.svg');
});

test('anything else is refused', () => {
  assert.equal(avatarSource('http://i.redd.it/a.png', PAGE), null);
  assert.equal(avatarSource('https://example.com/a.png', PAGE), null);
  assert.equal(avatarSource('https://i.redd.it.example.com/a.png', PAGE), null);
  assert.equal(avatarSource('javascript:alert(1)', PAGE), null);
  assert.equal(avatarSource('data:image/png;base64,AAAA', PAGE), null);
});

test('a tall snoovatar keeps its top square; a wide picture its middle', () => {
  assert.deepEqual(cropOf(380, 600), { x: 0, y: 0, side: 380 });
  assert.deepEqual(cropOf(200, 100), { x: 50, y: 0, side: 100 });
  assert.deepEqual(cropOf(64, 64), { x: 0, y: 0, side: 64 });
});
