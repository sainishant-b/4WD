# Four Wheel Steer — Daily Circuit

A top-down time-trial racer for Reddit where the **front and rear wheels steer independently**:
turn them opposite ways for a tight pivot, the same way to crab sideways. Every UTC day there is one
circuit, one leaderboard, and a streak for showing up.

This folder is the [Devvit Web](https://developers.reddit.com/docs/capabilities/devvit-web/devvit_web_overview)
app. The game itself is the Godot 4 project in the parent folder; its Web export is copied into
`public/` and booted by a loader that satisfies Reddit's content-security policy.

## How a post works

1. The post renders `public/splash.html` inline: circuit number, your best time, rank and streak.
2. **Drive** opens `public/game.html` in expanded mode, which downloads and starts the Godot engine.
3. The page exposes `window.FWS` to the game: `init` holds the day's data, and
   `request('POST', '/api/run', …)` reports a finished race. **The Godot side does not call it yet**;
   the game still boots into its normal menu.

## Commands

```bash
npm install
npm run export:godot   # export the Godot project (parent folder) into public/
npm run build          # bundle src/client -> public/, src/server -> dist/server/
npm test               # unit tests for the daily rules
npm run local          # local preview with a strict CSP and an in-memory API
npm run dev            # devvit playtest on your test subreddit
npm run upload         # build + devvit upload (private; do not publish during the hackathon)
```

`npm run export:godot` finds a Godot 4 editor in `~/Downloads`; set `GODOT=<path>` to use another.

## Layout

| Path | What it is |
| --- | --- |
| `devvit.json` | App config: post entrypoints, server, permissions, menu item, daily cron |
| `public/` | Everything uploaded to the web view. Hand-written: `splash.html`, `game.html`, `styles/`, `fonts/`. Generated: `splash.js`, `game.js`, `godot-config.js`, `index.*` |
| `src/client/` | Web view scripts (`splash.ts`, `game.ts`) |
| `src/server/` | `daily.ts` (rules, no Devvit imports), `index.ts` (Hono routes), tests |
| `src/shared/api.ts` | Request/response types shared by both sides |
| `tools/` | `export-godot.mjs`, `build.mjs`, `serve-local.ts` |

## Server API

| Route | Purpose |
| --- | --- |
| `GET /api/init` | Day number, seed, date, your best/rank/streak, top 10 |
| `POST /api/run` `{ timeMs }` | Record a finished race; returns the updated board and streak |
| `GET /api/leaderboard` | Top 10 and your row |
| `POST /internal/scheduler/daily-post` | 00:00 UTC cron: create the day's post |
| `POST /internal/menu/post-create` | Moderator menu: create (or jump to) today's post |
| `POST /internal/triggers/on-app-install` | Create today's post when the app is installed |

A post stores its day in `postData`, so older posts stay playable on their own circuit and board.
Only a finish on the current UTC day extends a streak.

## Data

Stored in Devvit redis, per subreddit install: each day's best times keyed by Reddit username, and
each player's streak. Keys expire 90 days after their last write. Nothing is sent off Reddit.

## Fonts

Chakra Petch and Barlow, SIL Open Font License (`public/fonts/*-OFL.txt`).
