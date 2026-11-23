extends Node2D
## The player's car as drawn (car.gd adds it as "Look"; it only draws, car.gd
## owns the physics). An open-wheel racer: the four steered wheels stand clear
## of the body so both axles can be seen turning, the body is the player's
## red-orange outlined in INK like every raised thing in Cobalt & Sun, and a
## gold-helmeted driver sits in the cockpit.
##
## Its lights suit the night circuit: headlight beams and a red underglow
## (additive), tail lights that flare on the brakes, and an exhaust flame while
## boosting. In the air (`set_air`, the dormant obstacle ramps' hop) it grows
## toward the camera.
##
## Car-local space: -y is forward. Its footprint (wheels included) matches the
## car's collision box in Car.tscn, 38 x 60, centred at (0, -2).

const WHEEL_X := 16.0
const WHEEL_FRONT_Y := -18.0
const WHEEL_REAR_Y := 21.0
const WHEEL := Rect2(-3.0, -7.0, 6.0, 14.0)
const OUTLINE := 1.6

const FRONT_WING := [Vector2(-17, -27), Vector2(-17, -30), Vector2(-5, -32), Vector2(5, -32), Vector2(17, -30), Vector2(17, -27)]
const NOSE := [Vector2(-3.5, -31), Vector2(3.5, -31), Vector2(6.5, -14), Vector2(-6.5, -14)]
const POD := [
	Vector2(-6.5, -15), Vector2(6.5, -15), Vector2(11, -8), Vector2(12.5, 6), Vector2(10.5, 16),
	Vector2(5, 22), Vector2(-5, 22), Vector2(-10.5, 16), Vector2(-12.5, 6), Vector2(-11, -8),
]
const DECK := [
	Vector2(-4.5, -12.5), Vector2(4.5, -12.5), Vector2(8.6, -6.5), Vector2(9.8, 5), Vector2(8, 13),
	Vector2(3.5, 18.5), Vector2(-3.5, 18.5), Vector2(-8, 13), Vector2(-9.8, 5), Vector2(-8.6, -6.5),
]
const COCKPIT := [Vector2(-4.5, -9), Vector2(4.5, -9), Vector2(5.5, 1), Vector2(3.5, 6), Vector2(-3.5, 6), Vector2(-5.5, 1)]
const REAR_WING := [Vector2(-12, 22.5), Vector2(12, 22.5), Vector2(12, 28), Vector2(-12, 28)]

var front_steer := 0.0
var rear_steer := 0.0
var braking := false
var flame := 0.0           # 0..1: how hard the exhaust is burning (boost)

var _t := 0.0
var _airborne := false
var _glow: Sprite2D        # red underglow
var _beams: Node2D         # headlight cones
var _tail_glow: Sprite2D
var _flame_glow: Sprite2D


func _ready() -> void:
	var add := CanvasItemMaterial.new()
	add.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD

	_glow = _glow_sprite(add, Vector2(0, -2), Vector2(84, 104), Color(Palette.POP_BRIGHT, 0.5))
	_glow.show_behind_parent = true

	_beams = Node2D.new()
	_beams.material = add
	_beams.show_behind_parent = true
	add_child(_beams)
	for x in [-10.0, 10.0]:
		var beam := Polygon2D.new()
		beam.polygon = PackedVector2Array([
			Vector2(x - 2.5, -31), Vector2(x + 2.5, -31), Vector2(x + 26.0, -170), Vector2(x - 26.0, -170),
		])
		var near := Color(Palette.LAMP, 0.26)
		var far := Color(Palette.LAMP, 0.0)
		beam.vertex_colors = PackedColorArray([near, near, far, far])
		beam.use_parent_material = true
		_beams.add_child(beam)

	_tail_glow = _glow_sprite(add, Vector2(0, 28), Vector2(56, 26), Color(Palette.DANGER, 0.25))
	_flame_glow = _glow_sprite(add, Vector2(0, 36), Vector2(40, 52), Color(Palette.GOLD, 0.0))


func _glow_sprite(mat: Material, pos: Vector2, size: Vector2, color: Color) -> Sprite2D:
	var s := Sprite2D.new()
	s.texture = HudStyle.glow()
	s.material = mat
	s.position = pos
	s.scale = size / s.texture.get_size()
	s.modulate = color
	add_child(s)
	return s


func _process(delta: float) -> void:
	_t += delta
	_glow.modulate.a = 0.0 if _airborne else 0.42 + 0.08 * sin(_t * 5.0)
	_beams.visible = not _airborne
	_tail_glow.modulate.a = 0.75 if braking else 0.22
	_flame_glow.modulate.a = 0.7 * flame
	queue_redraw()


## Height above the road: 0 on the ground .. 1 at the top of a hop.
func set_air(height: float) -> void:
	_airborne = height > 0.0
	scale = Vector2.ONE * (1.0 + height * 0.45)


func _draw() -> void:
	if flame > 0.01:
		_draw_flame()

	# Suspension arms first, so the wheels and body sit over them.
	for sx in [-1.0, 1.0]:
		draw_line(Vector2(sx * 6.0, -17.0), Vector2(sx * WHEEL_X, WHEEL_FRONT_Y), Palette.INK, 2.4, true)
		draw_line(Vector2(sx * 7.0, 19.0), Vector2(sx * WHEEL_X, WHEEL_REAR_Y), Palette.INK, 2.4, true)
	for sx in [-1.0, 1.0]:
		_draw_wheel(Vector2(sx * WHEEL_X, WHEEL_FRONT_Y), front_steer)
		_draw_wheel(Vector2(sx * WHEEL_X, WHEEL_REAR_Y), rear_steer)

	_shape(FRONT_WING, Palette.POP_DEEP)
	for sx in [-1.0, 1.0]:   # gold end plates on the front wing
		_shape([Vector2(sx * 15.0, -30.5), Vector2(sx * 18.5, -30.5), Vector2(sx * 18.5, -26.5), Vector2(sx * 15.0, -26.5)], Palette.GOLD)
		draw_rect(Rect2(sx * 10.0 - 2.0, -31.2, 4.0, 1.8), Palette.SURFACE)   # headlight
	_shape(NOSE, Palette.POP)
	_shape(POD, Palette.POP_DEEP)
	_fill(DECK, Palette.POP)
	for sx in [-1.0, 1.0]:   # side-pod intakes
		_fill([Vector2(sx * 11.0, -6.5), Vector2(sx * 8.6, -6.5), Vector2(sx * 8.8, -0.5), Vector2(sx * 11.6, -0.5)], Palette.INK)
	_fill([Vector2(-1.4, -30), Vector2(1.4, -30), Vector2(1.9, -15), Vector2(-1.9, -15)], Palette.GOLD)   # nose stripe
	_fill([Vector2(-1.7, 8), Vector2(1.7, 8), Vector2(1.3, 21), Vector2(-1.3, 21)], Palette.GOLD)        # engine-cover stripe
	_shape(COCKPIT, Palette.INK)
	draw_circle(Vector2(0, -2.5), 3.8, Palette.GOLD, true, -1.0, true)                 # the driver's helmet
	draw_circle(Vector2(0, -2.5), 3.8, Palette.INK, false, 1.2, true)
	draw_rect(Rect2(-2.4, -5.6, 4.8, 1.6), Palette.INK)                                # visor
	draw_circle(Vector2(-1.2, -1.4), 1.0, Color(Palette.TEXT_LIGHT, 0.7), true, -1.0, true)   # helmet glint
	draw_line(Vector2(-3.8, -8.2), Vector2(3.8, -8.2), Color(Palette.TEXT_LIGHT, 0.35), 1.2, true)   # screen glint

	_shape(REAR_WING, Palette.INK)
	_fill([Vector2(-11, 23.4), Vector2(11, 23.4), Vector2(11, 25.4), Vector2(-11, 25.4)], Palette.POP)
	var tail := Palette.DANGER if braking else Palette.DANGER_DEEP
	for x in [-8.0, 0.0, 8.0]:
		draw_rect(Rect2(x - 1.8, 26.2, 3.6, 1.6), tail)
	for sx in [-1.0, 1.0]:
		_fill([Vector2(sx * 11.0, 22.0), Vector2(sx * 13.0, 22.0), Vector2(sx * 13.0, 28.5), Vector2(sx * 11.0, 28.5)], Palette.GOLD)


func _draw_wheel(at: Vector2, angle: float) -> void:
	draw_set_transform(at, angle)
	draw_rect(WHEEL.grow(0.8), Palette.INK)
	draw_rect(WHEEL, Palette.BLACK)
	for y in [-4.5, -1.5, 1.5, 4.5]:   # tread
		draw_line(Vector2(-3.0, y), Vector2(3.0, y), Color(Palette.TEXT_LIGHT, 0.13), 1.0)
	draw_rect(Rect2(-3.0, -7.0, 1.4, 14.0), Color(Palette.TEXT_LIGHT, 0.1))   # lit sidewall
	draw_set_transform_matrix(Transform2D.IDENTITY)


func _draw_flame() -> void:
	var flick := 0.75 + 0.25 * sin(_t * 47.0) * sin(_t * 31.0)
	var reach := (12.0 + 18.0 * flame) * flick
	draw_colored_polygon(PackedVector2Array([
		Vector2(-5.5, 27.5), Vector2(5.5, 27.5), Vector2(0, 28.0 + reach),
	]), Palette.POP_BRIGHT)
	draw_colored_polygon(PackedVector2Array([
		Vector2(-3.2, 27.5), Vector2(3.2, 27.5), Vector2(0, 28.0 + reach * 0.7),
	]), Palette.GOLD)
	draw_colored_polygon(PackedVector2Array([
		Vector2(-1.5, 27.5), Vector2(1.5, 27.5), Vector2(0, 28.0 + reach * 0.4),
	]), Palette.SURFACE)


## A filled shape with an INK outline (the outline also smooths its edges).
func _shape(points: Array, color: Color) -> void:
	var pts := PackedVector2Array(points)
	draw_colored_polygon(pts, color)
	pts.append(pts[0])
	draw_polyline(pts, Palette.INK, OUTLINE, true)


## A filled shape with a hairline of its own colour round it (smooth, no outline).
func _fill(points: Array, color: Color) -> void:
	var pts := PackedVector2Array(points)
	draw_colored_polygon(pts, color)
	pts.append(pts[0])
	draw_polyline(pts, color, 0.8, true)
