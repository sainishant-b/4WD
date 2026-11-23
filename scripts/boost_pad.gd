extends Area2D
## A boost pad, laid on the road by track_builder.gd: a dark plate of gold
## chevrons with a wave of light running through them in the direction of
## travel, glowing on the night asphalt. Driving over it calls the car's
## `hit_boost_pad(forward)`. The node is turned so local +x points along the road.

const LENGTH := 92.0

var width := 64.0
var _t := 0.0
var _glow: Sprite2D
var _plate: StyleBoxFlat
var _rim: StyleBoxFlat


## Sizes the pad for a road `road_width` px wide (it covers about 60% of it,
## centred) and gives it its trigger area.
func setup(road_width: float) -> void:
	width = clampf(road_width * 0.6, 46.0, 72.0)
	var shape := RectangleShape2D.new()
	shape.size = Vector2(LENGTH, width)
	var col := CollisionShape2D.new()
	col.shape = shape
	add_child(col)

	var add := CanvasItemMaterial.new()
	add.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	_glow = Sprite2D.new()
	_glow.texture = HudStyle.glow()
	_glow.material = add
	_glow.scale = Vector2(LENGTH, width) * 2.0 / _glow.texture.get_size()
	_glow.modulate = Color(Palette.GOLD, 0.3)
	_glow.show_behind_parent = true
	add_child(_glow)

	_plate = StyleBoxFlat.new()
	_plate.bg_color = Palette.BG_RAISED
	_plate.set_corner_radius_all(10)
	_plate.set_border_width_all(3)
	_plate.border_color = Palette.INK
	_plate.anti_aliasing = true
	_rim = StyleBoxFlat.new()
	_rim.draw_center = false
	_rim.set_corner_radius_all(7)
	_rim.set_border_width_all(2)
	_rim.border_color = Palette.GOLD_DEEP
	_rim.anti_aliasing = true

	body_entered.connect(_on_body_entered)


func _process(delta: float) -> void:
	_t += delta
	_glow.modulate.a = 0.24 + 0.1 * sin(_t * 6.0)
	queue_redraw()


func _draw() -> void:
	if _plate == null:
		return
	var rect := Rect2(-LENGTH * 0.5, -width * 0.5, LENGTH, width)
	draw_style_box(_plate, rect)
	draw_style_box(_rim, rect.grow(-5.0))
	var half := width * 0.5 - 10.0
	for i in 3:
		var lit := 0.5 + 0.5 * sin(_t * 9.0 - i * 1.7)
		_chevron(-LENGTH * 0.5 + 13.0 + i * 25.0, half, Palette.GOLD_DEEP.lerp(Palette.GOLD_BRIGHT, lit))


## One chevron pointing +x, its back edge at `x`.
func _chevron(x: float, half: float, color: Color) -> void:
	const DEPTH := 15.0
	const THICK := 9.0
	var pts := PackedVector2Array([
		Vector2(x, -half), Vector2(x + THICK, -half), Vector2(x + THICK + DEPTH, 0),
		Vector2(x + THICK, half), Vector2(x, half), Vector2(x + DEPTH, 0),
	])
	draw_colored_polygon(pts, color)
	pts.append(pts[0])
	draw_polyline(pts, Palette.INK, 1.5, true)


func _on_body_entered(body: Node) -> void:
	if body.has_method("hit_boost_pad"):
		body.hit_boost_pad(Vector2.RIGHT.rotated(global_rotation))
