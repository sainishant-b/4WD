extends CanvasLayer
## Race HUD (built in code): level + lap, total time, current lap time, best
## time + best lap, the wall-hit pips, a mini map, speedometer, boost meter, a
## 3-2-1-GO countdown, an off-screen arrow to the next gate, a controls legend
## (key caps, or thumb-pad icons on touch), and the Results / Game Over + Pause
## overlays. On touch it also shows a pause button.
##
## Readouts sit on translucent "glass" panels (HudStyle) so their text needs no
## outline; a faint vignette darkens the screen corners behind them.
##
## Nodes are created once in `_ready`; `_layout()` positions and sizes them and
## runs again whenever `Layout` flips (landscape <-> portrait, keyboard <-> touch).
##
## Styling follows the design system: gold next-gate arrow, Palette medal colors,
## and design-system modal dialogs (scrim + PanelModal card) for Results/Pause.
## Buttons emit `ui_action(name)` -> game.gd
## ("retry" | "next" | "leaderboard" | "menu" | "resume" | "pause").
##
## Inside a Reddit post the results card also shows the server's answer to the
## finish (`show_daily_pending` then `show_daily_result`): the place on the
## day's board ("#12 OF 340 TODAY"), NEW BEST and streak chips, a live
## countdown to the next circuit, and (logged in) an opt-in toggle that shows
## the streak as the player's Reddit user flair. Its gold button is
## Leaderboard, not Next.

signal ui_action(action: String)

const Speedometer := preload("res://scripts/speedometer.gd")
const Minimap := preload("res://scripts/minimap.gd")

const MODAL_WIDTH := 440.0

# Glass panels behind the readouts.
var _p_lap: Panel      # landscape only; in portrait the lap shares the top bar
var _p_time: Panel     # the timer card (landscape) / the whole top bar (portrait)
var _p_best: Panel
var _p_walls: Panel
var _p_hint: PanelContainer   # the controls legend; takes the size its rows need

var _level_label: Label
var _lap_label: Label
var _timer_label: Label
var _laptime_label: Label
var _best_cap: Label
var _best_label: Label
var _bestlap_cap: Label
var _bestlap_label: Label
var _walls_cap: Label
var _walls_pips: Control
var _wall_used: int = 0
var _wall_limit: int = 3
var _warn_label: Label
var _warn_tween: Tween
var _hit_flash: TextureRect
var _delta_label: Label
var _minimap: Control
var _speedo: Control
var _boost_cap: Label
var _boost_bar: Control
var _boost_well: StyleBoxFlat
var _boost_fill: StyleBoxFlat
var _boost_value: float = 1.0
var _countdown_label: Label
var _countdown_glow: TextureRect
var _arrow: Polygon2D
var _pause_button: Button
var _pause_bar: StyleBoxFlat

var _modal_panels: Array[PanelContainer] = []
var _results_overlay: Control
var _results_title: Label
var _results_body: Label
var _results_buttons: BoxContainer
var _results_next: Button
var _results_board: Button    # Reddit: the next step after a finish

# Reddit's part of the results card: today's place, streak, next circuit.
var _daily_box: VBoxContainer
var _daily_rank: Label
var _daily_chips: HBoxContainer
var _daily_next: Label
var _flair_btn: Button          # opt-in: show the streak as Reddit user flair
var _next_circuit_at: int = 0   # Time.get_ticks_msec() when the next circuit starts; 0 = unknown

var _pause_overlay: Control


func _ready() -> void:
	var root := Control.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)

	# Darkened corners: pulls the eye to the car and gives the panels depth.
	var vignette := TextureRect.new()
	vignette.texture = HudStyle.vignette()
	vignette.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	vignette.stretch_mode = TextureRect.STRETCH_SCALE
	vignette.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	vignette.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(vignette)

	_p_lap = _make_panel(root)
	_p_time = _make_panel(root)
	_p_best = _make_panel(root)
	_p_walls = _make_panel(root)
	_p_hint = PanelContainer.new()   # filled by _rebuild_hint(); pill and rows fade as one
	_p_hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var hint_box := HudStyle.glass(HudStyle.RADIUS, 0.74)
	hint_box.set_content_margin_all(10)
	hint_box.content_margin_left = 14.0
	hint_box.content_margin_right = 14.0
	_p_hint.add_theme_stylebox_override("panel", hint_box)
	root.add_child(_p_hint)

	_level_label = _make_label(root, "", Palette.TEXT_MUTED)
	_lap_label = _make_label(root, "LAP 1/3")

	_timer_label = _make_label(root, "0:00.00")
	_timer_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_laptime_label = _make_label(root, "LAP 0:00.00", Palette.TEXT_MUTED)
	_laptime_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER

	_best_cap = _make_label(root, "BEST", Palette.TEXT_MUTED)
	_best_label = _make_label(root, "--")
	_best_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_bestlap_cap = _make_label(root, "BEST LAP", Palette.TEXT_MUTED)
	_bestlap_label = _make_label(root, "--")
	_bestlap_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT

	# Wall hits: one pip per allowed hit, filling red; the last one ends the race.
	_walls_cap = _make_label(root, "WALL HITS", Palette.TEXT_MUTED)
	_walls_pips = Control.new()
	_walls_pips.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_walls_pips.draw.connect(_draw_wall_pips)
	root.add_child(_walls_pips)

	_minimap = Minimap.new()
	root.add_child(_minimap)

	_speedo = Speedometer.new()
	root.add_child(_speedo)

	# Boost meter: a pill just above the speedo (gold = ready, dim = depleted).
	_boost_cap = _make_label(root, "BOOST", Palette.TEXT, true)
	HudStyle.style_floating_label(_boost_cap, Palette.TEXT, true)
	_boost_cap.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_boost_well = HudStyle.pill(Color(Palette.SURFACE_INSET, 0.92))
	_boost_well.border_color = Color(Palette.TEXT, 0.14)
	_boost_well.set_border_width_all(1)
	_boost_fill = HudStyle.pill(Palette.GOLD)
	_boost_bar = Control.new()
	_boost_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_boost_bar.draw.connect(_draw_boost)
	root.add_child(_boost_bar)

	# Live split delta vs your best lap (green = ahead, red = behind); fades out.
	_delta_label = _make_label(root, "", Palette.TEXT, true)
	_delta_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_delta_label.visible = false

	# Wall-hit warning: a red flash round the screen edge and a short banner.
	_hit_flash = TextureRect.new()
	_hit_flash.texture = HudStyle.rim()
	_hit_flash.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_hit_flash.stretch_mode = TextureRect.STRETCH_SCALE
	_hit_flash.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_hit_flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hit_flash.modulate = Color(Palette.DANGER, 0.0)
	root.add_child(_hit_flash)
	_warn_label = _make_label(root, "", Palette.DANGER, true)
	_warn_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_warn_label.visible = false
	_box(_warn_label, 0.5, 0.39, -200, -44, 400, 88)

	# Countdown: a big number over a soft dark blob (a thick outline goes blocky
	# at this size), in the gap between the hint and the car rather than on top
	# of either.
	_countdown_glow = TextureRect.new()
	_countdown_glow.texture = HudStyle.glow()
	_countdown_glow.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_countdown_glow.stretch_mode = TextureRect.STRETCH_SCALE
	_countdown_glow.modulate = Color(Palette.BLACK, 0.6)
	_countdown_glow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_countdown_glow.visible = false
	root.add_child(_countdown_glow)
	_box(_countdown_glow, 0.5, 0.39, -150, -110, 300, 220)
	_countdown_label = _make_label(root, "", Palette.TEXT, true)
	_countdown_label.add_theme_font_size_override("font_size", 100)
	_countdown_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_countdown_label.visible = false
	_box(_countdown_label, 0.5, 0.39, -200, -70, 400, 140)

	# Next-gate arrow, with a soft dark copy behind so it reads over the road.
	var arrow_shape := PackedVector2Array([Vector2(0, -18), Vector2(13, 12), Vector2(0, 5), Vector2(-13, 12)])
	_arrow = Polygon2D.new()
	_arrow.polygon = arrow_shape
	_arrow.color = Palette.GOLD
	_arrow.antialiased = true
	_arrow.visible = false
	var arrow_shadow := Polygon2D.new()
	var grown := PackedVector2Array()
	for p in arrow_shape:
		grown.append(p * 1.32 + Vector2(0, 1.5))
	arrow_shadow.polygon = grown
	arrow_shadow.color = Color(Palette.BLACK, 0.5)
	arrow_shadow.antialiased = true
	arrow_shadow.show_behind_parent = true
	_arrow.add_child(arrow_shadow)
	add_child(_arrow)

	# Touch has no Esc key, so pausing needs a button: a glass chip with two bars.
	_pause_button = Button.new()
	_pause_button.focus_mode = Control.FOCUS_NONE
	_pause_button.add_theme_stylebox_override("normal", HudStyle.glass(12))
	_pause_button.add_theme_stylebox_override("hover", HudStyle.glass(12))
	_pause_button.add_theme_stylebox_override("pressed", HudStyle.glass(12, 0.95))
	_pause_bar = HudStyle.pill(Palette.TEXT, 2)
	_pause_button.draw.connect(_draw_pause_icon)
	_pause_button.pressed.connect(func(): ui_action.emit("pause"))
	root.add_child(_pause_button)

	_build_results_overlay(root)
	_build_pause_overlay(root)

	Layout.changed.connect(_layout)
	_layout()


func _make_panel(parent: Control, alpha: float = 0.78) -> Panel:
	var p := Panel.new()
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	p.add_theme_stylebox_override("panel", HudStyle.glass(HudStyle.RADIUS, alpha))
	parent.add_child(p)
	return p


## `floating` labels sit straight on the track and get a soft halo; the rest sit
## on a glass panel and stay clean.
func _make_label(parent: Control, text: String, color: Color = Palette.TEXT, floating := false) -> Label:
	var l := Label.new()
	l.text = text
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	if floating:
		HudStyle.style_floating_label(l, color)
	else:
		HudStyle.style_panel_label(l, color)
	parent.add_child(l)
	return l


# --- Layout ----------------------------------------------------------------

## Places `c` as a w x h box whose top-left sits (x, y) from the anchor point
## (ax, ay), each 0 = left/top, 0.5 = centre, 1 = right/bottom of the screen.
func _box(c: Control, ax: float, ay: float, x: float, y: float, w: float, h: float) -> void:
	c.anchor_left = ax
	c.anchor_right = ax
	c.anchor_top = ay
	c.anchor_bottom = ay
	c.offset_left = x
	c.offset_top = y
	c.offset_right = x + w
	c.offset_bottom = y + h


## Places `c` across the top of the screen, `inset` px in from both sides.
func _span(c: Control, inset: float, y: float, h: float) -> void:
	c.anchor_left = 0.0
	c.anchor_right = 1.0
	c.anchor_top = 0.0
	c.anchor_bottom = 0.0
	c.offset_left = inset
	c.offset_right = -inset
	c.offset_top = y
	c.offset_bottom = y + h


func _font(l: Label, size: int) -> void:
	l.add_theme_font_size_override("font_size", size)


func _layout() -> void:
	var touch := Layout.touch
	_pause_button.visible = touch
	_rebuild_hint(touch)

	if Layout.portrait:
		_layout_portrait()
	else:
		_layout_landscape(touch)
	_boost_bar.queue_redraw()

	var narrow := Layout.portrait
	for panel in _modal_panels:
		panel.custom_minimum_size.x = Layout.PORTRAIT_CONTENT_WIDTH if narrow else MODAL_WIDTH
	# Three buttons do not fit side by side on a phone; stack them instead.
	_results_buttons.vertical = narrow
	for b in _results_buttons.get_children():
		(b as Control).size_flags_horizontal = Control.SIZE_EXPAND_FILL if narrow else Control.SIZE_FILL


## Desktop / wide window: three cards along the top, the map under the right one.
func _layout_landscape(touch: bool) -> void:
	_p_lap.visible = true
	_box(_p_lap, 0.0, 0.0, 16, 12, 190, 66)
	_font(_level_label, 12)
	_box(_level_label, 0.0, 0.0, 32, 20, 160, 16)
	_font(_lap_label, 24)
	_box(_lap_label, 0.0, 0.0, 32, 38, 160, 32)

	_box(_p_time, 0.5, 0.0, -115, 12, 230, 80)
	_font(_timer_label, 38)
	_box(_timer_label, 0.5, 0.0, -110, 16, 220, 46)
	_font(_laptime_label, 14)
	_box(_laptime_label, 0.5, 0.0, -110, 63, 220, 20)

	# The corner belongs to the mute button (MuteButton autoload). On touch the
	# pause button sits beside it, and the best times move left of both.
	var corner := MuteButton.RESERVED_LANDSCAPE
	var right := -(corner + 56.0) if touch else -(corner + 4.0)
	_box(_pause_button, 1.0, 0.0, -(corner + 48.0), 12, 48, 48)
	_box(_p_best, 1.0, 0.0, right - 214, 12, 214, 66)
	_font(_best_cap, 12)
	_box(_best_cap, 1.0, 0.0, right - 198, 21, 90, 22)
	_font(_best_label, 18)
	_box(_best_label, 1.0, 0.0, right - 126, 20, 110, 24)
	_font(_bestlap_cap, 12)
	_box(_bestlap_cap, 1.0, 0.0, right - 198, 46, 90, 22)
	_font(_bestlap_label, 18)
	_box(_bestlap_label, 1.0, 0.0, right - 126, 45, 110, 24)

	_box(_minimap, 1.0, 0.0, -230, 90, 214, 136)

	_box(_p_walls, 0.0, 0.0, 16, 86, 190, 40)
	_font(_walls_cap, 12)
	_walls_cap.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	_box(_walls_cap, 0.0, 0.0, 32, 96, 84, 20)
	_box(_walls_pips, 0.0, 0.0, 114, 94, 78, 24)

	_place_hint(106)
	_font(_warn_label, 32)

	_box(_speedo, 0.5, 1.0, -62, -160, 124, 124)
	_box(_boost_bar, 0.5, 1.0, -62, -180, 124, 10)
	_font(_boost_cap, 12)
	_box(_boost_cap, 0.5, 1.0, -62, -200, 124, 16)
	_font(_delta_label, 28)
	_box(_delta_label, 0.5, 1.0, -100, -242, 200, 34)


## Phone: at least 430 x 760 logical px. One glass bar carries level, lap, timer
## and pause; best times and the mini map sit under it. The bottom corners
## belong to the thumb pads, so the gauge sits between them.
func _layout_portrait() -> void:
	_p_lap.visible = false
	_span(_p_time, 8, 8, 62)
	_font(_level_label, 11)
	_box(_level_label, 0.0, 0.0, 22, 17, 150, 14)
	_font(_lap_label, 21)
	_box(_lap_label, 0.0, 0.0, 22, 32, 150, 28)

	_font(_timer_label, 30)
	_box(_timer_label, 0.5, 0.0, -80, 12, 160, 36)
	_font(_laptime_label, 12)
	_box(_laptime_label, 0.5, 0.0, -80, 47, 160, 16)

	# Mute button in the corner (MuteButton autoload), pause just left of it.
	_box(_pause_button, 1.0, 0.0, -(MuteButton.RESERVED_PORTRAIT + 40.0), 19, 40, 40)

	_box(_p_best, 0.0, 0.0, 8, 78, 158, 54)
	_font(_best_cap, 11)
	_box(_best_cap, 0.0, 0.0, 21, 85, 70, 20)
	_font(_best_label, 15)
	_box(_best_label, 0.0, 0.0, 84, 85, 70, 20)
	_font(_bestlap_cap, 11)
	_box(_bestlap_cap, 0.0, 0.0, 21, 106, 70, 20)
	_font(_bestlap_label, 15)
	_box(_bestlap_label, 0.0, 0.0, 84, 106, 70, 20)

	_box(_minimap, 1.0, 0.0, -150, 78, 142, 96)

	_box(_p_walls, 0.0, 0.0, 174, 78, 98, 54)
	_font(_walls_cap, 10)
	_walls_cap.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_box(_walls_cap, 0.0, 0.0, 174, 84, 98, 16)
	_box(_walls_pips, 0.0, 0.0, 174, 102, 98, 24)

	_place_hint(184)
	_font(_warn_label, 26)

	_box(_speedo, 0.5, 1.0, -48, -128, 96, 96)
	_box(_boost_bar, 0.5, 1.0, -48, -146, 96, 9)
	_font(_boost_cap, 10)
	_box(_boost_cap, 0.5, 1.0, -48, -163, 96, 14)
	_font(_delta_label, 24)
	_box(_delta_label, 0.5, 1.0, -100, -200, 200, 30)


## Rebuilds the controls legend for the current device and layout: key caps for
## the keyboard, little thumb pads for touch. A phone gets shorter rows.
func _rebuild_hint(touch: bool) -> void:
	for child in _p_hint.get_children():
		_p_hint.remove_child(child)
		child.queue_free()
	var narrow := Layout.portrait
	var per_row := (2 if touch else 3) if narrow else 6
	_p_hint.add_child(HudStyle.controls_legend(touch, per_row, 13 if narrow else 14))


## Centres the legend `y` px from the top; it grows to whatever its rows need.
func _place_hint(y: float) -> void:
	_p_hint.anchor_left = 0.5
	_p_hint.anchor_right = 0.5
	_p_hint.anchor_top = 0.0
	_p_hint.anchor_bottom = 0.0
	_p_hint.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_p_hint.grow_vertical = Control.GROW_DIRECTION_END
	_p_hint.offset_left = 0.0
	_p_hint.offset_right = 0.0
	_p_hint.offset_top = y
	_p_hint.offset_bottom = y
	_p_hint.reset_size()


func _draw_wall_pips() -> void:
	if _wall_limit <= 0:
		return
	var area := _walls_pips.size
	var r := minf(8.0, area.y * 0.5 - 2.0)
	var gap := r * 2.0 + 8.0
	var x0 := area.x * 0.5 - gap * (_wall_limit - 1) * 0.5
	for i in _wall_limit:
		var c := Vector2(x0 + gap * i, area.y * 0.5)
		if i < _wall_used:
			HudStyle.draw_glow(_walls_pips, c, r * 2.2, Color(Palette.DANGER, 0.55))
			_walls_pips.draw_circle(c, r, Palette.DANGER, true, -1.0, true)
		else:
			_walls_pips.draw_circle(c, r, Color(Palette.SURFACE_INSET, 0.9), true, -1.0, true)
			_walls_pips.draw_arc(c, r, 0.0, TAU, 32, Palette.STROKE_STRONG, 1.5, true)


func _medal_color(medal: String) -> Color:
	match medal:
		"gold": return Palette.MEDAL_GOLD
		"silver": return Palette.MEDAL_SILVER
		"bronze": return Palette.MEDAL_BRONZE
		_: return Palette.TEXT


func _draw_boost() -> void:
	var area := Rect2(Vector2.ZERO, _boost_bar.size)
	_boost_bar.draw_style_box(_boost_well, area)
	var inner := area.grow(-2.0)
	var w := inner.size.x * _boost_value
	if w < inner.size.y:
		return   # too short to draw as a pill
	var low := _boost_value < 0.15
	_boost_fill.bg_color = Palette.TEXT_DIM if low else Palette.GOLD
	if not low:
		# A little light spilling from the bright end of the bar.
		HudStyle.draw_glow(
			_boost_bar, Vector2(inner.position.x + w - inner.size.y * 0.5, area.size.y * 0.5),
			area.size.y * 1.6, Color(Palette.GOLD_BRIGHT, 0.45)
		)
	_boost_bar.draw_style_box(_boost_fill, Rect2(inner.position, Vector2(w, inner.size.y)))


func _draw_pause_icon() -> void:
	var s := _pause_button.size
	var bar := Vector2(maxf(4.0, s.x * 0.11), s.y * 0.38)
	for side in [-1.0, 1.0]:
		var centre: Vector2 = s * 0.5 + Vector2(side * bar.x * 0.95, 0.0)
		_pause_button.draw_style_box(_pause_bar, Rect2(centre - bar * 0.5, bar))


# --- Live HUD --------------------------------------------------------------

func set_level_name(name: String) -> void:
	_level_label.text = name.to_upper()


func set_timer(seconds: float) -> void:
	_timer_label.text = Game.format_time(seconds)


func set_lap_time(seconds: float) -> void:
	_laptime_label.text = "LAP " + Game.format_time(seconds)


func set_lap(cur: int, total: int) -> void:
	_lap_label.text = "LAP %d/%d" % [cur, total]


func set_best(seconds: float) -> void:
	_best_label.text = Game.format_time(seconds)


func set_best_lap(seconds: float) -> void:
	_bestlap_label.text = Game.format_time(seconds)


func flash_best_lap() -> void:
	_bestlap_label.modulate = Palette.GOLD
	var tw := create_tween()
	tw.tween_property(_bestlap_label, "modulate", Color(1, 1, 1, 1), 0.8)


func set_speed(px_per_sec: float) -> void:
	_speedo.set_value(px_per_sec)


## Sets the speedometer's full-scale value (call once per race).
func set_speed_max(top_speed: float) -> void:
	_speedo.set_max(top_speed)


## Updates the boost meter (0..1); gold when usable, dimmed when nearly empty.
func set_boost(t: float) -> void:
	var v := clampf(t, 0.0, 1.0)
	if is_equal_approx(v, _boost_value):
		return
	_boost_value = v
	_boost_bar.queue_redraw()


## Shows `used` of `limit` wall hits on the pips. A limit of 0 hides the readout
## (multiplayer, where the rule is off).
func set_wall_touches(used: int, limit: int) -> void:
	_wall_used = used
	_wall_limit = limit
	var on := limit > 0
	_p_walls.visible = on
	_walls_cap.visible = on
	_walls_pips.visible = on
	_walls_pips.queue_redraw()


## After a counted wall hit that did not end the race: a red flash round the
## screen edge and a banner saying how many are left.
func show_wall_warning(used: int, limit: int) -> void:
	var left := limit - used
	_warn_label.text = "WALL HIT %d/%d\n%s" % [
		used, limit, "LAST WARNING" if left <= 1 else "%d LEFT" % left
	]
	_warn_label.modulate.a = 1.0
	_warn_label.visible = true
	if _warn_tween != null:
		_warn_tween.kill()
	_warn_tween = create_tween()
	_warn_tween.tween_interval(1.3)
	_warn_tween.tween_property(_warn_label, "modulate:a", 0.0, 0.5)
	_flash()


func _flash() -> void:
	_hit_flash.modulate = Color(Palette.DANGER, 0.85)
	create_tween().tween_property(_hit_flash, "modulate:a", 0.0, 0.7)


## Hands the mini map the circuit (world space); gate 0 is the start/finish line.
func set_track(centerline: PackedVector2Array, gates: PackedVector2Array) -> void:
	_minimap.set_track(centerline, gates)


## Tells the mini map which gate to highlight.
func set_next_gate(index: int) -> void:
	_minimap.set_next_gate(index)


## Moves the mini map's car marker (`heading` = the car's rotation).
func set_car(world_pos: Vector2, heading: float) -> void:
	_minimap.set_car(world_pos, heading)


## Pops a transient split delta vs the best lap; negative = ahead (green).
func show_delta(delta: float) -> void:
	_delta_label.text = "%+.2f" % delta
	_delta_label.add_theme_color_override(
		"font_color", Palette.SUCCESS if delta < 0.0 else Palette.DANGER
	)
	_delta_label.modulate.a = 1.0
	_delta_label.visible = true
	var tw := create_tween()
	tw.tween_interval(1.4)
	tw.tween_property(_delta_label, "modulate:a", 0.0, 0.8)


## Called at GO. On touch the hint has done its job once the player is moving,
## and the screen is small, so it fades; the keyboard hint stays as before.
func fade_hint() -> void:
	if not Layout.touch:
		return
	var tw := create_tween()
	tw.tween_interval(8.0)
	tw.tween_property(_p_hint, "modulate:a", 0.0, 1.0)


func show_countdown(text: String) -> void:
	_countdown_label.text = text
	# Gold for "GO!", white (with a dark halo) for the 3-2-1 numbers.
	_countdown_label.add_theme_color_override(
		"font_color", Palette.GOLD if text.begins_with("GO") else Palette.TEXT
	)
	_countdown_label.visible = true
	_countdown_glow.visible = true


func hide_countdown() -> void:
	_countdown_label.visible = false
	_countdown_glow.visible = false


## `rel` is the on-screen angle to the next gate (0 = straight ahead, clockwise +).
func set_arrow(visible_: bool, rel: float) -> void:
	_arrow.visible = visible_
	if not visible_:
		return
	var view := get_viewport().get_visible_rect().size
	var radius := minf(150.0, view.x * 0.32)
	_arrow.position = view / 2.0 + Vector2(sin(rel), -cos(rel)) * radius
	_arrow.rotation = rel


# --- Overlays --------------------------------------------------------------

## A full-rect dimming overlay holding a centered PanelModal card. Returns the
## inner VBox to fill with content; `overlay` is what we toggle visible.
func _make_modal(parent: Control, scrim: Color) -> Array:
	var overlay := Control.new()
	overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	overlay.visible = false
	parent.add_child(overlay)

	var dim := ColorRect.new()
	dim.color = scrim
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)  # swallows clicks behind
	overlay.add_child(dim)

	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	overlay.add_child(center)

	var panel := PanelContainer.new()
	panel.theme_type_variation = "PanelModal"
	center.add_child(panel)
	_modal_panels.append(panel)

	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 12)
	panel.add_child(vb)
	return [overlay, vb]


func _build_results_overlay(parent: Control) -> void:
	var made := _make_modal(parent, Palette.HUD_SCRIM_STRONG)
	_results_overlay = made[0]
	var vb: VBoxContainer = made[1]

	_results_title = Label.new()
	_results_title.add_theme_font_size_override("font_size", 34)
	_results_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vb.add_child(_results_title)

	_results_body = Label.new()
	_results_body.add_theme_font_size_override("font_size", 22)
	_results_body.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vb.add_child(_results_body)

	# Reddit only: an inset strip with today's place, the streak and a countdown.
	var daily_panel := PanelContainer.new()
	var inset := HudStyle.glass(12, 0.9)
	inset.bg_color = Color(Palette.SURFACE_INSET, 0.9)
	inset.set_content_margin_all(12)
	daily_panel.add_theme_stylebox_override("panel", inset)
	vb.add_child(daily_panel)
	_daily_box = VBoxContainer.new()
	_daily_box.add_theme_constant_override("separation", 8)
	daily_panel.add_child(_daily_box)
	_daily_rank = Label.new()
	_daily_rank.add_theme_font_size_override("font_size", 28)
	_daily_rank.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_daily_box.add_child(_daily_rank)
	_daily_chips = HBoxContainer.new()
	_daily_chips.alignment = BoxContainer.ALIGNMENT_CENTER
	_daily_chips.add_theme_constant_override("separation", 8)
	_daily_box.add_child(_daily_chips)
	_daily_next = Label.new()
	_daily_next.add_theme_font_size_override("font_size", 16)
	_daily_next.add_theme_color_override("font_color", Palette.TEXT_MUTED)
	_daily_next.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_daily_box.add_child(_daily_next)
	# Opt-in streak flair: off unless the player turns it on here.
	_flair_btn = Button.new()
	_flair_btn.theme_type_variation = "ButtonGhost"
	_flair_btn.custom_minimum_size = Vector2(0, 40)
	_flair_btn.add_theme_font_size_override("font_size", 14)
	_flair_btn.focus_mode = Control.FOCUS_NONE
	_flair_btn.visible = false
	_flair_btn.pressed.connect(_on_flair_pressed)
	_daily_box.add_child(_flair_btn)
	Leaderboard.flair_changed.connect(_on_flair_changed)
	daily_panel.visible = false

	_results_buttons = BoxContainer.new()
	_results_buttons.alignment = BoxContainer.ALIGNMENT_CENTER
	_results_buttons.add_theme_constant_override("separation", 12)
	vb.add_child(_results_buttons)
	_add_action_button(_results_buttons, "Retry", "retry", "ButtonSecondary")
	_results_next = _add_action_button(_results_buttons, "Next", "next")          # gold forward CTA
	_results_board = _add_action_button(_results_buttons, "Leaderboard", "leaderboard")   # gold, Reddit
	_results_board.visible = false
	_add_action_button(_results_buttons, "Menu", "menu", "ButtonGhost")


func _build_pause_overlay(parent: Control) -> void:
	var made := _make_modal(parent, Palette.HUD_SCRIM)
	_pause_overlay = made[0]
	var vb: VBoxContainer = made[1]

	var title := Label.new()
	title.text = "PAUSED"
	title.add_theme_font_size_override("font_size", 34)
	title.add_theme_color_override("font_color", Palette.GOLD)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vb.add_child(title)

	_add_action_button(vb, "Resume", "resume")                       # gold primary
	_add_action_button(vb, "Restart", "retry", "ButtonSecondary")
	_add_action_button(vb, "Menu", "menu", "ButtonGhost")

	var vol_label := Label.new()
	vol_label.text = "Volume"
	vb.add_child(vol_label)
	var slider := HSlider.new()
	slider.min_value = 0.0
	slider.max_value = 1.0
	slider.step = 0.01
	slider.value = Game.get_volume()
	slider.custom_minimum_size = Vector2(0, 36)
	slider.value_changed.connect(func(v): Game.set_volume(v))
	vb.add_child(slider)


func _add_action_button(parent: Node, text: String, action: String, variation := "") -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(130, 48)
	b.focus_mode = Control.FOCUS_NONE
	if variation != "":
		b.theme_type_variation = variation
	b.pressed.connect(func(): ui_action.emit(action))
	parent.add_child(b)
	return b


func show_results(total: float, medal: String, best_total: float, best_lap: float, has_next: bool) -> void:
	if medal == "none":
		_results_title.text = "FINISHED"
		_results_title.add_theme_color_override("font_color", Palette.TEXT)
	else:
		_results_title.text = medal.to_upper() + " MEDAL"
		_results_title.add_theme_color_override("font_color", _medal_color(medal))
	_results_body.text = "Total   %s\nBest    %s\nBest lap   %s" % [
		Game.format_time(total), Game.format_time(best_total), Game.format_time(best_lap)
	]
	_results_next.visible = has_next
	_results_board.visible = false
	_daily_box.get_parent().visible = false
	_arrow.visible = false   # it draws above the overlays
	_results_overlay.visible = true


## Reddit: the results card while the time is on its way to the server. The
## gold button becomes Leaderboard, the one clear next step.
func show_daily_pending() -> void:
	_daily_rank.text = "POSTING YOUR TIME..."
	_daily_rank.add_theme_color_override("font_color", Palette.TEXT_MUTED)
	_clear_daily_chips()
	_daily_next.text = ""
	_next_circuit_at = 0
	_flair_btn.visible = false
	_results_next.visible = false
	_results_board.visible = true
	_daily_box.get_parent().visible = true


## Reddit: the server's answer (Leaderboard.run_recorded): today's place, the
## streak, a new-best chip and the countdown to the next circuit.
func show_daily_result(info: Dictionary) -> void:
	_clear_daily_chips()
	if info.is_empty():
		_daily_rank.text = "COULDN'T REACH REDDIT"
		_daily_rank.add_theme_color_override("font_color", Palette.TEXT_MUTED)
		_daily_next.text = "Your time is saved on this device."
		return
	if not bool(info.get("accepted", false)):
		_daily_rank.text = "LOG IN TO RANK"
		_daily_rank.add_theme_color_override("font_color", Palette.TEXT_MUTED)
	elif int(info.get("rank", 0)) > 0:
		var where := "TODAY" if Reddit.is_today else "ON DAY %d" % Reddit.day
		_daily_rank.text = "#%d OF %d %s" % [int(info["rank"]), int(info.get("players", 0)), where]
		_daily_rank.add_theme_color_override("font_color", Palette.GOLD)
	else:
		_daily_rank.text = "TIME SAVED"
		_daily_rank.add_theme_color_override("font_color", Palette.TEXT)
	if bool(info.get("improved", false)) and bool(info.get("accepted", false)):
		_daily_chips.add_child(_chip("NEW BEST", Palette.SUCCESS))
	var streak := int(info.get("streak", 0))
	if streak > 0:
		_daily_chips.add_child(_chip("%d-DAY STREAK" % streak if streak > 1 else "STREAK STARTED", Palette.GOLD))
	var next_ms := int(info.get("next_ms", 0))
	_next_circuit_at = int(info.get("at_msec", Time.get_ticks_msec())) + next_ms if next_ms > 0 else 0
	_update_countdown()
	# Only a logged-in player has a flair to set.
	_flair_btn.visible = bool(info.get("accepted", false))
	_show_flair_state(bool(info.get("flair_on", Reddit.flair_on)), "")


func _on_flair_pressed() -> void:
	_flair_btn.disabled = true
	_flair_btn.text = "UPDATING FLAIR..."
	Leaderboard.set_flair(not Reddit.flair_on)


func _on_flair_changed(on: bool, error: String) -> void:
	_show_flair_state(on, error)


func _show_flair_state(on: bool, error: String) -> void:
	_flair_btn.disabled = false
	if error != "":   # the reason is in the server log; keep the button short
		_flair_btn.text = "FLAIR UNAVAILABLE  ·  TRY AGAIN"
	elif on:
		_flair_btn.text = "STREAK FLAIR ON  ·  TURN OFF"
	else:
		_flair_btn.text = "SHOW MY STREAK AS FLAIR"


func _clear_daily_chips() -> void:
	for c in _daily_chips.get_children():
		c.queue_free()


## A small filled pill with dark text.
func _chip(text: String, color: Color) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", 13)
	l.add_theme_color_override("font_color", Palette.TEXT_ON_GOLD)
	var pill := HudStyle.pill(color)
	pill.content_margin_left = 10.0
	pill.content_margin_right = 10.0
	pill.content_margin_top = 2.0
	pill.content_margin_bottom = 2.0
	l.add_theme_stylebox_override("normal", pill)
	return l


func _process(_delta: float) -> void:
	if _next_circuit_at > 0 and _results_overlay.visible:
		_update_countdown()


func _update_countdown() -> void:
	if _next_circuit_at <= 0:
		return
	var left := (_next_circuit_at - Time.get_ticks_msec()) / 1000
	if left <= 0:
		_daily_next.text = "A NEW CIRCUIT IS UP"
		return
	_daily_next.text = "NEXT CIRCUIT IN %d:%02d:%02d" % [left / 3600, (left / 60) % 60, left % 60]


## The race ended on the last allowed wall hit. It reuses the results card, but
## there is nothing to record and no next level to offer.
func show_game_over(hits: int, lap: int, laps: int, elapsed: float) -> void:
	_results_title.text = "GAME OVER"
	_results_title.add_theme_color_override("font_color", Palette.DANGER)
	_results_body.text = "%d wall hits\nLap %d of %d   %s" % [hits, lap, laps, Game.format_time(elapsed)]
	_results_next.visible = false
	_results_board.visible = false
	_daily_box.get_parent().visible = false
	_next_circuit_at = 0
	_arrow.visible = false   # it draws above the overlays
	_warn_label.visible = false
	_flash()
	_results_overlay.visible = true


func hide_results() -> void:
	_results_overlay.visible = false


func show_pause(p: bool) -> void:
	if p:
		_arrow.visible = false   # it draws above the overlays; game.gd re-shows it on resume
	_pause_overlay.visible = p
