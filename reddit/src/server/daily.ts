// Daily Circuit rules: which day a moment belongs to, which level is that
// day's circuit (one per weekday, Monday the easiest), the three leaderboards
// (day, per level, overall) and each player's streak. Every time on them is a
// ranked race: ONE lap (the game's casual 3-lap races are never sent).
//
// No Devvit imports here on purpose: everything takes a `Store`, which Devvit's
// redis client satisfies in production and tools/serve-local.ts fakes in memory.

import type {
  Board,
  BoardKind,
  InitResponse,
  LeaderboardResponse,
  Row,
  RunResponse,
  Streak,
} from '../shared/api.ts';

/** The subset of Devvit's redis client this module uses. */
export interface Store {
  get(key: string): Promise<string | undefined>;
  set(key: string, value: string): Promise<unknown>;
  expire(key: string, seconds: number): Promise<unknown>;
  hGetAll(key: string): Promise<Record<string, string>>;
  hSet(key: string, fieldValues: Record<string, string>): Promise<unknown>;
  hDel(key: string, fields: string[]): Promise<unknown>;
  zAdd(key: string, ...members: { member: string; score: number }[]): Promise<unknown>;
  zRem(key: string, members: string[]): Promise<unknown>;
  zScore(key: string, member: string): Promise<number | undefined>;
  zRank(key: string, member: string): Promise<number | undefined>;
  zCard(key: string): Promise<number>;
  zRange(
    key: string,
    start: number,
    stop: number,
    options?: { by: 'rank' | 'score' | 'lex'; reverse?: boolean },
  ): Promise<{ member: string; score: number }[]>;
}

const DAY_MS = 86_400_000;
/** Daily Circuit #1 is this UTC date (a Monday). Days roll over at 00:00 UTC. */
const FIRST_DAY_UTC = Date.UTC(2026, 10, 16);

/**
 * The game's levels by permanent id, in level order: Monday's circuit (the
 * easiest) first, Sunday's (the hardest) last. Must match `LEVELS[i].id` in
 * scripts/game_data.gd: the game reports a finished race by this id.
 */
export const LEVEL_IDS: readonly number[] = [10, 11, 12, 13, 14, 15, 16];

/** Rows returned when the caller does not ask for a number. */
export const TOP_COUNT = 10;
const MAX_ROWS = 50;
/** Sanity bounds on a reported race time; the client is not trusted. */
const MIN_TIME_MS = 5_000;
const MAX_TIME_MS = 30 * 60_000;
/** Day boards and streaks are dropped after this long without activity. */
const RETENTION_SECONDS = 90 * 24 * 60 * 60;

export function dayOf(nowMs: number): number {
  return Math.floor((nowMs - FIRST_DAY_UTC) / DAY_MS) + 1;
}

/**
 * Milliseconds from `nowMs` until the next Daily Circuit starts. Sent as a
 * duration, not a clock time, so a player's wrong device clock cannot skew
 * the countdown the game shows.
 */
export function msUntilNextDay(nowMs: number): number {
  return FIRST_DAY_UTC + dayOf(nowMs) * DAY_MS - nowMs;
}

export function dateOf(day: number): string {
  return new Date(FIRST_DAY_UTC + (day - 1) * DAY_MS).toISOString().slice(0, 10);
}

/** Integer hash of the day number, so neighbouring days get unrelated seeds. */
export function seedOf(day: number): number {
  let x = (day + 0x9e3779b9) | 0;
  x = Math.imul(x ^ (x >>> 16), 0x85ebca6b);
  x = Math.imul(x ^ (x >>> 13), 0xc2b2ae35);
  return (x ^ (x >>> 16)) >>> 0;
}

/** 0 = Monday ... 6 = Sunday, for `day`'s UTC date. */
export function weekdayOf(day: number): number {
  return (new Date(FIRST_DAY_UTC + (day - 1) * DAY_MS).getUTCDay() + 6) % 7;
}

/** The level that is `day`'s circuit: one per weekday, Monday's the easiest. */
export function levelOfDay(day: number): number {
  return LEVEL_IDS[weekdayOf(day) % LEVEL_IDS.length] as number;
}

export function isLevelId(value: unknown): value is number {
  return typeof value === 'number' && LEVEL_IDS.includes(value);
}

export function postTitle(day: number): string {
  const label = new Date(FIRST_DAY_UTC + (day - 1) * DAY_MS).toLocaleDateString('en-US', {
    month: 'short',
    day: 'numeric',
    timeZone: 'UTC',
  });
  return `Four Wheel Steer: Daily Circuit #${day} (${label})`;
}

/** The post's day if it carries one, else today. */
export function dayFromPostData(postData: unknown, nowMs: number): number {
  if (typeof postData === 'object' && postData !== null && 'day' in postData) {
    const day = (postData as { day: unknown }).day;
    if (typeof day === 'number' && Number.isInteger(day) && day >= 1) return day;
  }
  return dayOf(nowMs);
}

// Sorted sets, member = username, score = time in ms (lowest ranks first).
// The day and overall keys carry `1lap`: before 2026-11-20 races were three
// laps on smaller tracks (ids 1, 2, 3, 8, 9), and those times must not mix
// with these. Level boards need no tag: the new tracks have new ids.
const dayKey = (day: number) => `1lap:board:${day}`;
/** Best time ever on one level. */
const levelKey = (levelId: number) => `level:${levelId}`;
/** Sum of a player's bests over every level; present only once they have them all. */
const OVERALL_KEY = '1lap:overall';
/** A player's streak, and their streak-flair choice (see flair.ts). */
export const playerKey = (name: string) => `player:${name}`;
/** Holds the post id once a day's post exists, so it is only created once. */
export const dayPostKey = (day: number) => `daypost:${day}`;

async function readBoard(
  store: Store,
  key: string,
  kind: BoardKind,
  levelId: number | null,
  username: string | null,
  limit: number = TOP_COUNT,
): Promise<Board> {
  const rows = Math.max(1, Math.min(MAX_ROWS, Math.floor(limit) || TOP_COUNT));
  const [players, range] = await Promise.all([
    store.zCard(key),
    store.zRange(key, 0, rows - 1, { by: 'rank' }),
  ]);
  const top: Row[] = range.map((entry, i) => ({
    rank: i + 1,
    name: entry.member,
    timeMs: entry.score,
  }));

  let me: Row | null = null;
  if (username) {
    const [score, rank] = await Promise.all([
      store.zScore(key, username),
      store.zRank(key, username),
    ]);
    if (score !== undefined && rank !== undefined) {
      me = { rank: rank + 1, name: username, timeMs: score };
    }
  }
  return { kind, levelId, players, top, me };
}

const readDayBoard = (store: Store, day: number, username: string | null, limit?: number) =>
  readBoard(store, dayKey(day), 'day', levelOfDay(day), username, limit);

/** The player's best time on each level, in LEVEL_IDS order (undefined = none yet). */
async function levelBests(store: Store, username: string): Promise<(number | undefined)[]> {
  return Promise.all(LEVEL_IDS.map((id) => store.zScore(levelKey(id), username)));
}

async function mapsDoneOf(store: Store, username: string | null): Promise<number> {
  if (!username) return 0;
  return (await levelBests(store, username)).filter((best) => best !== undefined).length;
}

export type PlayerRecord = { streak: number; best: number; lastDay: number; flairOn: boolean };

export async function readPlayer(store: Store, username: string): Promise<PlayerRecord> {
  const raw = await store.hGetAll(playerKey(username));
  return {
    streak: Number(raw.streak ?? 0) || 0,
    best: Number(raw.best ?? 0) || 0,
    lastDay: Number(raw.lastDay ?? 0) || 0,
    flairOn: raw.flair === '1',
  };
}

async function flairOnFor(store: Store, username: string | null): Promise<boolean> {
  return username ? (await readPlayer(store, username)).flairOn : false;
}

/** A streak is alive if its latest finish was today or yesterday. */
export function visibleStreak(player: PlayerRecord, today: number): Streak {
  const alive = player.lastDay >= today - 1;
  return { current: alive ? player.streak : 0, best: player.best };
}

async function streakOf(store: Store, username: string | null, today: number): Promise<Streak> {
  return username ? visibleStreak(await readPlayer(store, username), today) : { current: 0, best: 0 };
}

export async function getInit(
  store: Store,
  day: number,
  username: string | null,
  nowMs: number,
): Promise<InitResponse> {
  const today = dayOf(nowMs);
  const [board, streak, mapsDone, flairOn] = await Promise.all([
    readDayBoard(store, day, username),
    streakOf(store, username, today),
    mapsDoneOf(store, username),
    flairOnFor(store, username),
  ]);
  return {
    day,
    seed: seedOf(day),
    date: dateOf(day),
    isToday: day === today,
    levelId: levelOfDay(day),
    levelIds: [...LEVEL_IDS],
    username,
    avatar: null,   // filled in by the caller (avatars.ts needs Reddit's lookup)
    me: board.me,
    streak,
    players: board.players,
    top: board.top,
    mapsDone,
    nextCircuitInMs: msUntilNextDay(nowMs),
    flairOn,
  };
}

/**
 * One leaderboard. `levelId` is only read for kind `level`; an unknown level
 * (or kind) falls back to the overall board.
 */
export async function getLeaderboard(
  store: Store,
  day: number,
  username: string | null,
  kind: unknown = 'day',
  levelId: unknown = null,
  limit: number = TOP_COUNT,
): Promise<LeaderboardResponse> {
  let board: Board;
  if (kind === 'day') board = await readDayBoard(store, day, username, limit);
  else if (kind === 'level' && isLevelId(levelId))
    board = await readBoard(store, levelKey(levelId), 'level', levelId, username, limit);
  else board = await readBoard(store, OVERALL_KEY, 'overall', null, username, limit);
  return {
    ...board,
    day,
    mapsDone: await mapsDoneOf(store, username),
    mapsTotal: LEVEL_IDS.length,
  };
}

export function isValidTime(timeMs: unknown): timeMs is number {
  return (
    typeof timeMs === 'number' &&
    Number.isFinite(timeMs) &&
    timeMs >= MIN_TIME_MS &&
    timeMs <= MAX_TIME_MS
  );
}

/**
 * Records a finished race on `levelId`.
 *
 *  - The level board keeps the player's best time ever on that level.
 *  - The overall board holds the sum of their bests on every level, and only
 *    exists for them once they have a time on all of them.
 *  - If the level is `day`'s circuit, the day board takes the time too, and
 *    the streak advances on the first such finish of the current day only, so
 *    replaying an old post never extends it.
 */
export async function submitRun(
  store: Store,
  day: number,
  username: string | null,
  levelId: unknown,
  timeMs: unknown,
  nowMs: number,
): Promise<RunResponse> {
  const today = dayOf(nowMs);
  const valid = username !== null && username !== '' && isValidTime(timeMs) && isLevelId(levelId) && day <= today;

  let improved = false;
  let countsForDay = false;
  let player: PlayerRecord | null = null;

  if (valid) {
    const name = username as string;
    const level = levelId as number;
    const time = Math.round(timeMs as number);

    const previous = await store.zScore(levelKey(level), name);
    improved = previous === undefined || time < previous;
    if (improved) await store.zAdd(levelKey(level), { member: name, score: time });

    const bests = await levelBests(store, name);
    if (bests.every((best) => best !== undefined)) {
      const total = (bests as number[]).reduce((sum, best) => sum + best, 0);
      await store.zAdd(OVERALL_KEY, { member: name, score: total });
    }

    countsForDay = level === levelOfDay(day);
    player = await readPlayer(store, name);
    if (countsForDay) {
      const key = dayKey(day);
      const dayBest = await store.zScore(key, name);
      if (dayBest === undefined || time < dayBest) {
        await store.zAdd(key, { member: name, score: time });
        await store.expire(key, RETENTION_SECONDS);
      }
      if (day === today && player.lastDay !== today) {
        player.streak = player.lastDay === today - 1 ? player.streak + 1 : 1;
        player.best = Math.max(player.best, player.streak);
        player.lastDay = today;
        await store.hSet(playerKey(name), {
          streak: String(player.streak),
          best: String(player.best),
          lastDay: String(player.lastDay),
        });
      }
    }
    await store.expire(playerKey(name), RETENTION_SECONDS);
  }

  const shownLevel = isLevelId(levelId) ? levelId : levelOfDay(day);
  const [dayBoard, level, overall, mapsDone, streak] = await Promise.all([
    readDayBoard(store, day, username),
    readBoard(store, levelKey(shownLevel), 'level', shownLevel, username),
    readBoard(store, OVERALL_KEY, 'overall', null, username),
    mapsDoneOf(store, username),
    player ? Promise.resolve(visibleStreak(player, today)) : streakOf(store, username, today),
  ]);
  return {
    accepted: valid,
    improved,
    countsForDay,
    me: dayBoard.me,
    streak,
    players: dayBoard.players,
    top: dayBoard.top,
    level,
    overall,
    mapsDone,
    nextCircuitInMs: msUntilNextDay(nowMs),
    flairOn: player ? player.flairOn : await flairOnFor(store, username),
  };
}
