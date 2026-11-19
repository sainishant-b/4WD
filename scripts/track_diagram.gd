class_name TrackDiagram
extends Control
## A picture of a whole circuit for menus: the green road with its white edges
## at true proportions, the chequered start/finish line, and a gold arrow for
## the direction of travel. North is up, as on the in-race mini map.
##
##   var map := TrackDiagram.new()
##   map.track = Game.get_level(i)["track"]
##   map.custom_minimum_size = Vector2(360, 240)

const PADDING := 14.0        # clear space round the circuit
const MIN_ROAD := 6.0        # px: the road never draws thinner than this
const EDGE := 1.5            # px of white limit line each side of the road
const STRIDE := 2            # draw every Nth centre-line point (plenty at menu size)

## The level's track dict (`game_data.gd` TRACK_n). Setting it redraws.
var track: Dictionary = {}:
	set(value):
		track = value
		_world = TrackBuilder.centerline(track) if not track.is_empty() else PackedVector2Array()
		_start = 0
		if _world.size() > 0:
			_start = TrackBuilder.nearest(_world, TrackBuilder.spline_point(track["centerline"], 0.0))
		queue_redraw()

var _world := PackedVector2Array()
var _start: int = 0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	resized.connect(queue_redraw)


func _draw() -> void:
	var n := _world.size()
	if n < 3 or size.x <= PADDING * 2.0 or size.y <= PADDING * 2.0:
		return
	var bounds := Rect2(_world[0], Vector2.ZERO)
	for p in _world:
		bounds = bounds.expand(p)
	var road_world := float(track["road_width"])
	# Fit the circuit plus its road width inside the padding.
	var room := size - Vector2(PADDING, PADDING) * 2.0
	var span := bounds.size + Vector2(road_world, road_world)
	var fit := minf(room.x / maxf(span.x, 1.0), room.y / maxf(span.y, 1.0))
	var origin := size * 0.5 - bounds.get_center() * fit
	var road := maxf(road_world * fit, MIN_ROAD)

	var line := PackedVector2Array()
	for i in range(0, n, STRIDE):
		line.append(origin + _world[i] * fit)
	line.append(line[0])

	# A soft shadow under the whole circuit, then the casing, edges and road.
	HudStyle.draw_glow(self, size * 0.5 + Vector2(0, 6), minf(size.x, size.y) * 0.62, Color(Palette.BLACK, 0.45))
	draw_polyline(line, Palette.BLACK, road + EDGE * 2.0 + 4.0, true)
	draw_polyline(line, Palette.TEXT, road + EDGE * 2.0, true)
	draw_polyline(line, Palette.TRACK, road, true)

	# Start/finish: a chequered band across the road.
	var at := origin + _world[_start] * fit
	var along := TrackBuilder.tangent(_world, _start)
	var across := Vector2(-along.y, along.x)
	var cells := 4
	var cell := (road + EDGE * 2.0) / cells
	for row in 2:
		for c in cells:
			var o := at + across * (-(road + EDGE * 2.0) * 0.5 + cell * c) + along * (cell * (row - 1))
			var quad := PackedVector2Array([o, o + across * cell, o + across * cell + along * cell, o + along * cell])
			draw_colored_polygon(quad, Palette.TEXT if (row + c) % 2 == 0 else Palette.BLACK)

	# Which way to drive: a gold chevron a little past the line.
	var ahead := int(maxf(road * 3.0, 24.0) / maxf(fit * TrackBuilder.SPACING, 0.01))
	var k := (_start + ahead) % n
	var tip_at := origin + _world[k] * fit
	var dir := TrackBuilder.tangent(_world, k)
	var side := Vector2(-dir.y, dir.x)
	var r := maxf(road * 0.55, 5.0)
	var chevron := PackedVector2Array([
		tip_at + dir * r, tip_at - dir * r * 0.7 + side * r, tip_at - dir * r * 0.2,
		tip_at - dir * r * 0.7 - side * r,
	])
	draw_colored_polygon(chevron, Palette.GOLD)
	chevron.append(chevron[0])
	draw_polyline(chevron, Palette.GOLD, 1.0, true)
