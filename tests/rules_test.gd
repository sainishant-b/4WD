extends SceneTree
# Headless check of the level table and the three-wall-hits rule: drives the
# real car into real walls in the race scene and watches what game.gd counts.
# Run:
#   godot --headless --fixed-fps 60 --path . -s tests/rules_test.gd
#
# It never finishes a race, so it must leave the player's save file untouched
# (and checks that it did). This folder is .gdignore'd: never imported or exported.

const SAVE_PATH := "user://save.json"

var _failures := 0
var _car
var _race
var _line: PackedVector2Array
var _builder


func _initialize() -> void:
	_run.call_deferred()


func _check(label: String, ok: bool, detail := "") -> void:
	if ok:
		print("  ok    ", label)
	else:
		_failures += 1
		print("  FAIL  ", label, "  ", detail)


func _frames(n: int) -> void:
	for i in n:
		await physics_frame


func _save_text() -> String:
	return FileAccess.get_file_as_string(SAVE_PATH) if FileAccess.file_exists(SAVE_PATH) else ""


## Puts the car on the centre line at `fraction` of the lap, nose pointing at
## the wall on `side` (+1 left of travel, -1 right), and drives it into it.
func _ram(fraction: float, side: float, frames: int) -> void:
	var idx := int(_line.size() * fraction)
	var along: Vector2 = _builder.tangent(_line, idx)
	var toward: Vector2 = Vector2(-along.y, along.x) * side
	_car.position = _line[idx]
	_car.rotation = toward.angle() + PI / 2.0
	_car.ang_vel = 0.0
	_car.velocity = toward * 220.0
	await _frames(frames)


## Pushes again from wherever the car is now, along its nose.
func _push(frames: int) -> void:
	_car.velocity = Vector2.from_angle(_car.rotation - PI / 2.0) * 160.0
	await _frames(frames)


func _run() -> void:
	# Untyped on purpose: autoloads and scripts are looked up at run time here.
	var game = root.get_node("/root/Game")
	_builder = load("res://scripts/track_builder.gd")
	var save_before := _save_text()

	print("level table")
	_check("there are five levels", game.level_count() == 5, "%d" % game.level_count())
	var ids := {}
	var with_obstacles := 0
	for i in game.level_count():
		ids[game.level_id(i)] = true
		if game.get_level(i)["track"].has("obstacles"):
			with_obstacles += 1
		_check("%s runs three laps" % game.get_level(i)["name"], int(game.get_level(i)["laps"]) == 3)
	_check("every level has its own permanent id", ids.size() == game.level_count())
	_check("no level has obstacles (cones, walls, ramps)", with_obstacles == 0)
	_check("level 1 is always unlocked", game.is_unlocked(0))

	print("three wall hits")
	root.size = Vector2i(1280, 720)
	game.current_level = 0
	change_scene_to_file("res://scenes/Main.tscn")
	await _frames(240)   # 3-2-1 countdown, then GO
	_race = current_scene
	_car = get_first_node_in_group("car")
	var hud = _race.get_node("HUD")
	_line = _builder.centerline(game.get_level(0)["track"])
	_check("the race is running with no hits", _race._wall_touches == 0 and _race._state == 1,
		"hits=%d state=%d" % [_race._wall_touches, _race._state])

	await _ram(0.30, 1.0, 20)
	_check("first wall contact counts as hit 1", _race._wall_touches == 1, "hits=%d" % _race._wall_touches)
	_check("it warns and the race goes on", hud._warn_label.visible and _race._state == 1)
	_check("the HUD pips show 1 of 3", hud._wall_used == 1 and hud._wall_limit == 3)

	for i in 6:
		await _push(10)
	_check("grinding on the same wall is still one hit", _race._wall_touches == 1, "hits=%d" % _race._wall_touches)

	await _frames(150)   # sit against the wall well past the forgiveness window
	await _push(15)
	_check("resting on the wall, then pressing on, is still one hit", _race._wall_touches == 1,
		"hits=%d" % _race._wall_touches)

	await _frames(90)
	await _ram(0.55, -1.0, 20)
	_check("a fresh contact elsewhere is hit 2", _race._wall_touches == 2, "hits=%d" % _race._wall_touches)
	await _ram(0.56, 1.0, 20)   # straight across to the other wall, within a second
	_check("pinballing to the other wall right away is forgiven", _race._wall_touches == 2,
		"hits=%d" % _race._wall_touches)
	_check("still racing on the last warning", _race._state == 1)

	await _frames(90)
	await _ram(0.80, 1.0, 20)
	_check("the third hit ends the race", _race._wall_touches == 3 and _race._state == 2,
		"hits=%d state=%d" % [_race._wall_touches, _race._state])
	_check("the card says GAME OVER and offers no next level",
		hud._results_overlay.visible and hud._results_title.text == "GAME OVER" and not hud._results_next.visible,
		"title=%s" % hud._results_title.text)
	_check("the car is stopped", not _car.is_physics_processing())

	await _ram(0.10, 1.0, 20)
	_check("nothing more is counted after game over", _race._wall_touches == 3, "hits=%d" % _race._wall_touches)
	_check("the save file was not touched", _save_text() == save_before)

	print("")
	print("RESULT: ", "ALL PASSED" if _failures == 0 else "%d FAILED" % _failures)
	quit(1 if _failures > 0 else 0)
