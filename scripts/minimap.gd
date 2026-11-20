extends Control
## Mini map: the whole circuit at a glance on a deep-blue screen set into a
## cream panel. North stays up (the map does not turn with the camera), so the
## shape of the lap is always the same picture; the car is an arrow that turns
## instead.
##
## Shows the track (green with white edges), the start/finish line, every gate
## (the next one in gold, pulsing) and the player's car in red. game.gd feeds
## it through the HUD: `set_track()` once, then `set_next_gate()` and
## `set_car()` as the race runs.

const PADDING := 15.0      # clear space between the panel edge and the track
const SCREEN_INSET := 6.0  # cream rim round the deep-blue screen
const STRIDE := 2          # draw every Nth centre-line point (plenty at this size)

var _world_line := PackedVector2Array()
var _world_gates := PackedVector2Array()
var _line := PackedVector2Array()     # the same, in map space
var _gates := PackedVector2Array()
var _start_dir := Vector2.RIGHT       # direction of travel across the start line
var _scale: float = 1.0
var _origin := Vector2.ZERO
var _next: int = -1
var _car := Vector2.ZERO
var _heading: float = 0.0
var _has_car: bool = false
var _panel: StyleBoxFlat
var _screen: StyleBoxFlat


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_panel = HudStyle.panel(12)
	_screen = HudStyle.pill(Palette.BG_RAISED, 8)


func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED:
		_refit()


func _process(_delta: float) -> void:
	if _next >= 0 and is_visible_in_tree():
		queue_redraw()   # keeps the next gate pulsing, even before GO


## `centerline` and `gates` are in world space; gate 0 is the start/finish line.
func set_track(centerline: PackedVector2Array, gates: PackedVector2Array) -> void:
	_world_line = centerline
	_world_gates = gates
	_refit()


func set_next_gate(index: int) -> void:
	_next = index
	queue_redraw()


## `heading` is the car's rotation (0 = pointing up, as everywhere else).
func set_car(world_pos: Vector2, heading: float) -> void:
	_car = world_pos
	_heading = heading
	_has_car = true
	queue_redraw()


func _to_map(world: Vector2) -> Vector2:
	return _origin + world * _scale


## Scales the circuit to fill the panel (keeping its proportions) and centres it.
func _refit() -> void:
	_line = PackedVector2Array()
	_gates = PackedVector2Array()
	if _world_line.size() < 3 or size.x <= PADDING * 2.0 or size.y <= PADDING * 2.0:
		queue_redraw()
		return
	var bounds := Rect2(_world_line[0], Vector2.ZERO)
	for p in _world_line:
		bounds = bounds.expand(p)
	var room := size - Vector2(PADDING, PADDING) * 2.0
	_scale = minf(room.x / maxf(bounds.size.x, 1.0), room.y / maxf(bounds.size.y, 1.0))
	_origin = size * 0.5 - bounds.get_center() * _scale
	for i in range(0, _world_line.size(), STRIDE):
		_line.append(_to_map(_world_line[i]))
	_line.append(_line[0])   # close the loop
	for g in _world_gates:
		_gates.append(_to_map(g))
	if _world_gates.size() > 0:
		var n := _world_line.size()
		var at := 0
		var best := INF
		for i in n:
			var d := _world_line[i].distance_squared_to(_world_gates[0])
			if d < best:
				best = d
				at = i
		_start_dir = (_world_line[(at + 1) % n] - _world_line[(at - 1 + n) % n]).normalized()
	queue_redraw()


func _draw() -> void:
	draw_style_box(_panel, Rect2(Vector2.ZERO, size))
	draw_style_box(_screen, Rect2(Vector2.ZERO, size).grow(-SCREEN_INSET))
	if _line.size() < 3:
		return

	# The track: green road with white edges, like the real one.
	draw_polyline(_line, Palette.TEXT_LIGHT, 5.5, true)
	draw_polyline(_line, Palette.TRACK, 3.0, true)

	# Gates still to come this lap are small dots; the next one glows gold.
	var pulse := 0.5 + 0.5 * sin(Time.get_ticks_msec() / 1000.0 * 5.0)
	for i in _gates.size():
		if i == 0 or i == _next:
			continue
		draw_circle(_gates[i], 2.0, Palette.TEXT_LIGHT, true, -1.0, true)

	# Start/finish: a short dark bar across the white-edged road.
	if _gates.size() > 0:
		var across := Vector2(-_start_dir.y, _start_dir.x) * 5.0
		draw_line(_gates[0] - across, _gates[0] + across, Palette.BLACK, 2.5, true)

	if _next >= 0 and _next < _gates.size():
		var g := _gates[_next]
		HudStyle.draw_glow(self, g, 9.0 + pulse * 4.0, Color(Palette.GOLD, 0.55))
		draw_circle(g, 3.6, Palette.INK, true, -1.0, true)
		draw_circle(g, 2.6, Palette.GOLD, true, -1.0, true)

	# The car: a red arrow with a white rim, pointing where the car points.
	if _has_car:
		var at := _to_map(_car)
		var fwd := Vector2.from_angle(_heading - PI / 2.0)
		var side := Vector2(-fwd.y, fwd.x)
		HudStyle.draw_glow(self, at, 11.0, Color(Palette.POP, 0.5))
		var rim := PackedVector2Array([at + fwd * 7.5, at - fwd * 5.0 + side * 5.5, at - fwd * 2.0, at - fwd * 5.0 - side * 5.5])
		var body := PackedVector2Array([at + fwd * 5.5, at - fwd * 3.6 + side * 3.8, at - fwd * 1.6, at - fwd * 3.6 - side * 3.8])
		draw_colored_polygon(rim, Palette.TEXT_LIGHT)
		rim.append(rim[0])
		draw_polyline(rim, Palette.TEXT_LIGHT, 1.0, true)   # feathers the polygon's edge
		draw_colored_polygon(body, Palette.POP)
