// Local stand-in for Reddit's web view host, for checking the pages and the
// Godot build without uploading:
//
//   node tools/serve-local.ts        then open http://localhost:5180/splash.html
//
// It serves public/ under a strict Content-Security-Policy (no inline script
// or style, same-origin only) and answers /api/* with the real rules from
// src/server/daily.ts over an in-memory store. The policy is an approximation
// of Reddit's, so a clean run here is necessary, not sufficient.

import { createReadStream, existsSync, statSync } from 'node:fs';
import { createServer } from 'node:http';
import { extname, join, normalize } from 'node:path';
import { fileURLToPath } from 'node:url';
import { LEVEL_IDS, dayOf, getInit, getLeaderboard, levelOfDay, submitRun } from '../src/server/daily.ts';
import { type Flair, type FlairSink, refreshStreakFlair, setStreakFlair } from '../src/server/flair.ts';
import { MemoryStore } from '../src/server/memory-store.ts';

const publicDir = fileURLToPath(new URL('../public', import.meta.url));
const port = Number(process.env.PORT ?? 5180);
/** The pretend logged-in user. Set FWS_USER= (empty) to test logged out. */
const username = process.env.FWS_USER === undefined ? 'local_driver' : process.env.FWS_USER || null;

const CSP = [
  "default-src 'self'",
  "script-src 'self' 'wasm-unsafe-eval'",
  "style-src 'self'",
  "img-src 'self' data: blob:",
  "font-src 'self'",
  "connect-src 'self'",
  "worker-src 'self' blob:",
  "media-src 'self' blob:",
].join('; ');

const MIME: Record<string, string> = {
  '.html': 'text/html; charset=utf-8',
  '.js': 'text/javascript; charset=utf-8',
  '.css': 'text/css; charset=utf-8',
  '.json': 'application/json; charset=utf-8',
  '.wasm': 'application/wasm',
  // As Devvit's uploader labels it: a plain file, no Content-Encoding (game.ts unzips it).
  '.gz': 'application/gzip',
  '.pck': 'application/octet-stream',
  '.ttf': 'font/ttf',
  '.png': 'image/png',
  '.svg': 'image/svg+xml',
};

const store = new MemoryStore();

/** Pretend user flair: kept in memory and printed, since there is no subreddit here. */
const localFlairs = new Map<string, Flair>();
const localFlair: FlairSink = {
  async read(name) {
    return localFlairs.get(name);
  },
  async show(name, text) {
    localFlairs.set(name, { text });
    console.log(`flair u/${name}: ${text}`);
  },
  async restore(name, flair) {
    if (flair) localFlairs.set(name, flair);
    else localFlairs.delete(name);
    console.log(`flair u/${name}: ${flair ? flair.text : '(none)'}`);
  },
};

// A few rivals so the boards are not empty on first load. Two of them have a
// time on every level (so they rank overall); the third is one level short.
const now0 = Date.now();
const today = dayOf(now0);
const rivals: [string, number, number][] = [
  ['apex_hunter', 58_420, LEVEL_IDS.length],
  ['crabwalk', 61_930, LEVEL_IDS.length],
  ['late_braker', 66_105, LEVEL_IDS.length - 1],
];
for (const [name, base, levels] of rivals) {
  for (const [i, levelId] of LEVEL_IDS.slice(0, levels).entries()) {
    const day = levelId === levelOfDay(today) ? today : today - 400;   // an old day: no day board entry
    await submitRun(store, day, name, levelId, base + i * 4_870, now0);
  }
}

async function readBody(request: import('node:http').IncomingMessage): Promise<unknown> {
  const chunks: Buffer[] = [];
  for await (const chunk of request) chunks.push(chunk as Buffer);
  try {
    return JSON.parse(Buffer.concat(chunks).toString('utf8') || '{}');
  } catch {
    return {};
  }
}

async function api(
  path: string,
  query: URLSearchParams,
  request: import('node:http').IncomingMessage,
): Promise<unknown> {
  const now = Date.now();
  const day = dayOf(now);
  if (path === '/api/init' && request.method === 'GET') return getInit(store, day, username, now);
  if (path === '/api/leaderboard' && request.method === 'GET') {
    return getLeaderboard(
      store, day, username, query.get('board') ?? 'day', Number(query.get('level')),
      Number(query.get('limit')) || undefined,
    );
  }
  if (path === '/api/run' && request.method === 'POST') {
    const body = (await readBody(request)) as { levelId?: unknown; timeMs?: unknown };
    const result = await submitRun(store, day, username, body.levelId, body.timeMs, now);
    if (username && result.accepted && result.flairOn) {
      await refreshStreakFlair(store, localFlair, username, result.streak.current);
    }
    return result;
  }
  if (path === '/api/flair' && request.method === 'POST') {
    if (!username) return { on: false, text: null, error: 'Log in to Reddit to use flair.' };
    const body = (await readBody(request)) as { on?: unknown };
    return setStreakFlair(store, localFlair, username, body.on === true, now);
  }
  return undefined;
}

createServer(async (request, response) => {
  const url = new URL(request.url ?? '/', 'http://localhost');
  const path = url.pathname;
  response.setHeader('Content-Security-Policy', CSP);
  response.setHeader('Cache-Control', 'no-store');

  if (path.startsWith('/api/')) {
    const result = await api(path, url.searchParams, request);
    response.writeHead(result === undefined ? 404 : 200, { 'Content-Type': MIME['.json'] });
    response.end(JSON.stringify(result ?? { error: 'not found' }));
    return;
  }

  const file = normalize(join(publicDir, path === '/' ? 'splash.html' : decodeURIComponent(path)));
  if (!file.startsWith(publicDir) || !existsSync(file) || !statSync(file).isFile()) {
    response.writeHead(404, { 'Content-Type': 'text/plain' });
    response.end('not found');
    return;
  }
  response.writeHead(200, {
    'Content-Type': MIME[extname(file)] ?? 'application/octet-stream',
    'Content-Length': statSync(file).size,
  });
  createReadStream(file).pipe(response);
}).listen(port, () => {
  console.log(`http://localhost:${port}/splash.html  (user: ${username ?? 'logged out'})`);
});
