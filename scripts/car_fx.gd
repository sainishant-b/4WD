extends Node2D
## The player's car's effects and sounds (car.gd adds it as "Fx" and calls in):
##  - `contact`: sparks off a wall while the car scrapes it, and a grinding sound;
##  - `crash`: a counted wall hit: a burst of sparks, flying bits and a crunch;
##  - `update` (every physics step): tyre smoke on a slide, red light trails off
##    the tail lights when fast, and speed lines streaming past the screen;
##  - `boost_pad`: a whoosh; `launch`, `land` (the dormant obstacle ramps' hop):
##    a take-off swoop, then a dust ring and a thump.
## Particles are emitted into world space; this node sits in car space, which
## the camera follows (it turns with the car), so the speed lines it draws stay
## lined up with the screen. Sounds come from res://audio (tools/generate_sfx.py).

const TRAIL_POINTS := 16
const SPEED_LINES := 18

var car: CharacterBody2D

var _sparks: CPUParticles2D
var _burst: CPUParticles2D
var _bits: CPUParticles2D
var _smoke: CPUParticles2D
var _ring: CPUParticles2D
var _trails: Array = []          # two Line2D, world space
var _lines: Array = []           # speed lines: [Vector2 pos, float length]
var _line_k := 0.0               # 0..1, how strongly the speed lines show
var _line_dir := Vector2.UP      # which way the world streams past (car space)
var _since_contact := 1.0
var _sfx := {}
var _add: CanvasItemMaterial


func _ready() -> void:
	_add = CanvasItemMaterial.new()
	_add.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	var spark_tex := _streak_texture()

	_sparks = _particles(60, 0.35, false, spark_tex, true)
	_sparks.spread = 28.0
	_sparks.initial_velocity_min = 160.0
	_sparks.initial_velocity_max = 420.0
	_sparks.damping_min = 300.0
	_sparks.damping_max = 600.0
	_sparks.scale_amount_min = 0.7
	_sparks.scale_amount_max = 1.3
	_sparks.color_ramp = _ramp([Color.WHITE, Palette.GOLD_BRIGHT, Palette.POP, Color(Palette.POP, 0.0)], [0.0, 0.25, 0.65, 1.0])

	_burst = _particles(46, 0.6, true, spark_tex, true)
	_burst.spread = 75.0
	_burst.initial_velocity_min = 220.0
	_burst.initial_velocity_max = 560.0
	_burst.damping_min = 380.0
	_burst.damping_max = 700.0
	_burst.scale_amount_min = 1.0
	_burst.scale_amount_max = 1.9
	_burst.color_ramp = _sparks.color_ramp

	_bits = _particles(16, 0.8, true, null, false)
	_bits.spread = 90.0
	_bits.initial_velocity_min = 90.0
	_bits.initial_velocity_max = 300.0
	_bits.damping_min = 250.0
	_bits.damping_max = 400.0
	_bits.angular_velocity_min = -720.0
	_bits.angular_velocity_max = 720.0
	_bits.scale_amount_min = 3.0
	_bits.scale_amount_max = 6.0
	_bits.color_initial_ramp = _ramp([Palette.POP, Palette.GOLD, Palette.SURFACE, Palette.INK], [0.0, 0.3, 0.6, 1.0], true)
	_bits.color_ramp = _ramp([Color.WHITE, Color.WHITE, Color(1, 1, 1, 0)], [0.0, 0.7, 1.0])

	_smoke = _particles(28, 0.9, false, HudStyle.glow(), false)
	_smoke.top_level = false
	_smoke.position = Vector2(0, 22)
	_smoke.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
	_smoke.emission_rect_extents = Vector2(16, 3)
	_smoke.direction = Vector2(0, 1)
	_smoke.spread = 40.0
	_smoke.initial_velocity_min = 10.0
	_smoke.initial_velocity_max = 40.0
	_smoke.scale_amount_min = 0.12
	_smoke.scale_amount_max = 0.2
	_smoke.scale_amount_curve = _curve(0.6, 1.8)
	_smoke.color_ramp = _ramp([Color(0.78, 0.82, 0.95, 0.32), Color(0.78, 0.82, 0.95, 0.0)], [0.0, 1.0])

	_ring = _particles(26, 0.55, true, HudStyle.glow(), false)
	_ring.spread = 180.0
	_ring.initial_velocity_min = 150.0
	_ring.initial_velocity_max = 210.0
	_ring.damping_min = 280.0
	_ring.damping_max = 340.0
	_ring.scale_amount_min = 0.14
	_ring.scale_amount_max = 0.24
	_ring.color_ramp = _ramp([Color(0.85, 0.88, 1.0, 0.45), Color(0.85, 0.88, 1.0, 0.0)], [0.0, 1.0])

	for x in [-8.0, 8.0]:
		var t := Line2D.new()
		t.top_level = true
		t.width = 5.0
		t.material = _add
		t.begin_cap_mode = Line2D.LINE_CAP_ROUND
		t.end_cap_mode = Line2D.LINE_CAP_ROUND
		t.gradient = _ramp([Color(Palette.POP_BRIGHT, 0.0), Color(Palette.POP_BRIGHT, 0.55)], [0.0, 1.0])
		t.set_meta("x", x)
		_trails.append(t)
	_attach_trails.call_deferred()

	for i in SPEED_LINES:
		_lines.append([Vector2.ZERO, 0.0])
	z_index = 5   # the speed lines draw over the road and the car

	for spec in [["scrape", -12.0], ["crash", -2.0], ["boost", -4.0], ["jump", -6.0], ["land", -5.0]]:
		var player := AudioStreamPlayer.new()
		var stream: Resource = load("res://audio/%s.wav" % spec[0])
		if stream is AudioStreamWAV and spec[0] == "scrape":
			stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
			stream.loop_end = int(stream.get_length() * stream.mix_rate)
		player.stream = stream
		player.volume_db = spec[1]
		add_child(player)
		_sfx[spec[0]] = player


## The trails live in world space beside the car, ahead of it in the tree so
## the car draws over them.
func _attach_trails() -> void:
	var holder := car.get_parent()
	if holder == null:
		return
	for t in _trails:
		holder.add_child(t)
		holder.move_child(t, 0)


func _exit_tree() -> void:
	for t in _trails:
		if is_instance_valid(t):
			t.queue_free()


## A world-space particle emitter (`top_level`, so it is placed in world
## coordinates and its direction is a world direction).
func _particles(amount: int, life: float, one_shot: bool, tex: Texture2D, additive: bool) -> CPUParticles2D:
	var p := CPUParticles2D.new()
	p.top_level = true
	p.local_coords = false
	p.emitting = false
	p.one_shot = one_shot
	p.explosiveness = 1.0 if one_shot else 0.0
	p.amount = amount
	p.lifetime = life
	p.gravity = Vector2.ZERO
	p.texture = tex
	p.particle_flag_align_y = tex != null and tex.get_height() > tex.get_width()
	if additive:
		p.material = _add
	add_child(p)
	return p


## A short white streak, bright in the middle: a spark (stretched along its flight).
func _streak_texture() -> Texture2D:
	var img := Image.create(4, 18, false, Image.FORMAT_RGBA8)
	for y in 18:
		for x in 4:
			var a := sin(PI * (y + 0.5) / 18.0) * (1.0 - absf(x - 1.5) / 2.0)
			img.set_pixel(x, y, Color(1, 1, 1, clampf(a, 0.0, 1.0)))
	return ImageTexture.create_from_image(img)


func _ramp(colors: Array, offsets: Array, constant := false) -> Gradient:
	var g := Gradient.new()
	g.offsets = PackedFloat32Array(offsets)
	g.colors = PackedColorArray(colors)
	if constant:
		g.interpolation_mode = Gradient.GRADIENT_INTERPOLATE_CONSTANT
	return g


func _curve(from: float, to: float) -> Curve:
	var c := Curve.new()
	c.max_value = maxf(from, to)
	c.add_point(Vector2(0.0, from))
	c.add_point(Vector2(1.0, to))
	return c


func _play(sound: String, pitch := 1.0) -> void:
	var p: AudioStreamPlayer = _sfx.get(sound)
	if p != null and p.stream != null:
		p.pitch_scale = pitch
		p.play()


## The car is touching a wall this step, at `point` (world) with the wall's `normal`.
func contact(point: Vector2, normal: Vector2, velocity: Vector2) -> void:
	_since_contact = 0.0
	var along := velocity.slide(normal)
	if along.length() < 40.0:
		return   # leaning on the wall, not scraping along it
	_sparks.global_position = point
	_sparks.direction = (along.normalized() + normal * 0.7).normalized()
	_sparks.emitting = true
	var scrape: AudioStreamPlayer = _sfx["scrape"]
	if scrape.stream != null and not scrape.playing:
		scrape.pitch_scale = randf_range(0.9, 1.15)
		scrape.play()


## A counted wall hit: the big burst.
func crash(point: Vector2, normal: Vector2, speed: float) -> void:
	for p in [_burst, _bits]:
		p.global_position = point
		p.direction = normal
		p.restart()
	_play("crash", randf_range(0.9, 1.1) * lerpf(1.1, 0.9, clampf(speed / 500.0, 0.0, 1.0)))


func boost_pad() -> void:
	_play("boost", randf_range(0.95, 1.08))


func launch() -> void:
	_play("jump")


func land() -> void:
	_ring.global_position = car.global_position
	_ring.restart()
	_play("land", randf_range(0.95, 1.05))


## Every physics step. `speed_k` = speed / max_speed; `pushed` = boosting or on
## a boost pad's push.
func update(delta: float, speed_k: float, skidding: bool, pushed: bool) -> void:
	_since_contact += delta
	if _since_contact > 0.06:
		_sparks.emitting = false
		var scrape: AudioStreamPlayer = _sfx["scrape"]
		if scrape.playing:
			scrape.stop()
	_smoke.emitting = skidding

	# Light trails off the tail lights once the car is quick.
	var fast := speed_k > 0.5 or pushed
	for t in _trails:
		if not t.is_inside_tree():
			continue
		if fast:
			t.add_point(car.to_global(Vector2(t.get_meta("x"), 28.0)))
			if t.get_point_count() > TRAIL_POINTS:
				t.remove_point(0)
		elif t.get_point_count() > 0:
			t.remove_point(0)

	# Speed lines: from about cruising pace on boost, from well above it otherwise.
	var want := maxf(smoothstep(0.62, 0.95, speed_k), 0.7 if pushed else 0.0)
	_line_k = move_toward(_line_k, want, delta * 3.0)
	if car.velocity.length() > 1.0:
		_line_dir = car.velocity.rotated(-car.rotation).normalized()
	if _line_k > 0.01:
		var half := _half_view()
		var travel := (900.0 + 1400.0 * _line_k) * delta
		for line in _lines:
			line[0] -= _line_dir * travel
			if line[1] <= 0.0 or absf(line[0].x) > half.x or absf(line[0].y) > half.y:
				_respawn_line(line, half)
	queue_redraw()


func _half_view() -> Vector2:
	var cam := car.get_node("Camera2D") as Camera2D
	return get_viewport_rect().size * 0.5 / maxf(cam.zoom.x, 0.01)


## A new speed line somewhere ahead of the car (in its direction of travel),
## off to the sides so it never crosses the car itself.
func _respawn_line(line: Array, half: Vector2) -> void:
	var side := Vector2(-_line_dir.y, _line_dir.x)
	var across := randf_range(80.0, maxf(half.x, half.y)) * (1.0 if randf() < 0.5 else -1.0)
	line[0] = side * across + _line_dir * randf_range(-half.y, half.y * 1.2)
	line[1] = randf_range(40.0, 130.0)


func _draw() -> void:
	if _line_k <= 0.01:
		return
	var color := Color(Palette.TEXT_LIGHT, 0.22 * _line_k)
	for line in _lines:
		if line[1] > 0.0:
			draw_line(line[0], line[0] - _line_dir * line[1] * _line_k, color, 2.0, true)
