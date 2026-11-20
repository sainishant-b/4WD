// Devvit server for Four Wheel Steer.
//
//   /api/*       called by the web view (splash page and the Godot game)
//   /internal/*  called by Reddit: menu action, install trigger, daily cron
//
// The rules live in daily.ts (boards, streaks), flair.ts (the opt-in streak
// flair) and avatars.ts (snoovatars on the boards); this file only wires them
// to Devvit.

import { serve } from '@hono/node-server';
import { context, createServer, getServerPort, reddit, redis } from '@devvit/web/server';
import type { TaskResponse } from '@devvit/web/server';
import type { TriggerResponse, UiResponse } from '@devvit/web/shared';
import { Hono } from 'hono';
import type { FlairRequest, FlairResponse, RunRequest } from '../shared/api.ts';
import { type AvatarLookup, avatarsFor, withAvatars } from './avatars.ts';
import {
  dateOf,
  dayFromPostData,
  dayOf,
  dayPostKey,
  getInit,
  getLeaderboard,
  postTitle,
  readPlayer,
  submitRun,
} from './daily.ts';
import {
  type FlairSink,
  refreshAllStreakFlairs,
  refreshStreakFlair,
  setStreakFlair,
} from './flair.ts';

const app = new Hono();

/** The streak flair, set by the app account in the subreddit the app runs in. */
function flairSink(subredditName: string): FlairSink {
  return {
    async read(username) {
      const user = await reddit.getUserByUsername(username);
      const flair = user ? await user.getUserFlairBySubreddit(subredditName) : undefined;
      if (!flair || (!flair.flairText && !flair.flairCssClass)) return undefined;
      return { text: flair.flairText ?? '', ...(flair.flairCssClass ? { cssClass: flair.flairCssClass } : {}) };
    },
    async show(username, text) {
      // Gold with dark text: the game's own colours.
      await reddit.setUserFlair({ subredditName, username, text, backgroundColor: '#ffc21a', textColor: 'dark' });
    },
    async restore(username, flair) {
      if (flair) await reddit.setUserFlair({ subredditName, username, text: flair.text, cssClass: flair.cssClass });
      else await reddit.removeUserFlair(subredditName, username);
    },
  };
}

/** A player's snoovatar URL (free for the viewer: Devvit has it in the context). */
const snoovatar: AvatarLookup = (username) => reddit.getSnoovatarUrl(username);

app.get('/api/init', async (c) => {
  const now = Date.now();
  const day = dayFromPostData(context.postData, now);
  const username = context.username ?? null;
  const [init, avatars] = await Promise.all([
    getInit(redis, day, username, now),
    username ? avatarsFor(redis, snoovatar, [username]) : Promise.resolve({} as Record<string, string>),
  ]);
  return c.json({ ...init, avatar: username ? (avatars[username] ?? null) : null });
});

// ?board=overall|level|day  &level=<permanent level id>  &limit=<rows, up to 50>
app.get('/api/leaderboard', async (c) => {
  const day = dayFromPostData(context.postData, Date.now());
  const level = Number(c.req.query('level'));
  const limit = Number(c.req.query('limit')) || undefined;
  const board = await getLeaderboard(
    redis, day, context.username ?? null, c.req.query('board') ?? 'day', level, limit,
  );
  return c.json(await withAvatars(redis, snoovatar, board));
});

app.post('/api/run', async (c) => {
  const now = Date.now();
  const day = dayFromPostData(context.postData, now);
  const body = await c.req.json<Partial<RunRequest>>().catch(() => ({}) as Partial<RunRequest>);
  const username = context.username ?? null;
  const result = await submitRun(redis, day, username, body.levelId, body.timeMs, now);
  if (username && result.accepted && result.flairOn) {
    try {
      await refreshStreakFlair(redis, flairSink(context.subredditName), username, result.streak.current);
    } catch (error) {
      console.error('streak flair update failed', error);   // the race still counts
    }
  }
  return c.json(result);
});

// Opt-in streak flair. { on: true } shows "🔥 n-day streak"; { on: false } puts
// back the flair the player had before.
app.post('/api/flair', async (c) => {
  const username = context.username ?? null;
  if (!username) {
    return c.json<FlairResponse>({ on: false, text: null, error: 'Log in to Reddit to use flair.' });
  }
  const body = await c.req.json<Partial<FlairRequest>>().catch(() => ({}) as Partial<FlairRequest>);
  try {
    return c.json<FlairResponse>(
      await setStreakFlair(redis, flairSink(context.subredditName), username, body.on === true, Date.now()),
    );
  } catch (error) {
    console.error('streak flair change failed', error);
    const on = (await readPlayer(redis, username)).flairOn;
    return c.json<FlairResponse>({ on, text: null, error: "Couldn't change your flair in this subreddit." });
  }
});

/**
 * Creates the post for `day` unless one already exists. The cron job, the
 * install trigger and the menu action can all race to call this.
 */
async function ensureDailyPost(day: number): Promise<{ id: string; created: boolean }> {
  const existing = await redis.get(dayPostKey(day));
  if (existing) return { id: existing, created: false };

  const post = await reddit.submitCustomPost({
    subredditName: context.subredditName,
    title: postTitle(day),
    entry: 'default',
    postData: { day },
    textFallback: {
      text: `Daily Circuit #${day} (${dateOf(day)}). Seven circuits, one for each day of the week (Monday the easiest): steer the front and rear wheels separately and set your best one-lap time.`,
    },
  });
  await redis.set(dayPostKey(day), post.id);
  return { id: post.id, created: true };
}

app.post('/internal/menu/post-create', async (c) => {
  try {
    const post = await ensureDailyPost(dayOf(Date.now()));
    return c.json<UiResponse>({
      showToast: post.created ? "Posted today's Daily Circuit" : "Today's Daily Circuit is already up",
      navigateTo: `https://reddit.com/r/${context.subredditName}/comments/${post.id.replace(/^t3_/, '')}`,
    });
  } catch (error) {
    console.error('post-create failed', error);
    return c.json<UiResponse>({ showToast: 'Could not create the post' }, 400);
  }
});

app.post('/internal/triggers/on-app-install', async (c) => {
  await ensureDailyPost(dayOf(Date.now()));
  return c.json<TriggerResponse>({});
});

app.post('/internal/scheduler/daily-post', async (c) => {
  await ensureDailyPost(dayOf(Date.now()));
  // A new day can end streaks: keep everyone's streak flair honest.
  try {
    await refreshAllStreakFlairs(redis, flairSink(context.subredditName), Date.now());
  } catch (error) {
    console.error('daily streak flair refresh failed', error);
  }
  return c.json<TaskResponse>({});
});

serve({ fetch: app.fetch, createServer, port: getServerPort() });
