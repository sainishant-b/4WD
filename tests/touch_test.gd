extends SceneTree
# Headless check of the twin thumb pads: feeds real multi-touch events through
# Godot's input pipeline into the race scene and asserts what InputState (and
# the car) receive. Run:
#   godot --headless --fixed-fps 60 --path . -s tests/touch_test.gd
#
# This folder is .gdignore'd, so the test is never imported or exported.

const TRAVEL := 52.0

# Untyped on purpose: these are autoload scripts, looked up at run time.
var _input_state
var _layout
var _failures := 0


func _initialize() -> void:
	_run.call_deferred()


func _check(label: String, ok: bool, detail := "") -> void:
	if ok:
		print("  ok    ", label)
	else:
		_failures += 1
		print("  FAIL  ", label, "  ", detail)


func _near(a: float, b: float) -> bool:
	return absf(a - b) < 0.02


func _frames(n: int) -> void:
	for i in n:
		await process_frame


# Positions below are logical (what the game sees). Parsed events are taken as
# window pixels and scaled by the stretch transform, so convert on the way in.
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


## A real mouse (device 0), not one copied from a touch.
func _mouse(pos: Vector2, pressed: bool) -> void:
	var e := InputEventMouseButton.new()
	e.button_index = MOUSE_BUTTON_LEFT
	e.position = root.get_final_transform() * pos
	e.global_position = e.position
	e.pressed = pressed
	Input.parse_input_event(e)


func _mouse_move(pos: Vector2) -> void:
	var e := InputEventMouseMotion.new()
	e.position = root.get_final_transform() * pos
	e.global_position = e.position
	e.button_mask = MOUSE_BUTTON_MASK_LEFT
	Input.parse_input_event(e)


func _key(code: Key) -> void:
	for down in [true, false]:
		var e := InputEventKey.new()
		e.keycode = code
		e.physical_keycode = code
		e.pressed = down
		Input.parse_input_event(e)


func _state() -> String:
	return "front=%.2f rear=%.2f thr=%.2f boost=%s hb=%s" % [
		_input_state.touch_front, _input_state.touch_rear, _input_state.touch_throttle,
		_input_state.touch_boost, _input_state.touch_handbrake,
	]


func _run() -> void:
	_input_state = root.get_node("/root/InputState")
	_layout = root.get_node("/root/Layout")
	root.size = Vector2i(1280, 720)
	change_scene_to_file("res://scenes/Main.tscn")
	await _frames(3)

	var touch_layer = current_scene.get_node("TouchControls")
	var hud = current_scene.get_node("HUD")
	var view: Vector2 = _layout.view_size()
	print("view ", view, "  portrait=", _layout.portrait, "  touch=", _layout.touch)

	print("device switching")
	_check("starts in keyboard mode on desktop", not _layout.touch and not touch_layer.visible)
	_touch(0, Vector2(100, 600), true)
	await _frames(2)
	_touch(0, Vector2(100, 600), false)
	await _frames(2)
	_check("first touch switches to touch mode and shows the pads", _layout.touch and touch_layer.visible)

	var left := Vector2(140, view.y - 120)
	var right := Vector2(view.x - 140, view.y - 120)

	print("steering")
	_touch(0, left, true)
	_touch(1, right, true)
	await _frames(2)
	_check("resting thumbs do nothing", _near(_input_state.touch_front, 0) and _near(_input_state.touch_rear, 0)
		and _near(_input_state.touch_throttle, 0) and not _input_state.touch_boost and not _input_state.touch_handbrake, _state())

	_drag(0, left + Vector2(TRAVEL * 0.6, 0))
	await _frames(2)
	_check("left pad right -> front wheels only", _near(_input_state.touch_front, (0.6 - 0.1) / 0.9)
		and _near(_input_state.touch_rear, 0) and _near(_input_state.touch_throttle, 0), _state())

	_drag(1, right + Vector2(-TRAVEL * 2.0, 0))
	await _frames(2)
	_check("right pad far left -> rear wheels full lock", _near(_input_state.touch_rear, -1.0), _state())
	_drag(0, left)
	_drag(1, right)
	await _frames(2)

	print("throttle / boost")
	_drag(0, left + Vector2(0, -TRAVEL * 0.6))
	await _frames(2)
	_check("one pad up -> partial throttle, no boost", _near(_input_state.touch_throttle, (0.6 - 0.22) / 0.78)
		and not _input_state.touch_boost and not _input_state.touch_handbrake, _state())

	_drag(0, left + Vector2(0, -TRAVEL * 0.15))
	await _frames(2)
	_check("small vertical wobble is ignored", _near(_input_state.touch_throttle, 0), _state())

	_drag(0, left + Vector2(0, -TRAVEL * 1.2))
	await _frames(2)
	_check("one pad fully up -> full throttle, still no boost", _near(_input_state.touch_throttle, 1.0)
		and not _input_state.touch_boost, _state())

	_drag(1, right + Vector2(0, -TRAVEL * 0.6))
	await _frames(2)
	_check("second pad only part-way up -> no boost yet", not _input_state.touch_boost, _state())

	_drag(1, right + Vector2(0, -TRAVEL * 1.2))
	await _frames(2)
	_check("both pads fully up -> boost", _input_state.touch_boost and _near(_input_state.touch_throttle, 1.0), _state())

	print("drift / brake")
	_drag(1, right + Vector2(0, TRAVEL * 0.8))
	await _frames(2)
	_check("one up + one down -> handbrake with throttle (power drift)", _input_state.touch_handbrake
		and _near(_input_state.touch_throttle, 1.0) and not _input_state.touch_boost, _state())

	_drag(0, left)
	await _frames(2)
	_check("one down, other neutral -> handbrake, no throttle", _input_state.touch_handbrake
		and _near(_input_state.touch_throttle, 0), _state())

	_drag(1, right + Vector2(0, TRAVEL * 0.3))
	await _frames(2)
	_check("a slight pull down is not a drift", not _input_state.touch_handbrake, _state())

	_drag(0, left + Vector2(0, TRAVEL * 0.8))
	_drag(1, right + Vector2(0, TRAVEL * 0.8))
	await _frames(2)
	_check("both down -> brake/reverse, handbrake off", _near(_input_state.touch_throttle, -1.0)
		and not _input_state.touch_handbrake and not _input_state.touch_boost, _state())

	print("finger bookkeeping")
	_touch(2, left + Vector2(30, 30), true)        # third finger on a held pad
	_drag(2, left + Vector2(30, -200))
	await _frames(2)
	_check("extra finger on a held pad is ignored", _near(_input_state.touch_throttle, -1.0), _state())
	_touch(2, Vector2.ZERO, false)

	_touch(0, Vector2.ZERO, false)
	await _frames(2)
	_check("lifting one thumb leaves the other pad working", _input_state.touch_handbrake
		and _near(_input_state.touch_throttle, 0) and _near(_input_state.touch_front, 0), _state())
	_touch(1, Vector2.ZERO, false)
	await _frames(2)
	_check("lifting both returns everything to zero", _near(_input_state.touch_throttle, 0)
		and not _input_state.touch_handbrake and _near(_input_state.touch_rear, 0), _state())

	_touch(3, Vector2(200, 80), true)              # top of the screen: not a pad
	_drag(3, Vector2(200, 10))
	await _frames(2)
	_check("touches above the pad zone are ignored", _near(_input_state.touch_throttle, 0), _state())
	_touch(3, Vector2.ZERO, false)

	print("driving")
	await _frames(240)                              # 3-2-1 countdown, then GO
	var car = get_first_node_in_group("car")
	_check("car exists and is stopped at GO", car != null and car.velocity.length() < 1.0)
	_touch(0, left, true)
	_touch(1, right, true)
	# Kept short: the road bends soon after the start line and nobody is steering.
	_drag(0, left + Vector2(0, -TRAVEL * 1.2))
	await _frames(24)
	var cruising: float = car.velocity.length()
	_check("one pad up drives the car forward", cruising > 100.0, "speed=%.0f" % cruising)
	var meter_before: float = car.boost_meter
	_drag(1, right + Vector2(0, -TRAVEL * 1.2))
	await _frames(12)
	var fast: float = car.velocity.length()
	_check("both pads up burns the boost meter and adds speed",
		car.boost_meter < meter_before - 0.1 and fast > cruising + 60.0,
		"meter %.2f -> %.2f, speed %.0f -> %.0f" % [meter_before, car.boost_meter, cruising, fast])
	_drag(0, left + Vector2(0, TRAVEL * 0.8))
	_drag(1, right + Vector2(0, TRAVEL * 0.8))
	await _frames(15)
	_check("both pads down slows the car", car.velocity.length() < fast - 80.0,
		"speed %.0f -> %.0f" % [fast, car.velocity.length()])

	print("pause")
	hud.ui_action.emit("pause")
	await _frames(3)
	_check("pausing releases the pads", _near(_input_state.touch_throttle, 0) and not _input_state.touch_handbrake, _state())
	_drag(0, left + Vector2(0, -TRAVEL * 1.2))
	await _frames(2)
	_check("pads stay inert while paused", _near(_input_state.touch_throttle, 0), _state())
	hud.ui_action.emit("resume")
	await _frames(2)
	_touch(0, Vector2.ZERO, false)
	_touch(1, Vector2.ZERO, false)

	print("portrait")
	root.size = Vector2i(390, 760)
	await _frames(4)
	view = _layout.view_size()
	_check("a tall window switches to the portrait base", _layout.portrait
		and root.content_scale_size == Vector2i(430, 760), "scale_size=%s" % root.content_scale_size)
	_check("portrait logical size is at least 430 x 760", view.x >= 429.0 and view.y >= 759.0, "view=%s" % view)

	print("mouse in a phone-shaped window (a desktop browser's mobile view)")
	_key(KEY_X)
	await _frames(2)
	_check("a key press goes back to keyboard mode and hides the pads", not _layout.touch and not touch_layer.visible)
	_mouse(Vector2(view.x * 0.5, 200), true)
	_mouse(Vector2(view.x * 0.5, 200), false)
	await _frames(2)
	_check("a mouse click in a portrait window shows the pads", _layout.touch and touch_layer.visible)
	var pad_at := Vector2(100, view.y - 120)
	_mouse(pad_at, true)
	_mouse_move(pad_at + Vector2(TRAVEL * 0.6, -TRAVEL * 1.2))
	await _frames(2)
	_check("the mouse drags a pad like a thumb", _near(_input_state.touch_front, (0.6 - 0.1) / 0.9)
		and _near(_input_state.touch_throttle, 1.0), _state())
	_mouse(pad_at, false)
	await _frames(2)
	_check("letting go of the mouse releases the pad", _near(_input_state.touch_front, 0)
		and _near(_input_state.touch_throttle, 0), _state())
	_touch(5, pad_at, true)
	await _frames(2)
	_check("a touch is not counted twice (its copied mouse event is ignored)",
		touch_layer._pads[0].finger == 5, "finger=%d" % touch_layer._pads[0].finger)
	_touch(5, pad_at, false)

	root.size = Vector2i(1280, 720)
	await _frames(4)
	_check("a wide window switches back", not _layout.portrait and root.content_scale_size == Vector2i(1280, 720))
	_key(KEY_X)
	await _frames(2)
	_mouse(Vector2(640, 600), true)
	_mouse(Vector2(640, 600), false)
	await _frames(2)
	_check("a mouse click in a wide window stays in keyboard mode", not _layout.touch)

	print("menus rebuild in both layouts")
	for scene in ["MainMenu", "Instructions", "LevelSelect", "Leaderboard"]:
		change_scene_to_file("res://scenes/%s.tscn" % scene)
		await _frames(3)
		root.size = Vector2i(390, 760)
		await _frames(3)
		var portrait_children := current_scene.get_child_count()
		root.size = Vector2i(1280, 720)
		await _frames(3)
		_check("%s rebuilt for portrait and back" % scene,
			portrait_children > 0 and current_scene.get_child_count() == portrait_children,
			"children %d vs %d" % [portrait_children, current_scene.get_child_count()])

	print("RESULT: ", "ALL PASSED" if _failures == 0 else "%d FAILED" % _failures)
	quit(1 if _failures > 0 else 0)
