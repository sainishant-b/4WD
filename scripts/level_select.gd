extends Control
## Picks the circuit to race.
##
## Inside a Reddit post it is "Today's circuit": the one featured level of the
## day, drawn as a diagram, with its medal times and a DRIVE button. Nothing
## else is offered there.
##
## Everywhere else it is a grid of level cards. Unlocked ones are playable and
## show best time + medal; locked ones are dimmed and say what to finish first.
## One row on a desktop window, two columns on a portrait phone.
##
## `_build()` runs again when `Layout` flips, and on Reddit when the day's data
## arrives (it can land after the engine has started).

func _ready() -> void:
	Layout.changed.connect(_rebuild)
	Reddit.init_loaded.connect(_rebuild)
	_build()


func _rebuild() -> void:
	Layout.clear(self)
	_build()


func _build() -> void:
	if Reddit.is_available():
		_build_daily()
		return
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

	_add_back()


func _add_back() -> void:
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


## Reddit: today's one circuit on a glass card, the diagram beside (desktop) or
## above (phone) its name, your best, the medal times and DRIVE.
func _build_daily() -> void:
	var narrow := Layout.portrait
	HudStyle.add_backdrop(self)

	var title := Label.new()
	title.text = "TODAY'S CIRCUIT"
	title.add_theme_font_size_override("font_size", 34 if narrow else 44)
	HudStyle.style_title(title)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	title.offset_top = 30.0 if narrow else 44.0
	title.offset_bottom = title.offset_top + 56.0
	add_child(title)

	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.offset_top = title.offset_bottom   # keep the card clear of the title
	center.offset_bottom = -72.0              # ... and of the Back button
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(center)
	_add_back()

	var idx := Game.daily_index()
	if idx < 0:
		center.add_child(_line("Loading today's circuit...", 20, Palette.TEXT_MUTED))
		return
	var lv := Game.get_level(idx)

	var card := PanelContainer.new()
	var card_box := HudStyle.glass(20, 0.6)
	card_box.set_content_margin_all(18 if narrow else 24)
	card_box.shadow_size = 24
	card_box.shadow_offset = Vector2(0, 10)
	card.add_theme_stylebox_override("panel", card_box)
	center.add_child(card)

	var body: BoxContainer = VBoxContainer.new() if narrow else HBoxContainer.new()
	body.add_theme_constant_override("separation", 10 if narrow else 28)
	card.add_child(body)

	var map := TrackDiagram.new()
	map.custom_minimum_size = Vector2(Layout.PORTRAIT_CONTENT_WIDTH - 36.0, 230) if narrow else Vector2(470, 330)
	map.track = lv["track"]
	body.add_child(map)

	var info := VBoxContainer.new()
	info.alignment = BoxContainer.ALIGNMENT_CENTER
	info.add_theme_constant_override("separation", 8 if narrow else 12)
	info.custom_minimum_size = Vector2(0, 0) if narrow else Vector2(300, 0)
	body.add_child(info)

	if Reddit.day > 0:
		info.add_child(_chip("DAY %d" % Reddit.day, Palette.BLUE))
	info.add_child(_line(String(lv["name"]).to_upper(), 30 if narrow else 36, Palette.TEXT))
	info.add_child(_line("3 LAPS  ·  TOP SPEED %d" % int(lv["max_speed"]), 13 if narrow else 15, Palette.TEXT_MUTED))

	var best := Game.best_time(idx)
	if best > 0.0:
		var row := HBoxContainer.new()
		row.alignment = BoxContainer.ALIGNMENT_CENTER
		row.add_theme_constant_override("separation", 10)
		row.add_child(_line("YOUR BEST  " + Game.format_time(best), 18 if narrow else 22, Palette.TEXT))
		var medal := Game.best_medal(idx)
		if medal != Game.MEDAL_NONE:
			row.add_child(_chip(medal.to_upper(), _medal_color(medal)))
		info.add_child(row)

	# The three medal targets as coloured chips: what to aim for.
	var medals := HBoxContainer.new()
	medals.alignment = BoxContainer.ALIGNMENT_CENTER
	medals.add_theme_constant_override("separation", 8)
	for m in [Game.MEDAL_GOLD, Game.MEDAL_SILVER, Game.MEDAL_BRONZE]:
		medals.add_child(_chip("%s %s" % [m.to_upper(), _short_time(float(lv[m]))], _medal_color(m)))
	info.add_child(medals)

	var drive := Button.new()
	drive.text = "DRIVE"   # gold primary CTA (theme default)
	drive.custom_minimum_size = Vector2(260, 60)
	drive.add_theme_font_size_override("font_size", 28)
	drive.pressed.connect(func(): Game.start_level(idx))
	var drive_wrap := CenterContainer.new()
	drive_wrap.add_child(drive)
	info.add_child(drive_wrap)


## "1:20" (minutes:seconds), short enough for a chip.
func _short_time(seconds: float) -> String:
	return "%d:%02d" % [int(seconds) / 60, int(seconds) % 60]


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
