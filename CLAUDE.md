# FourWheelSteer — project guide for Claude

A Godot 4 (2D, top-down) car game where the player steers the **front and rear wheels
independently** (crab-walk when axles are aligned, tight pivot when opposed). Checkpoint
**time trial** with a three-wall-hits fail state, and it must run on **desktop and Android**.

Physics are a port of the user's earlier browser version in `../game`
(`CAR_PHYSICS_DOCUMENTATION.md`, `src/systems/physics.js`) — that folder is **read-only
reference; never modify it**.

## Documentation process (REQUIRED — follow on every session)

**After every major change, update the documentation before considering the task done.**

A change is **major** if it does any of:
- adds/removes/renames a scene or script,
- changes gameplay, physics, or controls (e.g. steering model, camera, win condition),
- changes project/config/export settings or how the game is run or built,
- changes the public API/behavior another script relies on.

When a change is major, in the same turn:
1. **`docs/CHANGELOG.md`** — add a dated entry: *what* changed and *why* (newest on top).
2. **`README.md`** — update if controls, how-to-run, or build steps changed.
3. **Doc-comments** — keep the `##` header comment on any script you touched accurate.
4. **`CLAUDE.md`** (this file) — update if a convention or project fact changed.

Trivial changes (typos, comment tweaks, tiny constant nudges) do **not** need a changelog
entry. When in doubt, add one — short is fine.

## Layout

- **Autoloads**: `Game` (`scripts/game_data.gd`) — level table, progress/save, medals, volume,
  scene navigation; `InputState` (`scripts/input_state.gd`) — merges keyboard + touch;
  `Palette` (`ui/Palette.gd`) — design-system color tokens for procedural drawing; `Layout`
  (`scripts/layout.gd`) — picks the logical canvas from the window's shape (landscape 1280x720,
  portrait 430x760) and exposes `portrait` / `touch` + a `changed` signal; `Net`
  (`scripts/net.gd`) — ENet host/join (the **dormant/hidden** multiplayer; `is_multiplayer`
  false = plain single-player); `Reddit` (`scripts/reddit.gd`) — the link to the Devvit server
  when running inside a Reddit post (`is_available()` false elsewhere); `Leaderboard`
  (`scripts/leaderboard.gd`) — the online leaderboard: the Reddit server when `Reddit` is there
  (per-level boards + OVERALL), else Appwrite (per level; no-op until its IDs are filled);
  `MuteButton` (`scripts/mute_button.gd`) — the speaker button in the top-right corner of every
  screen. **Keep that corner free** on every screen (`MuteButton.RESERVED_*`).
- `ui/` — the **design system**: `four_wheel_steer_theme.tres` (the project-wide GUI theme, set
  in `project.godot` `[gui] theme/custom`), `Palette.gd` (color tokens, autoloaded),
  `hud_style.gd` (`HudStyle`, static helpers: raised `panel()` / sunk `inset()` / `chip()`
  styles, the tilted `tag()`, line icons via `icon()` (SVG path data), glow/vignette textures,
  label styles incl. `style_sticker()`, the menus' striped `add_backdrop()`, `add_chequer()`,
  and `feather()` edge smoothing), and
  `fonts/` (Chakra Petch = default display face; Barlow = body, via the `LabelBody` variation).
  The reference kit lives in `Four Wheel Steer — Design System/` (marked `.gdignore` so Godot
  skips it; `res://ui/` holds the installed, compiled copies).
- `scenes/` — `MainMenu`, `Instructions` (first-launch how-to-play), `LevelSelect`, `Leaderboard`
  (online ranked times), `Lobby` (the hidden multiplayer host/join), `Main` (the race: deep-cobalt field
  + a generated green `Track` + gates + `Obstacles` + Car + HUD + touch), `Car`, `Checkpoint`,
  `Cone`/`Ramp` (obstacles), `HUD`, `TouchControls`.
  **Main scene = `MainMenu.tscn`** (redirects to `Instructions` on first run).
- `scripts/` — `car.gd` (physics; emits `wall_touched` once per new wall contact; also the unused
  `hit_cone()` + `jump()`/airborne hop), `game.gd` (race controller: countdown, lap logic,
  splits/delta, wall-hit count + game over, finish, pause), `leaderboard.gd` (`Leaderboard`
  autoload: Appwrite client), `leaderboard_ui.gd` (leaderboard screen), `avatar_badge.gd`
  (`AvatarBadge`: a player's round avatar or initial on board rows), `net.gd` (`Net` autoload:
  hidden multiplayer), `lobby.gd` (hidden host/join UI), `track_builder.gd` (waypoints → smooth
  centre line → road ribbon mesh/walls/gates, plus optional obstacles), `cone.gd`/`ramp.gd`
  (obstacles; unused since no level has any), `hud.gd` (HUD + results/game over/pause),
  `minimap.gd` (HUD mini map `_draw()`), `track_diagram.gd` (`TrackDiagram`: a whole circuit
  drawn for menus, used by Reddit's Today's Circuit screen),
  `speedometer.gd` (radial speed gauge `_draw()`), `checkpoint.gd`, `main_menu.gd`, `instructions.gd`,
  `level_select.gd` (on Reddit: Today's Circuit, the one daily level; elsewhere the level grid),
  `engine_audio.gd`, `touch_controls.gd` (multi-touch twin thumb pads; a real mouse works too),
  `layout.gd` (`Layout` autoload).
- `tests/` — `.gdignore`d (never exported). `touch_test.gd` feeds real multi-touch events into the
  race scene headlessly: `godot --headless --fixed-fps 60 --path . -s tests/touch_test.gd`. Run it
  after touching `touch_controls.gd`, `input_state.gd`, `layout.gd` or the HUD. `track_test.gd`
  checks every track's geometry (no folded edges, no over-tight bends, the road clear of itself,
  gates/start on the road): `godot --headless --path . -s tests/track_test.gd`. Run it after
  touching `track_builder.gd` or any `TRACK_n`. `rules_test.gd` checks the level table and the
  three-wall-hits rule by driving the real car into walls:
  `godot --headless --fixed-fps 60 --path . -s tests/rules_test.gd`. Run it after touching
  `game.gd`, the wall-contact code in `car.gd`, or `LEVELS`. `capture_screens.gd` regenerates
  `docs/screenshots/`; it needs a real window, so launch it only through `run_offscreen.ps1`
  (its own invisible desktop). Never start a capture window on the user's desktop, hidden or
  not: it takes keyboard focus and swallows their typing.
- `audio/` — SFX generated by `tools/generate_sfx.py`. `tools/preview_track.py` renders the track
  shape to a PNG (no editor needed).
- `reddit/` — the **Devvit Web** app for Reddit's "Game of the Day" hackathon (deadline
  2026-12-09 07:30 IST). `.gdignore`d. It ships the **Web export** of this project inside a Reddit
  post: `public/` (splash + game pages, generated engine files), `src/client` (web view TS),
  `src/server` (Hono: daily seed / leaderboard / streak on Devvit redis), `src/shared` (API types),
  `tools/` (`export-godot.mjs`, `build.mjs`, `serve-local.ts`). Reddit's CSP forbids inline
  script/style, so never ship Godot's stock `index.html`, and never call `JavaScriptBridge.eval`;
  talk to the page through `JavaScriptBridge.get_interface("FWS")`. After changing the Godot
  project, re-run `npm run export:godot` in `reddit/`. See README "Run it on Reddit".
  The engine ships as `index.wasm.gz`, unzipped and cached in the browser by
  `src/client/engine-files.ts`; keep the plain `index.wasm` too (the fallback).
- `docs/CHANGELOG.md` — running history of changes. `docs/TODO.md` — the hackathon to-do list
  (tick items off as they land; the user's own direction for the daily maps is still to come).
  `docs/DEVPOST.md` — the draft submission text. `reddit/README.md` — player-facing first.
- **Git**: tracked at https://github.com/sainishant-b/4WD (public, branch `main`). Old exported
  builds in the root (`Four Wheel Steer.*`), `.godot/`, `.claude/`, `node_modules` and the
  generated web build in `reddit/public` are git-ignored; commit source, docs and tests only.
- Flow: `MainMenu → LevelSelect → Main (race) → Results`. Each race is a circuit built from the
  level's own `track` (`game_data.gd` `TRACK_1`..`TRACK_7`). **7 levels, one per weekday**
  (the user's design, 2026-11-20): L1 Monday (easiest, flowing) ... L7 Sunday (hardest); L4-7
  are hairpin/switchback circuits. Laps are ~7-12k px (grown ~50% that day; keep new maps in
  that range). **Two modes** (the user's design): **ranked** = ONE lap + three strikes, the only
  times that get medals, unlock levels and go to any leaderboard; **casual** (`Game.casual`,
  `Game.goto_casual()`) = THREE laps, every map open, no wall-hit limit, just the time, kept as
  `casual_best` in `save.json`, never online (no casual board: the user chose that). The user removed the
  obstacle levels and all ramps/walls from the maps on 2026-11-17; **don't add obstacles back
  without asking**. The obstacle code is dormant: a track dict may still carry
  `"obstacles": [{type:"cone"|"wall"|"ramp", t, offset, …}]`, which `track_builder.gd` would build
  under `Main`'s `Obstacles` node. Medal targets are rough.
- **Three strikes** (the user's rule): each new wall touch in a race is counted; touches 1-2 warn,
  touch 3 (`game.gd` `MAX_WALL_TOUCHES`) is GAME OVER with nothing saved. `car.gd` merges a scrape
  or bounce into one touch. Single-player only.
- **Reddit = one circuit a day** (the user asked): inside a Reddit post the level screen shows
  only today's level (`Game.daily_index()`, from `Reddit.daily_level_id`) with its diagram and
  DRIVE (ranked), and `Game.has_next_level()` is false; its CASUAL button opens the casual grid
  (all maps, Next works). The ranked level progression is for desktop/Android. The day's level
  follows the UTC weekday (`levelOfDay` in `reddit/src/server/daily.ts`; day 1 was a Monday).
  Its day/overall board keys carry `1lap:` so the old 3-lap times never mix in.
  The game opens straight on Today's Circuit there (`main_menu.gd`, once per load via
  `Reddit.start_handled`); How to Play is behind its button, never forced. The post's splash
  draws today's track from `reddit/src/client/tracks.ts`, generated from the game by
  `reddit/tools/track-shapes.gd` (run by `npm run export:godot`); never edit it by hand.
- **Levels have permanent ids** (`LEVELS[i]["id"]`, `Game.level_id()`): `save.json` records and the
  leaderboard are keyed by id, not slot, so reordering levels never moves a time to another track.
  A new track takes the next unused id; never renumber. A reshaped track gets a new id too (the
  2026-11-20 maps are 10-16; 0-9 are retired). A level is unlocked when the level before
  it has a best time (`Game.is_unlocked`); nothing else is stored. Progress (best time + best lap
  + medal per id) saves to `user://save.json`. Mobile **portrait**, desktop **maximized**.
- **Online leaderboard** (the way to compete now): `MainMenu → Leaderboard`. Finishing a race
  (`game.gd` `_finish`, single-player) calls `Leaderboard.submit_score(name, level_id, time_ms)`;
  the screen shows ranked times via `Leaderboard.fetch_top(level_id | Leaderboard.OVERALL)`.
  On Reddit the server ranks OVERALL = the sum of each player's bests on ALL levels, lowest first
  (the user's spec), plus a board per level and a daily board for the featured level
  (`levelOfDay` in `reddit/src/server/daily.ts`; its `LEVEL_IDS` must match `LEVELS[i].id`).
  The screen's Reddit tabs are OVERALL (keep it first), TODAY (`Leaderboard.DAY`), then levels.
  On Reddit the results card waits for `Leaderboard.run_recorded` and shows the day rank, streak
  and a countdown (`nextCircuitInMs` from the server); its gold button is Leaderboard -> TODAY.
  **Streak flair is opt-in only** (`reddit/src/server/flair.ts`, the card's toggle): never set a
  player's flair without their tap, and always put their own flair back when it goes off.
  **Avatars**: board rows carry the player's snoovatar URL (`reddit/src/server/avatars.ts`,
  cached a day; Reddit-hosted https only). The page crops it to a 96 px PNG for Godot
  (`FWS.avatar`, `src/client/avatar-image.ts`); a test script must not name `AvatarBadge`
  (it uses the `Reddit` autoload, unknown at a `-s` script's compile time).
  Elsewhere the backend is **Appwrite** (IDs pasted into `leaderboard.gd`; name in `save.json`).
- **Difficulty rises across levels** (the user asked): Levels 1-2 stay as they are; from Level 3
  on each level has a narrower road and a higher top speed than the one before. Keep that
  ordering when tuning or adding levels.
- **Multiplayer is HIDDEN/dormant** (no menu entry). The code still works if revived: `Lobby` →
  `Net.host/join` → `Main` with `Game.active_race()` racing the wide `TRACK_MP`, the server dealing
  one `CharacterBody2D`-per-peer (each with a `MultiplayerSynchronizer`; layer-1 collision = bumping),
  and `car.gd` simulating only the authority's car. Port `24565`; playit.gg tunnel for internet.

## Controls

Desktop: **W/S** drive · **A/D** front wheels · **←/→** rear wheels · **Shift/C** boost · **Space** handbrake · **Esc/P** pause · **H** hide/show the race HUD's controls legend (saved).
Wide keyboard HUD: mini map bottom-left, legend bottom-right; touch layouts keep them up top
(the bottom corners are the pads'). The Reddit loading screen draws the same legend in HTML
(`reddit/src/client/game.ts`); keep it in step with `KEYBOARD_LEGEND` / `TOUCH_LEGEND`.
The in-race controls strip and the How to Play legend both come from `HudStyle.controls_legend()`
(`KEYBOARD_LEGEND` / `TOUCH_LEGEND`); change the controls there too.
Touch (phones, incl. the Reddit web view): two thumb pads — **left** = front wheels, **right** =
rear wheels (slide left/right) · either pad **up** = accelerate · **both up** = boost · **one
down** = handbrake/drift · **both down** = brake/reverse · **II** button = pause. This scheme is
the user's own design; don't change the gestures without asking.

## Conventions

- Godot 4.x, GDScript with tabs for indentation; type hints where practical.
- Car convention: `rotation = 0` points **up**; forward = `Vector2.from_angle(rotation - PI/2)`.
- **A tyre touching the white limit line is a wall hit** (the user asked): the car's collision
  box (`Car.tscn`, 42 x 63) covers the drawn tyres, and the limit line sits wholly outside the
  road so its inner edge is the wall. Keep the box matched to the car's drawing.
- **Keep the car planted** (the user found it drifted into walls): `car.gd` `traction` pulls the
  sideways slide toward the wheels' no-slip motion; grip 800, rear stiffer than front. Don't
  loosen these without asking. The handbrake is the drift button.
- **Touch mode** (`Layout.touch`, shows the pads): phones always; elsewhere a touchscreen browser
  at start, any touch, or a real-mouse click in a portrait window turns it on, a key press turns
  it off. Ignore mouse events with `device == InputEvent.DEVICE_ID_EMULATION` (copied from
  touches) anywhere a mouse is handled, or a touch counts twice.
- Tunable feel lives in `@export` vars on the Car node (mirrors the original physics constants).
- **Track waypoints are a guide, not the exact road.** `TrackBuilder.centerline()` splines them
  (centripetal Catmull-Rom), resamples to 10 px, and relaxes any bend tighter than half the road
  width + `BEND_MARGIN`, so an edge can never fold over itself. Anything placed on the track
  (gates, obstacles, the start slot, the mini map) must use that centre line, not the raw
  waypoints. `tools/preview_track.py` mirrors the math; keep the two in step.
- **Every screen must work in both layouts.** Menu screens build their UI in `_build()` and
  rebuild on `Layout.changed` (`Layout.clear(self)` then `_build()`); the HUD creates nodes once
  and re-places them in `_layout()`. Branch on `Layout.portrait` for sizes and on `Layout.touch`
  for wording/controls. A portrait screen is at least 430x760 logical px
  (`Layout.PORTRAIT_CONTENT_WIDTH` = 398 is the safe content width). Godot's stock Controls follow
  one pointer only, so anything needing two fingers must read `InputEventScreenTouch`/`Drag`.
- **Styling = design system, theme "Cobalt & Sun"** (the user's pick, 2026-11-20): striped cobalt
  backdrop, cream cards, sun-gold primary, red-orange `POP`, and a deep navy `INK` outline + hard
  lip on every raised thing. UI is built in code; don't hardcode colors. Pull procedural colors
  from `Palette.*` and let the project theme style Controls. `Palette.TEXT` is dark ink for text
  on cream; text straight on the backdrop or the track uses `TEXT_LIGHT`/`TEXT_LIGHT_MUTED`. For
  button intent use `theme_type_variation`: `""`/gold = primary, `ButtonSecondary` = red-orange,
  `ButtonGhost` = cream, `ButtonDanger` = red. Dialogs use the scrim + centered `PanelContainer`
  (`PanelModal`) pattern; gold or medal-coloured words on cream use `HudStyle.style_sticker()`.
- **Instructions are bold and visual** (the user asked twice): How to Play is pictures + key caps
  / pad icons + one or two words each, no sentences. Controls are shown as key caps / pad icons
  in the display face (`HudStyle.cap()`, `controls_legend()`), not as a sentence. Body copy (`LabelBody`) uses the emboldened Barlow
  from the theme; don't set thin body text on the dark background.
- **In-race HUD = raised cream panels.** Readouts go on `HudStyle.panel()` panels with
  `HudStyle.style_panel_label` (no outline); text straight over the track uses
  `style_floating_label` (white, INK halo). Menu screens start their `_build()` with
  `HudStyle.add_backdrop(self)`; their titles use `style_title()` (white on a hard INK shadow).
- **Smooth edges by hand.** The Compatibility renderer has no 2D MSAA and `Polygon2D.antialiased`
  does nothing, so pass `antialiased = true` to `Line2D` / `draw_line` / `draw_arc` / `draw_circle`,
  and call `HudStyle.feather(polygon)` on opaque `Polygon2D`s that sit on a contrasting colour.
