# To do: Reddit Game of the Day hackathon

Deadline: **Tue 8 Dec 2026, 6:00 pm Pacific = Wed 9 Dec, 7:30 am IST.** Judging runs 9–16 Dec.
Judged equally on **Delightful UX, Polish, Reddit-y, Daily Content**. Submit as a **port**
(the earlier browser version) to compete for **Best Ported Daily Game** as well.

Tick items off here as they land; the CHANGELOG has the details.

## 1. Get it running on Reddit (blocker, do first)

- [ ] `cd reddit`, `npx devvit login`, then `npm run dev` (playtest). It creates a private test
      subreddit with a test post and prints its link.
- [ ] Open that post on a phone in the Reddit app: does the 38 MB engine load, how long does it
      take, do the thumb pads work?
- [ ] Check the `.wasm` is accepted: the Devvit docs list "HTML/CSS/JS only" as a requirement
      and say nothing about `.wasm`. If it is refused, we need another plan quickly.
- [ ] Check logged-out play (it should still run, just not rank).
- [ ] Confirm `four-wheel-steer` is free as an app name (3–20 chars, lowercase, hyphens). If it
      is taken, change `name` in `reddit/devvit.json`.

## 2. Daily content

- [ ] **Daily maps: new direction from Nishant (to be specified).** It replaces the current
      "the five levels take turns" rule in `reddit/src/server/daily.ts` (`levelOfDay`).
- [ ] Medal times calibrated from real laps on every level (all are estimates today).

## 3. UX and polish

- [ ] One tap from the post to the race: on Reddit, **Drive** goes straight into today's
      circuit; How to Play moves behind a "?" (the in-race hints already teach the controls).
- [ ] Start screen (the post's splash): add the attribution ("by u/…"), today's level name and
      a small picture of the track.
- [ ] Result card on Reddit: place on today's board ("#12 of 340"), streak, countdown to the
      next circuit, one clear next step.
- [ ] Wording pass (for example the "->" arrows on How to Play).
- [ ] Loading time on phones: if the engine is slow, consider a smaller custom web template.

## 4. Reddit-y features

- [ ] Devvit Journeys events: post viewed, game started, race started, lap, wall hit, game
      over, finish, leaderboard opened. (Read the Journeys docs first.)
- [ ] "Post my time" as a comment on the day's post, or a "join the subreddit" prompt. Check
      what Devvit allows an app to do on the player's behalf.
- [ ] User flair for medals or streak.
- [ ] Reddit avatars on the leaderboard, if the web view's content rules allow loading them.

## 5. Submission (Devpost + Reddit)

- [ ] **Player-facing `README.md` in `reddit/`** (the app root): what the game is and how to
      play. Required by Devpost, and app review rejects missing or template READMEs.
- [ ] `npx devvit upload` (stays private), then note the app link
      `developers.reddit.com/apps/<app-name>`.
- [ ] A **public** subreddit with fewer than 200 members, the app installed
      (`npx devvit install r/<sub>`), and a public demo post. If the subreddit stays private,
      install `developers.reddit.com/apps/dr-admin-approve` so admins can join.
- [ ] Devpost text: features, how to play, and **what changed since 11 Nov** (the project
      existed before): phone layout, thumb pads, Reddit integration, new tracks, three-strike
      rule, leaderboards, visuals. Say it is a port.
- [ ] Demo video under 1 minute (optional but recommended), uploaded publicly to YouTube.
- [ ] Repo link: https://github.com/sainishant-b/4WD (optional field).
- [ ] Developer feedback survey (optional, separate $200 prize).
- [ ] Do **not** `devvit publish` before the hackathon ends; Reddit asked for private uploads.

## Done recently

- [x] Five levels with difficulty rising from Level 3; esses and hairpins on Levels 4–5.
- [x] Three wall hits = game over.
- [x] Phone layout, twin thumb pads, key-cap control hints, mute button on every screen.
- [x] Reddit server: per-level boards, OVERALL board (sum of best times, lowest first), daily
      board, streaks.
