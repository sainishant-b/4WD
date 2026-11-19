extends Control
## "How to Play" slide. Explains the hook with little car diagrams: independent
## front/rear steering, opposite = tight pivot, same = sideways crab-walk; then
## the one rule (the third wall hit ends the race) and the controls legend.
## Shown once on first launch (and from the menu's "How to Play"). GOT IT -> menu.
##
## `_build()` runs again when `Layout` flips: the rows narrow for a portrait
## phone, and the wording and legend name the thumb pads on touch or the keys
## otherwise.


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
	title.offset_top = 36.0 if narrow else 20.0
	title.offset_bottom = title.offset_top + 68.0
	add_child(title)

	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(center)

	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 12 if narrow else 16)
	center.add_child(vb)

	var steer := (
		"The LEFT pad steers the FRONT wheels. The RIGHT pad steers the REAR wheels."
		if touch else
		"A / D steer the FRONT wheels. The arrow keys steer the REAR wheels."
	)
	vb.add_child(_row(_make_car(24.0, 0.0, "forward"), steer))
	vb.add_child(_row(_make_car(32.0, -32.0, "pivot"),
		"Steer them OPPOSITE ways -> the car spins in a super-tight turn."))
	vb.add_child(_row(_make_car(32.0, 32.0, "side"),
		"Steer them the SAME way -> the car drives SIDEWAYS (crab walk)."))

	vb.add_child(_row(_make_strikes(), "Stay off the walls: the THIRD wall hit ends the race."))

	# The same key-cap legend the race HUD shows.
	var per_row := (2 if touch else 3) if narrow else 6
	var legend := CenterContainer.new()
	legend.add_child(HudStyle.controls_legend(touch, per_row, 14 if narrow else 16))
	vb.add_child(legend)

	var btn := Button.new()
	btn.text = "GOT IT - LET'S DRIVE"   # gold primary CTA (theme default)
	btn.custom_minimum_size = Vector2(340, 56)
	btn.add_theme_font_size_override("font_size", 24)
	btn.pressed.connect(_dismiss)
	var btn_wrap := CenterContainer.new()
	btn_wrap.add_child(btn)
	vb.add_child(btn_wrap)


func _dismiss() -> void:
	Game.mark_instructions_seen()
	Game.goto_menu()


func _label(text: String, size: int) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	return l


func _row(diagram: Control, text: String) -> Control:
	var narrow := Layout.portrait
	var gap := 12 if narrow else 24
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", gap)
	h.alignment = BoxContainer.ALIGNMENT_CENTER
	h.add_child(diagram)
	var l := _label(text, 18 if narrow else 22)
	l.theme_type_variation = "LabelBody"  # Barlow body face
	# On a phone the text takes whatever the diagram leaves of the content width.
	var text_width := Layout.PORTRAIT_CONTENT_WIDTH - diagram.custom_minimum_size.x - gap
	l.custom_minimum_size = Vector2(text_width, 80) if narrow else Vector2(560, 84)
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	h.add_child(l)
	return h


## A small top-down car icon with the front/rear wheels turned by the given
## angles, plus a motion hint ("forward" | "side" | "pivot").
func _make_car(front_deg: float, rear_deg: float, hint: String) -> Control:
	var box := _diagram_box()
	var c := box.custom_minimum_size * 0.5

	var body := Polygon2D.new()
	body.color = Palette.BLUE
	body.polygon = PackedVector2Array([
		c + Vector2(-13, -22), c + Vector2(13, -22), c + Vector2(13, 22), c + Vector2(-13, 22)])
	box.add_child(body)

	var nose := Polygon2D.new()
	nose.color = Palette.GOLD
	nose.polygon = PackedVector2Array([c + Vector2(0, -27), c + Vector2(7, -20), c + Vector2(-7, -20)])
	box.add_child(nose)

	_add_wheel(box, c + Vector2(-15, -15), front_deg)
	_add_wheel(box, c + Vector2(15, -15), front_deg)
	_add_wheel(box, c + Vector2(-15, 15), rear_deg)
	_add_wheel(box, c + Vector2(15, 15), rear_deg)

	_add_hint(box, c, hint)
	return box


## The frame every row's picture sits in, so the text lines up down the page.
func _diagram_box() -> Control:
	var box := Control.new()
	# The car drawing reaches ~45 px either side of its centre and ~42 px above it.
	box.custom_minimum_size = Vector2(100, 86) if Layout.portrait else Vector2(160, 90)
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return box


## Three red pips, as the race HUD shows them once every wall hit is used up.
func _make_strikes() -> Control:
	var box := _diagram_box()
	box.draw.connect(func() -> void:
		var c := box.size * 0.5
		for i in 3:
			var at := c + Vector2((i - 1) * 28.0, 0.0)
			HudStyle.draw_glow(box, at, 22.0, Color(Palette.DANGER, 0.5))
			box.draw_circle(at, 10.0, Palette.DANGER, true, -1.0, true)
	)
	return box


func _add_wheel(box: Control, pos: Vector2, deg: float) -> void:
	var w := Polygon2D.new()
	# Light, not the car's near-black: the wheel angle is the whole point of the
	# diagram and black disappears on the navy background.
	w.color = Palette.TEXT_MUTED
	w.polygon = PackedVector2Array([Vector2(-3, -8), Vector2(3, -8), Vector2(3, 8), Vector2(-3, 8)])
	w.position = pos
	w.rotation = deg_to_rad(deg)
	box.add_child(w)


func _add_hint(box: Control, c: Vector2, hint: String) -> void:
	var col := Palette.GOLD
	if hint == "forward":
		_line(box, [c + Vector2(34, 6), c + Vector2(34, -34)], col)
		_arrowhead(box, c + Vector2(34, -34), Vector2(0, -1), col)
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


func _line(box: Control, pts: Array, col: Color) -> void:
	var l := Line2D.new()
	l.width = 3.0
	l.default_color = col
	l.points = PackedVector2Array(pts)
	box.add_child(l)


func _arrowhead(box: Control, tip: Vector2, dir: Vector2, col: Color) -> void:
	var perp := Vector2(-dir.y, dir.x)
	_line(box, [tip - dir * 9.0 + perp * 5.0, tip, tip - dir * 9.0 - perp * 5.0], col)
