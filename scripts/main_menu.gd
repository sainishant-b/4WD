extends Control
## Title screen: Play -> Level Select, Leaderboard, How to Play, Settings
## (volume), Quit. UI is built in code by `_build()`, which runs again when
## `Layout` flips, so the same screen fits a desktop window and a portrait phone.
## Styling comes from the design-system theme
## (res://ui/four_wheel_steer_theme.tres) + Palette tokens: gold primary CTA,
## red-orange secondary, cream ghost, red danger, on a cream card over the
## striped cobalt backdrop.

var _settings_overlay: Control


func _ready() -> void:
	# Inside a Reddit post the game opens straight on Today's Circuit (one tap
	# from the race), or on the Leaderboard when the post's button asked for it.
	# Only on the way in: Back from either screen lands here as usual.
	if Reddit.is_available() and not Reddit.start_handled:
		Reddit.start_handled = true
		if Reddit.start_screen == "leaderboard":
			Game.goto_leaderboard.call_deferred()
		else:
			Game.goto_level_select.call_deferred()
		return
	# First launch elsewhere: show the how-to-play slide before the menu. (On
	# Reddit it waits behind Today's Circuit's How to Play button instead.)
	if not Game.has_seen_instructions() and not Reddit.is_available():
		Game.goto_instructions.call_deferred()
		return
	Layout.changed.connect(_rebuild)
	_build()


func _rebuild() -> void:
	Layout.clear(self)
	_build()


func _build() -> void:
	var narrow := Layout.portrait

	HudStyle.add_backdrop(self)

	var title_top := 110.0 if narrow else 90.0
	var title := Label.new()
	title.text = "FOUR WHEEL STEER"
	title.add_theme_font_size_override("font_size", 38 if narrow else 56)
	HudStyle.style_title(title)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	title.offset_top = title_top
	title.offset_bottom = title_top + (56.0 if narrow else 80.0)
	add_child(title)

	var subtitle := Label.new()
	subtitle.text = "steer the front and rear wheels independently"
	subtitle.theme_type_variation = "LabelBody"  # Barlow body face
	subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	subtitle.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	subtitle.add_theme_color_override("font_color", Palette.TEXT_LIGHT_MUTED)
	subtitle.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	subtitle.offset_left = 24.0
	subtitle.offset_right = -24.0
	subtitle.offset_top = title.offset_bottom - 2.0
	subtitle.offset_bottom = subtitle.offset_top + 56.0
	add_child(subtitle)

	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(center)

	# The buttons sit together on a cream card.
	var card := PanelContainer.new()
	var card_box := HudStyle.panel(20)
	card_box.set_content_margin_all(20)
	card_box.shadow_size = 18
	card_box.shadow_offset = Vector2(0, 10)
	card.add_theme_stylebox_override("panel", card_box)
	center.add_child(card)

	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 14)
	card.add_child(vb)
	_add_button(vb, "Play", _on_play)                       # gold primary
	_add_button(vb, "Leaderboard", _on_leaderboard, "ButtonSecondary")
	_add_button(vb, "How to Play", _on_howto, "ButtonGhost")
	_add_button(vb, "Settings", _on_settings, "ButtonGhost")
	# A browser tab (and a Reddit post) cannot be quit from inside the game.
	if not OS.has_feature("web"):
		_add_button(vb, "Quit", _on_quit, "ButtonDanger")

	_build_settings_overlay()


func _add_button(parent: Node, text: String, cb: Callable, variation := "") -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(300, 56) if Layout.portrait else Vector2(280, 52)
	b.add_theme_font_size_override("font_size", 24)
	if variation != "":
		b.theme_type_variation = variation
	b.pressed.connect(cb)
	parent.add_child(b)
	return b


## A centered modal dialog (scrim + PanelModal card), hidden until "Settings".
func _build_settings_overlay() -> void:
	_settings_overlay = Control.new()
	_settings_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_settings_overlay.visible = false
	add_child(_settings_overlay)

	var scrim := ColorRect.new()
	scrim.color = Palette.HUD_SCRIM
	scrim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	# Swallow clicks behind the dialog; tapping the scrim closes it.
	scrim.gui_input.connect(func(e):
		if e is InputEventMouseButton and e.pressed:
			_settings_overlay.visible = false)
	_settings_overlay.add_child(scrim)

	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_settings_overlay.add_child(center)

	var panel := PanelContainer.new()
	panel.theme_type_variation = "PanelModal"
	panel.custom_minimum_size = Vector2(Layout.PORTRAIT_CONTENT_WIDTH if Layout.portrait else 420.0, 0)
	center.add_child(panel)

	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 14)
	panel.add_child(vb)

	var heading := Label.new()
	heading.text = "SETTINGS"
	heading.add_theme_font_size_override("font_size", 30)
	heading.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	HudStyle.style_sticker(heading, Palette.GOLD)
	vb.add_child(heading)

	var label := Label.new()
	label.text = "Master volume"
	label.add_theme_font_size_override("font_size", 18)
	label.add_theme_color_override("font_color", Palette.TEXT_MUTED)
	vb.add_child(label)

	var slider := HSlider.new()
	slider.min_value = 0.0
	slider.max_value = 1.0
	slider.step = 0.01
	slider.value = Game.get_volume()
	slider.custom_minimum_size = Vector2(0, 36)
	slider.value_changed.connect(func(v): Game.set_volume(v))
	vb.add_child(slider)

	var back := Button.new()
	back.text = "Back"
	back.theme_type_variation = "ButtonGhost"
	back.custom_minimum_size = Vector2(0, 48)
	back.pressed.connect(func(): _settings_overlay.visible = false)
	vb.add_child(back)


func _on_play() -> void:
	Game.goto_level_select()


func _on_leaderboard() -> void:
	Game.goto_leaderboard()


func _on_howto() -> void:
	Game.goto_instructions()


func _on_settings() -> void:
	_settings_overlay.visible = not _settings_overlay.visible


func _on_quit() -> void:
	get_tree().quit()
