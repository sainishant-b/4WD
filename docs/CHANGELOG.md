# Changelog

Running history of major changes. Newest on top. See `CLAUDE.md` for when to add an entry.

## 2026-11-20

- **A tyre on the white line is a wall hit; a clearer race HUD; key caps on the loading screen.**
  *Why:* playtesting on Reddit, the user saw the tyres ride over the track edge without a hit,
  found the top of the desktop HUD crowded, and wanted the loading screen's controls to match the
  rest of the game. Road and car sizes are unchanged.
  - `Car.tscn`: the collision box grew from 30 x 58 to 42 x 63 so it covers the drawn tyres
    (they reach 21 px either side). The car now stops, and the hit counts, the moment a tyre
    reaches the wall; before, the tyres could cross the line and 3-4 px of kerb first. Fully
    steered front wheels can still poke ~4 px past the box. A lap bot still finishes every
    level, with about 2 more hits a lap than before (tyre touches now count).
  - `track_builder.gd`: the white limit line (`LIMIT_WIDTH` 5 px) now sits wholly outside the
    road, so the green-to-white edge is exactly the wall; the kerb and casing move out by the
    same 5 px (still inside `BEND_MARGIN`). The track test checks the new outer edge.
  - Race HUD, wide keyboard window: the mini map moves to the bottom-left corner and the
    controls legend to the bottom-right (two pairs a row), so the top row is only lap, timer
    and best. **H** hides the legend, leaving an "H CONTROLS" chip, and the choice is saved
    (`Game.is_controls_hidden()`, `settings.controls_hidden` in `save.json`). Touch layouts keep
    the old places: the bottom corners belong to the thumb pads.
  - Reddit loading screen (`game.html`, `game.ts`, `game.css`): the one-line sentence is now the
    game's own legend on a cream card: key caps (W S DRIVE, A D FRONT, arrows REAR, SHIFT
    BOOST, SPACE DRIFT, ESC PAUSE) or, on a phone, thumb-pad icons (FRONT, REAR, DRIVE, BOOST,
    DRIFT, BRAKE).

- **The sample layouts too: Today's Circuit, the results card, the pad names.** *Why:* the user
  wants the layout ideas from the Cobalt & Sun samples as well ("I did not mean no other UI
  changes").
  - Today's Circuit (`level_select.gd` `_build_daily`): a tilted DAY tag above a left-aligned
    title (beside it on a desktop); the card holds the track, CIRCUIT + the level's name with a
    3 LAPS tag, TOP SPEED and YOUR BEST tiles sunk into the card (with the medal chip), and the
    three medal targets as equal chips; then a full-width DRIVE with an arrow, Back (cream)
    beside How to Play (red-orange), and a chequered strip along the bottom of the screen. On a
    desktop the track sits beside the details and the buttons go under the details.
  - Results card (`hud.gd`): a medal disc on two ribbons poking out of the card's top edge (a
    red disc with a cross after a game over), an ink title, the times as rows in a sunk well
    (TOTAL big, BEST, BEST LAP; game over: TIME, LAP, WALL HITS), on Reddit the place on a gold
    plate ("#12 / TODAY'S RANK / of 340 racers"), the chips (streak now red-orange), the
    countdown with a clock, and streak flair as a switch row. Retry sits beside Next /
    Leaderboard, Menu under them, with line icons.
  - Thumb pads: FRONT / REAR on cream chips above the pads.
  - `HudStyle`: `tag()` (tilted chip; it sits in a plain holder because containers reset
    rotation), `icon()` (line icons from SVG path data via `Image.load_svg_from_string`, cached),
    `add_chequer()`.
  - Tests: `leaderboard_test.gd` reads the rank from the plate now. All suites pass; screenshots
    regenerated.

- **New look: "Cobalt & Sun", applied everywhere.** *Why:* the user wanted a more saturated,
  less generic UI with more depth and shadow; of three sample themes they picked Cobalt & Sun
  and asked for it across the whole app with no other changes. Layouts, text and behaviour are
  unchanged; only colours and depth styling moved.
  - `ui/Palette.gd`: cobalt `BG` backdrop with darker `BG_STRIPE` stripes, cream `SURFACE` cards,
    sun-gold `GOLD`, red-orange `POP` (replaces the player blue: `BLUE*` tokens are now
    `POP*`), a deep navy `INK` for outlines and lips, `FIELD` for the race ground, `BG_RAISED`
    for deep-blue map/pad wells, `KERB`. `TEXT` is now dark ink (most text sits on cream);
    `TEXT_LIGHT` / `TEXT_LIGHT_MUTED` are for text straight on the backdrop or the track.
  - Theme: every button and card has a 3 px INK outline and a hard INK lip drawn below its rect
    (`expand_margin_bottom`), over a soft navy shadow; pressed buttons lose the lip and their
    label drops. Gold primary, red-orange `ButtonSecondary`, cream `ButtonGhost`, red danger,
    cream `LineEdit`, and an inked slider.
  - `ui/hud_style.gd`: `glass()` is replaced by `panel()` (raised cream) and `inset()` (a sunk
    well); new `chip()`, `text_on()`, `style_sticker()` (coloured words with an INK outline,
    for medal titles and gold headings on cream); `style_title()` is now white on a hard INK
    shadow; `add_backdrop()` draws the striped cobalt; `controls_legend()` takes the action
    words' colour.
  - Race: deep-cobalt field, red-and-white kerbs and an INK casing outside each wall with the
    road's shadow dropped onto the field (replacing the green glow), a red car with a gold
    stripe and nose, red (front) and gold (rear) thumb pads with INK rims, a cream speedometer,
    and a mini map on a deep-blue screen. The track test now checks the kerb's outer edge.
  - Menus: Today's Circuit draws its track on a deep-blue screen; level cards are cream with a
    medal-coloured bar; results/pause/settings titles are stickers. The main menu's gold halo
    is gone (the flat backdrop replaces it).
  - Reddit: the post splash and the loading screen use the same colours (rings and lips are
    box-shadows there, so the 512 px post still fits). Screenshots regenerated.

- **Faster loading on Reddit: the engine downloads gzipped and is cached.** *Why:* the user picked
  loading time from the to-do list; the ~38 MB `index.wasm` was nearly the whole wait.
  - `reddit/tools/export-godot.mjs` also writes `public/index.wasm.gz` (gzip -9: 37.7 MB -> 9.7 MB)
    and `ENGINE_VERSION` (a hash of the wasm + pck) into `public/godot-config.js`. Devvit uploads
    web-view files as they are, so this does not depend on Reddit's CDN compressing anything.
  - New `reddit/src/client/engine-files.ts`: wraps `window.fetch` for exactly `index.wasm` and
    `index.pck` (the names Godot's loader asks for). `index.wasm` is served from `index.wasm.gz`
    through `DecompressionStream('gzip')` as it arrives, so streaming compile and the loading bar
    still work. Both files are kept in the Cache API (`fws-engine-<version>`), so a returning
    player downloads nothing; older versions' caches are deleted.
  - Falls back to the plain `index.wasm` if `DecompressionStream` is missing or the `.gz` fails; a
    body that is not gzip (a server already unzipped it) passes through; storage blocked in the
    web view just means no cache; a damaged cached copy is deleted so the next start re-downloads.
  - Tests: `src/client/engine-files.test.ts` (8, fake network and Cache API), run by `npm test`
    and typechecked by the new `tsconfig.client-test.json`. Checked in `npm run local`: first load
    fetched `index.wasm.gz` (never `index.wasm`) and booted; a reload fetched only `index.js`.
    Not yet measured on a phone in the Reddit app.

- **Opt-in streak flair.** *Why:* the user picked it from the Reddit-y to-do items.
  - On the Reddit results card a logged-in player gets **SHOW MY STREAK AS FLAIR**. Turning it on
    sets their user flair in the app's subreddit to "🔥 4-day streak" (gold, dark text);
    pressing again turns it off. It is off until the player chooses it.
  - Turning it on saves the flair the player had (text and CSS class); turning it off puts that
    back, or removes ours if they had none. Template colours of their old flair are not kept
    (Reddit's API does not report them).
  - It follows the streak: after each race, and once a day in the 00:00 UTC job for everyone who
    has it on, so a lapsed streak changes to "🏁 Daily Circuit racer" instead of showing an old
    number.
  - Server: new `src/server/flair.ts` (no Devvit imports; `FlairSink` is Reddit in `index.ts`,
    a fake in tests and in `tools/serve-local.ts`), `POST /api/flair {on}`, and `flairOn` in the
    init and run responses. If Reddit refuses (no flair permission, flair disabled), nothing is
    stored and the button says FLAIR UNAVAILABLE. The `Store` interface gained `hDel`/`zRem`.
  - Game: `Leaderboard.set_flair()` / `flair_changed`, `Reddit.flair_on`, the toggle in
    `hud.gd`.
  - Tests: `src/server/flair.test.ts` (7: off by default, saves and restores the old flair,
    follows a race, refused change stores nothing, the daily refresh ends a lapsed streak);
    `leaderboard_test.gd` +4 (offered and off, on, off, refused). Checked end to end against
    `npm run local`. Not verified on real Reddit: whether the app account may set flair there
    (the subreddit may need user flair enabled).

- **Credit on the post.** The splash shows "by u/donomadoit" under the title (the user's
  Reddit name, given for the credit line). Still fits a 512 px post.

- **One tap from the post, today's track on the post, a player README, a Devpost draft.**
  *Why:* the user asked to work through the rest of the to-do list.
  - **Reddit opens on Today's Circuit** (`scripts/main_menu.gd`): inside a Reddit post the game
    skips the menu once, on the way in, and lands on Today's Circuit (or the Leaderboard when the
    post's Leaderboard button was used; `Reddit.start_handled`). How to Play is no longer forced
    on first launch there: Today's Circuit has a "? HOW TO PLAY" button, and How to Play's GOT IT
    returns to Today's Circuit. Back still reaches the menu. Off Reddit nothing changes.
  - **The post shows today's track** (`reddit/public/splash.html`, `src/client/splash.ts`): a
    card with a picture of the circuit (green road, white edges, gold start line), its name, laps
    and top speed. The shapes come from the game itself: `reddit/tools/track-shapes.gd` writes
    `src/client/tracks.ts`, and `npm run export:godot` now runs it. The generic tagline hides once
    the card shows, and the steering-demo car shrinks to fit, so the screen fits a 512 px tall
    post (checked at 390x512 in a browser under the local strict CSP: no overflow, no errors).
  - **`reddit/README.md`** now starts with a player section (how to play, controls, the trick,
    daily rules, boards, streaks, data) for Devpost and app review; the developer notes below it
    are brought up to date (the bridge is in use, the API routes, `tracks.ts`).
  - **`docs/DEVPOST.md`**: a draft of the Devpost text (pitch, what it does, how to play, how it
    was built, what changed since 11 Nov), with the links and checks still to fill in.
  - Looked into Devvit Journeys: the protocol exists, but no SDK release (checked 0.15.3 and the
    newest 0.15.4) exposes it to apps, and it refuses events from playtest versions and from
    apps Reddit has not allowlisted. Left on the to-do list as blocked.
  - Tests: `leaderboard_test.gd` +3 (Reddit opens on Today's Circuit, Back shows the menu with
    no bounce, the post's Leaderboard button opens the boards). All suites pass.

- **Reddit results card: today's place, streak, countdown, and a TODAY board.** *Why:* the
  user picked the to-do item "result card on Reddit" next (Delightful UX / Daily Content).
  - After a finish inside a Reddit post the results card shows an inset strip under the times:
    "POSTING YOUR TIME..." until the server answers, then the place on the day's board ("#12 OF
    340 TODAY", or "ON DAY n" on an older post), a green NEW BEST chip and a gold "4-DAY STREAK"
    chip, and a live "NEXT CIRCUIT IN h:mm:ss" countdown. Logged out it says LOG IN TO RANK; with
    no answer, COULDN'T REACH REDDIT. The gold button is **Leaderboard** (the next step), which
    opens the Leaderboard screen on the new TODAY board. Off Reddit nothing changes.
  - Server: `GET /api/init` and `POST /api/run` now also return `nextCircuitInMs` (time to the
    next 00:00 UTC, `msUntilNextDay` in `daily.ts`). It is a duration, so a wrong device clock
    cannot skew the countdown. +1 server test (13).
  - Game: `Leaderboard.run_recorded(info)` hands the server's answer to the card;
    `Leaderboard.DAY` fetches the day board; `Leaderboard.open_on_day` starts the screen there.
    The Leaderboard screen on Reddit is OVERALL (still first), TODAY, then one board per level.
    `Reddit.is_today` comes from `/api/init`. `game.gd` shows the card, then connects to
    `run_recorded`, then posts the time.
  - Tests: `leaderboard_test.gd` +9: the TODAY board, and a real finish on Reddit through the
    stand-in server (place, chips, countdown, the Leaderboard button opening TODAY, logged-out and
    no-answer wording). It puts the save file back afterwards. `capture_screens.gd` shoots the
    card (`*-reddit-results.png`). Not verified on real Reddit yet.

- **Less drift, one circuit a day on Reddit, a picture-only How to Play, pads in mobile view.**
  *Why:* the user's first playtest on Reddit: the car drifted into the walls, the level screen
  offered Level 1 and Level 4 instead of just today's map, How to Play had too many words, and
  the thumb pads never appeared in the browser's mobile view.
  - **Handling** (`scripts/car.gd`): tyre grip 520 -> 800, rear cornering stiffness 3100 -> 4200
    (now stiffer than the front, so the tail stays planted), and a new `traction` pull (6/s) that
    eases the sideways speed toward what the wheel angles ask for, so the car goes where its
    wheels point. Crab-walk and the pivot still work (the pull aims at their own no-slip motion),
    and the handbrake keeps 20% of the pull (`handbrake_traction`), so its drift stays. Measured
    with a scratch probe at top speed: steering front and rear opposite ways slid 42% sideways
    on average before, 28% after. A driver bot lapping all five levels the same careful way
    touched the walls 26 times before and 9 after, and lapped 0.7-5 s faster on every level.
  - **Reddit: Today's Circuit.** Inside a Reddit post, Play now opens one screen with only the
    day's level: a diagram of the circuit (new `TrackDiagram` control, `scripts/track_diagram.gd`),
    "DAY n", its name, top speed, your best, the three medal times as chips, and DRIVE. The grid of
    five levels is shown only outside Reddit. `Game.has_next_level()` is false on Reddit, so the
    results card offers no "Next"; `Game.daily_index()` finds today's slot. The screen rebuilds
    when the day's data arrives (`Reddit.init_loaded`).
  - **How to Play** (`scripts/instructions.gd`): the three sentences are gone. Four glass tiles
    (FRONT, REAR, SPIN TURN, SIDEWAYS), each a car with the steered wheels lit, its key caps (or
    blue/gold thumb pads on touch) and a one- or two-word name; then three red pips with
    "3 WALL HITS = OUT"; then the other controls as caps. `HudStyle.cap()` (was `_cap`) draws one
    cap and knows a new "<>" token (a pad slid either way); `controls_legend()` takes an `omit`
    list.
  - **Thumb pads in mobile view** (`scripts/layout.gd`, `scripts/touch_controls.gd`): the pads
    used to appear only after a real touch, and a desktop browser's mobile view sends mouse
    clicks, so they never came up. Now touch mode also starts on in a browser that reports a
    touchscreen, and turns on when a phone-shaped window is clicked with a real mouse; the mouse
    then drags a pad like a thumb (one pad at a time). Mouse events Godot copies from a touch are
    ignored, so a touch never counts twice.
  - **Tests:** `touch_test.gd` +6 (mouse in a portrait window, a wide window stays keyboard, no
    double-counted touch), `leaderboard_test.gd` now checks the Reddit screen (one diagram of
    today's level, only DRIVE and Back, no next level) and the five-card grid off Reddit.
    `capture_screens.gd` also shoots Today's Circuit. All pass. Not verified: how the new grip
    feels to a person, or the pads on a real phone inside Reddit.
  - Also: the app is registered as **`fourwd`** (`reddit/devvit.json`, `package.json`; `devvit
    init` added `"license"` and the `dev.subreddit` playtest setting).

## 2026-11-17

- **Mute button, shaded menus, a Reddit leaderboard, harder Levels 3-5.** *Why:* the user's
  requests: a mute button everywhere, more depth in the menus and options, a leaderboard on
  Reddit with the lowest time across all maps on top, and difficulty that rises across the maps.
  - **Mute** (`scripts/mute_button.gd`, new `MuteButton` autoload): a speaker button in the
    top-right corner of every screen, drawn above everything (pause and results cards too). It
    mutes the master bus, is saved as `settings.muted`, and leaves the volume slider alone. The
    race HUD moved its pause button and best-times card left to make room.
  - **Menus:** solid buttons are raised (a darker front edge, a shadow; they sink when pressed),
    ghost buttons get a glass fill, cards and dialogs cast deeper shadows. The main menu's buttons
    sit on a glass card under a lit title; Settings has a heading; level select uses raised cards
    with a medal-coloured top strip, a medal chip, and "finish Level N first" on locked ones.
    Titles share `HudStyle.style_title`.
  - **Reddit leaderboard.** The Devvit server (`reddit/src/server/daily.ts`) now keeps three
    kinds of board in redis: per level (`level:<id>`, best time ever), OVERALL (`overall`, the sum
    of a player's bests on all 5 levels, only once they have all 5, lowest first), and the day
    board. Each day one level is featured, in turn (`levelOfDay`); only a run on it moves the day
    board and the streak. `POST /api/run` takes `{levelId, timeMs}`; `GET /api/leaderboard` takes
    `board=overall|level|day`, `level` and `limit`. The level ids must match `game_data.gd`
    (`LEVEL_IDS`).
  - **Game side:** new `Reddit` autoload (`scripts/reddit.gd`) reads `window.FWS` through
    `JavaScriptBridge.get_interface` (never `eval`). `Leaderboard` now talks to Reddit when it is
    there and Appwrite otherwise. The Leaderboard screen opens on OVERALL, shows "Racing as
    u/name", your rank and how many maps you have, medal badges for the top three and your own
    row in blue. Level select marks the featured level TODAY, and it is playable even if locked.
    The post's splash has a **Leaderboard** button that opens the game on that screen.
  - **Harder Levels 3-5** (1 and 2 unchanged): Level 3 road 76 -> 72 px, top speed 650 -> 665,
    deeper esses. Level 4 road 74 -> 68, speed 680 -> 700, its switchback hairpins pulled 20 px
    tighter. Level 5 road 72 -> 64, speed 700 -> 725, its inlet 40 px narrower.
  - **Wiggles on Levels 4 and 5** (the user: "there's just hairpins"). Level 4 gained esses along
    the top straight and a chicane along the bottom; Level 5 esses before the inlet, along the
    bottom and up the left side. Each ess is spaced wide enough to survive the bend-rounding pass
    (a first, tighter try came out as small bumps). Laps grew 3-4 % (L4 6950 px, L5 7220 px), so
    their medal targets went up to match (L4 80/103/133 s, L5 85/110/143 s); still estimates.
  - Dropped an attempted Wi-Fi phone test (`npm run phone`): Godot's web audio needs https, so a
    phone on plain http could not start the game. The user chose to skip it.
  - **Tests:** new `tests/leaderboard_test.gd` (the Reddit path against a stand-in server, the
    screen, the featured-level unlock, mute). `reddit` server tests: 12 (overall board, level
    boards, featured-level-only streaks). All game tests pass. `tests/capture_screens.gd` now also
    shoots the main menu, settings and leaderboard. Not verified: the board on real Reddit, a
    phone, or how the new widths and speeds feel to drive.

- **Five levels, three strikes, key-cap controls.** *Why:* the user's own redesign of the level
  set and rules, plus a request for bolder, friendlier instruction text.
  - **Levels: 8 -> 5.** Old Level 1 is gone; old 3 is now Level 1, old 2 stays Level 2, old 4 is
    Level 3. Old Level 5 and the three obstacle levels (6-8) are removed, so no map has cones,
    walls or ramps any more. Each moved level kept its own speed and medal targets.
  - **Two new, harder circuits.** Level 4 (74 px road, 6810 px lap, top speed 680): a two-hairpin
    switchback and esses. Level 5 (72 px road, 6950 px lap, top speed 700): three hairpins, in a
    deep inlet and a double switchback. Their medal targets are estimates, not driven times.
  - **Three wall hits = game over** (`game.gd` `MAX_WALL_TOUCHES`). `car.gd` emits `wall_touched`
    once per new contact: a scrape, a rest against the wall, or a pinball across the road inside
    one second counts once (`WALL_RELEASE_TIME`, `WALL_REARM_DISTANCE`, `WALL_TOUCH_GRACE`). The
    count runs over the whole 3-lap race. Hits 1 and 2 flash the screen edge red with a banner;
    hit 3 stops the car and shows a GAME OVER card (Retry / Menu). A game over saves nothing: no
    best time, no medal, no leaderboard entry, and the next level stays locked. Not applied in the
    hidden multiplayer. The HUD gained a WALL HITS readout (three pips).
  - **Controls legend.** The race hint was one thin line of body text; it is now a strip of key
    caps with bold labels (W S DRIVE, A D FRONT, arrows REAR, SHIFT BOOST, SPACE DRIFT, ESC
    PAUSE), or thumb-pad icons on touch (one pad up DRIVE, both up BOOST, one down DRIFT, both
    down BRAKE). Built by `HudStyle.controls_legend()`; it wraps to two rows on a phone. How to
    Play shows the same legend and a new line for the three-hits rule.
  - **Bolder body text.** Only Barlow Regular is bundled, so the theme's `LabelBody` now uses an
    emboldened `FontVariation` of it (How to Play, menu subtitle, leaderboard notes).
  - **Saves survive the reorder.** Levels now carry a permanent `id`; `save.json` records and the
    leaderboard are keyed by it (ids match the old slot numbers, so existing files need no
    migration and each kept track shows its own old times). The stored `unlocked` counter is gone:
    a level is unlocked when the one before it has a best time.
  - **Left in place, unused:** the obstacle code (`cone.gd`, `ramp.gd`, `_build_obstacles`,
    `car.hit_cone` / `jump`) and the hidden multiplayer's own wide track.
  - **Tests:** new `tests/rules_test.gd` (23 checks: level table, what counts as one hit, the
    warnings, game over, save file untouched). `track_test.gd` also checks that the road never
    runs into another part of itself (it bounds how close a hairpin's legs may be).
    `touch_test.gd` still passes 31/31. `tools/preview_track.py` has the five presets.
  - **Screenshot tooling:** `tests/capture_screens.gd` regenerates `docs/screenshots/`, launched
    through `tests/run_offscreen.ps1`, which runs Godot on its own invisible Windows desktop.
    A normal capture window, even a hidden one, takes keyboard focus and swallows typing.
  - Verified on Godot 4.7: the three tests, and screenshots at phone (860x1520) and desktop
    (1280x720) size of the countdown, race, wall warning, game over, both new tracks, How to Play
    and level select. The Reddit wrapper was re-exported. **Not verified:** how hard three hits
    over three laps is to actually drive, the new levels' medal times, a real phone, Reddit.

## 2026-11-16

- **Smooth track edges, a shaded HUD and a mini map.** *Why:* the user spotted the road's inside
  edge looping back over itself beside the Level 1 start line, found the HUD flat and low-res, and
  asked for a mini map.
  - **The loop was in the centre line, not just the edge.** The uniform Catmull-Rom spline kinks
    where two waypoints sit close together (Level 1's last two are 141 px apart between 440 px and
    800 px neighbours), giving a centre-line radius of 11 px on a road 50 px to each side, so the
    offset edge folded. 6 of the 8 tracks and the multiplayer track folded somewhere.
    `track_builder.gd` `centerline()` now: centripetal Catmull-Rom -> points resampled 10 px apart
    -> any bend tighter than half the road width + 24 px is relaxed until it clears.
  - **What that changes for players:** tight corners moved by up to about 33 px and are rounder,
    so tracks 2-5 are up to about 3 % shorter and their hairpins a little easier. Saved best times were set
    on the old shapes and were left alone. The start slot is now a fixed 60 px behind the line
    (it was 5 samples, which meant 39-80 px depending on the track). Gates and obstacles keep
    their `t` but are snapped to the nearest centre-line point.
  - **Also fixed:** the road fill left a sliver of background showing across the track just
    before the start line (the band polygon never closed the loop). The road is now a closed
    ribbon mesh.
  - **Track look:** the surface is one `MeshInstance2D` of ribbons shaded by vertex colour (a soft
    green glow outside the walls, darker road beside them, a lighter crown; `Palette.TRACK_EDGE`
    is finally used), on a faint grid that gives a speed reference off the road. Gate 0 is a
    chequered strip; the next gate is gold with a glow; gate numbers are flat paint. Barriers get
    a shadow and a lit top; cones take Palette colours.
  - **Car:** a soft shadow (it slides away during a ramp hop), darker flanks round a lighter deck,
    a glass cockpit. Built in `car.gd` `_build_visuals()`.
  - **HUD (`hud.gd`):** readouts sit on translucent glass panels, so their text no longer needs a
    5 px outline (the main cause of the coarse look). New **mini map** (`scripts/minimap.gd`):
    north-up circuit, car arrow, pulsing next gate, start line; fed by `set_track` /
    `set_next_gate` / `set_car` from `game.gd`. The speed gauge has a blue -> gold -> red arc with
    a glowing tip in place of the needle that crossed the number; the boost meter is a pill; the
    pause button is a drawn icon; the countdown sits between the hint and the car instead of on
    the car; a vignette darkens the corners. In landscape the gauge moved down to the bottom edge.
  - **Thumb pads** are redrawn (glass disc, glowing ring and knob, thin chevrons). The gestures
    and thresholds are untouched.
  - **Menus** share one backdrop (`HudStyle.add_backdrop`): faint grid, a wash of blue and gold,
    darkened corners. Buttons and cards are unchanged.
  - **New `ui/hud_style.gd` (`HudStyle`)** holds the glass panel styles, glow and vignette
    textures, label styles, the backdrop and `feather()`.
  - **Sharpness:** 2D MSAA is not available in the Compatibility renderer (Godot warns "2D MSAA is
    not yet supported for GLES3") and `Polygon2D.antialiased` has no visible effect, so edges are
    smoothed with anti-aliased `Line2D` / `draw_line` / `draw_circle`, and solid polygons are
    traced with a thin anti-aliased line (`HudStyle.feather`). `project.godot` sets the clear
    colour to the navy background.
  - **Tests:** new `tests/track_test.gd` (108 checks: for each of the 9 tracks, even spacing, no
    over-tight bend, neither edge nor glow folds, gates / start slot / obstacles on the road).
    `tests/touch_test.gd` still passes 31/31. `tools/preview_track.py` mirrors the new math,
    gained the missing `t2` preset, and has an `all` mode that draws every level on one sheet
    (`docs/tracks_overview.png`).
  - Verified on Godot 4.7 with both tests and screenshots at phone resolution (860x1520, i.e. 2x)
    and 1280x720: countdown, race, boost, drift, pause, a Level 2 hairpin, the three obstacle
    levels and the four menus (`docs/screenshots/`). The Reddit wrapper was re-exported.
    **Not verified:** a real phone, Reddit itself, or the frame rate of the extra glow and
    anti-aliased lines on a slow phone.

- **Mobile interface: phone-sized layouts + twin thumb-pad controls.** *Why:* Reddit is mostly
  phones, and on a portrait phone the game was unusable: the single 1280x720 logical canvas shrank
  every label and button to about a third of its size, and the touch controls were stock
  `HSlider`s/`Button`s, which follow only one finger, so two axles could never be steered at once.
  - **`Layout` autoload (new `scripts/layout.gd`)** swaps the logical canvas with the window's
    shape: landscape keeps 1280x720, portrait uses 430x760 (roughly 1 logical px per CSS px on a
    phone). It exposes `portrait` / `touch` and a `changed` signal. `touch` is fixed on phones and
    otherwise follows the last device used (first touch shows the pads, a key press hides them).
  - **Touch controls rewritten (`scripts/touch_controls.gd`)** as two multi-touch thumb pads drawn
    in code, to the user's spec: left pad = front wheels, right pad = rear wheels; either pad up =
    accelerate (analog); both fully up = boost; one down = handbrake/drift; both down = brake then
    reverse. A pad re-centres under the thumb; the knob colour shows the active gesture. Replaces
    the two sliders + BOOST/GAS/REV/RESTART buttons. `InputState` gains `touch_handbrake`.
    *Interpretation to confirm on a device:* boost needs both pads at least 85% up (`BOOST_AT`), so
    two thumbs can still drive at part throttle without burning the meter.
  - **HUD (`scripts/hud.gd`)**: nodes are created once and placed by `_layout()`, re-run on
    `Layout.changed`. Portrait gets a compact top row, the best times under it, and a smaller gauge
    between the pads; results buttons stack vertically and modals narrow to fit. On touch there is
    a **pause button** (`ui_action("pause")`, handled in `game.gd`) and a two-line gesture hint that
    fades 8 s after GO. `speedometer.gd` now scales its text and arc with its size.
  - **Menus** (`main_menu.gd`, `instructions.gd`, `level_select.gd`, `leaderboard_ui.gd`) build in
    `_build()` and rebuild on `Layout.changed`: smaller titles, a 2x4 level grid, a `< Level N >`
    stepper on the leaderboard, touch wording on How to Play. **Quit** is hidden on web builds.
  - **Camera**: `car.gd` `camera_zoom_portrait` (0.82) pulls back a little on the narrow screen.
  - **Small fixes found on the way:** the next-gate arrow and the thumb pads no longer draw over
    the pause/results cards; How to Play's wheel diagrams use a light colour (black wheels were
    invisible on the navy background); the split-delta label no longer overlaps the BOOST caption;
    the best-time labels sit flush with the right edge.
  - **Desktop is otherwise unchanged** (same arrangement, keyboard hint stays up).
  - New **`tests/touch_test.gd`** (`.gdignore`d, not exported): a headless script that feeds real
    multi-touch events into the race scene. 31 checks pass: steering, dead zones, throttle, boost,
    drift, brake, finger bookkeeping, driving the car, pause, the portrait switch, menu rebuilds.
  - Verified on Godot 4.7: that test; native 430x760 screenshots of the race (idle and mid-gesture),
    pause, results, leaderboard and How to Play screens, plus the 1280x720 race and results; and the
    web export at 390x760 in a browser (menu, How to Play, level select, race HUD with pads — seen
    on the build just before the small fixes above; the final export was not re-opened).
    **Not verified:** feel on a real phone (pad size, thresholds, the 0.82 zoom), and the results
    card through a real finish (the screenshot bypassed `_finish()` to avoid writing a save).

- **Reddit (Devvit Web) wrapper — first slice of the "Game of the Day" hackathon port.** New
  `reddit/` folder (`.gdignore`d so Godot skips it): a Devvit Web app that runs this project's Web
  export inside a Reddit post. *Why:* the hackathon only accepts games running on Reddit via Devvit,
  built around a daily loop.
  - **CSP-safe engine loader.** Reddit's web view forbids inline `<script>`/`<style>`, which Godot's
    stock `index.html` relies on. `reddit/tools/export-godot.mjs` runs the headless **Web** export,
    copies only the engine files into `reddit/public/`, and lifts `GODOT_CONFIG` into
    `godot-config.js`; `public/game.html` + `src/client/game.ts` replace the stock shell (styled
    loader with a one-line controls hint). The export preset itself is unchanged (threads already off).
  - **Inline splash post** (`public/splash.html`, `src/client/splash.ts`): title, circuit number +
    date, an animated pivot/crab steering demo, your best / rank / streak, and a Drive button that
    opens the game in expanded mode. Uses the design-system colors and the bundled fonts.
  - **Daily server** (`src/server/daily.ts` + `index.ts`, Hono on Devvit): a day number from the UTC
    date, a per-day seed, a per-day best-time leaderboard (redis sorted set), a streak that only
    advances on the current day, plus a 00:00 UTC cron / install trigger / mod menu item that create
    the day's post. Rules are unit-tested (`npm test`, 8 tests).
  - **`window.FWS` bridge** for the game to read the daily data and post a time — **not wired into
    the Godot side yet**: the game still boots into the normal menu, and the per-day seed does not
    generate a track yet.
  - `reddit/tools/serve-local.ts` + `.claude/launch.json`: a local stand-in for Reddit's host (strict
    CSP + in-memory API).
  - Verified locally on Godot 4.7 / Node 22: export, type-check, tests and `devvit.json` schema all
    pass; under the strict-CSP local server the splash renders and the engine boots to the How to
    Play screen with no CSP errors; the API round-trip works. **Not yet uploaded to or tested on
    Reddit**, and the loader's progress bar was not observed moving (the test pane was hidden, which
    pauses the animation frames Godot reports progress on).

## 2026-06-24

- **Six new tracks (8 total) + an obstacle system.** Three more tight/twisty circuits (Levels 3-5,
  `TRACK_3/4/5` — data-only on the existing builder) and three **obstacle** tracks (Levels 6-8):
  - **Obstacle data model + builder:** a track may carry `"obstacles": [{type, t, offset, …}]` placed
    along the centerline (`t` = 0..1, `offset` = lateral px). `track_builder.gd` instantiates them
    under a new `Obstacles` node in `Main.tscn`; `tools/preview_track.py` draws obstacle markers
    (presets `t3`..`t8`).
  - **Cones** (`scenes/Cone.tscn` + `cone.gd`): **soft** (plow through → `car.hit_cone()` bleeds ~18%
    speed + scatters) or **solid** (a `StaticBody` you must avoid) via a `solid` flag.
  - **Swerve-walls:** short `StaticBody` barriers jutting alternately into the lane (inline in
    `track_builder.gd`) — weave through; reuses the car's wall collision.
  - **Ramps** (`scenes/Ramp.tscn` + `ramp.gd`): a fake **hop** — `car.jump()` scales the car up and
    drops all collision (layer+mask → 0) so it sails over cones/walls, then lands (collision restored
    + a thump). 2D has no real height, so it's an illusion + a traversal mechanic.
  - **Levels 6-8** = a **cone slalom**, a **wall chicane**, and a **ramp run** (hit the ramp to clear
    the cluster), on medium-width (130-135) roads; level select is now a 4×2 grid. Medal targets are
    **rough** (retune after a drive).
  - Verified on Godot 4.7: all 8 tracks build (previews fold-free; headless build of every level with
    correct obstacle counts; the three obstacle race scenes run clean) + harnesses confirm `hit_cone`
    (speed drop) and `jump` (collision drop → restore, no NaN).

- **Pivoted online play: real-time multiplayer → an online leaderboard (Appwrite).** Racing together
  proved impractical, so players now race the single-player time-trial **separately** and compete on a
  **shared per-level leaderboard**.
  - **`Leaderboard` autoload (`scripts/leaderboard.gd`)** — a small Appwrite REST client over
    `HTTPRequest`: `submit_score(name, level, time_ms)` + `fetch_top(level)` (Appwrite queries plus a
    client-side level-filter/time-sort safety net). Config IDs (endpoint/project/database/collection)
    sit at the top; `configured()` is false until they're filled, so the whole feature is a graceful
    no-op (with a friendly note) before setup / offline.
  - **Submit on finish (`game.gd`).** `_finish()` (single-player) uploads name + level + total time
    (ms) after recording the local result.
  - **Player name** persisted in `save.json` settings (`game_data.gd` `get/set_player_name`).
  - **Leaderboard screen (`scenes/Leaderboard.tscn` + `scripts/leaderboard_ui.gd`)** off a new
    **Leaderboard** menu button (which **replaces Multiplayer**): name field, Level 1/2 toggle, a
    ranked list (rank · name · time), Refresh/Back, and loading/empty/error/not-configured states.
  - **Multiplayer is hidden, not deleted** — `Net`/`Lobby`/car-spawn code remains but is unreachable;
    single-player and the wide track are untouched.
  - Backend setup is user-side (Appwrite console): a `scores` collection (name/level/time_ms) with
    role **Any** granted Create + Read, then paste the four IDs into `leaderboard.gd` (see README).
  - Verified on Godot 4.7: clean import; menu, the Leaderboard screen (shows the "not set up yet" note
    with blank config), and the race all run error-free.

- **Multiplayer in-race: cars spawn, sync, and bump.** Builds on the foundation below — you now see
  each other's car move in real time on the shared wide track and can trade paint.
  - **Per-peer car spawning (`game.gd`, `Main.tscn`).** `Main.tscn` drops the hardcoded `Car` for a
    `Cars` node; `game.gd` spawns cars dynamically (one in single-player, one per peer online). Online
    uses a small **handshake**: each client reports its race scene is ready, then the **server deals**
    one car per peer at a side-by-side **start grid** (`_grid_positions`) via a `call_local` RPC, so
    every peer builds the identical set. Each car gets `set_multiplayer_authority(pid)`, and only the
    local player's `Camera2D` is made current.
  - **Transform replication (`Car.tscn`, `car.gd`).** A `MultiplayerSynchronizer` on the car
    replicates `position`/`rotation`/`front_steer`/`rear_steer`/`boost_meter`/`_boosting` from the
    owner. `car.gd` `_physics_process` **early-returns for non-authority cars** (puppets just reflect
    the synced wheel angles) — a no-op in single-player.
  - **Bumping.** Cars are `CharacterBody2D`s on collision layer 1 (same as walls), so each car's
    `move_and_collide` already blocks against the others — the existing wall-impact branch handles the
    bounce. No new collision code.
  - **Per-player progress (`checkpoint.gd`, `game.gd`).** Checkpoints now pass the triggering body;
    online, each peer counts only its **own** car's gates (remote cars also trip the gate locally).
    The countdown waits until the local car has been dealt.
  - Verified on Godot 4.7: single-player race runs clean with the new spawn path; a two-instance
    `127.0.0.1` integration test had **both** peers spawn 2 cars and the client's copy of the host's
    car follow the host's moved position (sync confirmed), no script errors.
  - *Known gaps (next phases): the countdown isn't tightly synced, and the MP results buttons
    (Retry/Menu) and disconnect cleanup aren't wired yet.*

- **Multiplayer foundation (online host/join lobby + wide bump track).** First slice of online
  multiplayer — the networking spine, the lobby, and the shared track. *In-race car spawning / sync /
  bumping land in the next phases.*
  - **`Net` autoload (`scripts/net.gd`).** Owns the ENet/UDP peer and connection lifecycle:
    `host()`/`join()`/`leave()`, a server-authoritative player registry kept in sync via RPC, and
    signals (`player_list_changed`, `connection_failed`, `server_disconnected`, `start_race`). Listen-
    server model (host plays as peer 1). `DEFAULT_PORT = 24565`. With no peer, `is_multiplayer` is
    false and the game is exactly single-player. Registered in `project.godot` `[autoload]`.
  - **Lobby (`scenes/Lobby.tscn` + `scripts/lobby.gd`)** reached from a new **Multiplayer** button on
    the main menu: Host / Join (paste `address:port`), a live player list, and a host-only **Start
    Race** that drives every peer into the race together via `Net.start_race`.
  - **Wide MP track + shared race path.** New `TRACK_MP` in `game_data.gd` — Track 1's flowing loop
    but **road_width 180** (vs 100) so cars run side-by-side and trade paint — plus an `MP_RACE`
    config and a `Game.active_race()` helper. `game.gd` now loads `active_race()` (MP → the wide
    track; else the chosen level) and **skips medals/unlocks online**. `tools/preview_track.py` takes
    a preset arg (`t1`/`mp`).
  - Verified on Godot 4.7: clean import; a two-instance `127.0.0.1` smoke test had host + client both
    reach a 2-player roster (RPC sync works); MainMenu, Lobby, and the race scene all run error-free;
    the MP track previews with no folds.

## 2026-06-23

- **Fixed: keyboard boost (Shift) didn't fire.** `input_state.gd` read boost via
  `Input.is_physical_key_pressed(KEY_SHIFT)`, which is unreliable for **modifier** keys — so Shift
  never registered. Switched to `Input.is_key_pressed(KEY_SHIFT)` (catches **both** left & right
  Shift) and added **C** as a non-modifier fallback (helps on keyboards that ghost Shift+W+D).
  Hint/README/CLAUDE controls now read "Shift/C boost".

- **Boost mechanic + a responsiveness tweak.** New held **boost** for a burst of speed.
  - **Input:** **Shift** (desktop) or an on-screen **BOOST** button (above GAS in the touch column).
    `input_state.gd` merges them into `InputState.boost` (keyboard OR `touch_boost`); `touch_controls.gd`
    adds the gold BOOST button.
  - **Physics (`car.gd`):** holding boost (while not reversing) adds `boost_accel` of forward thrust and
    raises the forward-speed ceiling to `boost_speed_mult × max_speed`; on release the overspeed **bleeds
    off smoothly** (`boost_decel`) instead of snapping. It burns a **meter** (`boost_meter`, 0..1) that
    empties in `boost_duration` s and refills at `boost_recharge_rate`/s, with `boost_min_to_fire` to stop
    stutter-firing. Boosting also kicks up dust and dollies the camera out a touch (`boost_zoom_out`).
  - **HUD (`hud.gd`):** a **BOOST meter bar** above the speedometer (gold when usable, dimmed near empty);
    `game.gd` resets it to full at the start line and feeds it each frame. On-screen hint adds "Shift boost".
  - **Feel tweak:** `steer_sensitivity` 5.0 → **6.0** (snappier turn-in). *(Deeper physics taste-tuning still
    wants an in-editor drive — all values are `@export`.)*
  - Verified on Godot 4.7: clean import + race-scene run with no script errors, **plus** a scripted
    physics-step harness confirming the boost path (speed exceeds the base cap, meter depletes then
    recharges, overspeed bleeds off, no NaN).

- **Polish & feel: speed-sensitive camera + brake lights (`scripts/car.gd`).** Two self-contained
  game-feel systems added in the Polish phase (no mechanics changed, `game.gd` interface untouched).
  - **Speed-sensitive camera dolly.** The `$Camera2D` now eases **out** as forward speed approaches
    `max_speed` (down to `camera_zoom_at_top` × the rest zoom, default 0.78×) and back **in** when
    slow, so fast sections reveal more road ahead. New `@export`s on the Car: `camera_zoom_rest`
    (1.4, matches `Car.tscn`), `camera_zoom_at_top`, `camera_zoom_lerp` (ease rate). Updates the
    `zoom` channel only — the wall-impact shake keeps using `offset`, so they don't fight.
  - **Brake lights.** Two rear red `Polygon2D` lights (created in code in `_ready`, like the dust)
    light up while **braking** (reverse held above ~5 px/s forward) or **handbraking** — pure visual
    feedback, no new input.
  - Verified on Godot 4.7: clean headless import + a race-scene run through the countdown into
    RACING with no parse/script errors or NaN. Final zoom-curve taste is `@export`-tunable.

## 2026-06-22

- **Speedometer gauge + live lap delta (HUD).**
  - **Radial speedometer.** New `scripts/speedometer.gd` — the design-system `_draw()` gauge:
    a dark scrim disc, an inset background track arc, a **gold value arc + needle** that sweep
    with speed, tick marks, and a center numeric readout. Replaces the old `SPD 0` text label in
    `hud.gd`. `game.gd` sets its full scale to the level's `max_speed` (`set_speed_max`); the HUD
    feeds it each frame via the existing `set_speed`.
  - **Live split delta.** Passing a gate now pops a transient **+/- vs your best lap** readout
    (green = ahead, red = behind), fading after ~1.4 s. `game.gd` records each gate's time within
    the current lap (`_cur_splits`) and, when a lap becomes the session's best, stores it as the
    reference (`_best_splits`); `hud.gd` `show_delta()` renders it with `Palette.SUCCESS`/`DANGER`.
    (The reference is the best lap **this session**, so deltas start from lap 2.)
  - Verified on Godot 4.7: clean import + race scene run; a scripted 3-lap replay confirmed the
    split/delta path (18 gate passes → finish, correct cumulative best-lap splits, no errors).

## 2026-06-21

- **Applied the "Four Wheel Steer" design system** (from `Four Wheel Steer — Design System/godot/`).
  - **Installed the tokens:** copied `Palette.gd` and `four_wheel_steer_theme.tres` into
    `res://ui/`. `Palette` is now an **autoload** (color tokens for procedural drawing —
    `Palette.GOLD`, `Palette.TRACK`, …) and the theme is the **project-wide GUI default**
    (`project.godot` → `[gui] theme/custom`), so every Button/Panel/Slider/Label is styled.
    *(Fonts — Chakra Petch / Barlow — are intentionally not embedded; drop them in `res://ui/fonts/`
    and set the theme's Default Font to enable them. The game runs fine on Godot's default font.)*
  - **Buttons now use the design variants** via `theme_type_variation`: gold primary (Play, GAS,
    Resume, Next, Got it), blue `ButtonSecondary` (How to Play, Retry, REV), outline `ButtonGhost`
    (Settings, Back, Menu, Restart), red `ButtonDanger` (Quit). Menu/instructions/level-select
    backgrounds + titles use Palette `BG`/`GOLD`/`TEXT_MUTED`.
  - **Dialogs are real modals.** Settings (menu) and the Results/Pause overlays (HUD) are rebuilt
    as a dimming **scrim + centered `PanelModal` card** (`PanelContainer` that sizes to content),
    replacing the old fixed-size `Panel`s. Medal/accent colors come from `Palette.MEDAL_*`; the
    next-gate **HUD arrow** and "GO!" are gold; the speedo reads gold.
  - **World recolored to the palette's model:** the drivable surface is now the green `TRACK`
    token, the surrounding field is the same dark-navy `BG` as the menus (was green grass / grey
    road), the lane line is gold and the wall/limit line bright. The **car** is `BLUE` body /
    `GOLD` nose / near-black wheels; **checkpoint gates** are gold (next) / blue (cleared) /
    muted (pending). Touch **steering sliders** are tinted per axle (front = blue, rear = gold).
  - `tools/preview_track.py` colors updated to match (navy field / green road / gold lane).
  - **Bundled the fonts.** Added **Chakra Petch** (Bold) and **Barlow** (Regular) under `ui/fonts/`
    (Open Font License). The theme's **default font** is now Chakra Petch (display/UI/HUD); a new
    **`LabelBody`** type variation uses Barlow for body copy (menu subtitle, instructions text +
    footer set `theme_type_variation = "LabelBody"`). Marked the reference `Four Wheel Steer —
    Design System/` folder with **`.gdignore`** so its duplicate `Palette.gd`/theme aren't compiled
    into the game (the installed copies in `res://ui/` are the live ones).
  - Verified on Godot 4.7: clean headless import; MainMenu, Instructions, LevelSelect and the
    race scene all run error-free with the theme + Palette + fonts applied.

## 2026-06-20

- **How-to-play slide.** New `Instructions` screen (`scenes/Instructions.tscn` + `instructions.gd`)
  with little car diagrams showing the hook: independent front/rear steering, opposite axles = a
  tight pivot, same axles = sideways crab-walk. Shown automatically on **first launch** (tracked
  via `seen_instructions` in the save) and re-openable from a new **How to Play** button on the menu.
- **Lane stripes, gate restyle, export presets.**
  - Added a **dashed centre lane line** down the middle of the road (`track_builder.gd`).
  - **Gates no longer read as walls:** the checkpoint visual is now a thin line (collision box
    unchanged, so detection still works) and the pass-flash is toned down (`checkpoint.gd`).
    (Gates were never collision walls — verified the wall geometry has no cross-road segments;
    the "wall" was a gate caught mid-flash.)
  - Added **Web** and **Windows** export presets (`export_presets.cfg`) for sharing the game.

- **Fixed: menu buttons unresponsive ("can't start the game").** Removed the forced
  `input_devices/pointing/emulate_touch_from_mouse` project setting. Once the window became
  maximized, that setting routed every click through a mouse→touch→mouse round-trip whose
  coordinates no longer matched the scaled UI, so the menu buttons never received them. The menus
  and the on-screen touch controls are plain `Control` widgets that already work natively with the
  mouse (desktop) and touch (mobile, via the default emulate-mouse-from-touch), so the setting was
  both unnecessary and the cause.
- **Two tracks, portrait phone support, and engine-noise fix.**
  - **Tracks:** Level 1 is a new **wide, flowing intro** circuit (140px road, 6 gates); the tight
    twisty circuit is now **Level 2** (75px, 9 gates). Level 1 road width tuned 140 → **100px**
    (still wider/easier than L2). Levels 3–5 removed. `game_data.gd` holds
    `TRACK_1`/`TRACK_2` and each level references its own `track`; `game.gd` builds `lv["track"]`.
  - **Orientation:** phone now runs **portrait** (`window/handheld/orientation="portrait"`),
    desktop opens **maximized** (`window/size/mode=2`); stretch stays `canvas_items`/`expand` so the
    HUD adapts to either aspect.
  - **Fixed the engine sound continuing after the race finishes** (also during countdown/pause):
    `engine_audio.gd` now silences whenever the car's physics processing is off.
  - Verified in Godot 4.7: both tracks build (L1 6 gates / L2 9 gates), clean import/run.
- **Juice / game feel (roadmap #5).** Added **skid marks** laid by the rear wheels when drifting
  (handbrake or oversteer; pooled Line2Ds in a world-space `TireMarks` node), **dust** off the rear
  while sliding (`CPUParticles2D` on the Car), **screen shake** on wall impacts (decaying camera
  offset), a **gate scale-pop + flash** when a checkpoint is passed (`checkpoint.gd` `pop()`), and
  **3-2-1 countdown beeps + a GO tone** (new `beep.wav`/`go.wav` from `tools/generate_sfx.py`).
  Skid detection: handbrake always lays rubber; big oversteer (`|lateral| > 70`) also does. Verified
  in Godot 4.7 — skid marks generate on a handbrake drift, no NaN/errors through a full race.
- **Shorter lap.** Scaled the `TRACK` centerline to ~0.72 about its centroid (same twisty shape,
  ~¾ the length) so a 3-lap race isn't a slog; trimmed medal target times to match. Road width and
  speeds unchanged. Re-previewed clean (no folds), spawn still on-road, headless run clean.
- **Fixed car spawning off the track.** The start position was extrapolated in a straight line
  behind the start gate, which lands off-road where the track curves into the start (obvious on
  the narrow road). `track_builder.gd` now spawns the car **on a centerline sample** just behind
  the line (`START_BACK_SAMPLES`), so it's always on the road, facing along the track.
- **Tighter, faster, twistier circuit (tuning).** Redesigned the `TRACK` centerline in
  `game_data.gd` into a **brutally narrow** (`road_width` 320 → **75**, ~2.5× the car) and much
  curvier loop — a top straight plus esses down the right, an undulating bottom, and esses up the
  left (**9 gates**) — so steering is constant and you must brake for corners. Bumped per-level
  car speed (`max_speed` ~340–580 → **520–860**, accel to match) and eased the camera (`Car.tscn`
  `zoom` 1.6 → 1.4). Shape verified via `tools/preview_track.py`; clean headless import/run in
  Godot 4.7. Medal target times are rough — retune after a drive.
- **Real circuit + 3-lap races (replaces the open arena).** New **data-driven track system**:
  `scripts/track_builder.gd` builds the road band, kerb lines, wall colliders on both edges, and
  the checkpoint gates from a shared closed **centerline** (`game_data.gd` `TRACK`; preview it with
  `tools/preview_track.py`). `Main.tscn` drops the rectangular arena for a green background + a
  generated `Track`. Each level is now a **3-lap race**: gates hit in order, crossing the
  start/finish gate (gate 0) = one lap; `game.gd` tracks lap count + lap time + **best lap** (HUD
  shows `Lap x/3`, a lap timer, and best lap that flashes on a new best). Saves best total
  (medal/unlock) **and** best lap; medal targets are now 3-lap totals. Bigger map with the camera
  **zoomed in** (`Car.tscn` `zoom = 1.6`) — you see the road ahead, not the whole map. Verified in
  Godot 4.7: clean import/run + a lap-logic test (21 gate passes = 3 laps → finish).
- **Sim-ish car handling — rewrote the physics (`scripts/car.gd`).** Replaced the arcade port
  (kinematic yaw + averaged grip + global-damping handbrake) with a **dynamic dual-axle
  slip-angle bicycle model**: momentum/weight (`yaw_inertia`), steering that stiffens with speed
  (`high_speed_lock`), per-axle tyre grip you can **overdrive into a slide/spin** (`grip_accel`,
  `cornering_stiffness_front/rear`), and a handbrake that frees the **rear** (`handbrake_rear_grip`)
  for drifts. Drive is applied along the wheel directions so the four-wheel-steer **crab/pivot**
  hook still works; a low-speed blend to kinematic steering keeps parking stable. Per-level
  `max_speed`/`accel_force` and `game.gd`'s interface are unchanged. Removed the arcade-only
  exports (`tire_grip`, `drift_threshold`, `turn_speed_reduction`, `four_wheel_speed_reduction`).
  Verified in Godot 4.7: clean headless import + a scripted throttle/steer/tight-turn run with no
  NaN (speed bleeds correctly in corners). *Feel still needs an in-editor drive + tuning pass.*
- **Levels, progression, menus, pause, and audio (big update).** Turned the single endless
  time-trial into a structured game.
  - New autoload **`Game`** (`scripts/game_data.gd`): a 5-level table with rising top speed
    (340 → 580), distinct checkpoint layouts, and gold/silver/bronze target times; per-level
    best time + medal and level unlocks; master volume. Saved to `user://save.json` (replaces
    the old single `besttime.save`).
  - **Flow**: `MainMenu → LevelSelect → Race → Results (medal + Retry/Next/Menu)`. New
    `MainMenu.tscn`/`main_menu.gd` and `LevelSelect.tscn`/`level_select.gd`; main scene is now
    the menu.
  - **Race refactor** (`Main.tscn` + `game.gd`): checkpoints are spawned from the level data
    (no longer hardcoded), the car's `max_speed`/`accel_force` are set per level, a **3-2-1-GO
    countdown** gates the start, and there's a **manual pause** (Esc/P) — no fail state.
    Finishing awards a medal and unlocks the next level.
  - **HUD** (`hud.gd`): speedometer, an off-screen **next-checkpoint arrow** (screen angle =
    `world_angle − car.rotation`, so it works with the rotating camera), countdown text, and
    the Results + Pause panels (buttons emit a `ui_action` signal).
  - **Audio**: procedural WAV SFX generated by `tools/generate_sfx.py` into `audio/` — engine
    loop pitched by speed (`engine_audio.gd` on the Car), checkpoint chime, finish fanfare.
    Loads are guarded so the game still runs if audio is missing.
  - **Verified** in Godot 4.7: headless import + headless runs of MainMenu, LevelSelect, and
    the race scene are all error-free.
- **Driving feel tuned (`scripts/car.gd`).** Wheels turn faster (`steer_sensitivity` 2.5 → 5.0);
  higher straight-line top speed (`max_speed` 210 → 340, `accel_force` 200 → 300). Added a
  dynamic speed limit that bleeds speed off in turns: new exports `turn_speed_reduction` (0.25 =
  25% off for a normal one-axle turn) and `four_wheel_speed_reduction` (0.35 = 35% off when both
  axles steer / all four wheels turn), scaling smoothly with steering amount in
  `_speed_limit_factor()`. (Per user request — numbers chosen within the 20–30% / 35% guidance.)
- **Camera now rotates with the car (north-up heading-lock).** Set `ignore_rotation = false`
  on the Car's `Camera2D` (`scenes/Car.tscn`) so the car's front always points up on screen
  and the world rotates around it. Controls become forward-relative (W always drives "up").
  The HUD/touch controls are on `CanvasLayer`s, so they stay screen-aligned. (Per user request.)
- **Camera locked rigidly to the car.** Removed position smoothing from the Car's `Camera2D`
  (`scenes/Car.tscn`) so the camera is glued to the car with no follow-lag — the world scrolls
  and the car stays centered. (Replaced the earlier smoothed/floaty follow, per user request.)
- **Documentation process established.** Added `CLAUDE.md` with a rule to update docs after
  every major change, and created this changelog.
- **Initial build.** Godot 4 dual-axle steering car game:
  - `car.gd` — dual-wheel-steering physics ported from the browser version
    (`../game/CAR_PHYSICS_DOCUMENTATION.md` + `src/systems/physics.js`): per-axle force along
    each wheel's heading, lateral tire-grip, dynamic max steer (55° aligned / 45° opposed),
    reverse, 50% speed loss on wall hits.
  - `input_state.gd` — autoload merging keyboard and touch into one steering model.
  - Scenes: `Main` (arena, walls, 5 checkpoints, HUD, touch controls), `Car`, `Checkpoint`,
    `HUD`, `TouchControls`.
  - `game.gd` — checkpoint ordering, timer, finish, best-time persistence, restart.
  - Android-ready: landscape, `gl_compatibility` renderer, two bottom steering sliders +
    GAS/REV buttons, `export_presets.cfg`.
  - Verified running in Godot 4.7.
