extends SceneTree
# Headless check of the steering feel (the user, 2026-11-23: "the car over
# steers, the wheels are not coming back to 0 degrees fast enough"). Drives the
# real Car.tscn on an open floor (no walls) with Level 1's and Level 7's
# settings, through InputState like a thumb pad would, and checks that:
#   - letting go of a tap of full lock straightens the wheels at once and the
#     car stops turning soon after (no long spin on),
#   - holding a turn never speeds the car up,
#   - the steering, the pivot (axles opposed) and the handbrake still turn it.
# Run:
#   godot --headless --fixed-fps 60 --path . -s tests/handling_test.gd
# Run it after touching the steering, tyre or traction code in car.gd.
# This folder is .gdignore'd: never imported or exported.

var _failures := 0
var _car
var _input


func _initialize() -> void:
	_run.call_deferred()


func _check(label: String, ok: bool, detail := "") -> void:
	if ok:
		print("  ok    ", label, "  ", detail)
	else:
		_failures += 1
		print("  FAIL  ", label, "  ", detail)


func _frames(n: int) -> void:
	for i in n:
		await physics_frame


func _steer_input(front: float, rear: float, throttle: float, handbrake := false) -> void:
	_input.touch_front = front
	_input.touch_rear = rear
	_input.touch_throttle = throttle
	_input.touch_handbrake = handbrake


func _speed() -> float:
	return (_car.velocity as Vector2).length()


## A fresh car on an empty floor, up to its cruising speed.
func _fresh_car(level: Dictionary) -> void:
	if _car != null:
		_car.get_parent().queue_free()
		await _frames(2)
	var floor_node := Node2D.new()
	root.add_child(floor_node)
	current_scene = floor_node
	_car = load("res://scenes/Car.tscn").instantiate()
	_car.max_speed = level["max_speed"]
	_car.accel_force = level["accel_force"]
	floor_node.add_child(_car)
	_steer_input(0.0, 0.0, 1.0)
	await _frames(420)


## Holds the given steering for `hold` s; returns the degrees turned meanwhile.
func _hold(front: float, rear: float, hold: float, handbrake := false) -> float:
	var h0: float = _car.rotation
	_steer_input(front, rear, 1.0, handbrake)
	await _frames(int(hold * 60.0))
	return rad_to_deg(absf(wrapf(_car.rotation - h0, -PI, PI)))


## Lets go; returns [s until the wheels are straight, s until the spin is under
## 5 deg/s, degrees turned after letting go].
func _release() -> Array:
	var h0: float = _car.rotation
	_steer_input(0.0, 0.0, 1.0)
	var straight := INF
	var stopped := INF
	for i in 90:
		await physics_frame
		var t := (i + 1) / 60.0
		if straight == INF and absf(_car.front_steer) < 0.001 and absf(_car.rear_steer) < 0.001:
			straight = t
		if stopped == INF and absf(_car.ang_vel) < deg_to_rad(5.0):
			stopped = t
	return [straight, stopped, rad_to_deg(absf(wrapf(_car.rotation - h0, -PI, PI)))]


func _run() -> void:
	_input = root.get_node("/root/InputState")
	var game = root.get_node("/root/Game")
	for slot in [0, game.level_count() - 1]:
		var level: Dictionary = game.get_level(slot)
		print("%s (cruise and steering)" % level["name"])
		await _fresh_car(level)
		var cruise: float = _car.cruise_speed()
		_check("it cruises at the speed cruise_speed() says", absf(_speed() - cruise) < cruise * 0.03,
			"%.0f vs %.0f px/s" % [_speed(), cruise])
		_check("lock is full when stopped and high_speed_lock at cruise",
			is_equal_approx(_car.lock_factor(0.0), 1.0)
			and is_equal_approx(_car.lock_factor(cruise), _car.high_speed_lock))

		var tapped: float = await _hold(1.0, 0.0, 0.2)
		var after: Array = await _release()
		_check("a tap of full lock turns the car", tapped > 8.0, "%.1f deg" % tapped)
		_check("letting go straightens the wheels at once", after[0] <= 0.08, "%.2f s" % after[0])
		_check("and the car stops turning soon after", after[1] <= 0.25, "%.2f s" % after[1])
		_check("it turns only a little more after letting go", after[2] < 12.0,
			"%.1f deg (was 21-26 before 2026-11-23)" % after[2])

		await _frames(60)
		var before: float = _speed()
		var held: float = await _hold(1.0, 0.0, 1.0)
		_check("holding full lock goes round", held > 60.0, "%.0f deg in 1 s" % held)
		_check("holding a turn never speeds the car up", _speed() <= before * 1.02,
			"%.0f -> %.0f px/s" % [before, _speed()])
		await _release()

		await _frames(60)
		var light: float = await _hold(0.3, 0.0, 0.5)
		await _release()
		_check("a light touch still steers", light > 8.0, "%.1f deg in 0.5 s" % light)

		await _frames(60)
		var front_only: float = await _hold(1.0, 0.0, 0.3)
		await _release()
		await _frames(90)
		var pivot: float = await _hold(1.0, -1.0, 0.3)
		await _release()
		_check("opposed axles pivot harder than the front alone", pivot > front_only * 1.15,
			"%.1f vs %.1f deg in 0.3 s" % [pivot, front_only])

		await _frames(90)
		var plain: float = await _hold(1.0, 0.0, 0.5)
		await _release()
		await _frames(90)
		var drift: float = await _hold(1.0, 0.0, 0.5, true)
		await _release()
		_check("the handbrake swings the car round further", drift > plain,
			"%.1f vs %.1f deg in 0.5 s" % [drift, plain])

	_steer_input(0.0, 0.0, 0.0)
	print("handling: ", "all passed" if _failures == 0 else "%d FAILED" % _failures)
	quit(1 if _failures > 0 else 0)
