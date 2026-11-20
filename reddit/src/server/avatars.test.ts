// Run with: npm test

import assert from 'node:assert/strict';
import { test } from 'node:test';
import type { Board } from '../shared/api.ts';
import { avatarsFor, isRedditImage, withAvatars } from './avatars.ts';
import { MemoryStore } from './memory-store.ts';

const SNOO = 'https://i.redd.it/snoovatar/avatars/abc.png';

/** Stands in for reddit.getSnoovatarUrl, counting calls per name. */
function fakeLookup(avatars: Record<string, string | Error>) {
  const calls: string[] = [];
  const lookup = async (name: string) => {
    calls.push(name);
    const found = avatars[name];
    if (found instanceof Error) throw found;
    return found;
  };
  return { lookup, calls };
}

const board = (names: string[], me: string | null): Board => ({
  kind: 'level',
  levelId: 2,
  players: names.length,
  top: names.map((name, i) => ({ rank: i + 1, name, timeMs: 60_000 + i })),
  me: me === null ? null : { rank: names.indexOf(me) + 1, name: me, timeMs: 60_000 },
});

test('rows get their player avatar; players without one get none', async () => {
  const store = new MemoryStore();
  const { lookup } = fakeLookup({ ann: SNOO });
  const result = await withAvatars(store, lookup, board(['ann', 'bob'], 'ann'));
  assert.equal(result.top[0]?.avatar, SNOO);
  assert.equal(result.top[1]?.avatar, undefined);
  assert.equal('avatar' in (result.top[1] ?? {}), false);
  assert.equal(result.me?.avatar, SNOO);
});

test('each name is looked up once, then served from the cache', async () => {
  const store = new MemoryStore();
  const { lookup, calls } = fakeLookup({ ann: SNOO });
  await withAvatars(store, lookup, board(['ann', 'bob'], 'ann'));
  assert.deepEqual(calls.sort(), ['ann', 'bob']);
  const again = await withAvatars(store, lookup, board(['ann', 'bob'], 'bob'));
  assert.deepEqual(calls.sort(), ['ann', 'bob'], 'no new lookups: "has none" is cached too');
  assert.equal(again.top[0]?.avatar, SNOO);
});

test('a failed lookup gives no avatar and is tried again next time', async () => {
  const store = new MemoryStore();
  const avatars: Record<string, string | Error> = { ann: new Error('GQL down') };
  const { lookup, calls } = fakeLookup(avatars);
  assert.deepEqual(await avatarsFor(store, lookup, ['ann']), {});
  avatars.ann = SNOO;
  assert.deepEqual(await avatarsFor(store, lookup, ['ann']), { ann: SNOO });
  assert.equal(calls.length, 2);
});

test('only Reddit-hosted https images are passed on', async () => {
  assert.equal(isRedditImage(SNOO), true);
  assert.equal(isRedditImage('https://styles.redditmedia.com/t5_1/styles/profileIcon.png'), true);
  assert.equal(isRedditImage('http://i.redd.it/x.png'), false);
  assert.equal(isRedditImage('https://example.com/x.png'), false);
  assert.equal(isRedditImage('https://i.redd.it.evil.com/x.png'), false);
  assert.equal(isRedditImage('not a url'), false);
  const store = new MemoryStore();
  const { lookup } = fakeLookup({ eve: 'https://example.com/eve.png' });
  assert.deepEqual(await avatarsFor(store, lookup, ['eve']), {});
});

test('cached avatars expire after a day', async () => {
  const store = new MemoryStore();
  const { lookup } = fakeLookup({ ann: SNOO });
  await avatarsFor(store, lookup, ['ann']);
  assert.equal(store.ttl('avatar:ann'), 24 * 60 * 60);
});
