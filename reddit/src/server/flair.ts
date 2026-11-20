// Opt-in streak flair: a player can show their Daily Circuit streak as their
// user flair in the subreddit the app runs in ("🔥 4-day streak").
//
//  - Off by default; only the player turns it on (POST /api/flair).
//  - Turning it on saves the flair they had; turning it off puts that back.
//  - It follows the streak: after each race (refreshStreakFlair) and once a
//    day for everyone who has it on (refreshAllStreakFlairs), so a lapsed
//    streak never keeps showing.
//
// No Devvit imports: the flair itself goes through a `FlairSink`, which
// index.ts backs with Devvit's reddit client and the tests fake.

import type { FlairResponse } from '../shared/api.ts';
import { type Store, dayOf, playerKey, readPlayer, visibleStreak } from './daily.ts';

/** A user flair as Reddit reports it. */
export type Flair = { text: string; cssClass?: string };

export interface FlairSink {
  /** The player's current user flair in the subreddit, or undefined for none. */
  read(username: string): Promise<Flair | undefined>;
  /** Shows our streak flair. */
  show(username: string, text: string): Promise<void>;
  /** Puts back the flair the player had (undefined = none). */
  restore(username: string, flair: Flair | undefined): Promise<void>;
}

/** Everyone with the flair on (a sorted set used as a plain set). */
const FLAIR_SET = 'flair:on';
const FLAIR_FIELDS = ['flair', 'flairShown', 'flairPrevText', 'flairPrevCss'];

export function streakFlairText(streak: number): string {
  return streak > 0 ? `🔥 ${streak}-day streak` : '🏁 Daily Circuit racer';
}

/**
 * Turns the streak flair on or off for `username`. Throws if Reddit refuses the
 * change; nothing is stored in that case, so the saved state never claims a
 * flair that is not there.
 */
export async function setStreakFlair(
  store: Store,
  sink: FlairSink,
  username: string,
  on: boolean,
  nowMs: number,
): Promise<FlairResponse> {
  const key = playerKey(username);
  const raw = await store.hGetAll(key);
  const isOn = raw.flair === '1';

  if (on) {
    const player = await readPlayer(store, username);
    const text = streakFlairText(visibleStreak(player, dayOf(nowMs)).current);
    if (!isOn) {
      const before = await sink.read(username);
      await sink.show(username, text);
      await store.hSet(key, {
        flair: '1',
        flairShown: text,
        flairPrevText: before?.text ?? '',
        flairPrevCss: before?.cssClass ?? '',
      });
      await store.zAdd(FLAIR_SET, { member: username, score: 0 });
    } else if (raw.flairShown !== text) {
      await sink.show(username, text);
      await store.hSet(key, { flairShown: text });
    }
    return { on: true, text };
  }

  if (isOn) {
    const hadOwn = Boolean(raw.flairPrevText || raw.flairPrevCss);
    const own: Flair | undefined = hadOwn
      ? { text: raw.flairPrevText ?? '', ...(raw.flairPrevCss ? { cssClass: raw.flairPrevCss } : {}) }
      : undefined;
    await sink.restore(username, own);
    await store.hDel(key, FLAIR_FIELDS);
    await store.zRem(FLAIR_SET, [username]);
  }
  return { on: false, text: null };
}

/** After a race: keeps an opted-in player's flair in step with their streak. */
export async function refreshStreakFlair(
  store: Store,
  sink: FlairSink,
  username: string,
  streak: number,
): Promise<void> {
  const key = playerKey(username);
  const raw = await store.hGetAll(key);
  if (raw.flair !== '1') return;
  const text = streakFlairText(streak);
  if (raw.flairShown === text) return;
  await sink.show(username, text);
  await store.hSet(key, { flairShown: text });
}

/**
 * Once a day (the daily cron): a streak that has lapsed must not keep showing.
 * Returns how many flairs changed. One player's failure does not stop the rest.
 */
export async function refreshAllStreakFlairs(store: Store, sink: FlairSink, nowMs: number): Promise<number> {
  const today = dayOf(nowMs);
  const members = await store.zRange(FLAIR_SET, 0, -1, { by: 'rank' });
  let changed = 0;
  for (const { member } of members) {
    const player = await readPlayer(store, member);
    if (!player.flairOn) {
      await store.zRem(FLAIR_SET, [member]);   // their record expired; nothing to keep in step
      continue;
    }
    try {
      const before = (await store.hGetAll(playerKey(member))).flairShown;
      await refreshStreakFlair(store, sink, member, visibleStreak(player, today).current);
      if ((await store.hGetAll(playerKey(member))).flairShown !== before) changed++;
    } catch (error) {
      console.error(`streak flair for ${member} failed`, error);
    }
  }
  return changed;
}
