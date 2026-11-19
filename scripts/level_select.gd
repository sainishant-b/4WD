extends Control
## Grid of level cards. Unlocked ones are playable and show best time + medal;
## locked ones are dimmed and say what to finish first. `_build()` runs again when `Layout` flips: one row
## on a desktop window, two columns on a portrait phone.

func _ready() -> void:
	Layout.changed.connect(_rebuild)
	_build()


func _rebuild() -> void:
	Layout.clear(self)
	_build()


func _build() -> void:
	var narrow := Layout.portrait

	HudStyle.add_backdrop(self)

	var title := Label.new()
	title.text = "SELECT LEVEL"
	title.add_theme_font_size_override("font_size", 34 if narrow else 44)
	HudStyle.style_title(title)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	title.offset_top = 36.0 if narrow else 60.0
	title.offset_bottom = title.offset_top + 60.0
	add_child(title)

	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(center)

	var grid := GridContainer.new()
	grid.columns = 2 if narrow else mini(Game.level_count(), 5)
	grid.add_theme_constant_override("h_separation", 16)
	grid.add_theme_constant_override("v_separation", 16)
	center.add_child(grid)

	for i in Game.level_count():
		grid.add_child(_make_card(i, narrow))

	var back := Button.new()
	back.text = "Back"
	back.theme_type_variation = "ButtonGhost"
	back.custom_minimum_size = Vector2(160, 48)
	back.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT)
	back.offset_left = 24.0
	back.offset_top = -72.0
	back.offset_right = 184.0
	back.offset_bottom = -24.0
	back.pressed.connect(func(): Game.goto_menu())
	add_child(back)


## One level as a raised card: name, top speed, then the best time and a medal
## chip, or what is still needed. The strip along the top takes the medal's
## colour (gold while unraced, grey while locked).
func _make_card(idx: int, narrow: bool) -> Button:
	var lv := Game.get_level(idx)
	var open := Game.is_unlocked(idx)
	var best := Game.best_time(idx)
	var medal := Game.best_medal(idx)
	var accent := Palette.STROKE_STRONG
	if open:
		accent = _medal_color(medal) if best > 0.0 and medal != Game.MEDAL_NONE else Palette.GOLD

	var card := Button.new()
	card.custom_minimum_size = Vector2(190, 124) if narrow else Vector2(204, 156)
	card.focus_mode = Control.FOCUS_NONE
	card.disabled = not open
	for state in ["normal", "hover", "pressed", "disabled"]:
		card.add_theme_stylebox_override(state, HudStyle.card(accent, state))
	card.pressed.connect(func(): Game.start_level(idx))

	var box := VBoxContainer.new()
	box.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT, Control.PRESET_MODE_MINSIZE, 10)
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_theme_constant_override("separation", 2 if narrow else 4)
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_child(box)

	# Inside a Reddit post, one level a day is the Daily Circuit.
	if Reddit.daily_level_id == Game.level_id(idx):
		box.add_child(_chip("TODAY", Palette.BLUE))
	box.add_child(_line(String(lv["name"]).to_upper(), 20 if narrow else 22, Palette.TEXT if open else Palette.TEXT_DIM))
	box.add_child(_line("TOP SPEED %d" % int(lv["max_speed"]), 11 if narrow else 12, Palette.TEXT_MUTED if open else Palette.TEXT_DIM))
	if not open:
		box.add_child(_line("LOCKED", 13, Palette.TEXT_DIM))
		box.add_child(_line("finish %s first" % String(Game.get_level(idx - 1)["name"]), 11, Palette.TEXT_DIM))
	elif best <= 0.0:
		box.add_child(_line("NOT RACED YET", 13, Palette.GOLD))
	else:
		box.add_child(_line(Game.format_time(best), 22 if narrow else 26, Palette.TEXT))
		if medal != Game.MEDAL_NONE:
			box.add_child(_chip(medal.to_upper(), _medal_color(medal)))
	return card


func _line(text: String, size: int, color: Color) -> Label:
	var l := Label.new()
	l.text = text
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	return l


## A small filled pill, e.g. the medal on a level card.
func _chip(text: String, color: Color) -> Control:
	var l := _line(text, 11, Palette.TEXT_ON_GOLD)
	var pill := HudStyle.pill(color)
	pill.content_margin_left = 10.0
	pill.content_margin_right = 10.0
	pill.content_margin_top = 1.0
	pill.content_margin_bottom = 1.0
	l.add_theme_stylebox_override("normal", pill)
	var wrap := CenterContainer.new()
	wrap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	wrap.add_child(l)
	return wrap


func _medal_color(medal: String) -> Color:
	match medal:
		Game.MEDAL_GOLD: return Palette.MEDAL_GOLD
		Game.MEDAL_SILVER: return Palette.MEDAL_SILVER
		Game.MEDAL_BRONZE: return Palette.MEDAL_BRONZE
		_: return Palette.GOLD
