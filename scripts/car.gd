extends CharacterBody2D
## Dual-axle (four-wheel-steering) car — SIM-ISH handling.
##
## A slip-angle bicycle model with TWO steered axles: it has weight/momentum,
## steering that stiffens with speed, tyre grip you can overdrive into a slide or
## spin, and a handbrake that breaks the REAR loose. At very low speed it blends
## to a kinematic steer so parking stays stable (no spin-in-place / phantom slide).
## A `traction` pull keeps the slide small: each frame the car's direction of
## travel is eased toward what the wheel angles ask for, so the car goes where its
## wheels point (the handbrake keeps most of its drift). It turns the velocity
## without changing its size, and the tyres' side force leans with the wheels, so
## a turn scrubs a little speed and never adds any. A `yaw_hold` pull does the
## same for the spin: the car turns as fast as its wheels ask and stops turning
## when they straighten. The wheels go back to straight faster (`steer_return`)
## than they turn in.
##
## Convention (unchanged): rotation = 0 means the car points UP.
##   forward = Vector2.from_angle(rotation - PI/2),  right = Vector2.from_angle(rotation)
## Work is done in the body frame (vx = forward speed, vy = sideways speed) then
## recomposed into the world `velocity` (px/s). Forces are expressed directly as
## accelerations (px/s^2), so `accel_force` stays the forward acceleration and
## game.gd can keep setting `max_speed`/`accel_force` per level. The cruising
## speed is where `accel_force` meets `rolling_resistance` + `drag`; scale all
## three together to change how quickly the car gets there without moving it.
##
## Feel owned here: a held BOOST (extra thrust + raised speed ceiling on a
## meter), skid marks on a drift, wall-impact screen shake and a speed-sensitive
## camera dolly (zooms out at speed). The track's boost pads call in too:
## `hit_boost_pad` (a short hard push along the road).
## The car is drawn by its "Look" child (car_look.gd) and its effects and
## sounds come from its "Fx" child (car_fx.gd); a soft shadow stays on the
## ground under it.
##
## It also reports wall contact: `wall_touched` fires once per NEW touch (one
## scrape or bounce is one touch), which game.gd counts toward game over. The
## collision box (Car.tscn, 38 x 60) covers the drawn tyres, so a hit happens
## the moment a tyre reaches the white limit line, never after it rides over.

## A new contact with a track wall. See `_note_wall_contact` for what "new" means.
signal wall_touched

const CarLook := preload("res://scripts/car_look.gd")
const CarFx := preload("res://scripts/car_fx.gd")

# --- Drive / speed ---------------------------------------------------------
@export var max_speed: float = 340.0          # forward top speed (set per level)
@export var accel_force: float = 120.0        # forward drive accel (set per level)
@export var brake_force: float = 1200.0       # braking decel
@export var rolling_resistance: float = 0.36  # linear coast-down (1/s)
@export var drag: float = 0.0008              # quadratic drag
# 2026-11-21: the drive (LEVELS accel_force), rolling_resistance, drag and
# boost_accel were all cut to 0.4x (the user: "it instantly hits full speed on
# mobile"), so the cruising speed is the same but it takes ~2.5x as long to
# reach: half speed 0.45 -> 1.1 s, 90% 1.3 -> 3.2 s. Lifting off now slows the
# car less (1 s of coasting keeps 59% of its speed, was 30%), so the brakes
# were doubled too (600 -> 1200; the user: "make the brakes stronger"): a stop
# from cruising speed takes 0.45 -> 0.3 s and a third less road. The bot's laps
# got ~5% slower (LEVELS medals moved with them) and hit walls 29 -> 23 times.
# 2026-11-22: every car 20% slower (the user: still "very difficult on mobile"):
# LEVELS max_speed/accel_force and boost_accel x0.8, drag / 0.8, so the cruising
# speed drops a fifth (Level 1: 334 -> 268 px/s) while the time to reach it is
# unchanged (rolling_resistance sets that and stays put).

# --- Geometry / mass-feel --------------------------------------------------
@export var wheelbase: float = 50.0
@export var lf: float = 25.0                   # CoM -> front axle
@export var lr: float = 25.0                   # CoM -> rear axle
@export var yaw_inertia: float = 2200.0        # higher = slower to rotate (weight)

# --- Tyres (the heart of the feel) -----------------------------------------
@export var cornering_stiffness_front: float = 3500.0
@export var cornering_stiffness_rear: float = 4200.0  # > front => the tail stays planted
@export var grip_accel: float = 1400.0         # max lateral accel before the tyre slides
@export_range(0, 1) var handbrake_rear_grip: float = 0.15  # rear grip multiplier on handbrake
# How fast a sideways slide is pulled back toward the line the wheels point
# along (1/s). 0 = pure tyre model (slides a lot); higher = more planted.
# 2026-11-20: grip 520 -> 800, rear 3100 -> 4200 and traction 0 -> 6 (the user
# found the car drifted into the walls). A driver bot lapping all five levels
# the same way hit walls 26 -> 9 times and lapped faster on every level.
# 2026-11-21: grip 800 -> 1400 and traction 6 -> 30 (the user: "reduce drift").
# Full lock at top speed slides 25% -> 16% sideways; the bot's hard laps of all
# seven levels hit walls 41 -> 29 times. The handbrake still drifts (62% -> 55%).
@export var traction: float = 30.0
@export_range(0, 1) var handbrake_traction: float = 0.2    # share of traction kept on the handbrake

# --- Steering --------------------------------------------------------------
# 2026-11-23 (the user: "the car over steers, the wheels are not coming back to
# 0 degrees fast enough"): the wheels now centre at `steer_return`, `yaw_hold`
# stops the car spinning on once they are straight, a turn no longer adds speed
# (see `traction`), and the lock shrinks toward `high_speed_lock` by the CRUISING
# speed, not `max_speed` (only reached on a boost now). A 0.2 s tap of full lock
# at cruise used to turn the car 21-26 deg more after letting go (spinning on for
# 0.4-0.5 s) and holding full lock for 1 s sped Level 1 up 266 -> 427 px/s; now
# it turns ~6 deg more, stops in ~0.15 s and the speed stays put.
@export var steer_sensitivity: float = 6.0     # radians/sec the wheels turn in
@export var steer_return: float = 14.0         # radians/sec the wheels turn back toward straight
@export var yaw_hold: float = 20.0             # 1/s the spin is pulled toward what the wheels ask
@export_range(0, 1) var high_speed_lock: float = 0.45  # fraction of full lock at cruising speed
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
@export var boost_accel: float = 184.0               # extra forward accel while boosting
@export var boost_speed_mult: float = 1.45           # top-speed multiplier while boosting
@export var boost_duration: float = 1.6              # seconds of boost from a full meter
@export var boost_recharge_rate: float = 0.35        # meter refilled per second when idle
@export_range(0, 1) var boost_min_to_fire: float = 0.15   # min meter to start a fresh boost
@export var boost_decel: float = 700.0               # overspeed bleed-off after boost (px/s^2)
@export_range(0.5, 1.0) var boost_zoom_out: float = 0.92  # extra camera dolly-out while boosting

# --- Boost pads (track_builder.gd lays them; boost_pad.gd calls in) ----------
@export var pad_kick: float = 70.0           # px/s added along the pad at once
@export var pad_accel: float = 320.0         # extra forward accel while the push lasts
@export var pad_time: float = 0.9            # s the push lasts

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
var _shake: float = 0.0
var _tiremarks: Node2D
var _skid_active: bool = false
var _skid_l: Line2D
var _skid_r: Line2D
var _skid_all: Array = []
var _look: Node2D         # CarLook: draws the car
var _fx: Node2D           # CarFx: sparks, smoke, trails, speed lines, sounds
var _pad_t: float = 0.0   # time left on a boost pad's push

# --- Fake jump (the dormant obstacle ramps): a short hop that scales the
#     look up and drops all collision so the car sails over obstacles. ---
var _air_t: float = 0.0
var _air_dur: float = 0.0
var _base_layer: int = 1
var _base_mask: int = 1
var _shadow: Sprite2D
const SHADOW_REST := Vector2(4.0, 7.0)    # where the shadow lies with the car on the ground
const SHADOW_ALPHA := 0.8
const SHADOW_LIFT := Vector2(18.0, 30.0)  # extra drift at the top of a jump
const WHEEL_RL := Vector2(-16, 21)
const WHEEL_RR := Vector2(16, 21)


func _ready() -> void:
	add_to_group("car")
	# TireMarks is a sibling of the Cars node under the race scene root.
	var scene := get_tree().current_scene
	_tiremarks = scene.get_node_or_null("TireMarks") if scene != null else null

	# A soft blob of shadow, first in the tree so it lies under everything else.
	_shadow = Sprite2D.new()
	_shadow.texture = HudStyle.glow()
	_shadow.scale = Vector2(78.0, 104.0) / _shadow.texture.get_size()
	_shadow.modulate = Color(Palette.BLACK, SHADOW_ALPHA)
	_shadow.position = SHADOW_REST
	add_child(_shadow)
	move_child(_shadow, 0)

	_look = CarLook.new()
	_look.name = "Look"
	add_child(_look)
	_fx = CarFx.new()
	_fx.name = "Fx"
	_fx.car = self
	add_child(_fx)


func _is_puppet() -> bool:
	return Net.is_multiplayer and not is_multiplayer_authority()


func _physics_process(delta: float) -> void:
	# Online: only the owning peer simulates its car. Everyone else's car is a
	# puppet whose transform/steer arrive via the MultiplayerSynchronizer; we just
	# reflect the synced wheel angles. (No-op in single-player.)
	if _is_puppet():
		_update_wheel_visuals()
		return

	if _air_t > 0.0:
		_fly(delta)
		return
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
	var pushed := _pad_t > 0.0   # a boost pad's push
	if pushed:
		_pad_t -= delta
		drive += pad_accel

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

	# --- Integrate body-frame velocity. Each tyre's side force is square to its
	#     WHEEL, so a steered axle's force also leans back against the motion:
	#     cornering scrubs a little speed. ---
	var tyre_x := -(ayf * sin(front_steer) + ayr * sin(rear_steer))
	var tyre_y := ayf * cos(front_steer) + ayr * cos(rear_steer)
	vx += (ax_drive + tyre_x + vy * omega - rolling_resistance * vx - drag * vx * absf(vx)) * delta
	vy += (ay_drive + tyre_y - vx * omega) * delta

	# --- Traction: pull the sideways speed toward the no-slip value the wheel
	#     angles ask for (zero when pivoting, vx*tan when crabbing), so the car
	#     goes where its wheels point instead of sliding wide. Much weaker on the
	#     handbrake, which keeps its drift. It TURNS the velocity, keeping its
	#     size: setting vy alone added speed every frame of a turn (Level 1 went
	#     266 -> 427 px/s in a second of full lock). ---
	var vy_track := vx * (lr * tan(front_steer) + lf * tan(rear_steer)) / wheelbase
	var hold := traction * grip_scale * (handbrake_traction if handbrake else 1.0)
	var vy_held := lerpf(vy, vy_track, 1.0 - exp(-hold * delta))
	if absf(vx) > 1.0:
		var body_speed := Vector2(vx, vy).length()
		var held := Vector2(vx, vy_held).normalized() * body_speed
		vx = held.x
		vy = held.y
	else:
		vy = vy_held

	# --- Yaw: dynamic tyre moment at speed, kinematic steer geometry when slow ---
	var moment := lf * ayf - lr * ayr
	var omega_dyn := omega + (moment / yaw_inertia) * delta
	var omega_kin := (vx / wheelbase) * (tan(front_steer) - tan(rear_steer))
	omega = lerpf(omega_kin, omega_dyn, grip_scale) * 0.99
	# Yaw hold: the spin eases toward what the wheels ask, so the car stops
	# turning soon after they straighten instead of spinning on. Off on the
	# handbrake, so a drift still swings the tail round.
	var yaw_k := 0.0 if handbrake else yaw_hold * grip_scale
	omega = lerpf(omega, omega_kin, 1.0 - exp(-yaw_k * delta))

	# --- Clamp forward speed: boost raises the ceiling instantly, then it eases
	#     back down to max_speed so the overspeed bleeds off smoothly. ---
	if _boosting or pushed:
		_speed_cap = max_speed * boost_speed_mult
	else:
		_speed_cap = move_toward(_speed_cap, max_speed, boost_decel * delta)
	vx = clampf(vx, -max_speed * 0.6, maxf(_speed_cap, max_speed))
	velocity = fwd * vx + right * vy
	ang_vel = omega
	rotation += omega * delta

	_move(delta, speed)

	var skidding := speed > 40.0 and (handbrake or absf(vy) > 70.0)
	var braking := handbrake or (thr < 0.0 and vx > 5.0)
	_update_tire_fx(skidding)
	_look.braking = braking
	_look.flame = move_toward(_look.flame, 1.0 if (_boosting or pushed) else 0.0, delta * 6.0)
	_fx.update(delta, speed / maxf(max_speed, 1.0), skidding, _boosting or pushed)
	_update_camera_zoom(delta, speed)
	_apply_shake(delta)
	_update_wheel_visuals()


## Moves the car one step; a wall stops it like a cushion (slide along it,
## shed speed), throws sparks and, at speed, shakes the camera.
func _move(delta: float, speed: float) -> void:
	_since_wall_contact += delta
	_since_wall_touch += delta
	var collision := move_and_collide(velocity * delta)
	if collision == null:
		return
	var normal := collision.get_normal()
	var fresh := _note_wall_contact(collision.get_collider())
	_fx.contact(collision.get_position(), normal, velocity)
	if fresh:
		_fx.crash(collision.get_position(), normal, speed)
		UiFeel.buzz(60)   # a short buzz on a phone
	velocity = velocity.slide(normal) * collision_speed_keep
	ang_vel *= 0.5
	if speed > 120.0:
		_shake = minf(5.0 + speed * 0.012, 14.0) * (1.5 if fresh else 1.0)


## Called on every frame the car collides. Emits `wall_touched` (and returns
## true) only when this is the start of a new touch (see the constants above).
func _note_wall_contact(collider: Object) -> bool:
	if not (collider is StaticBody2D):
		return false   # another car, not a wall
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
	return fresh


func _update_steering(delta: float) -> void:
	var fin: float = InputState.front_steer_input
	var rin: float = InputState.rear_steer_input
	var speed := velocity.length()

	var aligned := absf(front_steer - rear_steer) < 0.1
	var base_max := deg_to_rad(max_steer_aligned_deg if aligned else max_steer_opposed_deg)
	# The handbrake (the drift button) gets the full lock at any speed, so a
	# drift can swing the car round a hairpin.
	var max_a := base_max * (1.0 if InputState.handbrake else lock_factor(speed))

	front_steer = move_toward(front_steer, fin * max_a, _steer_rate(front_steer, fin * max_a) * delta)
	rear_steer = move_toward(rear_steer, rin * max_a, _steer_rate(rear_steer, rin * max_a) * delta)
	front_steer = clampf(front_steer, -base_max, base_max)
	rear_steer = clampf(rear_steer, -base_max, base_max)


## How fast a wheel moves from `current` toward `target` (rad/s): quicker on
## the way back to straight than on the way in.
func _steer_rate(current: float, target: float) -> float:
	var centring := current != 0.0 and (current * target < 0.0 or absf(target) < absf(current))
	return steer_return if centring else steer_sensitivity


## Steering stiffens with speed: the share of full lock left at `speed`, down
## to `high_speed_lock` at the cruising speed (and held there on a boost). Eased
## in (squared), so a car slowed for a hairpin keeps most of its lock.
func lock_factor(speed: float) -> float:
	var k := clampf(speed / cruise_speed(), 0.0, 1.0)
	return lerpf(1.0, high_speed_lock, k * k)


## The speed the car settles at on full throttle (px/s): where `accel_force`
## meets `rolling_resistance` + `drag`.
func cruise_speed() -> float:
	if drag <= 0.0:
		return accel_force / maxf(rolling_resistance, 0.001)
	var rr := rolling_resistance
	return (-rr + sqrt(rr * rr + 4.0 * drag * accel_force)) / (2.0 * drag)


func _update_wheel_visuals() -> void:
	_look.front_steer = front_steer
	_look.rear_steer = rear_steer


## Soft-cone hit (called by cone.gd): bleed some speed + a small jolt.
func hit_cone() -> void:
	velocity *= 0.82
	ang_vel *= 0.9
	_shake = maxf(_shake, 4.0)


## A boost pad (boost_pad.gd): a kick along the road at once, then a hard
## push for `pad_time` that may run past max_speed (it bleeds off after).
func hit_boost_pad(forward: Vector2) -> void:
	if _is_puppet():
		return
	_pad_t = pad_time
	velocity += forward * pad_kick
	_fx.boost_pad()


## Start a fake hop (called by ramp.gd, the dormant obstacle): drop all
## collision so we sail over obstacles, and scale the visuals up for height.
func jump(dur: float) -> void:
	if _air_t <= 0.0:
		_base_layer = collision_layer
		_base_mask = collision_mask
		collision_layer = 0
		collision_mask = 0
		_fx.launch()
	_air_dur = maxf(dur, 0.1)
	_air_t = _air_dur


## One physics step in the air: no grip, no steering, no throttle; the car
## carries on (a little air drag) while the Look grows toward the camera and
## the shadow drifts off.
func _fly(delta: float) -> void:
	_air_t -= delta
	var p := clampf(1.0 - _air_t / _air_dur, 0.0, 1.0)
	var height := sin(p * PI)
	_look.set_air(height)
	_shadow.position = SHADOW_REST + SHADOW_LIFT * height
	_shadow.modulate.a = SHADOW_ALPHA * (1.0 - height * 0.55)
	_shadow.scale = Vector2(78.0, 104.0) * (1.0 - height * 0.25) / _shadow.texture.get_size()
	ang_vel = 0.0
	velocity *= 1.0 - 0.1 * delta
	boost_meter = minf(1.0, boost_meter + boost_recharge_rate * delta)
	var speed := velocity.length()
	_move(delta, speed)
	_look.flame = move_toward(_look.flame, 0.0, delta * 6.0)
	_fx.update(delta, speed / maxf(max_speed, 1.0), false, false)
	if _air_t <= 0.0:
		_land()
	_update_camera_zoom(delta, speed)
	_apply_shake(delta)


func _land() -> void:
	_air_t = 0.0
	_look.set_air(0.0)
	_shadow.position = SHADOW_REST
	_shadow.modulate.a = SHADOW_ALPHA
	_shadow.scale = Vector2(78.0, 104.0) / _shadow.texture.get_size()
	collision_layer = _base_layer
	collision_mask = _base_mask
	_shake = maxf(_shake, 7.0)   # landing thump
	_fx.land()


## Eases the camera out as speed rises (more road visible at speed) and back in
## when slow. Leaves Camera2D.offset alone — that's the shake's channel.
func _update_camera_zoom(delta: float, speed: float) -> void:
	var t := clampf(speed / max_speed, 0.0, 1.0)
	var target := camera_zoom_rest * lerpf(1.0, camera_zoom_at_top, t)
	if Layout.portrait:
		target *= camera_zoom_portrait
	if _boosting or _pad_t > 0.0:
		target *= boost_zoom_out
	var cam := $Camera2D
	var z := lerpf(cam.zoom.x, target, clampf(camera_zoom_lerp * delta, 0.0, 1.0))
	cam.zoom = Vector2(z, z)


## Skid marks from the rear tyres while sliding (tyre smoke is the Fx's).
func _update_tire_fx(skidding: bool) -> void:
	if skidding and _tiremarks != null:
		if not _skid_active:
			_skid_active = true
			_skid_l = _new_skid_line()
			_skid_r = _new_skid_line()
		var rl := to_global(WHEEL_RL)
		var pc := _skid_l.get_point_count()
		if pc == 0 or _skid_l.get_point_position(pc - 1).distance_to(rl) > 4.0:
			_skid_l.add_point(rl)
			_skid_r.add_point(to_global(WHEEL_RR))
	else:
		_skid_active = false


func _new_skid_line() -> Line2D:
	var l := Line2D.new()
	l.width = 6.0
	l.default_color = Color(Palette.BLACK, 0.55)
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
