extends Control
## Online leaderboard screen (via the Leaderboard autoload). Pick a board, see
## the ranked times.
##
## Inside a Reddit post the first board is OVERALL: every player's best time on
## all the levels added up, lowest total on top; then TODAY (fastest on the
## day's circuit; the results card's Leaderboard button opens here); then one
## board per level. The player is their Reddit account, and each row shows the
## player's snoovatar (`AvatarBadge`; their initial when they have none).
## Elsewhere (Appwrite) there is one board per level, initials only, and a box
## to type a display name.
##
## `_build()` runs again when `Layout` flips, narrowing the column and swapping
## the row of board buttons for a < Board > stepper on a portrait phone.

const WIDE_WIDTH := 560.0
const ROWS := 25
const AVATAR_PX := 30.0

const OVERALL_SLOT := -1
const DAY_SLOT := -2
var _boards: Array[int] = []    # level slots, or OVERALL_SLOT / DAY_SLOT
var _board: int = 0             # index into _boards
var _rows_box: VBoxContainer
var _status: Label
var _board_btns: Array = []     # desktop: one toggle per board
var _board_name: Label = null   # phone: the stepper's current board


func _ready() -> void:
	Leaderboard.scores_loaded.connect(_on_scores_loaded)
	Leaderboard.request_failed.connect(_on_request_failed)
	Reddit.init_loaded.connect(_rebuild)   # the username can arrive after the screen opens
	Layout.changed.connect(_rebuild)
	if Leaderboard.open_on_day and Leaderboard.has_overall():
		_board = 1   # TODAY sits right after OVERALL (see _build)
	Leaderboard.open_on_day = false
	_build()


func _rebuild() -> void:
	Layout.clear(self)
	_board_btns.clear()
	_board_name = null
	_build()


func _build() -> void:
	var narrow := Layout.portrait
	var width := Layout.PORTRAIT_CONTENT_WIDTH if narrow else WIDE_WIDTH

	_boards.clear()
	if Leaderboard.has_overall():
		_boards.append(OVERALL_SLOT)
		_boards.append(DAY_SLOT)
	for i in Game.level_count():
		_boards.append(i)
	_board = clampi(_board, 0, _boards.size() - 1)

	HudStyle.add_backdrop(self)

	var title := Label.new()
	title.text = "LEADERBOARD"
	title.add_theme_font_size_override("font_size", 34 if narrow else 44)
	HudStyle.style_title(title)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	title.offset_top = 30.0 if narrow else 22.0
	title.offset_bottom = title.offset_top + 56.0
	add_child(title)

	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.offset_top = 70.0   # keep the column clear of the title
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(center)

	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 10)
	col.custom_minimum_size = Vector2(width, 0)
	center.add_child(col)

	col.add_child(_build_identity())
	col.add_child(_build_picker(narrow))

	_status = Label.new()
	_status.theme_type_variation = "LabelBody"
	_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status.custom_minimum_size = Vector2(width, 44)
	_status.add_theme_color_override("font_color", Palette.TEXT_LIGHT_MUTED)
	col.add_child(_status)

	var panel := PanelContainer.new()
	var box := HudStyle.panel()
	box.set_content_margin_all(8)
	panel.add_theme_stylebox_override("panel", box)
	panel.custom_minimum_size = Vector2(width, 300 if narrow else 330)
	col.add_child(panel)
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	panel.add_child(scroll)
	_rows_box = VBoxContainer.new()
	_rows_box.add_theme_constant_override("separation", 4)
	_rows_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_rows_box)

	var btn_row := HBoxContainer.new()
	btn_row.alignment = BoxContainer.ALIGNMENT_CENTER
	btn_row.add_theme_constant_override("separation", 12)
	col.add_child(btn_row)
	var refresh := _btn(btn_row, "Refresh", "ButtonSecondary")
	refresh.pressed.connect(func(): _select(_board))
	var back := _btn(btn_row, "Back", "ButtonGhost")
	back.pressed.connect(func(): Game.goto_menu())

	_select(_board)


## Who the player is on the board: their Reddit account inside a post, or a
## name they type (used when their times are submitted) elsewhere.
func _build_identity() -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	var label := Label.new()
	label.add_theme_color_override("font_color", Palette.TEXT_LIGHT_MUTED)
	row.add_child(label)
	if Reddit.is_available():
		if Reddit.username != "":
			label.text = "Racing as"
			var avatar := AvatarBadge.new()
			avatar.setup(Reddit.username, Reddit.avatar_url, AVATAR_PX)
			row.add_child(avatar)
			var who := Label.new()
			who.text = "u/" + Reddit.username
			who.add_theme_color_override("font_color", Palette.GOLD)
			row.add_child(who)
		else:
			label.text = "Log in to Reddit to appear on the board"
		return row
	label.text = "Your name"
	var name_edit := LineEdit.new()
	name_edit.text = Game.get_player_name()
	name_edit.max_length = 24
	name_edit.custom_minimum_size = Vector2(240, 44)
	name_edit.text_submitted.connect(func(t): Game.set_player_name(t))
	name_edit.focus_exited.connect(func(): Game.set_player_name(name_edit.text))
	row.add_child(name_edit)
	return row


## Board picker: a toggle per board on desktop. A phone has no room for that
## many buttons in a row, so there it is a < Board > stepper.
func _build_picker(narrow: bool) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	if narrow:
		var prev := _btn(row, "<", "ButtonGhost")
		prev.custom_minimum_size = Vector2(56, 46)
		prev.pressed.connect(func(): _select(posmod(_board - 1, _boards.size())))
		_board_name = Label.new()
		_board_name.custom_minimum_size = Vector2(170, 0)
		_board_name.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_board_name.add_theme_font_size_override("font_size", 22)
		HudStyle.style_title(_board_name)
		row.add_child(_board_name)
		var next := _btn(row, ">", "ButtonGhost")
		next.custom_minimum_size = Vector2(56, 46)
		next.pressed.connect(func(): _select(posmod(_board + 1, _boards.size())))
		return row
	for i in _boards.size():
		var at := i
		var b := Button.new()
		b.text = _board_title(i)
		b.toggle_mode = true
		b.theme_type_variation = "ButtonGhost"
		b.custom_minimum_size = Vector2(104, 42)
		b.add_theme_font_size_override("font_size", 14)
		b.focus_mode = Control.FOCUS_NONE
		b.pressed.connect(func(): _select(at))
		row.add_child(b)
		_board_btns.append(b)
	return row


func _btn(parent: Node, text: String, variation := "") -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(150, 46)
	b.focus_mode = Control.FOCUS_NONE
	if variation != "":
		b.theme_type_variation = variation
	parent.add_child(b)
	return b


func _is_overall(at: int) -> bool:
	return _boards[at] == OVERALL_SLOT


func _is_day(at: int) -> bool:
	return _boards[at] == DAY_SLOT


func _board_title(at: int) -> String:
	if _is_overall(at):
		return "OVERALL"
	if _is_day(at):
		return "TODAY"
	return String(Game.get_level(_boards[at])["name"]).to_upper()


## The id the Leaderboard autoload knows this board by.
func _board_id(at: int) -> int:
	if _is_overall(at):
		return Leaderboard.OVERALL
	if _is_day(at):
		return Leaderboard.DAY
	return Game.level_id(_boards[at])


func _select(at: int) -> void:
	_board = at
	for i in _board_btns.size():
		_board_btns[i].button_pressed = (i == at)
	if _board_name != null:
		_board_name.text = _board_title(at)
	_clear_rows()
	if not Leaderboard.configured():
		_status.text = "Online leaderboard isn't set up yet — add your Appwrite keys in scripts/leaderboard.gd."
		return
	_status.text = "Loading…"
	Leaderboard.fetch_top(_board_id(at), ROWS)


func _on_scores_loaded(level: int, rows: Array) -> void:
	if level != _board_id(_board):
		return
	_clear_rows()
	_status.text = _summary(rows.size())
	var rank := 1
	for r in rows:
		_add_row(rank, String(r["name"]), int(r["time_ms"]), String(r.get("avatar", "")))
		rank += 1


## The line under the picker: what this board ranks, and where the player is.
func _summary(shown: int) -> String:
	var info := Leaderboard.last_info
	var text := ""
	if _is_overall(_board):
		text = "Best times on all %d maps, added up. Lowest total wins." % Game.level_count()
		var done := int(info.get("maps_done", 0))
		var total := int(info.get("maps_total", Game.level_count()))
		if Reddit.username != "" and done < total:
			text += "\nYou have %d of %d maps. Finish them all to rank." % [done, total]
	elif shown == 0:
		text = "No times yet — be the first to set one!"
	elif _is_day(_board):
		var idx := Game.daily_index()
		var level_name := String(Game.get_level(idx)["name"]) if idx >= 0 else "today's circuit"
		text = "Fastest on %s %s. Top %d shown." % [level_name, "today" if Reddit.is_today else "that day", shown]
	else:
		text = "Best time on this map. Top %d shown." % shown
	if int(info.get("me_rank", 0)) > 0:
		text += "\nYou are #%d of %d, with %s." % [
			int(info["me_rank"]), int(info.get("players", shown)),
			Game.format_time(int(info.get("me_time_ms", 0)) / 1000.0),
		]
	return text


func _on_request_failed(message: String) -> void:
	_status.text = "Couldn't reach the leaderboard (%s)." % message


func _clear_rows() -> void:
	for c in _rows_box.get_children():
		c.queue_free()


## One ranked line: a badge (medal colours for the top three), the player's
## avatar, the name, the time. The player's own line is picked out in red-orange.
func _add_row(rank: int, who: String, time_ms: int, avatar_url := "") -> void:
	var mine := Reddit.username != "" and who == Reddit.username
	var line := PanelContainer.new()
	var back := HudStyle.pill(Color(Palette.SURFACE_INSET, 1.0 if rank % 2 == 1 else 0.0), 10)
	if mine:
		back.bg_color = Color(Palette.POP, 0.16)
		back.border_color = Palette.POP
		back.set_border_width_all(2)
	back.content_margin_left = 8.0
	back.content_margin_right = 12.0
	back.content_margin_top = 4.0
	back.content_margin_bottom = 4.0
	line.add_theme_stylebox_override("panel", back)
	line.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	line.add_child(row)

	var badge := Label.new()
	badge.text = str(rank)
	badge.custom_minimum_size = Vector2(38, 26)
	badge.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	badge.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	var medals := [Palette.MEDAL_GOLD, Palette.MEDAL_SILVER, Palette.MEDAL_BRONZE]
	if rank <= 3:
		badge.add_theme_stylebox_override("normal", HudStyle.chip(medals[rank - 1]))
		badge.add_theme_color_override("font_color", Palette.TEXT_ON_GOLD)
	else:
		var plain := HudStyle.pill(Palette.STROKE)
		badge.add_theme_stylebox_override("normal", plain)
		badge.add_theme_color_override("font_color", Palette.TEXT_MUTED)
	row.add_child(badge)

	var avatar := AvatarBadge.new()
	avatar.setup(who, avatar_url, AVATAR_PX)
	row.add_child(avatar)

	var name_lbl := Label.new()
	name_lbl.text = who
	name_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_lbl.clip_text = true
	name_lbl.add_theme_color_override("font_color", Palette.POP_DEEP if mine else Palette.TEXT)
	row.add_child(name_lbl)

	var time_lbl := Label.new()
	time_lbl.text = Game.format_time(time_ms / 1000.0)
	time_lbl.custom_minimum_size = Vector2(96, 0)
	time_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	row.add_child(time_lbl)
	_rows_box.add_child(line)
