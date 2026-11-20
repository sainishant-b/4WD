extends Control
## Picks the circuit to race.
##
## Inside a Reddit post it is "Today's circuit": the one featured level of the
## day, drawn as a diagram, with its top speed, your best, its medal times, a
## big DRIVE button, and Back beside How to Play. Nothing else is offered there. It is the first screen a Reddit
## player sees (main_menu.gd sends them here), so the race is one tap away.
##
## Everywhere else it is a grid of level cards (raised cream tiles with a
## colour bar along the top: the medal's colour, gold while unraced, grey while
## locked). Unlocked ones are playable and show best time + medal; locked ones
## are faded and say what to finish first. One row on a desktop window, two
## columns on a portrait phone.
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


## Reddit: today's one circuit. A tilted DAY tag and the title, then a cream
## card: the track on a deep-blue screen, CIRCUIT + the level's name with a
## 3 LAPS tag, TOP SPEED and YOUR BEST tiles sunk into the card, and the medal
## times. Under it a full-width DRIVE, then Back beside How to Play. On a phone
## all of that stacks; on a desktop the track sits beside the details and the
## buttons go under the details. A chequered strip runs along the bottom.
func _build_daily() -> void:
	var narrow := Layout.portrait
	HudStyle.add_backdrop(self)
	HudStyle.add_chequer(self)

	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 14 if narrow else 18)
	if narrow:
		col.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		col.offset_left = 16.0
		col.offset_right = -16.0
		col.offset_top = 18.0
		col.offset_bottom = -(HudStyle.CHEQUER + 20.0)
		add_child(col)
	else:
		var center := CenterContainer.new()
		center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		center.offset_bottom = -(HudStyle.CHEQUER + 8.0)
		center.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(center)
		center.add_child(col)

	# The DAY tag and the title: stacked on a phone (the top-right corner is the
	# mute button's), side by side on a desktop.
	var title := Label.new()
	title.text = "TODAY'S CIRCUIT"
	title.add_theme_font_size_override("font_size", 34 if narrow else 44)
	HudStyle.style_title(title)
	var head: BoxContainer = VBoxContainer.new() if narrow else HBoxContainer.new()
	head.add_theme_constant_override("separation", 10 if narrow else 20)
	if not narrow:
		head.add_child(title)
	if Reddit.day > 0:
		head.add_child(HudStyle.tag("DAY %d" % Reddit.day, Palette.POP))
	if narrow:
		head.add_child(title)
	col.add_child(head)

	var idx := Game.daily_index()
	if idx < 0:
		col.add_child(_line("Loading today's circuit...", 20, Palette.TEXT_LIGHT_MUTED))
		col.add_child(_daily_buttons(narrow, false))
		return
	var lv := Game.get_level(idx)

	var card := PanelContainer.new()
	var card_box := HudStyle.panel(22)
	card_box.set_content_margin_all(12 if narrow else 20)
	card_box.shadow_size = 18
	card_box.shadow_offset = Vector2(0, 10)
	card.add_theme_stylebox_override("panel", card_box)
	col.add_child(card)

	var map := TrackDiagram.new()
	map.track = lv["track"]
	var details := _daily_details(idx, lv, narrow)
	var drive := _drive_button(idx, narrow)
	var buttons := _daily_buttons(narrow, true)

	if narrow:
		var body := VBoxContainer.new()
		body.add_theme_constant_override("separation", 10)
		card.add_child(body)
		map.custom_minimum_size = Vector2(0, 196)
		body.add_child(map)
		body.add_child(details)
		col.add_child(drive)
		col.add_child(buttons)
	else:
		var body := HBoxContainer.new()
		body.add_theme_constant_override("separation", 24)
		card.add_child(body)
		map.custom_minimum_size = Vector2(500, 350)
		body.add_child(map)
		var side := VBoxContainer.new()
		side.add_theme_constant_override("separation", 14)
		side.custom_minimum_size = Vector2(340, 0)
		body.add_child(side)
		side.add_child(details)
		var gap := Control.new()
		gap.size_flags_vertical = Control.SIZE_EXPAND_FILL
		side.add_child(gap)
		side.add_child(drive)
		side.add_child(buttons)


## The circuit's name with a 3 LAPS tag, the TOP SPEED / YOUR BEST tiles and
## the three medal targets.
func _daily_details(idx: int, lv: Dictionary, narrow: bool) -> VBoxContainer:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 10)

	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 10)
	box.add_child(head)
	var names := VBoxContainer.new()
	names.add_theme_constant_override("separation", 0)
	names.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(names)
	var kicker := _line("CIRCUIT", 12, Palette.TEXT_MUTED)
	kicker.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	names.add_child(kicker)
	var level_name := _line(String(lv["name"]).to_upper(), 32 if narrow else 36, Palette.TEXT)
	level_name.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	names.add_child(level_name)
	var laps := _line("3 LAPS", 13, Palette.TEXT)
	var laps_box := HudStyle.inset(10)
	laps_box.content_margin_left = 10.0
	laps_box.content_margin_right = 10.0
	laps_box.content_margin_top = 5.0
	laps_box.content_margin_bottom = 4.0
	laps.add_theme_stylebox_override("normal", laps_box)
	laps.size_flags_vertical = Control.SIZE_SHRINK_END
	head.add_child(laps)

	var tiles := HBoxContainer.new()
	tiles.add_theme_constant_override("separation", 10)
	box.add_child(tiles)
	tiles.add_child(_stat_tile("TOP SPEED", "%d" % int(lv["max_speed"]), null))
	var best := Game.best_time(idx)
	var medal := Game.best_medal(idx)
	var badge: Control = null
	if best > 0.0 and medal != Game.MEDAL_NONE:
		badge = _chip_label(medal.to_upper(), _medal_color(medal))
	tiles.add_child(_stat_tile("YOUR BEST", Game.format_time(best) if best > 0.0 else "--", badge))

	# The three medal targets as coloured chips of equal width: what to aim for.
	var medals := HBoxContainer.new()
	medals.add_theme_constant_override("separation", 8)
	for m in [Game.MEDAL_GOLD, Game.MEDAL_SILVER, Game.MEDAL_BRONZE]:
		var chip := _chip_label("%s %s" % [m.to_upper(), _short_time(float(lv[m]))], _medal_color(m), 13)
		chip.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		medals.add_child(chip)
	box.add_child(medals)
	return box


## A figure sunk into the card: a small caption over a big value, and an
## optional chip beside the value.
func _stat_tile(caption: String, value: String, chip: Control) -> PanelContainer:
	var tile := PanelContainer.new()
	var well := HudStyle.inset(14)
	well.content_margin_left = 12.0
	well.content_margin_right = 12.0
	well.content_margin_top = 8.0
	well.content_margin_bottom = 8.0
	tile.add_theme_stylebox_override("panel", well)
	tile.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 0)
	tile.add_child(box)
	var cap := _line(caption, 11, Palette.TEXT_MUTED)
	cap.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	box.add_child(cap)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	box.add_child(row)
	var figure := _line(value, 24, Palette.TEXT)
	figure.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	row.add_child(figure)
	if chip != null:
		chip.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.add_child(chip)
	return tile


## The big gold DRIVE, full width, with an arrow just after the word.
func _drive_button(idx: int, narrow: bool) -> Button:
	var drive := Button.new()
	drive.text = "DRIVE"   # gold primary CTA (theme default)
	var font_size := 34 if narrow else 30
	drive.custom_minimum_size = Vector2(0, 70 if narrow else 62)
	drive.add_theme_font_size_override("font_size", font_size)
	drive.pressed.connect(func(): Game.start_level(idx))
	var arrow := TextureRect.new()
	arrow.texture = HudStyle.icon(HudStyle.ICON_ARROW, Palette.TEXT_ON_GOLD, 30, 3.2)
	arrow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	drive.add_child(arrow)
	drive.resized.connect(func() -> void:
		var word := drive.get_theme_font("font").get_string_size(
			drive.text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size
		).x
		arrow.size = Vector2(30, 30)
		arrow.position = Vector2(drive.size.x * 0.5 + word * 0.5 + 10.0, (drive.size.y - 30.0) * 0.5)
	)
	return drive


## Back (cream) beside How to Play (red-orange). On Reddit the game opens on
## Today's Circuit, so How to Play waits behind its button here.
func _daily_buttons(narrow: bool, with_help: bool) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	var back := Button.new()
	back.text = "Back"
	back.theme_type_variation = "ButtonGhost"
	back.icon = HudStyle.icon(HudStyle.ICON_BACK, Palette.TEXT, 20, 3.2)
	back.custom_minimum_size = Vector2(0 if narrow else 120, 54 if narrow else 50)
	back.add_theme_font_size_override("font_size", 18)
	back.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	back.size_flags_stretch_ratio = 1.0
	back.pressed.connect(func(): Game.goto_menu())
	row.add_child(back)
	if with_help:
		var help := Button.new()
		help.text = "?  HOW TO PLAY"
		help.theme_type_variation = "ButtonSecondary"
		help.custom_minimum_size = Vector2(0, 54 if narrow else 50)
		help.add_theme_font_size_override("font_size", 17)
		help.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		help.size_flags_stretch_ratio = 1.7
		help.pressed.connect(func(): Game.goto_instructions())
		row.add_child(help)
	return row


## "1:20" (minutes:seconds), short enough for a chip.
func _short_time(seconds: float) -> String:
	return "%d:%02d" % [int(seconds) / 60, int(seconds) % 60]


## One level as a raised card: name, top speed, then the best time and a medal
## chip, or what is still needed. The bar along the top takes the medal's
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
		card.add_theme_stylebox_override(state, HudStyle.card(state))
	card.pressed.connect(func(): Game.start_level(idx))

	# The colour bar, just inside the card's outline.
	var bar := Panel.new()
	var bar_box := HudStyle.pill(accent, 3)
	bar_box.border_color = Palette.INK
	bar_box.border_width_bottom = 2
	bar.add_theme_stylebox_override("panel", bar_box)
	bar.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	bar.offset_left = 12.0
	bar.offset_right = -12.0
	bar.offset_top = 9.0
	bar.offset_bottom = 17.0
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_child(bar)

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
		box.add_child(_line("NOT RACED YET", 13, Palette.POP_DEEP))
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


## A small filled chip with an INK rim, e.g. the medal on a level card,
## centred in its own box.
func _chip(text: String, color: Color) -> Control:
	var l := _chip_label(text, color)
	var wrap := CenterContainer.new()
	wrap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	wrap.add_child(l)
	return wrap


## The chip itself: a label on a filled pill with an INK rim.
func _chip_label(text: String, color: Color, size: int = 11) -> Label:
	var l := _line(text, size, HudStyle.text_on(color))
	l.add_theme_stylebox_override("normal", HudStyle.chip(color))
	return l


func _medal_color(medal: String) -> Color:
	match medal:
		Game.MEDAL_GOLD: return Palette.MEDAL_GOLD
		Game.MEDAL_SILVER: return Palette.MEDAL_SILVER
		Game.MEDAL_BRONZE: return Palette.MEDAL_BRONZE
		_: return Palette.GOLD
