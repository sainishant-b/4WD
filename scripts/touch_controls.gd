extends CanvasLayer
## On-screen twin thumb pads for touchscreens (multi-touch, drawn in code).
##
##   LEFT pad  -> front wheels      RIGHT pad -> rear wheels   (slide left / right)
##   push either pad UP        -> accelerate (further = more throttle)
##   push BOTH pads fully up   -> boost
##   pull ONE pad down         -> handbrake (drift)
##   pull BOTH pads down       -> brake, then reverse
##
## A pad re-centres under the thumb wherever it lands in its half of the lower
## screen, so "up" always means "up from where you touched". Everything is
## written into the InputState autoload, so the car treats touch and keyboard
## identically.
##
## Godot's own Controls follow a single pointer, which cannot steer two axles
## at once; hence the raw InputEventScreenTouch / ScreenDrag handling here.
## A real mouse works too, as one more finger (one pad at a time), so the pads
## can be tried in a desktop browser's mobile view.
## Shown only while `Layout.touch` is true. game.gd calls `set_enabled(false)`
## while the race is paused or finished.

const PAD_RADIUS := 62.0       # drawn base ring
const KNOB_RADIUS := 26.0
const TRAVEL := 52.0           # thumb travel (px) for full deflection on either axis
const STEER_DEADZONE := 0.10
const UP_DEADZONE := 0.22      # ignore the vertical wobble of a thumb that is only steering
const DOWN_AT := 0.5           # pull at least this far down to count as "down"
const BOOST_AT := 0.85         # both pads at least this far up = boost
const ZONE_TOP := 0.42         # the pads own the screen below this fraction of its height
const EDGE_MARGIN := 18.0
const MOUSE_FINGER := 1000     # finger index given to a real mouse (touch indices are small)


class Pad:
	var label: String
	var color: Color
	var finger: int = -1             # touch index holding this pad, -1 = free
	var center: Vector2 = Vector2.ZERO   # where the base is drawn
	var vec: Vector2 = Vector2.ZERO      # deflection, each axis -1..1 (up is negative y)


var _pads: Array[Pad] = []
var _surface: Control
var _enabled: bool = true
var _chip_box := HudStyle.chip(Palette.SURFACE)   # behind the FRONT / REAR names


func _ready() -> void:
	# Front axle = the car's red-orange, rear axle = hero gold (design tokens).
	_pads = [_make_pad("FRONT", Palette.POP), _make_pad("REAR", Palette.GOLD)]

	_surface = Control.new()
	_surface.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_surface.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_surface.draw.connect(_draw_pads)
	add_child(_surface)

	Layout.changed.connect(_sync_visibility)
	_sync_visibility()


func _make_pad(label: String, color: Color) -> Pad:
	var pad := Pad.new()
	pad.label = label
	pad.color = color
	return pad


## Off: lets go of both pads, hides them and ignores touches until on again.
func set_enabled(on: bool) -> void:
	_enabled = on
	_surface.visible = on
	if not on:
		_release_all()


func _sync_visibility() -> void:
	visible = Layout.touch
	if not visible:
		_release_all()


func _release_all() -> void:
	for pad in _pads:
		pad.finger = -1
		pad.vec = Vector2.ZERO
	_publish()


func _input(event: InputEvent) -> void:
	if not _enabled or not visible:
		return
	if event is InputEventScreenTouch:
		if event.pressed:
			_press(event.index, event.position)
		else:
			_release(event.index)
	elif event is InputEventScreenDrag:
		_drag(event.index, event.position)
	# Mouse events copied from a touch carry DEVICE_ID_EMULATION; only a real
	# mouse counts here, or every touch would press a pad twice.
	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT \
			and event.device != InputEvent.DEVICE_ID_EMULATION:
		if event.pressed:
			_press(MOUSE_FINGER, event.position)
		else:
			_release(MOUSE_FINGER)
	elif event is InputEventMouseMotion and event.device != InputEvent.DEVICE_ID_EMULATION:
		_drag(MOUSE_FINGER, event.position)


func _press(finger: int, pos: Vector2) -> void:
	var view := Layout.view_size()
	if pos.y < view.y * ZONE_TOP:
		return
	var pad := _pads[0] if pos.x < view.x * 0.5 else _pads[1]
	if pad.finger != -1:
		return
	pad.finger = finger
	pad.vec = Vector2.ZERO
	# Keep the whole base on screen even when the thumb lands near an edge.
	var inset := PAD_RADIUS + 4.0
	pad.center = pos.clamp(Vector2(inset, inset), view - Vector2(inset, inset))


func _drag(finger: int, pos: Vector2) -> void:
	for pad in _pads:
		if pad.finger == finger:
			var offset := (pos - pad.center) / TRAVEL
			pad.vec = offset.clamp(-Vector2.ONE, Vector2.ONE)


func _release(finger: int) -> void:
	for pad in _pads:
		if pad.finger == finger:
			pad.finger = -1
			pad.vec = Vector2.ZERO


func _process(_delta: float) -> void:
	if not visible:
		return
	# Idle pads rest in the bottom corners (recomputed so they follow a resize).
	var view := Layout.view_size()
	var inset := EDGE_MARGIN + PAD_RADIUS
	if _pads[0].finger == -1:
		_pads[0].center = Vector2(inset, view.y - inset)
	if _pads[1].finger == -1:
		_pads[1].center = Vector2(view.x - inset, view.y - inset)
	_publish()
	_surface.queue_redraw()


## Translates the two pad deflections into the car's inputs.
func _publish() -> void:
	var front := _pads[0].vec
	var rear := _pads[1].vec
	InputState.touch_front = _past_deadzone(front.x, STEER_DEADZONE)
	InputState.touch_rear = _past_deadzone(rear.x, STEER_DEADZONE)

	var up_front := maxf(0.0, -_past_deadzone(front.y, UP_DEADZONE))
	var up_rear := maxf(0.0, -_past_deadzone(rear.y, UP_DEADZONE))
	var down_front := front.y >= DOWN_AT
	var down_rear := rear.y >= DOWN_AT

	if down_front and down_rear:
		InputState.touch_throttle = -1.0
		InputState.touch_handbrake = false
	else:
		InputState.touch_throttle = maxf(up_front, up_rear)
		InputState.touch_handbrake = down_front or down_rear
	InputState.touch_boost = up_front >= BOOST_AT and up_rear >= BOOST_AT


## Rescales `v` (-1..1) so it reads 0 inside the deadzone and still reaches +/-1.
func _past_deadzone(v: float, deadzone: float) -> float:
	if absf(v) <= deadzone:
		return 0.0
	return signf(v) * (absf(v) - deadzone) / (1.0 - deadzone)


func _draw_pads() -> void:
	var font := _surface.get_theme_default_font()
	var braking := InputState.touch_throttle < 0.0
	for pad in _pads:
		var held := pad.finger != -1
		var c := pad.center

		# Base: a soft shadow, an INK lip, a deep-blue well lit faintly in the
		# pad's colour, and a thick ring in that colour inside an INK rim. The ring
		# brightens (with a halo) while a thumb is on it.
		HudStyle.draw_glow(_surface, c + Vector2(0, 8.0), PAD_RADIUS * 1.35, Color(Palette.BLACK, 0.5))
		_surface.draw_circle(c + Vector2(0, HudStyle.LIP), PAD_RADIUS + 4.0, Palette.INK, true, -1.0, true)
		_surface.draw_circle(c, PAD_RADIUS + 4.0, Palette.INK, true, -1.0, true)
		_surface.draw_circle(c, PAD_RADIUS, Color(Palette.BG_RAISED, 0.92), true, -1.0, true)
		HudStyle.draw_glow(_surface, c, PAD_RADIUS, Color(pad.color, 0.22 if held else 0.1))
		if held:
			_surface.draw_arc(c, PAD_RADIUS - 6.0, 0.0, TAU, 64, Color(pad.color, 0.25), 8.0, true)
		_surface.draw_arc(c, PAD_RADIUS - 2.5, 0.0, TAU, 64, Color(pad.color, 1.0 if held else 0.8), 5.0, true)
		_draw_chevron(c + Vector2(0, -PAD_RADIUS + 15.0), -1.0, pad.vec.y < -UP_DEADZONE)
		_draw_chevron(c + Vector2(0, PAD_RADIUS - 15.0), 1.0, pad.vec.y >= DOWN_AT)

		# The knob takes the colour of what the gesture is doing right now.
		var knob := pad.color
		if braking:
			knob = Palette.DANGER
		elif InputState.touch_boost:
			knob = Palette.GOLD_BRIGHT
		elif pad.vec.y >= DOWN_AT:
			knob = Palette.WARNING
		var at := c + pad.vec * TRAVEL
		var alpha := 0.96 if held else 0.7
		HudStyle.draw_glow(_surface, at + Vector2(0, 6.0), KNOB_RADIUS * 1.5, Color(Palette.BLACK, 0.55))
		if held:
			HudStyle.draw_glow(_surface, at, KNOB_RADIUS * 1.9, Color(knob, 0.45))
		# The knob: INK lip and rim, a darker edge, then the face.
		_surface.draw_circle(at + Vector2(0, 4.0), KNOB_RADIUS + 2.5, Color(Palette.INK, alpha), true, -1.0, true)
		_surface.draw_circle(at, KNOB_RADIUS + 2.5, Color(Palette.INK, alpha), true, -1.0, true)
		_surface.draw_circle(at, KNOB_RADIUS, Color(knob.darkened(0.2), alpha), true, -1.0, true)
		_surface.draw_circle(at + Vector2(0, -1.5), KNOB_RADIUS - 3.5, Color(knob, alpha), true, -1.0, true)
		# A highlight toward the top, as if lit from above.
		HudStyle.draw_glow(
			_surface, at + Vector2(0, -KNOB_RADIUS * 0.34), KNOB_RADIUS * 0.62, Color(Palette.TEXT_LIGHT, 0.45 * alpha)
		)

		if not held:
			# The pad's name on a cream chip just above it.
			var text_w := font.get_string_size(pad.label, HORIZONTAL_ALIGNMENT_LEFT, -1, 13).x
			var chip := Rect2(c.x - text_w * 0.5 - 12.0, c.y - PAD_RADIUS - 34.0, text_w + 24.0, 22.0)
			_surface.draw_style_box(_chip_box, chip)
			_surface.draw_string(
				font, Vector2(chip.position.x, chip.position.y + 16.0), pad.label,
				HORIZONTAL_ALIGNMENT_CENTER, chip.size.x, 13, Palette.TEXT
			)


## A thin arrowhead centred on `at`, pointing up (dir -1) or down (dir +1).
func _draw_chevron(at: Vector2, dir: float, lit: bool) -> void:
	_surface.draw_polyline(
		PackedVector2Array([
			at + Vector2(-8.0, -4.0 * dir), at + Vector2(0, 4.0 * dir), at + Vector2(8.0, -4.0 * dir)
		]),
		Palette.TEXT_LIGHT if lit else Color(Palette.TEXT_LIGHT, 0.35), 2.5, true
	)
