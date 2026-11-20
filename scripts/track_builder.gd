class_name TrackBuilder
extends RefCounted
## Builds a racetrack from a closed loop of waypoints: a smooth centre line, a
## shaded road ribbon edged with red-and-white kerbs and an INK casing over a
## drop shadow (so the road looks raised off the field), limit lines, wall
## colliders on both edges, the checkpoint gates and any obstacles.
##
## Centre-line pipeline (`centerline()`; tools/preview_track.py mirrors it):
##   1. a centripetal Catmull-Rom spline through the waypoints. Unlike the
##      uniform kind it cannot overshoot or kink where two waypoints sit close
##      together,
##   2. resampled to evenly spaced points, `SPACING` px apart,
##   3. relaxed wherever a bend is tighter than half the road width plus
##      `BEND_MARGIN`, so the inside edge of the road can never fold over itself.
## Gates, obstacles and the start slot are located on the raw spline by their
## "t" (0..1 round the waypoints) and snapped to the nearest centre-line point.

const SPLINE_STEPS := 48     # spline evaluations per waypoint segment
const SPACING := 10.0        # px between centre-line points
const BEND_MARGIN := 24.0    # tightest bend radius = half the road width + this
const RELAX_PASSES := 400    # upper bound; the tracks settle in well under 100
const RELAX_SPREAD := 3      # neighbours either side of a tight point that also ease
const GATE_DEPTH := 28.0
const START_BACK := 60.0     # px behind the start line where the car spawns

const LIMIT_WIDTH := 5.0     # solid white limit line just outside each wall: its inner edge IS the wall ...
const KERB_WIDTH := 9.0      # ... then a red/white kerb ...
const CASING_WIDTH := 4.0    # ... then an INK casing (all three must stay under BEND_MARGIN)
const KERB_BLOCK := 2        # centre-line points per kerb block (so ~20 px blocks)
const SHADOW_DROP := Vector2(0, 14)   # how far the road's shadow falls on the field
const SHADE_WIDTH := 16.0    # darkened strip of road beside each wall
const GROUND_MARGIN := 900.0 # how far the ground grid reaches past the track
const GRID_STEP := 120.0
const DASH_ON := 4           # centre-line points per lane dash ...
const DASH_PERIOD := 10      # ... out of every this many

const ConeScene := preload("res://scenes/Cone.tscn")
const RampScene := preload("res://scenes/Ramp.tscn")


# --- Centre line -----------------------------------------------------------

static func _centripetal(p0: Vector2, p1: Vector2, p2: Vector2, p3: Vector2, u: float) -> Vector2:
	# Barry-Goldman form with knots spaced by the square root of the chord length.
	var t0 := 0.0
	var t1 := t0 + sqrt(maxf(p0.distance_to(p1), 0.0001))
	var t2 := t1 + sqrt(maxf(p1.distance_to(p2), 0.0001))
	var t3 := t2 + sqrt(maxf(p2.distance_to(p3), 0.0001))
	var t := lerpf(t1, t2, u)
	var a1 := p0.lerp(p1, (t - t0) / (t1 - t0))
	var a2 := p1.lerp(p2, (t - t1) / (t2 - t1))
	var a3 := p2.lerp(p3, (t - t2) / (t3 - t2))
	var b1 := a1.lerp(a2, (t - t0) / (t2 - t0))
	var b2 := a2.lerp(a3, (t - t1) / (t3 - t1))
	return b1.lerp(b2, (t - t1) / (t2 - t1))


## The raw spline at `t` (0..1 = once round the waypoints, each segment an
## equal share). This is the scale gates and obstacles are placed on.
static func spline_point(waypoints: Array, t: float) -> Vector2:
	var n := waypoints.size()
	var f := fposmod(t, 1.0) * n
	var i := int(f) % n
	return _centripetal(
		waypoints[(i - 1 + n) % n], waypoints[i], waypoints[(i + 1) % n], waypoints[(i + 2) % n],
		f - floorf(f)
	)


## Evenly spaced copy of a closed polyline.
static func resample(points: PackedVector2Array, spacing: float) -> PackedVector2Array:
	var n := points.size()
	var total := 0.0
	for i in n:
		total += points[i].distance_to(points[(i + 1) % n])
	var count := maxi(8, roundi(total / spacing))
	var step := total / count
	var out := PackedVector2Array()
	var seg := 0
	var seg_start := 0.0
	var seg_len := points[0].distance_to(points[1])
	for k in count:
		var d := k * step
		while seg_start + seg_len < d and seg < n - 1:
			seg_start += seg_len
			seg += 1
			seg_len = points[seg].distance_to(points[(seg + 1) % n])
		var w := 0.0 if seg_len < 0.000001 else (d - seg_start) / seg_len
		out.append(points[seg].lerp(points[(seg + 1) % n], w))
	return out


## Radius of the circle through three points (INF when they are in line).
static func bend_radius(a: Vector2, b: Vector2, c: Vector2) -> float:
	var cross := absf((b - a).cross(c - a))
	if cross < 0.000001:
		return INF
	return a.distance_to(b) * b.distance_to(c) * c.distance_to(a) / (2.0 * cross)


## Eases every bend tighter than `min_radius` by sliding its points toward the
## midpoint of their neighbours. Only the tight spots move; the rest of the
## line is left exactly where the spline put it.
static func _relax(points: PackedVector2Array, min_radius: float) -> PackedVector2Array:
	var pts := points
	for pass_i in RELAX_PASSES:
		var n := pts.size()
		var tight := PackedByteArray()
		tight.resize(n)
		var any_tight := false
		for i in n:
			if bend_radius(pts[(i - 1 + n) % n], pts[i], pts[(i + 1) % n]) < min_radius:
				tight[i] = 1
				any_tight = true
		if not any_tight:
			break
		var next := pts.duplicate()
		for i in n:
			var near := false
			for k in range(-RELAX_SPREAD, RELAX_SPREAD + 1):
				if tight[(i + k + n) % n] == 1:
					near = true
					break
			if near:
				var mid := (pts[(i - 1 + n) % n] + pts[(i + 1) % n]) * 0.5
				next[i] = pts[i].lerp(mid, 0.5)
		pts = next
		if pass_i % 8 == 7:
			pts = resample(pts, SPACING)   # keep the spacing even so radii stay meaningful
	return pts


## The finished centre line of a track dict: closed, evenly spaced, and never
## bending tighter than the road can follow.
static func centerline(track: Dictionary) -> PackedVector2Array:
	var waypoints: Array = track["centerline"]
	var dense := PackedVector2Array()
	var total := waypoints.size() * SPLINE_STEPS
	for i in total:
		dense.append(spline_point(waypoints, float(i) / float(total)))
	var hw := float(track["road_width"]) * 0.5
	var line := _relax(resample(dense, SPACING), hw + BEND_MARGIN)
	return resample(line, SPACING)


static func tangent(points: PackedVector2Array, i: int) -> Vector2:
	var n := points.size()
	var t := points[(i + 1) % n] - points[(i - 1 + n) % n]
	return t.normalized() if t.length() > 0.0001 else Vector2.RIGHT


## Copy of a closed line pushed sideways by `distance` px (+ = left of travel).
static func offset(points: PackedVector2Array, distance: float) -> PackedVector2Array:
	var out := PackedVector2Array()
	out.resize(points.size())
	for i in points.size():
		var t := tangent(points, i)
		out[i] = points[i] + Vector2(-t.y, t.x) * distance
	return out


static func nearest(points: PackedVector2Array, to: Vector2) -> int:
	var best := 0
	var best_d := INF
	for i in points.size():
		var d := points[i].distance_squared_to(to)
		if d < best_d:
			best_d = d
			best = i
	return best


# --- Build -----------------------------------------------------------------

## Builds road/wall nodes under `road_parent` and gate instances under `cp_parent`.
## Returns { checkpoints, car_start_pos, car_start_rot, centerline, gate_points,
## half_width }; the last three feed the HUD's mini map.
static func build(track: Dictionary, road_parent: Node2D, cp_parent: Node2D, cp_scene: PackedScene, obstacle_parent: Node2D = null) -> Dictionary:
	var waypoints: Array = track["centerline"]
	var hw: float = float(track["road_width"]) * 0.5
	var line := centerline(track)
	var n := line.size()
	var left := offset(line, hw)
	var right := offset(line, -hw)

	_build_ground(road_parent, line)
	_build_surface(road_parent, line, hw)
	_build_lane_dashes(road_parent, line)

	# Limit lines + wall colliders on both edges.
	var walls := StaticBody2D.new()
	road_parent.add_child(walls)
	for side in [1.0, -1.0]:
		var edge: PackedVector2Array = left if side > 0.0 else right
		# The hard limit line: solid white, wholly outside the road, so where the
		# green meets it is exactly the wall. The car's collision box covers its
		# tyres, so a tyre touching this line is a wall hit.
		var limit := Line2D.new()
		limit.points = offset(line, side * (hw + LIMIT_WIDTH * 0.5))
		limit.closed = true
		limit.width = LIMIT_WIDTH
		limit.antialiased = true
		limit.default_color = Palette.TEXT_LIGHT
		road_parent.add_child(limit)

		var col := CollisionPolygon2D.new()
		col.polygon = edge
		col.build_mode = CollisionPolygon2D.BUILD_SEGMENTS
		walls.add_child(col)

	# Checkpoint gates, an equal share of the waypoints apart; gate 0 = start/finish.
	var checkpoints: Array = []
	var gate_points := PackedVector2Array()
	var count: int = int(track["checkpoint_count"])
	for j in count:
		var idx := nearest(line, spline_point(waypoints, float(j) / float(count)))
		var cp := cp_scene.instantiate()
		cp.index = j
		cp.position = line[idx]
		cp.rotation = tangent(line, idx).angle()
		cp_parent.add_child(cp)
		cp.configure_gate(hw * 2.0, GATE_DEPTH)
		checkpoints.append(cp)
		gate_points.append(line[idx])

	# Obstacles (optional): cones / swerve-walls / ramps placed along the centre line.
	if obstacle_parent != null:
		_build_obstacles(track, line, obstacle_parent)

	# Car start: ON the centre line a little behind the start/finish line. Walking
	# back along the line (not a straight extrapolation) keeps the spawn on the
	# road even where the track curves into the start.
	var start_idx := nearest(line, spline_point(waypoints, 0.0))
	var si := posmod(start_idx - roundi(START_BACK / SPACING), n)
	return {
		"checkpoints": checkpoints,
		"car_start_pos": line[si],
		"car_start_rot": tangent(line, si).angle() + PI / 2.0,
		"centerline": line,
		"gate_points": gate_points,
		"half_width": hw,
	}


# --- Looks -----------------------------------------------------------------

## The field the track sits on: deep cobalt with a faint white grid, so there
## is something to read your speed against away from the road.
static func _build_ground(parent: Node2D, line: PackedVector2Array) -> void:
	var bounds := Rect2(line[0], Vector2.ZERO)
	for p in line:
		bounds = bounds.expand(p)
	bounds = bounds.grow(GROUND_MARGIN)
	var ground := Node2D.new()
	ground.draw.connect(func() -> void:
		ground.draw_rect(bounds, Palette.FIELD)
		var minor := Color(Palette.TEXT_LIGHT, 0.05)
		var major := Color(Palette.TEXT_LIGHT, 0.09)
		var x0 := ceilf(bounds.position.x / GRID_STEP)
		var x1 := floorf(bounds.end.x / GRID_STEP)
		for gx in range(int(x0), int(x1) + 1):
			var x := gx * GRID_STEP
			ground.draw_line(
				Vector2(x, bounds.position.y), Vector2(x, bounds.end.y),
				major if gx % 4 == 0 else minor, 2.0, true
			)
		var y0 := ceilf(bounds.position.y / GRID_STEP)
		var y1 := floorf(bounds.end.y / GRID_STEP)
		for gy in range(int(y0), int(y1) + 1):
			var y := gy * GRID_STEP
			ground.draw_line(
				Vector2(bounds.position.x, y), Vector2(bounds.end.x, y),
				major if gy % 4 == 0 else minor, 2.0, true
			)
	)
	parent.add_child(ground)


## The drivable surface as meshes of ribbons running round the circuit: a hard
## shadow dropped onto the field, an INK casing, red-and-white kerbs outside
## each wall, a darker strip of road beside each wall, and a slightly lifted
## crown down the middle. Vertex colours do the blending.
static func _build_surface(parent: Node2D, line: PackedVector2Array, hw: float) -> void:
	var shade := minf(SHADE_WIDTH, hw * 0.45)
	var crown := Palette.TRACK.lightened(0.07)
	var inner := hw + LIMIT_WIDTH   # the kerb starts where the limit line ends
	var kerb := inner + KERB_WIDTH
	var outer := kerb + CASING_WIDTH
	var rails := {}   # offset -> PackedVector2Array, so shared rails are computed once
	for d in [outer, kerb, inner, hw, hw - shade, 0.0, -(hw - shade), -hw, -inner, -kerb, -outer]:
		rails[d] = offset(line, d)

	# The shadow: the whole road's footprint in translucent black, dropped.
	var shadow_mesh := ArrayMesh.new()
	var dark := Color(Palette.BLACK, 0.5)
	_add_ribbon(shadow_mesh, rails[outer], rails[-outer], dark, dark)
	var shadow := MeshInstance2D.new()
	shadow.mesh = shadow_mesh
	shadow.position = SHADOW_DROP
	parent.add_child(shadow)

	# Casing and kerbs go under the road, so where two legs of a hairpin sit
	# close, the road always covers the other leg's kerb rather than the reverse.
	var edges := ArrayMesh.new()
	_add_ribbon(edges, rails[outer], rails[kerb], Palette.INK, Palette.INK)
	_add_ribbon(edges, rails[-kerb], rails[-outer], Palette.INK, Palette.INK)
	_add_kerb(edges, rails[kerb], rails[inner])
	_add_kerb(edges, rails[-inner], rails[-kerb])
	var edge_node := MeshInstance2D.new()
	edge_node.mesh = edges
	parent.add_child(edge_node)

	# (offset from the centre line, colour) rails; consecutive pairs make a ribbon.
	var bands := [
		[hw, Palette.TRACK_EDGE, hw - shade, Palette.TRACK],
		[hw - shade, Palette.TRACK, 0.0, crown],
		[0.0, crown, -(hw - shade), Palette.TRACK],
		[-(hw - shade), Palette.TRACK, -hw, Palette.TRACK_EDGE],
	]
	var mesh := ArrayMesh.new()
	for band in bands:
		_add_ribbon(mesh, rails[band[0]], rails[band[2]], band[1], band[3])
	var surface := MeshInstance2D.new()
	surface.mesh = mesh
	parent.add_child(surface)


## Adds a kerb between rails `a` and `b` to `mesh`: blocks of `KERB_BLOCK`
## centre-line points, alternating red and white.
static func _add_kerb(mesh: ArrayMesh, a: PackedVector2Array, b: PackedVector2Array) -> void:
	var n := a.size()
	var verts := PackedVector2Array()
	var colors := PackedColorArray()
	for i in n:
		var k := (i + 1) % n
		var color := Palette.KERB if floori(float(i) / KERB_BLOCK) % 2 == 0 else Palette.TEXT_LIGHT
		for p in [a[i], b[i], b[k], a[i], b[k], a[k]]:
			verts.append(p)
			colors.append(color)
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_COLOR] = colors
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)


## Adds a closed triangle-strip ribbon between rails `a` and `b` to `mesh`.
static func _add_ribbon(mesh: ArrayMesh, a: PackedVector2Array, b: PackedVector2Array, color_a: Color, color_b: Color) -> void:
	var n := a.size()
	var verts := PackedVector2Array()
	var colors := PackedColorArray()
	for i in n + 1:
		var k := i % n
		verts.append(a[k])
		colors.append(color_a)
		verts.append(b[k])
		colors.append(color_b)
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_COLOR] = colors
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLE_STRIP, arrays)


## Dashed centre lane stripes down the middle of the road.
static func _build_lane_dashes(parent: Node2D, line: PackedVector2Array) -> void:
	var n := line.size()
	var at := 0
	while at + DASH_ON < n:
		var dash := Line2D.new()
		dash.width = 4.0
		dash.antialiased = true
		dash.begin_cap_mode = Line2D.LINE_CAP_ROUND
		dash.end_cap_mode = Line2D.LINE_CAP_ROUND
		dash.default_color = Color(Palette.GOLD, 0.55)
		for k in range(at, at + DASH_ON + 1):
			dash.add_point(line[k])
		parent.add_child(dash)
		at += DASH_PERIOD


# --- Obstacles -------------------------------------------------------------
# Each entry: { "type": "cone"|"wall"|"ramp", "t": 0..1 along the centerline,
# "offset": lateral px from it (+/- across the road), plus per-type fields }.

static func _build_obstacles(track: Dictionary, line: PackedVector2Array, parent: Node2D) -> void:
	var obstacles: Array = track.get("obstacles", [])
	var waypoints: Array = track["centerline"]
	for ob in obstacles:
		var idx := nearest(line, spline_point(waypoints, float(ob.get("t", 0.0))))
		var tang := tangent(line, idx)
		var nrm := Vector2(-tang.y, tang.x)
		var world: Vector2 = line[idx] + nrm * float(ob.get("offset", 0.0))
		match String(ob.get("type", "")):
			"wall":
				_make_swerve_wall(parent, world, tang.angle(), ob)
			"cone":
				_make_cone(parent, world, tang.angle(), ob)
			"ramp":
				_make_ramp(parent, world, tang.angle(), ob)
			_:
				push_warning("TrackBuilder: unknown obstacle type '%s'" % ob.get("type", ""))


## A short barrier jutting across part of the lane (local x = along road, y = across).
## Reuses the car's normal wall collision (layer 1). Alternate the offset to slalom.
static func _make_swerve_wall(parent: Node2D, pos: Vector2, ang: float, ob: Dictionary) -> void:
	var thick := float(ob.get("thick", 24.0))
	var jut := float(ob.get("jut", 70.0))
	var body := StaticBody2D.new()
	body.position = pos
	body.rotation = ang
	var col := CollisionShape2D.new()
	var shape := RectangleShape2D.new()
	shape.size = Vector2(thick, jut)
	col.shape = shape
	body.add_child(col)
	var rect := PackedVector2Array([
		Vector2(-thick / 2.0, -jut / 2.0), Vector2(thick / 2.0, -jut / 2.0),
		Vector2(thick / 2.0, jut / 2.0), Vector2(-thick / 2.0, jut / 2.0),
	])
	# A shadow under the barrier, then the barrier with a lit top face.
	var shadow := Polygon2D.new()
	shadow.polygon = rect
	shadow.position = Vector2(3.0, 4.0)
	shadow.color = Color(Palette.BLACK, 0.35)
	body.add_child(shadow)
	var vis := Polygon2D.new()
	vis.polygon = rect
	vis.color = Palette.DANGER_DEEP
	body.add_child(vis)
	HudStyle.feather(vis)
	var top := Polygon2D.new()
	var inset := minf(4.0, thick * 0.2)
	top.polygon = PackedVector2Array([
		Vector2(-thick / 2.0 + inset, -jut / 2.0 + inset), Vector2(thick / 2.0 - inset, -jut / 2.0 + inset),
		Vector2(thick / 2.0 - inset, jut / 2.0 - inset), Vector2(-thick / 2.0 + inset, jut / 2.0 - inset),
	])
	top.color = Palette.DANGER
	body.add_child(top)
	parent.add_child(body)


static func _make_cone(parent: Node2D, pos: Vector2, ang: float, ob: Dictionary) -> void:
	var c := ConeScene.instantiate()
	c.position = pos
	c.rotation = ang
	parent.add_child(c)
	c.configure(bool(ob.get("solid", false)))


static func _make_ramp(parent: Node2D, pos: Vector2, ang: float, ob: Dictionary) -> void:
	var r := RampScene.instantiate()
	r.position = pos
	r.rotation = ang
	if ob.has("dur"):
		r.jump_duration = float(ob["dur"])
	parent.add_child(r)
