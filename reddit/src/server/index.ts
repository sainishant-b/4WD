// Devvit server for Four Wheel Steer.
//
//   /api/*       called by the web view (splash page and the Godot game)
//   /internal/*  called by Reddit: menu action, install trigger, daily cron
//
// The rules live in daily.ts; this file only wires them to Devvit.

import { serve } from '@hono/node-server';
import { context, createServer, getServerPort, reddit, redis } from '@devvit/web/server';
import type { TaskResponse } from '@devvit/web/server';
import type { TriggerResponse, UiResponse } from '@devvit/web/shared';
import { Hono } from 'hono';
import type { RunRequest } from '../shared/api.ts';
import {
  dateOf,
  dayFromPostData,
  dayOf,
  dayPostKey,
  getInit,
  getLeaderboard,
  postTitle,
  submitRun,
} from './daily.ts';

const app = new Hono();

app.get('/api/init', async (c) => {
  const now = Date.now();
  const day = dayFromPostData(context.postData, now);
  return c.json(await getInit(redis, day, context.username ?? null, now));
});

// ?board=overall|level|day  &level=<permanent level id>  &limit=<rows, up to 50>
app.get('/api/leaderboard', async (c) => {
  const day = dayFromPostData(context.postData, Date.now());
  const level = Number(c.req.query('level'));
  const limit = Number(c.req.query('limit')) || undefined;
  return c.json(
    await getLeaderboard(redis, day, context.username ?? null, c.req.query('board') ?? 'day', level, limit),
  );
});

app.post('/api/run', async (c) => {
  const now = Date.now();
  const day = dayFromPostData(context.postData, now);
  const body = await c.req.json<Partial<RunRequest>>().catch(() => ({}) as Partial<RunRequest>);
  return c.json(
    await submitRun(redis, day, context.username ?? null, body.levelId, body.timeMs, now),
  );
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
      text: `Daily Circuit #${day} (${dateOf(day)}). Five circuits, one featured each day: steer the front and rear wheels separately and set your best time.`,
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
  return c.json<TaskResponse>({});
});

serve({ fetch: app.fetch, createServer, port: getServerPort() });
