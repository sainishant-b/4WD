# Devpost submission draft: Four Wheel Steer

A draft to paste into Devpost and edit. Lines in *[brackets]* need filling in or checking before
you submit (links, things not yet verified on a phone).

---

## Project name

Four Wheel Steer: Daily Circuit

## Elevator pitch (one line)

A top-down racer where you steer the front and rear wheels separately: pivot through hairpins,
crab sideways past walls, and chase today's fastest time on Reddit.

## Category

Game of the Day. Also entering **Best Ported Daily Game**: this is a port of my earlier
browser game.

## About the project

### What it does

Every day one circuit is featured in a Reddit post. You open the post, see today's track and
your standing, tap **Drive** and race three laps. The twist is the car: the **front and rear
axles steer independently**. Turn them opposite ways and the car pivots on the spot; turn them
the same way and it slides sideways like a crab. Hairpins that would stop a normal car become a
puzzle of when to pivot and when to crab.

- **Daily content:** one featured circuit a day (five circuits rotate), a new post at 00:00 UTC
  created by the app's own scheduler, and older posts stay playable on their own day.
- **Reddit-native competition:** players are their Reddit accounts. After a finish the results
  card shows your place on today's board ("#12 of 340 today"), a new-best chip, your streak and
  a countdown to the next circuit. The leaderboard has TODAY, OVERALL (best times on all five
  circuits added up, lowest total first) and a board per circuit.
- **Three strikes:** the third wall hit ends the race, so every corner matters.
- **Made for phones:** a portrait layout and two thumb pads (left pad = front wheels, right pad
  = rear wheels; push up to drive, both up to boost, pull down to drift or brake). Keyboard on
  desktop.
- **Instant post:** the post itself is a tiny HTML page (today's track drawn as a picture, your
  best, rank and streak); the game engine only downloads when you tap Drive.

### How to play

1. Tap **Drive** on today's post, then **DRIVE** on Today's Circuit.
2. Race 3 laps through the gates; the gold arrow points to the next one.
3. Steer front and rear opposite ways to pivot, the same way to slide sideways.
4. Don't hit the walls three times. Finish to see your place today and your streak.

### How I built it

- **Game:** Godot 4 (GL Compatibility renderer), all UI built in code on a small design system.
  The handling is a slip-angle bicycle model with two steered axles, ported from my earlier
  JavaScript version, plus a traction assist so the car goes where its wheels point.
- **Tracks:** each circuit is a list of waypoints turned into a road by a centripetal
  Catmull-Rom spline that is resampled and relaxed so the road edge can never fold over itself.
- **Reddit:** a Devvit Web app. The Godot Web export runs in the expanded post view. Reddit's
  content-security policy blocks the inline script in Godot's default page, so the app ships its
  own loader and talks to the game through `JavaScriptBridge.get_interface` (never `eval`).
  A Hono server on Devvit keeps the boards and streaks in Devvit redis.
- **Testing:** headless Godot tests for the track geometry, the three-strike rule, the
  multi-touch thumb pads and the Reddit leaderboard path; unit tests for the server's daily
  rules; a lap bot used to tune the handling (wall hits fell from 26 to 9 across the five
  circuits after the grip change).

### Challenges

- Running a 38 MB WebAssembly game engine inside a Reddit post under a strict CSP.
- Two-thumb controls for two steering axles: Godot's own controls follow one pointer, so the
  pads read raw multi-touch events.
- Making hairpins drivable: the track builder had to guarantee the road never folds.

### What I learned

*[your words]*

### What's next

*[e.g. user flair for streaks, posting your time as a comment, new circuits]*

## What changed since 11 Nov 2026 (the project existed before the hackathon)

Before the hackathon this was a desktop Godot game ported from my browser prototype, with
levels, medals, an Appwrite leaderboard and a hidden multiplayer mode. New for the hackathon:

- **Reddit integration (Devvit Web):** the post splash, the CSP-safe engine loader, the game ↔
  server bridge, the daily post scheduler and menu action, and the server's boards and streaks.
- **One circuit a day:** Today's Circuit screen with a map of the track, a TODAY board, and the
  results card with place, streak and countdown.
- **Phones:** portrait layouts for every screen and the twin thumb-pad controls.
- **Tracks:** a new track builder (smooth edges that cannot fold), five redesigned circuits with
  rising difficulty and hairpins, and the obstacle levels removed.
- **Rules:** three wall hits end the race; every race is three laps.
- **Look and feel:** glass HUD panels, a mini map, a radial speedometer, key-cap control hints,
  a picture-only How to Play, a mute button on every screen, shaded menus, and more grip so the
  car stops drifting into walls.

## Built with

Godot 4, GDScript, Devvit Web, TypeScript, Hono, Devvit redis, esbuild

## Links

- App: *[developers.reddit.com/apps/fourwd, after `npm run upload`]*
- Demo post: *[link to the post in your public test subreddit]*
- Code: https://github.com/sainishant-b/4WD
- Video: *[YouTube link, under 1 minute]*

## Before submitting, check

- *[Played on a phone in the Reddit app: the engine loads and the pads work.]*
- *[Logged-out play works.]*
- *[The subreddit is public with fewer than 200 members, or dr-admin-approve is installed.]*
- *[Not published with `devvit publish`.]*
