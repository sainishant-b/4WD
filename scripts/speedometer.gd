extends Control
## Radial speedometer gauge (design system): a glass disc with a soft shadow, an
## inset background arc, a value arc that sweeps blue -> gold -> red with speed
## and ends in a glowing tip, tick marks, and a centre numeric readout. Floats
## over the play area.
##
## `set_max(top_speed)` once per race sets the scale; `set_value(px_per_sec)`
## each frame moves the arc. Colors come from the Palette autoload.

const START_ANGLE := deg_to_rad(135.0)   # low end: down-left ...
const SWEEP := deg_to_rad(270.0)         # ... sweeping over the top to down-right
const ARC_STEPS := 48                    # points along the full sweep

var _value: float = 0.0
var _max: float = 600.0

var _value_label: Label
var _caption: Label


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE  # never steal taps from the touch controls
	_value_label = _make_label(Palette.TEXT)
	_value_label.text = "0"
	_caption = _make_label(Palette.TEXT_MUTED)
	_caption.text = "SPD"
	_relayout()


func _make_label(color: Color) -> Label:
	var l := Label.new()
	HudStyle.style_panel_label(l, color)   # sits on the gauge's own disc
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(l)
	return l


func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED:
		_relayout()
		queue_redraw()


## Everything scales with the gauge, so the HUD can size it for a phone.
func _relayout() -> void:
	if _value_label == null:
		return
	var d := minf(size.x, size.y)
	_value_label.add_theme_font_size_override("font_size", roundi(d * 0.27))
	_value_label.position = Vector2(0, size.y * 0.5 - d * 0.2)
	_value_label.size = Vector2(size.x, d * 0.3)
	_caption.add_theme_font_size_override("font_size", roundi(d * 0.11))
	_caption.position = Vector2(0, size.y * 0.5 + d * 0.12)
	_caption.size = Vector2(size.x, d * 0.14)


func set_max(top_speed: float) -> void:
	_max = maxf(top_speed, 1.0)
	queue_redraw()


func set_value(px_per_sec: float) -> void:
	_value = px_per_sec
	_value_label.text = "%d" % int(px_per_sec)
	queue_redraw()


## Arc colour at `t` (0 = stopped, 1 = flat out).
func _heat(t: float) -> Color:
	if t < 0.6:
		return Palette.BLUE.lerp(Palette.GOLD, t / 0.6)
	return Palette.GOLD.lerp(Palette.DANGER, (t - 0.6) / 0.4)


func _draw() -> void:
	var c := size * 0.5
	var d := minf(size.x, size.y)
	var width := d / 14.0
	var r := d * 0.5 - width * 1.6
	var frac := clampf(_value / _max, 0.0, 1.0)

	# Soft shadow, then the glass disc with a hairline rim.
	HudStyle.draw_glow(self, c + Vector2(0, d * 0.04), d * 0.62, Color(Palette.BLACK, 0.55))
	draw_circle(c, d * 0.5, Color(Palette.BG_RAISED, 0.86), true, -1.0, true)
	draw_arc(c, d * 0.5 - 0.5, 0.0, TAU, 72, Color(Palette.TEXT, 0.14), 1.0, true)

	# Inset background arc with rounded ends.
	var well := Palette.STROKE
	draw_arc(c, r, START_ANGLE, START_ANGLE + SWEEP, ARC_STEPS, well, width, true)
	draw_circle(c + Vector2.from_angle(START_ANGLE) * r, width * 0.5, well, true, -1.0, true)
	draw_circle(c + Vector2.from_angle(START_ANGLE + SWEEP) * r, width * 0.5, well, true, -1.0, true)

	# Tick marks just inside the arc; every third one is brighter.
	var ticks := 9
	for i in ticks + 1:
		var dir := Vector2.from_angle(START_ANGLE + SWEEP * (float(i) / float(ticks)))
		var major := i % 3 == 0
		draw_line(
			c + dir * (r - width * 0.5 - (d * 0.07 if major else d * 0.045)),
			c + dir * (r - width * 0.5 - d * 0.02),
			Palette.TEXT_MUTED if major else Palette.STROKE_STRONG, 1.5, true
		)

	# Value arc: colour runs along its length, and the tip glows.
	if frac > 0.004:
		var steps := maxi(2, ceili(ARC_STEPS * frac))
		var points := PackedVector2Array()
		var colors := PackedColorArray()
		for i in steps + 1:
			var t := frac * float(i) / float(steps)
			points.append(c + Vector2.from_angle(START_ANGLE + SWEEP * t) * r)
			colors.append(_heat(t))
		draw_circle(points[0], width * 0.5, colors[0], true, -1.0, true)
		draw_polyline_colors(points, colors, width, true)
		var tip := points[points.size() - 1]
		var tip_color := _heat(frac)
		HudStyle.draw_glow(self, tip, width * 2.4, Color(tip_color, 0.6))
		draw_circle(tip, width * 0.5, tip_color, true, -1.0, true)
		draw_circle(tip, width * 0.24, Palette.TEXT, true, -1.0, true)
