extends SceneTree
# Regenerates docs/screenshots/*.png: the race HUD (countdown, a boost pad, a
# wall-hit warning, game over, the hairpin levels) and every menu (main menu, settings,
# How to Play, level select, and as shown inside a Reddit post today's circuit,
# the results card and the leaderboard), at
# phone size (860x1520, i.e. the 430x760 layout at 2x) and desktop size.
#
# It needs a real window to render, and a normal (even hidden) window takes the
# keyboard focus and swallows whatever is being typed, so run it on its own
# invisible desktop with the helper beside this file (PowerShell):
#
#   .\tests\run_offscreen.ps1 -CommandLine '"<godot.exe>" --fixed-fps 60 --resolution 860x1520 --path "<project>" --log-file "<log>" -s tests/capture_screens.gd'
#
# It never finishes a race, so the save file is only read. This folder is
# .gdignore'd: never imported or exported.

var _layout
var _game
var _builder
var _out: String


func _initialize() -> void:
	_out = ProjectSettings.globalize_path("res://docs/screenshots")
	_run.call_deferred()


func _frames(n: int) -> void:
	for i in n:
		await process_frame


func _shot(name: String) -> void:
	await _frames(3)
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("%s/%s.png" % [_out, name])
	print("saved ", name)


func _touch(index: int, pos: Vector2, pressed: bool) -> void:
	var e := InputEventScreenTouch.new()
	e.index = index
	e.position = root.get_final_transform() * pos
	e.pressed = pressed
	Input.parse_input_event(e)


func _drag(index: int, pos: Vector2) -> void:
	var e := InputEventScreenDrag.new()
	e.index = index
	e.position = root.get_final_transform() * pos
	Input.parse_input_event(e)


## Any key press switches the UI to keyboard mode.
func _key() -> void:
	var key := InputEventKey.new()
	key.physical_keycode = KEY_F12
	key.pressed = true
	Input.parse_input_event(key)


func _race(level: int, wait: int) -> void:
	_game.current_level = level
	change_scene_to_file("res://scenes/Main.tscn")
	await _frames(wait)


## Parks the car on the centre line at `fraction` of the lap, facing along it.
func _place(level: int, fraction: float) -> void:
	var car = get_first_node_in_group("car")
	var line: PackedVector2Array = _builder.centerline(_game.get_level(level)["track"])
	var idx := int(line.size() * fraction)
	car.position = line[idx]
	car.rotation = _builder.tangent(line, idx).angle() + PI / 2.0
	car.velocity = Vector2.ZERO


## Puts the car on the centre line `back` px before `fraction` of the lap,
## heading along the road at `speed` px/s (to run it over a boost pad).
func _approach(level: int, fraction: float, back: float, speed: float) -> void:
	var car = get_first_node_in_group("car")
	var line: PackedVector2Array = _builder.centerline(_game.get_level(level)["track"])
	var n := line.size()
	var idx := posmod(int(n * fraction) - int(back / 10.0), n)
	var along: Vector2 = _builder.tangent(line, idx)
	car.position = line[idx]
	car.rotation = along.angle() + PI / 2.0
	car.velocity = along * speed
	car.ang_vel = 0.0


## Drives the car nose-first into the left wall at `fraction` of the lap and
## waits (up to a second) for the hit to count.
func _ram(level: int, fraction: float) -> void:
	var car = get_first_node_in_group("car")
	car._pad_t = 0.0   # no boost pad push left over
	var line: PackedVector2Array = _builder.centerline(_game.get_level(level)["track"])
	var idx := int(line.size() * fraction)
	var along: Vector2 = _builder.tangent(line, idx)
	var before: int = current_scene._wall_touches
	car.position = line[idx]
	car.rotation = along.angle() + PI / 2.0 + 0.6
	car.velocity = (along * 0.5 + Vector2(-along.y, along.x) * 0.87) * 260.0
	for i in 60:
		await _frames(1)
		if current_scene._wall_touches > before:
			break
	await _frames(6)


## A stand-in for the Devvit server, so the leaderboard shots have rows.
func _fake_server(_method: String, path: String, _body: Dictionary, done: Callable) -> void:
	var names := ["apex_hunter", "crabwalk", "local_driver", "late_braker", "four_by_four",
		"pivot_king", "sideways_sam", "gate_keeper"]
	var overall := path.contains("board=overall")
	var top: Array = []
	for i in names.size():
		var base := 301000 if overall else 58420
		var row := {"rank": i + 1, "name": names[i], "timeMs": base + i * (9130 if overall else 2470)}
		if FAKE_AVATARS.has(names[i]):
			row["avatar"] = "https://i.redd.it/snoovatar/avatars/%s.png" % names[i]
		top.append(row)
	done.call({
		"players": 132, "mapsDone": 5, "mapsTotal": 5, "top": top,
		"me": {"rank": 3, "name": "local_driver", "timeMs": int(top[2]["timeMs"])},
	})


## Pretend snoovatars (players without one show their initial).
const FAKE_AVATARS := {"apex_hunter": "e15948", "local_driver": "1f9a4f", "pivot_king": "ffc400"}


## A stand-in for the page's FWS.avatar: a tall full-body figure (like a
## snoovatar, the same one tools/serve-local.ts draws), cut to its top square
## and handed over as a base64 PNG, as reddit/src/client/avatar-image.ts does.
func _fake_avatar(url: String, done: Callable) -> void:
	var player := url.get_file().get_basename()
	var color: String = FAKE_AVATARS.get(player, "2346e0")
	var svg := ("<svg xmlns='http://www.w3.org/2000/svg' width='380' height='600' viewBox='0 0 380 600'>"
		+ "<rect x='70' y='250' width='240' height='300' rx='60' fill='#%s'/>" % color
		+ "<circle cx='190' cy='170' r='130' fill='#fff4dc' stroke='#0d1b55' stroke-width='12'/>"
		+ "<rect x='70' y='120' width='240' height='70' rx='30' fill='#%s' stroke='#0d1b55' stroke-width='10'/>" % color
		+ "<circle cx='150' cy='215' r='16' fill='#0d1b55'/><circle cx='230' cy='215' r='16' fill='#0d1b55'/></svg>")
	var image := Image.new()
	image.load_svg_from_string(svg, 96.0 / 380.0)
	var head := image.get_region(Rect2i(0, 0, image.get_width(), image.get_width()))
	done.call(Marshalls.raw_to_base64(head.save_png_to_buffer()))


## The menu screens: main menu, its settings card, level select, How to Play,
## and the leaderboard as it looks inside a Reddit post.
func _menus(prefix: String) -> void:
	change_scene_to_file("res://scenes/MainMenu.tscn")
	await _frames(6)
	await _shot(prefix + "-main-menu")
	current_scene._on_settings()
	await _shot(prefix + "-settings")
	for spec in [["Instructions", "how-to-play"], ["LevelSelect", "level-select"]]:
		change_scene_to_file("res://scenes/%s.tscn" % spec[0])
		await _frames(6)
		await _shot("%s-%s" % [prefix, spec[1]])
	_game.casual = true   # the casual list: every map, three laps
	change_scene_to_file("res://scenes/LevelSelect.tscn")
	await _frames(6)
	await _shot(prefix + "-casual")
	_game.casual = false
	var reddit = root.get_node("/root/Reddit")
	reddit.transport = _fake_server
	reddit.avatar_transport = _fake_avatar
	reddit.apply_init({"username": "local_driver", "day": 4, "levelId": _game.level_id(3),
		"avatar": "https://i.redd.it/snoovatar/avatars/local_driver.png"})
	change_scene_to_file("res://scenes/LevelSelect.tscn")   # Reddit: today's circuit only
	await _frames(6)
	await _shot(prefix + "-todays-circuit")
	# Reddit's results card, filled by hand: finishing a race would write the save.
	await _race(3, 5)
	var hud = current_scene.get_node("HUD")
	current_scene._touch.set_enabled(false)   # as a real finish does
	hud.show_results(42.18, "silver", 42.18, 42.18, false, 1)   # a ranked race: one lap
	hud.show_daily_pending()
	hud.show_daily_result({
		"accepted": true, "improved": true, "rank": 12, "players": 340, "streak": 4,
		"best_streak": 6, "next_ms": 5 * 3_600_000 + 12 * 60_000 + 9_000, "at_msec": Time.get_ticks_msec(),
	})
	await _shot(prefix + "-reddit-results")
	change_scene_to_file("res://scenes/Leaderboard.tscn")
	await _frames(6)
	await _shot(prefix + "-leaderboard")
	reddit.transport = Callable()
	reddit.avatar_transport = Callable()
	reddit.apply_init({"username": null, "day": 0, "levelId": -1})


func _run() -> void:
	_layout = root.get_node("/root/Layout")
	_game = root.get_node("/root/Game")
	_builder = load("res://scripts/track_builder.gd")

	# ---- Phone (2x), touch ----
	root.size = Vector2i(860, 1520)
	await _frames(5)
	await _race(0, 5)
	_touch(5, Vector2(200, 300), true)      # any touch switches the UI to touch mode
	_touch(5, Vector2(200, 300), false)
	await _frames(70)
	await _shot("mobile-countdown")
	await _frames(180)                      # past GO

	var view: Vector2 = _layout.view_size()
	var left := Vector2(90, view.y - 110)
	var right := Vector2(view.x - 90, view.y - 110)
	_touch(0, left, true)
	_touch(1, right, true)
	_drag(0, left + Vector2(10, -60))
	_drag(1, right + Vector2(0, -60))
	await _frames(26)
	await _shot("mobile-race")              # both pads up: boosting
	_touch(0, Vector2.ZERO, false)
	_touch(1, Vector2.ZERO, false)

	# Level 1's second boost pad.
	var track: Dictionary = _game.get_level(0)["track"]
	await _approach(0, track["boost_pads"][1], 140.0, 260.0)
	await _frames(22)
	await _shot("mobile-boost-pad")
	await _frames(60)

	await _ram(0, 0.20)
	await _shot("mobile-wall-warning")
	for fraction in [0.35, 0.47, 0.70, 0.80]:   # hits 2-5: the fifth ends it (clear of the pads and ramp)
		await _frames(90)
		await _ram(0, fraction)
		# Stop it grinding on the wall, so the next ram is a new hit, not the same one.
		get_first_node_in_group("car").velocity = Vector2.ZERO
	await _frames(20)
	await _shot("mobile-game-over")

	for spec in [[3, 0.36, "mobile-level4-hairpin"], [4, 0.82, "mobile-level5-switchback"], [6, 0.575, "mobile-level7-tongue"]]:
		await _race(spec[0], 200)
		_place(spec[0], spec[1])
		await _frames(40)
		await _shot(spec[2])

	await _menus("mobile")

	# ---- Desktop, keyboard ----
	root.size = Vector2i(1280, 720)
	_key()
	await _race(0, 250)
	await _shot("desktop-race")
	await _menus("desktop")
	quit()
