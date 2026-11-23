extends Control
## "How to Play": pictures, key caps and a word or two, no sentences (the user
## asked for it short). Four tiles show the hook, each a little car with its
## wheels turned, the keys (or thumb pads) that do it, and its name: FRONT,
## REAR, SPIN TURN (opposite ways), SIDEWAYS (same way). Under them the one rule
## (a red pip per hit: 5 hits = out, from game.gd `MAX_WALL_TOUCHES`) and the rest
## of the controls as key caps.
## On touch the pads are drawn like the real ones (`HudStyle.pad_icon()`: the
## red FRONT / gold REAR ring and its knob pushed the way to slide).
## Shown once on first launch (and from the menu's "How to Play"). GOT IT -> menu.
## On Reddit it is never forced: Today's Circuit has a How to Play button, and
## GOT IT goes back to Today's Circuit.
##
## `_build()` runs again when `Layout` flips: the tiles go 2 x 2 on a portrait
## phone, and touch shows the thumb pads instead of keys.

# One tile each: [front wheel deg, rear wheel deg, motion hint, keyboard caps,
# touch caps as [arrow, pad] (pad 0 = left/front, red; 1 = right/rear, gold),
# both-at-once, label].
const Race := preload("res://scripts/game.gd")   # for MAX_WALL_TOUCHES

const TILES := [
	[24.0, 0.0, "forward", ["A", "D"], [["<>", 0]], false, "FRONT"],
	[0.0, -24.0, "forward", ["<", ">"], [["<>", 1]], false, "REAR"],
	[32.0, -32.0, "pivot", ["D", "<"], [[">", 0], ["<", 1]], true, "SPIN TURN"],
	[32.0, 32.0, "side", ["D", ">"], [[">", 0], [">", 1]], true, "SIDEWAYS"],
]


func _ready() -> void:
	Layout.changed.connect(_rebuild)
	_build()


func _rebuild() -> void:
	Layout.clear(self)
	_build()


func _build() -> void:
	var narrow := Layout.portrait
	var touch := Layout.touch

	HudStyle.add_backdrop(self)

	var title := _label("HOW TO PLAY", 36 if narrow else 48)
	HudStyle.style_title(title)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	title.offset_top = 36.0 if narrow else 28.0
	title.offset_bottom = title.offset_top + 68.0
	add_child(title)

	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.offset_top = title.offset_bottom
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(center)

	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 14 if narrow else 20)
	center.add_child(vb)

	var grid := GridContainer.new()
	grid.columns = 2 if narrow else 4
	grid.add_theme_constant_override("h_separation", 12 if narrow else 18)
	grid.add_theme_constant_override("v_separation", 12)
	for t in TILES:
		grid.add_child(_tile(t, touch, narrow))
	vb.add_child(_centered(grid))

	# The one rule.
	var rule := HBoxContainer.new()
	rule.alignment = BoxContainer.ALIGNMENT_CENTER
	rule.add_theme_constant_override("separation", 10)
	rule.add_child(_make_strikes())
	var rule_text := _label("%d WALL HITS = OUT" % Race.MAX_WALL_TOUCHES, 20 if narrow else 24)
	rule_text.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	HudStyle.style_title(rule_text)
	rule.add_child(rule_text)
	vb.add_child(rule)

	# Everything else, as the same key caps the race HUD shows.
	var per_row := 2 if narrow else 4
	vb.add_child(_centered(HudStyle.controls_legend(
		touch, per_row, 15 if narrow else 17, ["FRONT", "REAR"], Palette.TEXT_LIGHT
	)))

	var btn := Button.new()
	btn.text = "GOT IT - LET'S DRIVE"   # gold primary CTA (theme default)
	btn.custom_minimum_size = Vector2(320 if narrow else 340, 56)
	btn.add_theme_font_size_override("font_size", 24)
	btn.pressed.connect(_dismiss)
	vb.add_child(_centered(btn))


func _dismiss() -> void:
	Game.mark_instructions_seen()
	# "Let's drive": on Reddit that means Today's Circuit, one tap from the race.
	if Reddit.is_available():
		Game.goto_level_select()
	else:
		Game.goto_menu()


func _label(text: String, size: int) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	return l


func _centered(child: Control) -> CenterContainer:
	var c := CenterContainer.new()
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	c.add_child(child)
	return c


## One tile: the car picture, the caps that do it, and its name, on a cream card.
func _tile(t: Array, touch: bool, narrow: bool) -> Control:
	var panel := PanelContainer.new()
	var sb := HudStyle.panel(14)
	sb.set_content_margin_all(10)
	panel.add_theme_stylebox_override("panel", sb)
	panel.custom_minimum_size = Vector2(186 if narrow else 236, 0)
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 6)
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(box)

	var car := _make_car(t[0], t[1], t[2], 1.0 if narrow else 1.35)
	car.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	box.add_child(car)

	var caps := HBoxContainer.new()
	caps.alignment = BoxContainer.ALIGNMENT_CENTER
	caps.add_theme_constant_override("separation", 5)
	caps.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var fs := 16 if narrow else 18
	var tokens: Array = t[4] if touch else t[3]
	for k in tokens.size():
		if k > 0 and t[5]:
			var plus := _label("+", fs)
			plus.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
			HudStyle.style_panel_label(plus, Palette.TEXT_MUTED)
			caps.add_child(plus)
		if touch:
			var pad: Array = tokens[k]
			caps.add_child(HudStyle.pad_icon(pad[0], fs + 26.0, Palette.POP if pad[1] == 0 else Palette.GOLD))
		else:
			caps.add_child(HudStyle.cap(tokens[k], fs))
	box.add_child(caps)

	var word := _label(t[6], 18 if narrow else 20)
	word.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	HudStyle.style_sticker(word, Palette.GOLD, 6)
	box.add_child(word)
	return panel


## A small top-down car icon with the front/rear wheels turned by the given
## angles, plus a motion hint ("forward" | "side" | "pivot"). Wheels that are
## turned are drawn bright, straight ones dim, so the eye goes to the steering.
func _make_car(front_deg: float, rear_deg: float, hint: String, zoom: float) -> Control:
	var box := Control.new()
	# The car drawing reaches ~45 px either side of its centre and ~42 px above it.
	box.custom_minimum_size = Vector2(100, 84) * zoom
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	# Drawn at 1x round (0, 0) on a scaled Node2D, so one set of numbers serves every size.
	var art := Node2D.new()
	art.position = box.custom_minimum_size * 0.5 + Vector2(0, 2) * zoom
	art.scale = Vector2(zoom, zoom)
	box.add_child(art)
	var c := Vector2.ZERO

	var body := Polygon2D.new()
	body.color = Palette.POP
	body.polygon = PackedVector2Array([
		c + Vector2(-13, -22), c + Vector2(13, -22), c + Vector2(13, 22), c + Vector2(-13, 22)])
	art.add_child(body)
	HudStyle.feather(body)

	var nose := Polygon2D.new()
	nose.color = Palette.GOLD
	nose.polygon = PackedVector2Array([c + Vector2(0, -27), c + Vector2(7, -20), c + Vector2(-7, -20)])
	art.add_child(nose)
	HudStyle.feather(nose)

	_add_wheel(art, c + Vector2(-15, -15), front_deg)
	_add_wheel(art, c + Vector2(15, -15), front_deg)
	_add_wheel(art, c + Vector2(-15, 15), rear_deg)
	_add_wheel(art, c + Vector2(15, 15), rear_deg)

	_add_hint(art, c, hint)
	return box


## Three red pips, as the race HUD shows them once every wall hit is used up.
func _make_strikes() -> Control:
	var box := Control.new()
	var n: int = Race.MAX_WALL_TOUCHES
	const GAP := 24.0
	box.custom_minimum_size = Vector2(GAP * (n - 1) + 26.0, 40)
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.draw.connect(func() -> void:
		var c := box.size * 0.5
		for i in n:
			var at := c + Vector2((i - (n - 1) * 0.5) * GAP, 0.0)
			box.draw_circle(at + Vector2(0, 2), 10.5, Palette.INK, true, -1.0, true)   # the lip
			box.draw_circle(at, 10.5, Palette.INK, true, -1.0, true)
			box.draw_circle(at, 8.0, Palette.DANGER, true, -1.0, true)
	)
	return box


func _add_wheel(box: Node, pos: Vector2, deg: float) -> void:
	var w := Polygon2D.new()
	# Turned wheels in full ink, straight ones faded: the wheel angle is the
	# whole point of the diagram.
	w.color = Palette.TEXT if absf(deg) > 0.1 else Palette.TEXT_DIM
	w.polygon = PackedVector2Array([Vector2(-3, -8), Vector2(3, -8), Vector2(3, 8), Vector2(-3, 8)])
	w.position = pos
	w.rotation = deg_to_rad(deg)
	box.add_child(w)
	HudStyle.feather(w)


func _add_hint(box: Node, c: Vector2, hint: String) -> void:
	var col := Palette.POP
	if hint == "forward":
		_line(box, [c + Vector2(34, 6), c + Vector2(34, -30)], col)
		_arrowhead(box, c + Vector2(34, -30), Vector2(0, -1), col)
	elif hint == "side":
		var d := Vector2(0.8, -0.6).normalized()
		_line(box, [c, c + d * 42.0], col)
		_arrowhead(box, c + d * 42.0, d, col)
	elif hint == "pivot":
		var pts: Array[Vector2] = []
		var r := 30.0
		for i in range(0, 25):
			var a := deg_to_rad(-50.0 + i * 9.0)
			pts.append(c + Vector2(cos(a), sin(a)) * r)
		_line(box, pts, col)
		var ae := deg_to_rad(-50.0 + 24 * 9.0)
		_arrowhead(box, pts[pts.size() - 1], Vector2(-sin(ae), cos(ae)), col)


func _line(box: Node, pts: Array, col: Color) -> void:
	var l := Line2D.new()
	l.width = 3.0
	l.default_color = col
	l.antialiased = true
	l.points = PackedVector2Array(pts)
	box.add_child(l)


func _arrowhead(box: Node, tip: Vector2, dir: Vector2, col: Color) -> void:
	var perp := Vector2(-dir.y, dir.x)
	_line(box, [tip - dir * 9.0 + perp * 5.0, tip, tip - dir * 9.0 - perp * 5.0], col)
