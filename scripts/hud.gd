extends CanvasLayer
## Race HUD (built in code): level + lap, total time, current lap time, best
## time + best lap, the wall-hit pips (the newest one swells as it fills), a mini
## map, speedometer, boost meter, start lights (three lamps lit red with the
## 3-2-1 beeps, all green on GO), an off-screen arrow to the next gate, a keyboard controls
## legend (key caps; H hides it, remembered in the settings), and the Results /
## Game Over + Pause overlays. On touch it shows a pause button and no legend
## (the user: it covered the road; How to Play shows the pads). In a wide
## keyboard window the mini map sits bottom-left
## and the legend bottom-right, so the top row is only lap, timer and best.
##
## Readouts sit on solid cream panels (`HudStyle.panel()`: INK outline and a hard
## lip) in dark ink, so their text needs no outline; a faint vignette darkens
## the screen corners behind them. Text straight over the track is white with
## an INK halo.
##
## Nodes are created once in `_ready`; `_layout()` positions and sizes them and
## runs again whenever `Layout` flips (landscape <-> portrait, keyboard <-> touch).
##
## Styling follows the design system: gold next-gate arrow, Palette medal colors
## (as INK-outlined "sticker" titles on the cream card), and design-system modal
## dialogs (scrim + PanelModal card) for Results/Pause.
## Buttons emit `ui_action(name)` -> game.gd
## ("retry" | "next" | "leaderboard" | "menu" | "resume" | "pause").
##
## The results card: a medal disc on ribbons poking out of its top edge, the
## title, the times in a sunk well, then Retry beside the gold next step and
## Menu under them. Game over reuses it with a red disc and a cross. A new best
## time gets a gold NEW BEST sticker slapped on the card's top-right corner (with
## how much it beat the old one by) and a chime; a better medal than before makes
## the disc pop.
##
## Inside a Reddit post the results card also shows the server's answer to the
## finish (`show_daily_pending` then `show_daily_result`): the place on the
## day's board on a gold plate ("#12 / TODAY'S RANK / of 340 racers") that pops
## in with the number rolling down to it (TOP 10 / FASTEST for the best
## places, and an UP n chip when it climbed), the NEW BEST sticker when the
## server says the time beat the player's best, a streak chip with a flame
## (it pops when the streak grew), a live countdown to the next circuit, and
## (logged in) an opt-in switch that shows the streak as the player's Reddit
## user flair. Its gold button is Leaderboard, not Next.

signal ui_action(action: String)

const Speedometer := preload("res://scripts/speedometer.gd")
const Minimap := preload("res://scripts/minimap.gd")

const MODAL_WIDTH := 440.0
const LIGHTS_SIZE := Vector2(184, 62)   # the start lights' bar
const LAMP_R := 17.0
const LAMP_GAP := 52.0

# Cream panels behind the readouts.
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
var _wall_limit: int = 5
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
var _countdown_label: Label      # "GO!", under the start lights
var _countdown_glow: TextureRect
var _start_box: Control          # the start lights, GO! and the blob behind; fades as one
var _lights: Control
var _lights_face: StyleBoxFlat
var _lights_on: int = 0          # lamps lit
var _lights_go := false          # all green
var _light_pop: float = 0.0      # 1 -> 0 as the lamp just lit settles
var _pip_pop: float = 0.0        # 1 -> 0 as the newest wall-hit pip settles
var _results_card: Control       # the results card itself (the sticker sits on its corner)
var _best_sticker: Control
var _arrow: Polygon2D
var _pause_button: Button
var _pause_bar: StyleBoxFlat

var _modal_panels: Array[PanelContainer] = []
var _results_overlay: Control
var _results_badge: Control   # the medal disc sticking out of the card's top edge
var _badge_color := Palette.MEDAL_SILVER
var _badge_cross := false     # game over: a cross instead of a star
var _results_title: Label
var _results_rows: VBoxContainer   # the times, one row each in a sunk well
var _results_buttons: HBoxContainer   # Retry beside Next / Leaderboard; Menu goes under
var _results_next: Button
var _results_board: Button    # Reddit: the next step after a finish

# Reddit's part of the results card: today's place, streak, next circuit.
var _daily_box: VBoxContainer
var _rank_plate: PanelContainer   # gold plate: "#12" + TODAY'S RANK + "of 340 racers"
var _rank_num: Label
var _rank_caption: Label
var _rank_of: Label
var _daily_rank: Label            # the line shown instead of the plate (posting, log in, ...)
var _daily_chips: HBoxContainer
var _daily_next: Label
var _flair_btn: Button          # opt-in: show the streak as Reddit user flair
var _flair_on := false          # how the button's switch is drawn
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
	var hint_box := HudStyle.panel()
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
	_boost_cap = _make_label(root, "BOOST", Palette.TEXT_LIGHT, true)
	HudStyle.style_floating_label(_boost_cap, Palette.TEXT_LIGHT, true)
	_boost_cap.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_boost_well = HudStyle.pill(Palette.SURFACE_INSET)
	_boost_well.border_color = Palette.INK
	_boost_well.set_border_width_all(2)
	_boost_fill = HudStyle.pill(Palette.GOLD)
	_boost_bar = Control.new()
	_boost_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_boost_bar.draw.connect(_draw_boost)
	root.add_child(_boost_bar)

	# Live split delta vs your best lap (green = ahead, red = behind); fades out.
	_delta_label = _make_label(root, "", Palette.TEXT_LIGHT, true)
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

	# The start: three lamps on a dark bar light red with the 3-2-1 beeps and all
	# turn green on GO, when GO! punches in under them. Over a soft dark blob (a
	# thick outline goes blocky at this size), in the gap between the hint and
	# the car rather than on top of either. They fade out together.
	_start_box = Control.new()
	_start_box.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_start_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_start_box.visible = false
	root.add_child(_start_box)
	_countdown_glow = TextureRect.new()
	_countdown_glow.texture = HudStyle.glow()
	_countdown_glow.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_countdown_glow.stretch_mode = TextureRect.STRETCH_SCALE
	_countdown_glow.modulate = Color(Palette.BLACK, 0.6)
	_countdown_glow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_start_box.add_child(_countdown_glow)
	_box(_countdown_glow, 0.5, 0.39, -170, -120, 340, 240)
	_lights_face = HudStyle.panel(int(LIGHTS_SIZE.y * 0.5))
	_lights_face.bg_color = Palette.BLACK
	_lights = Control.new()
	_lights.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_lights.draw.connect(_draw_lights)
	_start_box.add_child(_lights)
	_box(_lights, 0.5, 0.39, -LIGHTS_SIZE.x * 0.5, -LIGHTS_SIZE.y - 4, LIGHTS_SIZE.x, LIGHTS_SIZE.y)
	_countdown_label = _make_label(_start_box, "GO!", Palette.GOLD, true)
	_countdown_label.add_theme_font_size_override("font_size", 64)
	_countdown_label.add_theme_color_override("font_color", Palette.GOLD)
	_countdown_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_countdown_label.visible = false
	_box(_countdown_label, 0.5, 0.39, -160, 8, 320, 84)

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

	# Touch has no Esc key, so pausing needs a button: a cream chip with two bars.
	_pause_button = Button.new()
	_pause_button.focus_mode = Control.FOCUS_NONE
	_pause_button.add_theme_stylebox_override("normal", HudStyle.panel(12))
	_pause_button.add_theme_stylebox_override("hover", HudStyle.panel(12))
	_pause_button.add_theme_stylebox_override("pressed", HudStyle.panel(12, true))
	_pause_bar = HudStyle.pill(Palette.TEXT, 2)
	_pause_button.draw.connect(_draw_pause_icon)
	_pause_button.pressed.connect(func(): ui_action.emit("pause"))
	root.add_child(_pause_button)

	_build_results_overlay(root)
	_build_pause_overlay(root)

	Layout.changed.connect(_layout)
	_layout()


func _make_panel(parent: Control) -> Panel:
	var p := Panel.new()
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	p.add_theme_stylebox_override("panel", HudStyle.panel())
	parent.add_child(p)
	return p


## `floating` labels sit straight on the track and get an INK halo; the rest sit
## on a cream panel and stay clean.
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
	if _best_sticker.visible:
		_place_sticker.call_deferred()   # the card moved


## Desktop / wide window: lap + wall hits top-left, the timer top-centre, best
## times top-right. With a keyboard the mini map sits bottom-left and the
## controls legend bottom-right (H hides it), keeping the top clear; on a
## touchscreen the bottom corners belong to the thumb pads, so the map goes under
## the best times and the legend under the timer (it fades once racing).
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

	if touch:
		_box(_minimap, 1.0, 0.0, -230, 90, 214, 136)
	else:
		_box(_minimap, 0.0, 1.0, 16, -158, 214, 136)

	_box(_p_walls, 0.0, 0.0, 16, 86, 190, 40)
	_font(_walls_cap, 12)
	_walls_cap.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	_box(_walls_cap, 0.0, 0.0, 32, 96, 68, 20)
	_box(_walls_pips, 0.0, 0.0, 100, 94, 92, 24)

	if touch:
		_place_hint(0.5, 0.0, 0, 106)
	else:
		_place_hint(1.0, 1.0, -16, -22)
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
	_box(_walls_pips, 0.0, 0.0, 183, 102, 80, 24)

	_place_hint(0.5, 0.0, 0, 184)
	_font(_warn_label, 26)

	_box(_speedo, 0.5, 1.0, -48, -128, 96, 96)
	_box(_boost_bar, 0.5, 1.0, -48, -146, 96, 9)
	_font(_boost_cap, 10)
	_box(_boost_cap, 0.5, 1.0, -48, -163, 96, 14)
	_font(_delta_label, 24)
	_box(_delta_label, 0.5, 1.0, -100, -200, 200, 30)


## Rebuilds the keyboard controls legend (key caps) for the current layout: a
## narrow window gets shorter rows; a wide one stacks it in the bottom-right
## corner. It ends in "H HIDE", and once hidden (saved with the settings) only a
## small "H CONTROLS" chip is left to bring it back. On touch there is none.
func _rebuild_hint(touch: bool) -> void:
	for child in _p_hint.get_children():
		_p_hint.remove_child(child)
		child.queue_free()
	_p_hint.visible = not touch
	if touch:
		return
	var narrow := Layout.portrait
	var fs := 13 if narrow else 14
	if Game.is_controls_hidden():
		_p_hint.add_child(HudStyle.controls_legend(false, 1, fs, [
			"DRIVE", "FRONT", "REAR", "BOOST", "DRIFT", "PAUSE"
		], Palette.TEXT, [[["H"], "CONTROLS"]]))
		return
	var per_row := 3 if narrow else 2
	_p_hint.add_child(HudStyle.controls_legend(false, per_row, fs, [], Palette.TEXT, [[["H"], "HIDE"]]))


## H (keyboard only) hides or shows the controls legend, and remembers it.
func _unhandled_key_input(event: InputEvent) -> void:
	var key := event as InputEventKey
	if key == null or not key.pressed or key.echo or key.physical_keycode != KEY_H or Layout.touch:
		return
	Game.set_controls_hidden(not Game.is_controls_hidden())
	_layout()
	get_viewport().set_input_as_handled()


## Pins the legend at screen point (ax, ay) (each 0 = left/top, 0.5 = centre,
## 1 = right/bottom), offset by (x, y); it grows away from that point to
## whatever its rows need.
func _place_hint(ax: float, ay: float, x: float, y: float) -> void:
	_p_hint.anchor_left = ax
	_p_hint.anchor_right = ax
	_p_hint.anchor_top = ay
	_p_hint.anchor_bottom = ay
	_p_hint.grow_horizontal = Control.GROW_DIRECTION_BOTH if ax == 0.5 else (
		Control.GROW_DIRECTION_BEGIN if ax == 1.0 else Control.GROW_DIRECTION_END)
	_p_hint.grow_vertical = Control.GROW_DIRECTION_BEGIN if ay == 1.0 else Control.GROW_DIRECTION_END
	_p_hint.offset_left = x
	_p_hint.offset_right = x
	_p_hint.offset_top = y
	_p_hint.offset_bottom = y
	_p_hint.reset_size()


func _draw_wall_pips() -> void:
	if _wall_limit <= 0:
		return
	var area := _walls_pips.size
	# As big as fits: n pips of radius r, a half-radius apart, across the box.
	var r := minf(minf(8.0, area.y * 0.5 - 2.0), area.x / (2.5 * (_wall_limit - 1) + 2.0))
	var gap := r * 2.5
	var x0 := area.x * 0.5 - gap * (_wall_limit - 1) * 0.5
	for i in _wall_limit:
		var c := Vector2(x0 + gap * i, area.y * 0.5)
		var pip_r := r
		if i == _wall_used - 1 and _pip_pop > 0.0:
			# The hit just counted: its pip swells and a red ring spreads off it.
			pip_r = r * (1.0 + 0.4 * _pip_pop)
			_walls_pips.draw_arc(c, r * (1.0 + 1.6 * (1.0 - _pip_pop)), 0.0, TAU, 40,
				Color(Palette.DANGER, _pip_pop), 2.0, true)
		_walls_pips.draw_circle(c, pip_r, Palette.DANGER if i < _wall_used else Palette.SURFACE_INSET, true, -1.0, true)
		_walls_pips.draw_arc(c, pip_r, 0.0, TAU, 40, Palette.INK, 2.5, true)


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
	# Ink text can't be tinted brighter, so the flash eases its colour back instead.
	create_tween().tween_method(
		func(c: Color) -> void: _bestlap_label.add_theme_color_override("font_color", c),
		Palette.POP, Palette.TEXT, 0.8
	)


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
	var fresh := used > _wall_used
	_wall_used = used
	if fresh:
		create_tween().tween_method(_set_pip_pop, 1.0, 0.0, 0.45).set_ease(Tween.EASE_OUT)
	_wall_limit = limit
	var on := limit > 0
	_p_walls.visible = on
	_walls_cap.visible = on
	_walls_pips.visible = on
	_walls_pips.queue_redraw()


func _set_pip_pop(v: float) -> void:
	_pip_pop = v
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


## The start, called every frame of it: "3", "2", "1" light one, two, three
## lamps red (one per beep); "GO!" turns them all green and punches GO! in.
func show_countdown(text: String) -> void:
	var go := text.begins_with("GO")
	var lit := 3 if go else clampi(4 - text.to_int(), 0, 3)
	if lit != _lights_on or go != _lights_go:
		_lights_on = lit
		_lights_go = go
		create_tween().tween_method(_set_light_pop, 1.0, 0.0, 0.22).set_ease(Tween.EASE_OUT)
		if go:
			_countdown_label.visible = true
			_countdown_label.pivot_offset = _countdown_label.size * 0.5
			create_tween().tween_property(_countdown_label, "scale", Vector2.ONE, 0.3) \
				.from(Vector2.ONE * 1.5).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	if not _start_box.visible:
		_start_box.modulate.a = 1.0
		_start_box.visible = true
	_lights.queue_redraw()


func _set_light_pop(v: float) -> void:
	_light_pop = v
	_lights.queue_redraw()


## The start lights and GO! fade out together.
func hide_countdown() -> void:
	if not _start_box.visible:
		return
	var tw := create_tween()
	tw.tween_property(_start_box, "modulate:a", 0.0, 0.25)
	tw.tween_callback(func() -> void: _start_box.visible = false)


## Three lamps on a dark bar with an INK rim and lip. Lit ones glow red, or all
## green on GO; the lamp just lit swells a touch as it comes on.
func _draw_lights() -> void:
	var s := _lights.size
	_lights.draw_style_box(_lights_face, Rect2(Vector2.ZERO, s))
	var colour := Palette.SUCCESS if _lights_go else Palette.DANGER
	var centres: Array[Vector2] = []
	for i in 3:
		centres.append(Vector2(s.x * 0.5 + (i - 1) * LAMP_GAP, s.y * 0.5))
	for i in _lights_on:
		HudStyle.draw_glow(_lights, centres[i], LAMP_R * 2.8, Color(colour, 0.55))
	for i in 3:
		var c := centres[i]
		if i < _lights_on:
			var fresh := _lights_go or i == _lights_on - 1
			var r := LAMP_R * (1.0 + 0.16 * _light_pop) if fresh else LAMP_R
			_lights.draw_circle(c, r, colour, true, -1.0, true)
			_lights.draw_circle(c + Vector2(-0.3, -0.3) * r, r * 0.3, Color(colour.lightened(0.65), 0.9), true, -1.0, true)
			_lights.draw_arc(c, r, 0.0, TAU, 48, Palette.INK, 2.5, true)
		else:
			_lights.draw_circle(c, LAMP_R, Palette.BG_RAISED, true, -1.0, true)
			_lights.draw_arc(c, LAMP_R, 0.0, TAU, 48, Palette.INK, 2.5, true)


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

	# The medal: a disc on two ribbons, half outside the card's top edge.
	_results_badge = Control.new()
	_results_badge.custom_minimum_size = Vector2(0, 40)
	_results_badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_results_badge.draw.connect(_draw_badge)
	vb.add_child(_results_badge)

	_results_title = Label.new()
	_results_title.add_theme_font_size_override("font_size", 32)
	_results_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	HudStyle.style_title(_results_title, true)
	vb.add_child(_results_title)

	# The times, one row each in a well sunk into the card.
	var times := PanelContainer.new()
	var well := HudStyle.inset(16)
	well.content_margin_left = 16.0
	well.content_margin_right = 16.0
	well.content_margin_top = 8.0
	well.content_margin_bottom = 8.0
	times.add_theme_stylebox_override("panel", well)
	vb.add_child(times)
	_results_rows = VBoxContainer.new()
	_results_rows.add_theme_constant_override("separation", 0)
	times.add_child(_results_rows)

	# Reddit only: today's place on a gold plate, the chips, the countdown and the
	# opt-in streak flair switch.
	_daily_box = VBoxContainer.new()
	_daily_box.add_theme_constant_override("separation", 10)
	_daily_box.visible = false
	vb.add_child(_daily_box)
	_rank_plate = PanelContainer.new()
	_rank_plate.add_theme_stylebox_override("panel", _plate_box())
	_daily_box.add_child(_rank_plate)
	var plate_row := HBoxContainer.new()
	plate_row.add_theme_constant_override("separation", 14)
	_rank_plate.add_child(plate_row)
	_rank_num = Label.new()
	_rank_num.add_theme_font_size_override("font_size", 44)
	_rank_num.add_theme_color_override("font_color", Palette.TEXT_ON_GOLD)
	plate_row.add_child(_rank_num)
	var plate_text := VBoxContainer.new()
	plate_text.alignment = BoxContainer.ALIGNMENT_CENTER
	plate_text.add_theme_constant_override("separation", 0)
	plate_row.add_child(plate_text)
	_rank_caption = Label.new()
	_rank_caption.add_theme_font_size_override("font_size", 12)
	_rank_caption.add_theme_color_override("font_color", Palette.TEXT_ON_GOLD)
	plate_text.add_child(_rank_caption)
	_rank_of = Label.new()
	_rank_of.theme_type_variation = "LabelBody"
	_rank_of.add_theme_font_size_override("font_size", 19)
	_rank_of.add_theme_color_override("font_color", Palette.TEXT_ON_GOLD)
	plate_text.add_child(_rank_of)
	_daily_rank = Label.new()
	_daily_rank.add_theme_font_size_override("font_size", 22)
	_daily_rank.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_daily_box.add_child(_daily_rank)
	_daily_chips = HBoxContainer.new()
	_daily_chips.alignment = BoxContainer.ALIGNMENT_CENTER
	_daily_chips.add_theme_constant_override("separation", 10)
	_daily_box.add_child(_daily_chips)
	var next_row := HBoxContainer.new()
	next_row.alignment = BoxContainer.ALIGNMENT_CENTER
	next_row.add_theme_constant_override("separation", 7)
	_daily_box.add_child(next_row)
	var clock := TextureRect.new()
	clock.texture = HudStyle.icon(HudStyle.ICON_CLOCK, Palette.TEXT_MUTED, 16, 2.6)
	clock.stretch_mode = TextureRect.STRETCH_KEEP_CENTERED
	clock.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	next_row.add_child(clock)
	_daily_next = Label.new()
	_daily_next.add_theme_font_size_override("font_size", 15)
	_daily_next.add_theme_color_override("font_color", Palette.TEXT_MUTED)
	next_row.add_child(_daily_next)
	# Opt-in streak flair: a switch row, off unless the player turns it on here.
	_flair_btn = Button.new()
	_flair_btn.custom_minimum_size = Vector2(0, 48)
	_flair_btn.add_theme_font_size_override("font_size", 14)
	_flair_btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
	for state in ["normal", "hover", "pressed", "hover_pressed", "disabled"]:
		var sb := HudStyle.inset(14)
		sb.content_margin_left = 16.0
		sb.content_margin_right = 76.0   # room for the switch
		sb.content_margin_top = 4.0
		sb.content_margin_bottom = 4.0
		if state == "hover":
			sb.bg_color = Palette.SURFACE_INSET.lightened(0.04)
		elif state.contains("pressed"):
			sb.bg_color = Palette.STROKE
		_flair_btn.add_theme_stylebox_override(state, sb)
	for c in ["font_color", "font_hover_color", "font_pressed_color", "font_hover_pressed_color", "font_focus_color"]:
		_flair_btn.add_theme_color_override(c, Palette.TEXT)
	_flair_btn.add_theme_color_override("font_disabled_color", Palette.TEXT_MUTED)
	_flair_btn.focus_mode = Control.FOCUS_NONE
	_flair_btn.visible = false
	_flair_btn.pressed.connect(_on_flair_pressed)
	_flair_btn.draw.connect(_draw_flair_switch)
	_daily_box.add_child(_flair_btn)
	Leaderboard.flair_changed.connect(_on_flair_changed)

	# NEW BEST: a gold sticker slapped over the card's top-right corner, beside
	# the medal. It lives on the overlay, not in the card, so it moves nothing.
	_results_card = vb.get_parent()
	_best_sticker = HudStyle.tag("NEW BEST", Palette.GOLD, 17)
	(_best_sticker.get_child(0) as Label).horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_best_sticker.visible = false
	_results_overlay.add_child(_best_sticker)

	# Retry beside the gold next step (Next, or Leaderboard on Reddit); Menu under.
	var actions := VBoxContainer.new()
	actions.add_theme_constant_override("separation", 14)
	vb.add_child(actions)
	_results_buttons = HBoxContainer.new()
	_results_buttons.add_theme_constant_override("separation", 12)
	actions.add_child(_results_buttons)
	var retry := _add_action_button(_results_buttons, "Retry", "retry", "ButtonSecondary")
	retry.icon = HudStyle.icon(HudStyle.ICON_RETRY, Palette.TEXT_ON_POP, 20, 3.0)
	_results_next = _add_action_button(_results_buttons, "Next", "next")          # gold forward CTA
	_results_next.icon = HudStyle.icon(HudStyle.ICON_ARROW, Palette.TEXT_ON_GOLD, 20, 3.0)
	_results_next.icon_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_results_board = _add_action_button(_results_buttons, "Leaderboard", "leaderboard")   # gold, Reddit
	_results_board.icon = HudStyle.icon(HudStyle.ICON_BOARD, Palette.TEXT_ON_GOLD, 20, 2.8)
	_results_board.visible = false
	for b: Button in _results_buttons.get_children():
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.custom_minimum_size = Vector2(0, 56)
		b.add_theme_font_size_override("font_size", 18)
	var menu := _add_action_button(actions, "Menu", "menu", "ButtonGhost")
	menu.add_theme_font_size_override("font_size", 16)


## The gold plate behind today's rank: INK rim and lip, like a race number plate.
func _plate_box() -> StyleBoxFlat:
	var sb := HudStyle.panel(16)
	sb.bg_color = Palette.GOLD
	sb.shadow_size = 0   # it sits on the card; the lip is enough
	sb.content_margin_left = 16.0
	sb.content_margin_right = 16.0
	sb.content_margin_top = 4.0
	sb.content_margin_bottom = 4.0
	return sb


## The medal at the top of the results card, poking out above the card: two
## ribbons, an INK lip and rim, the disc in the medal's colour with an inner
## ring, and a star (or, after a game over, a cross).
func _draw_badge() -> void:
	var c := Vector2(_results_badge.size.x * 0.5, -22.0)
	var r := 38.0
	var k := r / 46.0
	for side: float in [-1.0, 1.0]:
		var ribbon := PackedVector2Array()
		for p: Vector2 in [Vector2(24, 12), Vector2(38, 70), Vector2(22, 61), Vector2(13, 75), Vector2(2, 18)]:
			ribbon.append(c + Vector2(p.x * side, p.y) * k)
		_results_badge.draw_colored_polygon(ribbon, Palette.POP if side < 0.0 else Palette.GOLD)
		ribbon.append(ribbon[0])
		_results_badge.draw_polyline(ribbon, Palette.INK, 2.5, true)
	_results_badge.draw_circle(c + Vector2(0, HudStyle.LIP), r, Palette.INK, true, -1.0, true)
	_results_badge.draw_circle(c, r, Palette.INK, true, -1.0, true)
	_results_badge.draw_circle(c, r - 3.5, _badge_color, true, -1.0, true)
	_results_badge.draw_circle(c, r * 0.72, _badge_color.darkened(0.1), true, -1.0, true)
	_results_badge.draw_arc(c, r * 0.72, 0.0, TAU, 48, _badge_color.lightened(0.5), 2.5, true)
	if _badge_cross:
		# Both INK strokes first, then both white ones, so the cross reads as one.
		for pass_color: Color in [Palette.INK, Palette.TEXT_LIGHT]:
			for d: Vector2 in [Vector2(1, 1), Vector2(1, -1)]:
				_results_badge.draw_line(c - d * r * 0.3, c + d * r * 0.3, pass_color,
					10.0 if pass_color == Palette.INK else 5.0, true)
		return
	var star := PackedVector2Array()
	for i in 10:
		star.append(c + Vector2.from_angle(-PI / 2.0 + i * PI / 5.0) * (r * 0.42 if i % 2 == 0 else r * 0.18))
	var star_color := Palette.GOLD if _badge_color.get_luminance() > 0.85 else _badge_color.lightened(0.6)
	_results_badge.draw_colored_polygon(star, star_color)
	star.append(star[0])
	_results_badge.draw_polyline(star, Palette.INK, 2.0, true)


## The switch at the right end of the flair button: gold, knob right, when on.
func _draw_flair_switch() -> void:
	var s := _flair_btn.size
	var track := Rect2(s.x - 66.0, s.y * 0.5 - 14.0, 50.0, 28.0)
	var sb := HudStyle.pill(Palette.GOLD if _flair_on else Palette.STROKE)
	sb.border_color = Palette.INK
	sb.set_border_width_all(HudStyle.OUTLINE)
	_flair_btn.draw_style_box(sb, track)
	var at := Vector2(track.end.x - 14.0 if _flair_on else track.position.x + 14.0, track.get_center().y)
	_flair_btn.draw_circle(at + Vector2(0, 1.5), 9.0, Palette.INK, true, -1.0, true)
	_flair_btn.draw_circle(at, 7.5, Palette.SURFACE, true, -1.0, true)


func _build_pause_overlay(parent: Control) -> void:
	var made := _make_modal(parent, Palette.HUD_SCRIM)
	_pause_overlay = made[0]
	var vb: VBoxContainer = made[1]

	var title := Label.new()
	title.text = "PAUSED"
	title.add_theme_font_size_override("font_size", 34)
	HudStyle.style_sticker(title, Palette.GOLD)
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


## The finish card. `laps` is the race's lap count: a one-lap (ranked) race
## shows TIME and BEST; a longer one TOTAL, BEST and BEST LAP. `new_best` (casual,
## which has no medal) titles the card NEW BEST. `improved_by` > 0 (seconds the
## old best was beaten by) brings in the NEW BEST sticker; `medal_up` (a better
## medal than this level had) makes the medal disc pop.
func show_results(total: float, medal: String, best_total: float, best_lap: float, has_next: bool,
		laps := 3, new_best := false, improved_by := 0.0, medal_up := false) -> void:
	if medal == "none":
		_results_title.text = "NEW BEST" if new_best else "FINISHED"
		_badge_color = Palette.GOLD if new_best else Palette.SURFACE
	else:
		_results_title.text = medal.to_upper() + " MEDAL"
		_badge_color = _medal_color(medal)
	_badge_cross = false
	_results_badge.queue_redraw()
	if laps <= 1:
		_set_rows([
			["TIME", Game.format_time(total)],
			["BEST", Game.format_time(best_total)],
		])
	else:
		_set_rows([
			["TOTAL", Game.format_time(total)],
			["BEST", Game.format_time(best_total)],
			["BEST LAP", Game.format_time(best_lap)],
		])
	_results_next.visible = has_next
	_results_board.visible = false
	_daily_box.visible = false
	_arrow.visible = false   # it draws above the overlays
	_best_sticker.visible = false
	_results_badge.scale = Vector2.ONE
	_results_overlay.visible = true
	if improved_by > 0.0:
		# The casual card's title already says NEW BEST; its sticker is the margin.
		var by := "-%.2fs" % improved_by
		_pop_sticker(by if medal == "none" else "NEW BEST
" + by)
	if medal_up:
		_pop_badge(improved_by <= 0.0)


## Slaps the NEW BEST sticker on the card's top-right corner: it lands big
## and settles, with the best-time chime.
func _pop_sticker(text: String) -> void:
	var label: Label = _best_sticker.get_child(0)
	label.text = text
	_best_sticker.modulate.a = 0.0
	_best_sticker.visible = true
	await get_tree().process_frame   # let the card and the label take their sizes
	_place_sticker()
	_best_sticker.pivot_offset = _best_sticker.custom_minimum_size * 0.5
	var tw := create_tween()
	tw.tween_interval(0.3)
	tw.tween_callback(UiFeel.sound.bind("best"))
	tw.tween_property(_best_sticker, "modulate:a", 1.0, 0.08)
	tw.parallel().tween_property(_best_sticker, "scale", Vector2.ONE, 0.34).from(Vector2.ONE * 1.7) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


## Over the card's top-right corner, clear of the medal and the title.
func _place_sticker() -> void:
	var need := _best_sticker.custom_minimum_size
	_best_sticker.global_position = _results_card.global_position 		+ Vector2(_results_card.size.x - need.x - 18.0, -need.y * 0.45)


## A better medal than before: the disc swells and settles (`with_sound` when
## no NEW BEST chime is coming).
func _pop_badge(with_sound: bool) -> void:
	await get_tree().process_frame
	_results_badge.pivot_offset = Vector2(_results_badge.size.x * 0.5, -22.0)
	var tw := create_tween()
	tw.tween_interval(0.12)
	if with_sound:
		tw.tween_callback(UiFeel.sound.bind("pop"))
	tw.tween_property(_results_badge, "scale", Vector2.ONE, 0.42).from(Vector2.ONE * 1.35) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


## Fades `node` in, landing a little big and settling, after `delay` seconds.
func _pop_in(node: Control, delay: float) -> void:
	node.modulate.a = 0.0
	await get_tree().process_frame   # sized by its container first
	node.pivot_offset = node.size * 0.5
	var tw := create_tween()
	tw.tween_interval(delay)
	tw.tween_callback(UiFeel.sound.bind("pop"))
	tw.tween_property(node, "modulate:a", 1.0, 0.1)
	tw.parallel().tween_property(node, "scale", Vector2.ONE, 0.3).from(Vector2.ONE * 1.25) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


## Fills the times well with [label, value] rows; the first one is big.
func _set_rows(rows: Array) -> void:
	for c in _results_rows.get_children():
		_results_rows.remove_child(c)
		c.queue_free()
	for i in rows.size():
		var row := HBoxContainer.new()
		_results_rows.add_child(row)
		var cap := Label.new()
		cap.text = String(rows[i][0])
		cap.add_theme_font_size_override("font_size", 13)
		cap.add_theme_color_override("font_color", Palette.TEXT_MUTED)
		cap.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		cap.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		row.add_child(cap)
		var value := Label.new()
		value.text = String(rows[i][1])
		value.add_theme_font_size_override("font_size", 32 if i == 0 else 19)
		row.add_child(value)


## Reddit: the results card while the time is on its way to the server. The
## gold button becomes Leaderboard, the one clear next step.
func show_daily_pending() -> void:
	_set_rank("POSTING YOUR TIME...", Palette.TEXT_MUTED)
	_clear_daily_chips()
	_set_next("")
	_next_circuit_at = 0
	_flair_btn.visible = false
	_results_next.visible = false
	_results_board.visible = true
	_daily_box.visible = true


## Reddit: the server's answer (Leaderboard.run_recorded): today's place on the
## gold plate, the streak, a new-best chip and the countdown to the next circuit.
func show_daily_result(info: Dictionary) -> void:
	_clear_daily_chips()
	if info.is_empty():
		_set_rank("COULDN'T REACH REDDIT", Palette.TEXT_MUTED)
		_set_next("Your time is saved on this device.")
		return
	var rank := int(info.get("rank", 0))
	var prev_rank := int(info.get("prev_rank", 0))
	if not bool(info.get("accepted", false)):
		_set_rank("LOG IN TO RANK", Palette.TEXT_MUTED)
	elif rank > 0:
		_show_plate(rank, int(info.get("players", 0)), prev_rank)
		if prev_rank > rank:
			_daily_chips.add_child(_chip("UP %d" % (prev_rank - rank), Palette.SUCCESS))
	else:
		_set_rank("TIME SAVED", Palette.TEXT)
	# On Reddit the server says whether this beat the player's best (on any device).
	if bool(info.get("improved", false)) and bool(info.get("accepted", false)):
		_pop_sticker("NEW BEST")
	var streak := int(info.get("streak", 0))
	if streak > 0:
		var chip := _chip("%d-DAY STREAK" % streak if streak > 1 else "STREAK STARTED", Palette.POP)
		chip.get_theme_stylebox("normal").content_margin_left = 30.0   # room for the flame
		chip.draw.connect(_draw_flame.bind(chip))
		_daily_chips.add_child(chip)
		if streak > int(info.get("prev_streak", streak)):
			_pop_in(chip, 0.6)   # the streak grew with this run
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
	_flair_on = on and error == ""
	if error != "":   # the reason is in the server log; keep the button short
		_flair_btn.text = "FLAIR UNAVAILABLE  ·  TRY AGAIN"
	elif on:
		_flair_btn.text = "STREAK FLAIR ON"
	else:
		_flair_btn.text = "SHOW MY STREAK AS FLAIR"
	_flair_btn.queue_redraw()


func _clear_daily_chips() -> void:
	for c in _daily_chips.get_children():
		c.queue_free()


## Today's place as a plain line (posting, log in, ...); hides the gold plate.
func _set_rank(text: String, color: Color) -> void:
	_rank_plate.visible = false
	_daily_rank.visible = true
	_daily_rank.text = text
	_daily_rank.add_theme_color_override("font_color", color)


## Today's place on the gold plate: "#12", TODAY'S RANK, "of 340 racers". It
## pops in and the number rolls down to the place: from the old one, else from
## the back of the field. The top ten and first place say so.
func _show_plate(rank: int, players: int, prev_rank := 0) -> void:
	_daily_rank.visible = false
	_rank_plate.visible = true
	var when := "TODAY" if Reddit.is_today else "ON DAY %d" % Reddit.day
	if rank == 1:
		_rank_caption.text = "FASTEST " + when
	elif rank <= 10:
		_rank_caption.text = "TOP 10 " + when
	else:
		_rank_caption.text = "TODAY'S RANK" if Reddit.is_today else "DAY %d RANK" % Reddit.day
	_rank_of.text = "of %d racers" % players
	var from := prev_rank if prev_rank > rank else maxi(players, rank)
	_rank_num.custom_minimum_size.x = 0.0
	_rank_num.text = "#%d" % from
	_rank_num.custom_minimum_size.x = _rank_num.get_minimum_size().x   # no jitter as it rolls
	_pop_in(_rank_plate, 0.1)
	if from > rank:
		create_tween().tween_method(func(v: float) -> void: _rank_num.text = "#%d" % roundi(v),
			float(from), float(rank), 0.7).set_delay(0.25).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	else:
		_rank_num.text = "#%d" % rank


## A small flame at the left of the streak chip (drawn, so it stays sharp).
func _draw_flame(chip: Label) -> void:
	var h := chip.size.y
	var o := Vector2(11.0, h * 0.5 - 8.0)
	var outer := PackedVector2Array()
	for p: Vector2 in [Vector2(6, 0), Vector2(9.5, 4.5), Vector2(12, 9), Vector2(11, 13), Vector2(8, 15.6),
			Vector2(6, 16), Vector2(4, 15.6), Vector2(1, 13), Vector2(0.4, 9), Vector2(2.4, 5.2),
			Vector2(4.2, 7.6), Vector2(4.6, 3.4)]:
		outer.append(o + p)
	chip.draw_colored_polygon(outer, Palette.GOLD)
	var rim := outer.duplicate()
	rim.append(outer[0])
	chip.draw_polyline(rim, Palette.INK, 1.6, true)
	var inner := PackedVector2Array()
	for p: Vector2 in [Vector2(6, 7), Vector2(8.2, 10.5), Vector2(8, 13.4), Vector2(6, 14.6), Vector2(4, 13.4), Vector2(3.8, 10.5)]:
		inner.append(o + p)
	chip.draw_colored_polygon(inner, Palette.GOLD_BRIGHT.lightened(0.45))


## The line under the chips, with its clock; hidden when there is nothing to say.
func _set_next(text: String) -> void:
	_daily_next.text = text
	_daily_next.get_parent().visible = text != ""


## A small filled chip with an INK rim; dark or white text to suit its colour.
func _chip(text: String, color: Color) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", 13)
	l.add_theme_color_override("font_color", HudStyle.text_on(color))
	var box := HudStyle.chip(color)
	box.content_margin_left = 12.0
	box.content_margin_right = 12.0
	box.content_margin_top = 3.0
	box.content_margin_bottom = 3.0
	l.add_theme_stylebox_override("normal", box)
	return l


func _process(_delta: float) -> void:
	if _next_circuit_at > 0 and _results_overlay.visible:
		_update_countdown()


func _update_countdown() -> void:
	if _next_circuit_at <= 0:
		return
	var left := (_next_circuit_at - Time.get_ticks_msec()) / 1000
	if left <= 0:
		_set_next("A NEW CIRCUIT IS UP")
		return
	_set_next("NEXT CIRCUIT IN %d:%02d:%02d" % [left / 3600, (left / 60) % 60, left % 60])


## The race ended on the last allowed wall hit. It reuses the results card (a
## red badge with a cross), but there is nothing to record and no next level.
func show_game_over(hits: int, lap: int, laps: int, elapsed: float) -> void:
	_results_title.text = "GAME OVER"
	_badge_color = Palette.DANGER
	_badge_cross = true
	_best_sticker.visible = false
	_results_badge.queue_redraw()
	_set_rows([
		["TIME", Game.format_time(elapsed)],
		["LAP", "%d OF %d" % [lap, laps]],
		["WALL HITS", "%d" % hits],
	])
	_results_next.visible = false
	_results_board.visible = false
	_daily_box.visible = false
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
