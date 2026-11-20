# To do: Reddit Game of the Day hackathon

Deadline: **Tue 8 Dec 2026, 6:00 pm Pacific = Wed 9 Dec, 7:30 am IST.** Judging runs 9–16 Dec.
Judged equally on **Delightful UX, Polish, Reddit-y, Daily Content**. Submit as a **port**
(the earlier browser version) to compete for **Best Ported Daily Game** as well.

Tick items off here as they land; the CHANGELOG has the details.

## 1. Get it running on Reddit (blocker, do first)

- [x] `cd reddit`, `npx devvit login`, then `npm run dev` (playtest). It runs on Reddit (2026-11-20).
- [ ] Open that post on a phone in the Reddit app: does the engine load (9.7 MB gzipped, cached
      after the first play), how long does it take, do the thumb pads work?
- [x] Check the `.wasm` is accepted: the playtest runs the engine on Reddit (2026-11-20).
      Re-check after `npm run upload` in case review treats it differently.
- [ ] Check logged-out play (it should still run, just not rank).
- [x] Register the app as **`fourwd`** (`npx devvit init --force` in `reddit/`), then playtest.
- [x] First playtest fixes (2026-11-20): less drift, Today's Circuit screen (one map + diagram),
      picture-only How to Play, thumb pads in the browser's mobile view.
- [ ] Re-test on Reddit after `npm run export:godot`: does the car feel planted enough now?

## 2. Daily content

- [x] **Daily maps** (2026-11-20, the user's direction): seven maps, one per weekday, Monday the
      easiest; every map ~50% longer with new corners; ranked races are one lap; a casual mode
      plays any map for three laps with no wall-hit limit.
- [ ] Medal times calibrated from real laps on every level (one-lap targets come from a bot).

## 3. UX and polish

- [x] One tap from the post to the race: on Reddit the game opens on Today's Circuit (DRIVE
      is one tap); How to Play sits behind its "?" button and is never forced there.
- [x] Start screen (the post's splash): today's level name and a picture of the track (from
      the game's own shapes, `src/client/tracks.ts`). Fits a 512 px post.
- [x] Attribution on the splash: "by u/donomadoit" under the title.
- [x] Result card on Reddit: place on today's board ("#12 of 340"), streak, countdown to the
      next circuit, one clear next step (Leaderboard -> the new TODAY board). 2026-11-20.
- [x] Wording pass on How to Play: now pictures and key caps, no sentences.
- [x] Loading time: the engine downloads gzipped (38 MB -> 9.7 MB) and is cached for return
      visits (`reddit/src/client/engine-files.ts`). 2026-11-20.
- [ ] If phones are still slow: a custom Godot web template (3D and unused modules off) could
      roughly halve the engine. Needs emsdk + scons and a source build.

## 4. Reddit-y features

- [ ] **Blocked:** Devvit Journeys events. The protocol exists, but no SDK release (0.15.3,
      0.15.4) exposes it to apps yet, and it refuses playtest versions and apps Reddit has not
      allowlisted. Revisit if a newer `@devvit/web` adds it.
- [ ] "Post my time" as a comment on the day's post, or a "join the subreddit" prompt.
      Possible: `reddit.submitComment` (as the app, or as the user with
      `permissions.reddit.scope: "user"`) and `subscribeToCurrentSubreddit` (asUser
      `SUBSCRIBE_TO_SUBREDDIT`). Needs Nishant's call: opt-in button, and as whom.
- [x] Streak flair, opt-in from the results card ("🔥 4-day streak"); the player's own flair
      comes back when they turn it off. 2026-11-20.
- [ ] Check streak flair on real Reddit: the subreddit may need user flair enabled
      (mod tools > User flair), and the app account must be allowed to set it.
- [x] Reddit avatars on the leaderboard (2026-11-20): snoovatars on every row, initials for
      players without one.
- [ ] Check avatars on real Reddit: if the web view refuses `i.redd.it`, rows show initials.
      Then the server would have to fetch the pictures (`permissions.http.domains`, reviewed).

## 5. Submission (Devpost + Reddit)

- [x] **Player-facing `README.md` in `reddit/`** (the app root): what the game is, how to
      play, controls, daily rules, boards; developer notes below. 2026-11-20.
- [ ] `npx devvit upload` (stays private), then note the app link
      `developers.reddit.com/apps/<app-name>`.
- [ ] A **public** subreddit with fewer than 200 members, the app installed
      (`npx devvit install r/<sub>`), and a public demo post. If the subreddit stays private,
      install `developers.reddit.com/apps/dr-admin-approve` so admins can join.
- [ ] Devpost text: **drafted in `docs/DEVPOST.md`** (features, how to play, how it was
      built, what changed since 11 Nov, port note). Fill in the links, "What I learned", and the
      checks at the bottom, then paste it into Devpost.
- [ ] Demo video under 1 minute (optional but recommended), uploaded publicly to YouTube.
- [ ] Repo link: https://github.com/sainishant-b/4WD (optional field).
- [ ] Developer feedback survey (optional, separate $200 prize).
- [ ] Do **not** `devvit publish` before the hackathon ends; Reddit asked for private uploads.

## Done recently

- [x] Seven levels (one per weekday) with difficulty rising from Level 3; hairpins and
      switchbacks on Levels 4–7.
- [x] Three wall hits = game over.
- [x] Phone layout, twin thumb pads, key-cap control hints, mute button on every screen.
- [x] Reddit server: per-level boards, OVERALL board (sum of best times, lowest first), daily
      board, streaks.
- [x] Handling: grip up and a traction pull, so the car stops drifting into walls.
