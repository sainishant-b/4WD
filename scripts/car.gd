extends CharacterBody2D
## Dual-axle (four-wheel-steering) car — SIM-ISH handling.
##
## A slip-angle bicycle model with TWO steered axles: it has weight/momentum,
## steering that stiffens with speed, tyre grip you can overdrive into a slide or
## spin, and a handbrake that breaks the REAR loose. At very low speed it blends
## to a kinematic steer so parking stays stable (no spin-in-place / phantom slide).
## A `traction` pull keeps the slide small: each frame the sideways speed is
## eased toward what the wheel angles ask for, so the car goes where its wheels
## point (the handbrake keeps most of its drift).
##
## Convention (unchanged): rotation = 0 means the car points UP.
##   forward = Vector2.from_angle(rotation - PI/2),  right = Vector2.from_angle(rotation)
## Work is done in the body frame (vx = forward speed, vy = sideways speed) then
## recomposed into the world `velocity` (px/s). Forces are expressed directly as
## accelerations (px/s^2), so `accel_force` stays the forward acceleration and
## game.gd can keep setting `max_speed`/`accel_force` per level.
##
## Feel/FX owned here: a held BOOST (extra thrust + raised speed ceiling on a
## meter), skid marks + dust on a drift, wall-impact screen shake, a
## speed-sensitive camera dolly (zooms out at speed), and rear brake lights.
## The look is dressed in code too (`_build_visuals`): a soft shadow under the
## car, darker flanks round a lighter deck, and a glass cockpit.
##
## It also reports wall contact: `wall_touched` fires once per NEW touch (one
## scrape or bounce is one touch), which game.gd counts toward game over. The
## collision box (Car.tscn, 42 x 63) covers the drawn tyres, so a hit happens
## the moment a tyre reaches the white limit line, never after it rides over.

## A new contact with a track wall. See `_note_wall_contact` for what "new" means.
signal wall_touched

# --- Drive / speed ---------------------------------------------------------
@export var max_speed: float = 340.0          # forward top speed (set per level)
@export var accel_force: float = 300.0        # forward drive accel (set per level)
@export var brake_force: float = 600.0        # braking decel
@export var rolling_resistance: float = 0.9   # linear coast-down (1/s)
@export var drag: float = 0.0016              # quadratic drag

# --- Geometry / mass-feel --------------------------------------------------
@export var wheelbase: float = 50.0
@export var lf: float = 25.0                   # CoM -> front axle
@export var lr: float = 25.0                   # CoM -> rear axle
@export var yaw_inertia: float = 2200.0        # higher = slower to rotate (weight)

# --- Tyres (the heart of the feel) -----------------------------------------
@export var cornering_stiffness_front: float = 3500.0
@export var cornering_stiffness_rear: float = 4200.0  # > front => the tail stays planted
@export var grip_accel: float = 800.0          # max lateral accel before the tyre slides
@export_range(0, 1) var handbrake_rear_grip: float = 0.15  # rear grip multiplier on handbrake
# How fast a sideways slide is pulled back toward the line the wheels point
# along (1/s). 0 = pure tyre model (slides a lot); higher = more planted.
# 2026-11-20: grip 520 -> 800, rear 3100 -> 4200 and traction 0 -> 6 (the user
# found the car drifted into the walls). A driver bot lapping all five levels
# the same way hit walls 26 -> 9 times and lapped faster on every level.
@export var traction: float = 6.0
@export_range(0, 1) var handbrake_traction: float = 0.2    # share of traction kept on the handbrake

# --- Steering --------------------------------------------------------------
@export var steer_sensitivity: float = 6.0     # radians/sec the wheels turn (snappier turn-in)
@export_range(0, 1) var high_speed_lock: float = 0.45  # fraction of full lock at top speed
@export_range(0, 90) var max_steer_aligned_deg: float = 55.0
@export_range(0, 90) var max_steer_opposed_deg: float = 45.0

# --- Camera feel -----------------------------------------------------------
# The camera dollies OUT as you speed up so fast sections reveal more road
# ahead; it eases back in when slow. (Godot zoom > 1 = magnified, so higher
# speed -> lower zoom.) `_at_top` is the fraction of rest zoom held at max_speed.
@export var camera_zoom_rest: float = 1.4            # zoom when stopped (matches Car.tscn)
@export_range(0.3, 1.0) var camera_zoom_at_top: float = 0.78
@export var camera_zoom_lerp: float = 3.0            # ease rate toward target (1/s)
# A portrait phone is only ~430 logical px wide, so pull back a little to keep
# the road's edges and the next bend in view.
@export_range(0.3, 1.0) var camera_zoom_portrait: float = 0.82

# --- Boost -----------------------------------------------------------------
# A held boost (Shift / on-screen BOOST) burns a meter for extra forward thrust
# and a higher speed ceiling; the meter refills when not boosting. After a boost
# the overspeed bleeds off smoothly (no hard snap back to max_speed).
@export var boost_accel: float = 460.0               # extra forward accel while boosting
@export var boost_speed_mult: float = 1.45           # top-speed multiplier while boosting
@export var boost_duration: float = 1.6              # seconds of boost from a full meter
@export var boost_recharge_rate: float = 0.35        # meter refilled per second when idle
@export_range(0, 1) var boost_min_to_fire: float = 0.15   # min meter to start a fresh boost
@export var boost_decel: float = 700.0               # overspeed bleed-off after boost (px/s^2)
@export_range(0.5, 1.0) var boost_zoom_out: float = 0.92  # extra camera dolly-out while boosting

@export_range(0, 1) var collision_speed_keep: float = 0.5

# --- State (read/reset by game.gd) -----------------------------------------
var front_steer: float = 0.0
var rear_steer: float = 0.0
var ang_vel: float = 0.0
var boost_meter: float = 1.0      # 0..1, read by the HUD; refills when not boosting
var _boosting: bool = false
var _speed_cap: float = 0.0       # current forward-speed ceiling (eases down after a boost)

# --- Wall touches ---
# A touch is over only when the car has been clear of the walls for a moment AND
# has moved away from where it last touched, so resting against a wall and then
# pressing on is still the same touch. After a counted touch, further contact
# is forgiven briefly so one crash that pinballs across the road counts once.
const WALL_RELEASE_TIME := 0.35     # s without contact before a touch can end
const WALL_REARM_DISTANCE := 30.0   # px the car must get from its last contact point
const WALL_TOUCH_GRACE := 1.0       # s after a counted touch during which contact is forgiven
var _wall_contact_pos := Vector2.INF
var _since_wall_contact: float = INF
var _since_wall_touch: float = INF

# --- Juice / FX ---
const MAX_SKID_LINES := 60
var _dust: CPUParticles2D
var _shake: float = 0.0
var _tiremarks: Node2D
var _skid_active: bool = false
var _skid_l: Line2D
var _skid_r: Line2D
var _skid_all: Array = []
var _brake_l: Polygon2D
var _brake_r: Polygon2D

# --- Fake jump (ramps): a short hop that scales the visuals up and drops all
#     collision so the car sails over obstacles, then lands. ---
var _air_t: float = 0.0
var _air_dur: float = 0.0
var _base_layer: int = 1
var _base_mask: int = 1
var _visual_nodes: Array = []
var _shadow: Sprite2D
const SHADOW_REST := Vector2(4.0, 7.0)    # where the shadow lies with the car on the ground
const SHADOW_ALPHA := 0.8
const SHADOW_LIFT := Vector2(9.0, 15.0)   # extra drift at the top of a hop

@onready var _front_wheels := [$WheelFL, $WheelFR]
@onready var _rear_wheels := [$WheelRL, $WheelRR]


func _ready() -> void:
	add_to_group("car")
	# TireMarks is a sibling of the Cars node under the race scene root.
	var scene := get_tree().current_scene
	_tiremarks = scene.get_node_or_null("TireMarks") if scene != null else null
	_dust = CPUParticles2D.new()
	_dust.local_coords = false
	_dust.emitting = false
	_dust.amount = 20
	_dust.lifetime = 0.5
	_dust.position = Vector2(0, 24)
	_dust.spread = 50.0
	_dust.gravity = Vector2.ZERO
	_dust.initial_velocity_min = 15.0
	_dust.initial_velocity_max = 50.0
	_dust.scale_amount_min = 1.5
	_dust.scale_amount_max = 3.5
	_dust.color = Color(0.7, 0.68, 0.6, 0.5)
	add_child(_dust)

	# Rear brake lights (created in code like the dust); lit when braking/handbraking.
	_brake_l = _make_brake_light(Vector2(-10, 27))
	_brake_r = _make_brake_light(Vector2(10, 27))

	_build_visuals()
	_visual_nodes = [$Body, $Nose, $WheelFL, $WheelFR, $WheelRL, $WheelRR]


## Dresses the plain shapes from Car.tscn so the car reads as a lit object
## rather than a flat cut-out. Colours are Palette tokens (red-orange POP = the
## player, a gold nose).
func _build_visuals() -> void:
	var body: Polygon2D = $Body
	body.polygon = PackedVector2Array([
		Vector2(-5, -32), Vector2(5, -32), Vector2(13, -25), Vector2(16, -15), Vector2(16, 22),
		Vector2(13, 28), Vector2(-13, 28), Vector2(-16, 22), Vector2(-16, -15), Vector2(-13, -25),
	])
	body.color = Palette.POP_DEEP   # the flanks; the lighter deck sits on top
	HudStyle.feather(body)

	# A soft blob of shadow, first in the tree so it lies under everything else.
	_shadow = Sprite2D.new()
	_shadow.texture = HudStyle.glow()
	_shadow.scale = Vector2(78.0, 104.0) / _shadow.texture.get_size()
	_shadow.modulate = Color(Palette.BLACK, SHADOW_ALPHA)
	_shadow.position = SHADOW_REST
	add_child(_shadow)
	move_child(_shadow, 0)

	# Children of Body draw over it and follow it when a hop scales it up.
	_add_shape(body, [
		Vector2(-4, -28.5), Vector2(4, -28.5), Vector2(10, -23), Vector2(12.5, -14), Vector2(12.5, 21),
		Vector2(10, 25), Vector2(-10, 25), Vector2(-12.5, 21), Vector2(-12.5, -14), Vector2(-10, -23),
	], Palette.POP)
	_add_shape(body, [
		Vector2(-3, -27), Vector2(3, -27), Vector2(3, -12), Vector2(-3, -12),
	], Palette.GOLD)                                          # racing stripe
	_add_shape(body, [
		Vector2(-9, -10), Vector2(9, -10), Vector2(10.5, 5), Vector2(8.5, 15),
		Vector2(-8.5, 15), Vector2(-10.5, 5),
	], Palette.INK)                                           # cockpit glass
	_add_shape(body, [
		Vector2(-8, -8.5), Vector2(8, -8.5), Vector2(8.8, -3.5), Vector2(-8.8, -3.5),
	], Color(Palette.TEXT_LIGHT, 0.3))                        # windscreen glint

	$Nose.color = Palette.GOLD
	HudStyle.feather($Nose)
	for wheel in [$WheelFL, $WheelFR, $WheelRL, $WheelRR]:
		wheel.color = Palette.BLACK
		HudStyle.feather(wheel)


## Adds a filled shape under `parent`; opaque ones get a smoothed edge.
func _add_shape(parent: Node, points: Array, color: Color) -> Polygon2D:
	var shape := Polygon2D.new()
	shape.polygon = PackedVector2Array(points)
	shape.color = color
	parent.add_child(shape)
	if color.a >= 1.0:
		HudStyle.feather(shape)
	return shape


func _physics_process(delta: float) -> void:
	# Online: only the owning peer simulates its car. Everyone else's car is a
	# puppet whose transform/steer arrive via the MultiplayerSynchronizer; we just
	# reflect the synced wheel angles. (No-op in single-player.)
	if Net.is_multiplayer and not is_multiplayer_authority():
		_update_wheel_visuals()
		return

	_update_airborne(delta)
	_update_steering(delta)

	var fwd := Vector2.from_angle(rotation - PI / 2.0)
	var right := Vector2.from_angle(rotation)
	var vx := velocity.dot(fwd)     # forward speed
	var vy := velocity.dot(right)   # sideways speed (right +)
	var omega := ang_vel
	var speed := velocity.length()

	var handbrake: bool = InputState.handbrake
	var thr: float = InputState.throttle_input

	# --- Longitudinal drive, applied along the WHEEL directions so steering both
	#     axles the same way crabs the car sideways (the four-wheel-steer hook). ---
	var drive := 0.0
	if thr > 0.0:
		drive = accel_force * thr
	elif thr < 0.0:
		drive = (-brake_force * -thr) if vx > 5.0 else (accel_force * 0.6 * thr)

	# --- Boost: extra forward thrust on a depleting meter (not while reversing). ---
	if _speed_cap <= 0.0:
		_speed_cap = max_speed
	var can_fire: bool = boost_meter > (0.0 if _boosting else boost_min_to_fire)
	_boosting = InputState.boost and can_fire and thr >= 0.0 and boost_meter > 0.0
	if _boosting:
		boost_meter = maxf(0.0, boost_meter - delta / boost_duration)
		drive += boost_accel
	else:
		boost_meter = minf(1.0, boost_meter + boost_recharge_rate * delta)

	var ax_drive := drive * 0.5 * (cos(front_steer) + cos(rear_steer))
	var ay_drive := drive * 0.5 * (sin(front_steer) + sin(rear_steer))

	# --- Lateral tyre forces from slip angles. Saturated (clamped) so exceeding
	#     grip makes the tyre slide; faded out at low speed for stability. ---
	var grip_scale := smoothstep(10.0, 70.0, speed)
	var denom := maxf(absf(vx), 40.0)
	var af := atan2(vy + lf * omega, denom) - front_steer
	var ar := atan2(vy - lr * omega, denom) - rear_steer

	var cr := cornering_stiffness_rear
	var grip_r := grip_accel
	if handbrake:
		cr *= handbrake_rear_grip
		grip_r *= handbrake_rear_grip
	var ayf := clampf(-cornering_stiffness_front * af, -grip_accel, grip_accel) * grip_scale
	var ayr := clampf(-cr * ar, -grip_r, grip_r) * grip_scale

	# --- Integrate body-frame velocity ---
	vx += (ax_drive + vy * omega - rolling_resistance * vx - drag * vx * absf(vx)) * delta
	vy += (ay_drive + ayf + ayr - vx * omega) * delta

	# --- Traction: pull the sideways speed toward the no-slip value the wheel
	#     angles ask for (zero when pivoting, vx*tan when crabbing), so the car
	#     goes where its wheels point instead of sliding wide. Much weaker on the
	#     handbrake, which keeps its drift. ---
	var vy_track := vx * (lr * tan(front_steer) + lf * tan(rear_steer)) / wheelbase
	var hold := traction * grip_scale * (handbrake_traction if handbrake else 1.0)
	vy = lerpf(vy, vy_track, 1.0 - exp(-hold * delta))

	# --- Yaw: dynamic tyre moment at speed, kinematic steer geometry when slow ---
	var moment := lf * ayf - lr * ayr
	var omega_dyn := omega + (moment / yaw_inertia) * delta
	var omega_kin := (vx / wheelbase) * (tan(front_steer) - tan(rear_steer))
	omega = lerpf(omega_kin, omega_dyn, grip_scale) * 0.99

	# --- Clamp forward speed: boost raises the ceiling instantly, then it eases
	#     back down to max_speed so the overspeed bleeds off smoothly. ---
	if _boosting:
		_speed_cap = max_speed * boost_speed_mult
	else:
		_speed_cap = move_toward(_speed_cap, max_speed, boost_decel * delta)
	vx = clampf(vx, -max_speed * 0.6, maxf(_speed_cap, max_speed))
	velocity = fwd * vx + right * vy
	ang_vel = omega
	rotation += omega * delta

	_since_wall_contact += delta
	_since_wall_touch += delta
	var collision := move_and_collide(velocity * delta)
	if collision:
		_note_wall_contact(collision.get_collider())
		velocity = velocity.slide(collision.get_normal()) * collision_speed_keep
		ang_vel *= 0.5
		if speed > 120.0:
			_shake = minf(5.0 + speed * 0.012, 14.0)

	var skidding := speed > 40.0 and (handbrake or absf(vy) > 70.0)
	var braking := handbrake or (thr < 0.0 and vx > 5.0)
	_update_tire_fx(skidding, _boosting)
	_update_brake_lights(braking)
	_update_camera_zoom(delta, speed)
	_apply_shake(delta)
	_update_wheel_visuals()


## Called on every frame the car collides. Emits `wall_touched` only when this
## is the start of a new touch (see the constants above).
func _note_wall_contact(collider: Object) -> void:
	if not (collider is StaticBody2D):
		return   # another car, not a wall
	var fresh := (
		_since_wall_contact >= WALL_RELEASE_TIME
		and _since_wall_touch >= WALL_TOUCH_GRACE
		and global_position.distance_to(_wall_contact_pos) > WALL_REARM_DISTANCE
	)
	_since_wall_contact = 0.0
	_wall_contact_pos = global_position
	if fresh:
		_since_wall_touch = 0.0
		wall_touched.emit()


func _update_steering(delta: float) -> void:
	var fin: float = InputState.front_steer_input
	var rin: float = InputState.rear_steer_input
	var speed := velocity.length()

	var aligned := absf(front_steer - rear_steer) < 0.1
	var base_max := deg_to_rad(max_steer_aligned_deg if aligned else max_steer_opposed_deg)
	# Steering stiffens with speed: less lock available the faster you go.
	var speed_factor := lerpf(1.0, high_speed_lock, clampf(speed / max_speed, 0.0, 1.0))
	var max_a := base_max * speed_factor

	front_steer = move_toward(front_steer, fin * max_a, steer_sensitivity * delta)
	rear_steer = move_toward(rear_steer, rin * max_a, steer_sensitivity * delta)
	front_steer = clampf(front_steer, -base_max, base_max)
	rear_steer = clampf(rear_steer, -base_max, base_max)


func _update_wheel_visuals() -> void:
	for w in _front_wheels:
		w.rotation = front_steer
	for w in _rear_wheels:
		w.rotation = rear_steer


## Soft-cone hit (called by cone.gd): bleed some speed + a small jolt.
func hit_cone() -> void:
	velocity *= 0.82
	ang_vel *= 0.9
	_shake = maxf(_shake, 4.0)


## Start a fake hop (called by ramp.gd): drop all collision so we sail over
## obstacles, and scale the visuals up for a height illusion.
func jump(dur: float) -> void:
	if _air_t <= 0.0:
		_base_layer = collision_layer
		_base_mask = collision_mask
		collision_layer = 0
		collision_mask = 0
	_air_dur = maxf(dur, 0.1)
	_air_t = _air_dur


func _update_airborne(delta: float) -> void:
	if _air_t <= 0.0:
		return
	_air_t -= delta
	# Scale peaks at mid-hop (sine arc), back to 1 at landing.
	var p := clampf(1.0 - _air_t / _air_dur, 0.0, 1.0)
	var height := sin(p * PI)
	var s := 1.0 + height * 0.4
	for nd in _visual_nodes:
		nd.scale = Vector2(s, s)
	# The shadow slides away and thins as the car rises.
	_shadow.position = SHADOW_REST + SHADOW_LIFT * height
	_shadow.modulate.a = SHADOW_ALPHA * (1.0 - height * 0.5)
	if _air_t <= 0.0:
		collision_layer = _base_layer
		collision_mask = _base_mask
		for nd in _visual_nodes:
			nd.scale = Vector2.ONE
		_shadow.position = SHADOW_REST
		_shadow.modulate.a = SHADOW_ALPHA
		_shake = maxf(_shake, 6.0)   # landing thump


## Eases the camera out as speed rises (more road visible at speed) and back in
## when slow. Leaves Camera2D.offset alone — that's the shake's channel.
func _update_camera_zoom(delta: float, speed: float) -> void:
	var t := clampf(speed / max_speed, 0.0, 1.0)
	var target := camera_zoom_rest * lerpf(1.0, camera_zoom_at_top, t)
	if Layout.portrait:
		target *= camera_zoom_portrait
	if _boosting:
		target *= boost_zoom_out
	var cam := $Camera2D
	var z := lerpf(cam.zoom.x, target, clampf(camera_zoom_lerp * delta, 0.0, 1.0))
	cam.zoom = Vector2(z, z)


func _make_brake_light(pos: Vector2) -> Polygon2D:
	var p := Polygon2D.new()
	p.polygon = PackedVector2Array([Vector2(-5, -2), Vector2(5, -2), Vector2(5, 2), Vector2(-5, 2)])
	p.position = pos
	p.color = Color(1.0, 0.18, 0.12)
	p.visible = false
	add_child(p)
	return p


func _update_brake_lights(braking: bool) -> void:
	if _brake_l != null:
		_brake_l.visible = braking
		_brake_r.visible = braking


func _update_tire_fx(skidding: bool, dust_extra: bool = false) -> void:
	if _dust != null:
		_dust.emitting = skidding or dust_extra
	if skidding and _tiremarks != null:
		if not _skid_active:
			_skid_active = true
			_skid_l = _new_skid_line()
			_skid_r = _new_skid_line()
		var pc := _skid_l.get_point_count()
		if pc == 0 or _skid_l.get_point_position(pc - 1).distance_to($WheelRL.global_position) > 4.0:
			_skid_l.add_point($WheelRL.global_position)
			_skid_r.add_point($WheelRR.global_position)
	else:
		_skid_active = false


func _new_skid_line() -> Line2D:
	var l := Line2D.new()
	l.width = 6.0
	l.default_color = Color(0.05, 0.05, 0.05, 0.5)
	l.joint_mode = Line2D.LINE_JOINT_ROUND
	l.begin_cap_mode = Line2D.LINE_CAP_ROUND
	l.end_cap_mode = Line2D.LINE_CAP_ROUND
	_tiremarks.add_child(l)
	_skid_all.append(l)
	if _skid_all.size() > MAX_SKID_LINES:
		var old = _skid_all.pop_front()
		if is_instance_valid(old):
			old.queue_free()
	return l


func _apply_shake(delta: float) -> void:
	if _shake > 0.1:
		$Camera2D.offset = Vector2(randf_range(-_shake, _shake), randf_range(-_shake, _shake))
		_shake = move_toward(_shake, 0.0, 40.0 * delta)
	elif $Camera2D.offset != Vector2.ZERO:
		$Camera2D.offset = Vector2.ZERO
