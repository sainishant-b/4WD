// Run with: npm test

import assert from 'node:assert/strict';
import { test } from 'node:test';
import {
  LEVEL_IDS,
  dateOf,
  dayFromPostData,
  dayOf,
  getInit,
  getLeaderboard,
  levelOfDay,
  weekdayOf,
  msUntilNextDay,
  seedOf,
  submitRun,
} from './daily.ts';
import { MemoryStore } from './memory-store.ts';

const DAY_MS = 86_400_000;
/** Noon UTC on Daily Circuit #1. */
const DAY_1 = Date.UTC(2026, 10, 16, 12);
const noonOf = (day: number) => DAY_1 + (day - 1) * DAY_MS;

/** A run on `day`'s own circuit, which is what counts for the day board. */
const dailyRun = (store: MemoryStore, day: number, name: string | null, timeMs: unknown, now: number) =>
  submitRun(store, day, name, levelOfDay(day), timeMs, now);

test('days are numbered from launch and roll over at 00:00 UTC', () => {
  assert.equal(dayOf(Date.UTC(2026, 10, 16, 0, 0, 0)), 1);
  assert.equal(dayOf(Date.UTC(2026, 10, 16, 23, 59, 59)), 1);
  assert.equal(dayOf(Date.UTC(2026, 10, 17, 0, 0, 0)), 2);
  assert.equal(dateOf(1), '2026-11-16');
  assert.equal(dateOf(24), '2026-12-09');
});

test('the next circuit is counted down to 00:00 UTC', async () => {
  assert.equal(msUntilNextDay(Date.UTC(2026, 10, 16, 12)), 12 * 3_600_000);
  assert.equal(msUntilNextDay(Date.UTC(2026, 10, 16, 23, 59, 59)), 1_000);
  assert.equal(msUntilNextDay(Date.UTC(2026, 10, 17, 0, 0, 0)), DAY_MS);
  const store = new MemoryStore();
  assert.equal((await getInit(store, 1, 'ana', DAY_1)).nextCircuitInMs, 12 * 3_600_000);
  assert.equal((await dailyRun(store, 1, 'ana', 60_000, DAY_1)).nextCircuitInMs, 12 * 3_600_000);
});

test('every day has its own stable seed', () => {
  assert.equal(seedOf(5), seedOf(5));
  const seeds = new Set(Array.from({ length: 365 }, (_, i) => seedOf(i + 1)));
  assert.equal(seeds.size, 365);
});

test('the levels take turns as the daily circuit', () => {
  const week = Array.from({ length: LEVEL_IDS.length * 2 }, (_, i) => levelOfDay(i + 1));
  assert.deepEqual(week, [...LEVEL_IDS, ...LEVEL_IDS]);
  // Day 1 was Monday 16 Nov 2026: Monday gets the first (easiest) level,
  // Friday 20 Nov the fifth, Sunday the last (hardest).
  assert.equal(LEVEL_IDS.length, 7);
  assert.equal(weekdayOf(1), 0);
  assert.equal(levelOfDay(1), LEVEL_IDS[0]);
  assert.equal(weekdayOf(5), 4);
  assert.equal(levelOfDay(5), LEVEL_IDS[4]);
  assert.equal(levelOfDay(7), LEVEL_IDS[6]);
  assert.equal(levelOfDay(8), LEVEL_IDS[0]);
});

test('a post plays its own day; anything else plays today', () => {
  assert.equal(dayFromPostData({ day: 3 }, noonOf(9)), 3);
  assert.equal(dayFromPostData(undefined, noonOf(9)), 9);
  assert.equal(dayFromPostData({ day: 'x' }, noonOf(9)), 9);
  assert.equal(dayFromPostData({ day: 0 }, noonOf(9)), 9);
});

test('the day board keeps only a player’s best time and ranks fastest first', async () => {
  const store = new MemoryStore();
  await dailyRun(store, 1, 'ana', 70_000, DAY_1);
  await dailyRun(store, 1, 'ben', 60_000, DAY_1);

  const slower = await dailyRun(store, 1, 'ben', 65_000, DAY_1);
  assert.equal(slower.accepted, true);
  assert.equal(slower.improved, false);
  assert.deepEqual(slower.me, { rank: 1, name: 'ben', timeMs: 60_000 });

  const faster = await dailyRun(store, 1, 'ana', 55_000, DAY_1);
  assert.equal(faster.improved, true);
  assert.deepEqual(
    faster.top.map((row) => [row.rank, row.name, row.timeMs]),
    [
      [1, 'ana', 55_000],
      [2, 'ben', 60_000],
    ],
  );
  assert.equal(faster.players, 2);
});

test('logged-out players, impossible times and unknown levels are not stored', async () => {
  const store = new MemoryStore();
  for (const bad of [0, 4_999, -1, Number.NaN, Infinity, '60000', undefined, 31 * 60_000]) {
    const result = await dailyRun(store, 1, 'ana', bad, DAY_1);
    assert.equal(result.accepted, false, `time ${String(bad)}`);
  }
  for (const level of [0, 7, -1, '2', undefined, null, 2.5]) {
    const result = await submitRun(store, 1, 'ana', level, 60_000, DAY_1);
    assert.equal(result.accepted, false, `level ${String(level)}`);
  }
  assert.equal((await dailyRun(store, 1, null, 60_000, DAY_1)).accepted, false);
  assert.equal((await dailyRun(store, 2, 'ana', 60_000, DAY_1)).accepted, false, 'future day');
  assert.equal((await getInit(store, 1, 'ana', DAY_1)).players, 0);
  assert.equal((await getLeaderboard(store, 1, 'ana', 'overall')).players, 0);
});

test('a run on another level ranks on that level but not on the day board', async () => {
  const store = new MemoryStore();
  const other = LEVEL_IDS.find((id) => id !== levelOfDay(1)) as number;

  const run = await submitRun(store, 1, 'ana', other, 60_000, DAY_1);
  assert.equal(run.accepted, true);
  assert.equal(run.countsForDay, false);
  assert.equal(run.me, null);
  assert.equal(run.players, 0);
  assert.deepEqual(run.streak, { current: 0, best: 0 });
  assert.deepEqual(run.level.me, { rank: 1, name: 'ana', timeMs: 60_000 });
  assert.equal(run.level.levelId, other);

  const daily = await dailyRun(store, 1, 'ana', 62_000, DAY_1);
  assert.equal(daily.countsForDay, true);
  assert.deepEqual(daily.me, { rank: 1, name: 'ana', timeMs: 62_000 });
  assert.equal(daily.streak.current, 1);
});

test('overall ranks the sum of best times, only for players with every level', async () => {
  const store = new MemoryStore();
  // ana: 60s on each level; ben: 50s on all but the last one.
  for (const id of LEVEL_IDS) await submitRun(store, 1, 'ana', id, 60_000, DAY_1);
  for (const id of LEVEL_IDS.slice(0, -1)) await submitRun(store, 1, 'ben', id, 50_000, DAY_1);

  let board = await getLeaderboard(store, 1, 'ben', 'overall');
  assert.deepEqual(board.top, [{ rank: 1, name: 'ana', timeMs: 60_000 * LEVEL_IDS.length }]);
  assert.equal(board.me, null, 'ben is one level short');
  assert.equal(board.mapsDone, LEVEL_IDS.length - 1);
  assert.equal(board.mapsTotal, LEVEL_IDS.length);

  // ben finishes the last level: his lower total goes to the top.
  const last = LEVEL_IDS[LEVEL_IDS.length - 1] as number;
  const done = await submitRun(store, 1, 'ben', last, 50_000, DAY_1);
  assert.equal(done.mapsDone, LEVEL_IDS.length);
  assert.deepEqual(done.overall.me, { rank: 1, name: 'ben', timeMs: 50_000 * LEVEL_IDS.length });

  // A faster lap on one level lowers ana's total; a slower one changes nothing.
  await submitRun(store, 1, 'ana', last, 20_000, DAY_1);
  await submitRun(store, 1, 'ana', last, 90_000, DAY_1);
  board = await getLeaderboard(store, 1, 'ana', 'overall');
  assert.deepEqual(
    board.top.map((row) => [row.rank, row.name, row.timeMs]),
    [
      [1, 'ben', 50_000 * LEVEL_IDS.length],
      [2, 'ana', 60_000 * (LEVEL_IDS.length - 1) + 20_000],
    ],
  );
  assert.deepEqual(board.me, { rank: 2, name: 'ana', timeMs: 60_000 * (LEVEL_IDS.length - 1) + 20_000 });
});

test('leaderboard picks the board asked for and limits its rows', async () => {
  const store = new MemoryStore();
  const level = LEVEL_IDS[0] as number;
  for (let i = 0; i < 30; i++) await submitRun(store, 1, `driver${i}`, level, 60_000 + i, DAY_1);

  const byLevel = await getLeaderboard(store, 1, null, 'level', level, 25);
  assert.equal(byLevel.kind, 'level');
  assert.equal(byLevel.levelId, level);
  assert.equal(byLevel.top.length, 25);
  assert.equal(byLevel.players, 30);
  assert.equal(byLevel.top[0]?.name, 'driver0');

  assert.equal((await getLeaderboard(store, 1, null, 'level', level)).top.length, 10);
  assert.equal((await getLeaderboard(store, 1, null, 'level', level, 999)).top.length, 30);
  assert.equal((await getLeaderboard(store, 1, null, 'level', 12345)).kind, 'overall');
  assert.equal((await getLeaderboard(store, 1, null, 'day')).kind, 'day');
});

test('streak grows on consecutive days, once per day', async () => {
  const store = new MemoryStore();
  assert.equal((await dailyRun(store, 1, 'ana', 60_000, noonOf(1))).streak.current, 1);
  assert.equal((await dailyRun(store, 1, 'ana', 59_000, noonOf(1))).streak.current, 1);
  assert.equal((await dailyRun(store, 2, 'ana', 60_000, noonOf(2))).streak.current, 2);
  assert.deepEqual((await dailyRun(store, 3, 'ana', 60_000, noonOf(3))).streak, {
    current: 3,
    best: 3,
  });
});

test('a missed day resets the streak but keeps the best', async () => {
  const store = new MemoryStore();
  await dailyRun(store, 1, 'ana', 60_000, noonOf(1));
  await dailyRun(store, 2, 'ana', 60_000, noonOf(2));

  // Day 3 skipped: on day 4 the streak already reads as broken.
  assert.deepEqual((await getInit(store, 4, 'ana', noonOf(4))).streak, { current: 0, best: 2 });
  assert.deepEqual((await dailyRun(store, 4, 'ana', 60_000, noonOf(4))).streak, {
    current: 1,
    best: 2,
  });
});

test('replaying an old post ranks but never extends the streak', async () => {
  const store = new MemoryStore();
  await dailyRun(store, 5, 'ana', 60_000, noonOf(5));

  const replay = await dailyRun(store, 2, 'ana', 50_000, noonOf(6));
  assert.equal(replay.accepted, true);
  assert.deepEqual(replay.me, { rank: 1, name: 'ana', timeMs: 50_000 });
  assert.deepEqual(replay.streak, { current: 1, best: 1 });

  const init = await getInit(store, 2, 'ana', noonOf(6));
  assert.equal(init.isToday, false);
  assert.equal(init.levelId, levelOfDay(2));
});
