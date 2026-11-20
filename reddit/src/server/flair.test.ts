// Run with: npm test

import assert from 'node:assert/strict';
import { test } from 'node:test';
import { getInit, levelOfDay, playerKey, submitRun } from './daily.ts';
import { type Flair, type FlairSink, refreshAllStreakFlairs, refreshStreakFlair, setStreakFlair, streakFlairText } from './flair.ts';
import { MemoryStore } from './memory-store.ts';

const DAY_MS = 86_400_000;
const DAY_1 = Date.UTC(2026, 10, 16, 12);
const noonOf = (day: number) => DAY_1 + (day - 1) * DAY_MS;
const dailyRun = (store: MemoryStore, day: number, name: string, now: number) =>
  submitRun(store, day, name, levelOfDay(day), 60_000, now);

/** Stands in for Reddit: each player's current flair, and whether it refuses changes. */
class FakeReddit implements FlairSink {
  flairs = new Map<string, Flair>();
  refuse = false;

  async read(username: string) {
    return this.flairs.get(username);
  }

  async show(username: string, text: string) {
    if (this.refuse) throw new Error('403 no flair permission');
    this.flairs.set(username, { text });
  }

  async restore(username: string, flair: Flair | undefined) {
    if (this.refuse) throw new Error('403 no flair permission');
    if (flair) this.flairs.set(username, flair);
    else this.flairs.delete(username);
  }
}

test('flair text follows the streak', () => {
  assert.equal(streakFlairText(4), '🔥 4-day streak');
  assert.equal(streakFlairText(1), '🔥 1-day streak');
  assert.equal(streakFlairText(0), '🏁 Daily Circuit racer');
});

test('it is off until the player turns it on', async () => {
  const store = new MemoryStore();
  const reddit = new FakeReddit();
  await dailyRun(store, 1, 'ana', noonOf(1));
  assert.equal((await getInit(store, 1, 'ana', noonOf(1))).flairOn, false);
  assert.equal(reddit.flairs.size, 0);
});

test('turning it on shows the streak and remembers the flair it replaced', async () => {
  const store = new MemoryStore();
  const reddit = new FakeReddit();
  reddit.flairs.set('ana', { text: 'Pit crew', cssClass: 'crew' });
  await dailyRun(store, 1, 'ana', noonOf(1));
  await dailyRun(store, 2, 'ana', noonOf(2));

  const on = await setStreakFlair(store, reddit, 'ana', true, noonOf(2));
  assert.deepEqual(on, { on: true, text: '🔥 2-day streak' });
  assert.deepEqual(reddit.flairs.get('ana'), { text: '🔥 2-day streak' });
  assert.equal((await getInit(store, 2, 'ana', noonOf(2))).flairOn, true);

  const off = await setStreakFlair(store, reddit, 'ana', false, noonOf(2));
  assert.deepEqual(off, { on: false, text: null });
  assert.deepEqual(reddit.flairs.get('ana'), { text: 'Pit crew', cssClass: 'crew' }, 'their own flair is back');
  assert.equal((await getInit(store, 2, 'ana', noonOf(2))).flairOn, false);
});

test('turning it off when they had no flair removes it', async () => {
  const store = new MemoryStore();
  const reddit = new FakeReddit();
  await dailyRun(store, 1, 'ben', noonOf(1));
  await setStreakFlair(store, reddit, 'ben', true, noonOf(1));
  await setStreakFlair(store, reddit, 'ben', false, noonOf(1));
  assert.equal(reddit.flairs.has('ben'), false);
});

test('a race moves the flair with the streak', async () => {
  const store = new MemoryStore();
  const reddit = new FakeReddit();
  await dailyRun(store, 1, 'ana', noonOf(1));
  await setStreakFlair(store, reddit, 'ana', true, noonOf(1));

  const run = await dailyRun(store, 2, 'ana', noonOf(2));
  assert.equal(run.flairOn, true, 'the run response says the flair is on');
  await refreshStreakFlair(store, reddit, 'ana', run.streak.current);
  assert.equal(reddit.flairs.get('ana')?.text, '🔥 2-day streak');

  // Without the opt-in, a race never touches flair.
  await dailyRun(store, 2, 'cat', noonOf(2));
  await refreshStreakFlair(store, reddit, 'cat', 1);
  assert.equal(reddit.flairs.has('cat'), false);
});

test('if Reddit refuses, nothing is stored and it stays off', async () => {
  const store = new MemoryStore();
  const reddit = new FakeReddit();
  reddit.refuse = true;
  await dailyRun(store, 1, 'ana', noonOf(1));
  await assert.rejects(setStreakFlair(store, reddit, 'ana', true, noonOf(1)));
  assert.equal((await getInit(store, 1, 'ana', noonOf(1))).flairOn, false);
});

test('the daily refresh stops a lapsed streak from showing', async () => {
  const store = new MemoryStore();
  const reddit = new FakeReddit();
  await dailyRun(store, 1, 'ana', noonOf(1));
  await dailyRun(store, 2, 'ana', noonOf(2));
  await setStreakFlair(store, reddit, 'ana', true, noonOf(2));

  // Day 3: still alive (yesterday counts), nothing changes.
  assert.equal(await refreshAllStreakFlairs(store, reddit, noonOf(3)), 0);
  assert.equal(reddit.flairs.get('ana')?.text, '🔥 2-day streak');

  // Day 4: day 3 was missed, so the streak is over.
  assert.equal(await refreshAllStreakFlairs(store, reddit, noonOf(4)), 1);
  assert.equal(reddit.flairs.get('ana')?.text, '🏁 Daily Circuit racer');

  // A record that expired is dropped from the daily list, flair untouched.
  store.hashes.delete(playerKey('ana'));
  assert.equal(await refreshAllStreakFlairs(store, reddit, noonOf(5)), 0);
  assert.equal(await store.zCard('flair:on'), 0);
});
