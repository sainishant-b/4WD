extends SceneTree
# Headless check of the track geometry: on every level (and the multiplayer
# track) the road edges must not fold over themselves, no bend may be tighter
# than the road can follow, and the gates / start slot must sit on the road.
# Run:
#   godot --headless --path . -s tests/track_test.gd
#
# This folder is .gdignore'd, so the test is never imported or exported.

var _failures := 0


func _initialize() -> void:
	_run.call_deferred()


func _check(label: String, ok: bool, detail := "") -> void:
	if ok:
		print("  ok    ", label)
	else:
		_failures += 1
		print("  FAIL  ", label, "  ", detail)


func _crosses(a: Vector2, b: Vector2, c: Vector2, d: Vector2) -> bool:
	var d1 := (d - c).cross(a - c)
	var d2 := (d - c).cross(b - c)
	var d3 := (b - a).cross(c - a)
	var d4 := (b - a).cross(d - a)
	return d1 * d2 < 0.0 and d3 * d4 < 0.0


## Number of places a closed polyline crosses itself.
func _folds(points: PackedVector2Array) -> int:
	var n := points.size()
	var hits := 0
	for i in n:
		for j in range(i + 2, n):
			if i == 0 and j == n - 1:
				continue
			if _crosses(points[i], points[(i + 1) % n], points[j], points[(j + 1) % n]):
				hits += 1
	return hits


func _run() -> void:
	# Untyped on purpose: autoloads and class_names are looked up at run time here.
	var game = root.get_node("/root/Game")
	var builder = load("res://scripts/track_builder.gd")

	var tracks := []
	for i in game.level_count():
		tracks.append([game.get_level(i)["name"], game.get_level(i)["track"]])
	tracks.append(["Multiplayer", game.MP_RACE["track"]])

	for entry in tracks:
		var track: Dictionary = entry[1]
		var hw: float = float(track["road_width"]) * 0.5
		print(entry[0], "  (road ", hw * 2.0, " px wide)")

		var line: PackedVector2Array = builder.centerline(track)
		var n := line.size()

		var tightest := INF
		var shortest := INF
		var longest := 0.0
		for i in n:
			tightest = minf(tightest, builder.bend_radius(line[(i - 1 + n) % n], line[i], line[(i + 1) % n]))
			var step := line[i].distance_to(line[(i + 1) % n])
			shortest = minf(shortest, step)
			longest = maxf(longest, step)
		_check("points are evenly spaced", shortest > 7.0 and longest < 13.0,
			"%.1f .. %.1f px" % [shortest, longest])
		# The relax pass aims for hw + BEND_MARGIN; the final resample can shave a little.
		_check("no bend tighter than the road can follow", tightest >= hw + builder.BEND_MARGIN - 4.0,
			"tightest radius %.1f, road half width %.1f" % [tightest, hw])

		var rim: float = hw + builder.KERB_WIDTH + builder.CASING_WIDTH
		for side in [["left edge", hw], ["right edge", -hw],
				["left kerb", rim], ["right kerb", -rim]]:
			var folds := _folds(builder.offset(line, side[1]))
			_check("%s does not fold over itself" % side[0], folds == 0, "%d crossings" % folds)

		# The road must not run into another part of itself. This is what bounds
		# how close the two legs of a hairpin may sit. Points near each other
		# along the lap are neighbours, not another part, so skip those.
		var skip := ceili(PI * (hw + builder.BEND_MARGIN) / builder.SPACING)
		var closest := INF
		for i in n:
			for j in range(i + skip, n):
				if n - (j - i) < skip:
					continue   # close together the other way round the loop
				closest = minf(closest, line[i].distance_squared_to(line[j]))
		closest = sqrt(closest)
		_check("the road keeps clear of itself", closest >= hw * 2.0 + 8.0,
			"two parts %.0f px apart, road is %.0f px wide" % [closest, hw * 2.0])

		# Build it for real and check where things landed.
		var holder := Node2D.new()
		root.add_child(holder)
		var roads := Node2D.new()
		var gates := Node2D.new()
		var obstacles := Node2D.new()
		holder.add_child(roads)
		holder.add_child(gates)
		holder.add_child(obstacles)
		var built: Dictionary = builder.build(
			track, roads, gates, load("res://scenes/Checkpoint.tscn"), obstacles)
		_check("one gate per checkpoint", built["checkpoints"].size() == int(track["checkpoint_count"]))

		var start: Vector2 = built["car_start_pos"]
		var start_idx: int = builder.nearest(line, start)
		_check("car starts on the centre line", line[start_idx].distance_to(start) < 0.5)
		var gate0: Vector2 = built["gate_points"][0]
		var back := start.distance_to(gate0)
		_check("car starts just behind the start line", back > 40.0 and back < 70.0, "%.0f px" % back)
		var ahead: Vector2 = Vector2.from_angle(float(built["car_start_rot"]) - PI / 2.0)
		_check("car faces the start line", ahead.dot((gate0 - start).normalized()) > 0.8)

		var expected: int = (track.get("obstacles", []) as Array).size()
		_check("every obstacle was built", obstacles.get_child_count() == expected,
			"%d of %d" % [obstacles.get_child_count(), expected])
		var stray := 0
		for ob in obstacles.get_children():
			var p: Vector2 = (ob as Node2D).position
			if line[builder.nearest(line, p)].distance_to(p) > hw:
				stray += 1
		_check("obstacles sit on the road", stray == 0, "%d off the road" % stray)

		holder.free()

	print("")
	print("%d failure(s)" % _failures)
	quit(1 if _failures > 0 else 0)
