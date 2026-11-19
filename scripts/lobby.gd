extends Control
## Multiplayer lobby (built in code, design-system styled): Host or Join by
## address, see the connected players, and (host only) Start Race. All networking
## goes through the Net autoload; the scene change into the race is driven by
## Net.start_race so the host and every client switch together.

var _status: Label
var _addr_edit: LineEdit
var _list_box: VBoxContainer
var _host_btn: Button
var _join_btn: Button
var _start_btn: Button


func _ready() -> void:
	var bg := ColorRect.new()
	bg.color = Palette.BG
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)

	var title := Label.new()
	title.text = "MULTIPLAYER"
	title.add_theme_font_size_override("font_size", 48)
	title.add_theme_color_override("font_color", Palette.GOLD)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	title.offset_top = 56.0
	title.offset_bottom = 120.0
	add_child(title)

	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(center)

	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 12)
	vb.custom_minimum_size = Vector2(440, 0)
	center.add_child(vb)

	var addr_label := Label.new()
	addr_label.text = "Host address (paste what your friend sent)"
	addr_label.theme_type_variation = "LabelBody"
	addr_label.add_theme_color_override("font_color", Palette.TEXT_MUTED)
	vb.add_child(addr_label)

	_addr_edit = LineEdit.new()
	_addr_edit.text = "127.0.0.1:%d" % Net.DEFAULT_PORT
	_addr_edit.custom_minimum_size = Vector2(0, 44)
	vb.add_child(_addr_edit)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	vb.add_child(row)
	_host_btn = _btn(row, "Host", _on_host)                 # gold primary
	_join_btn = _btn(row, "Join", _on_join, "ButtonSecondary")

	_status = Label.new()
	_status.theme_type_variation = "LabelBody"
	_status.text = "Host a game, or paste a friend's address and Join."
	_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status.custom_minimum_size = Vector2(440, 0)
	_status.add_theme_color_override("font_color", Palette.TEXT_MUTED)
	vb.add_child(_status)

	var players_label := Label.new()
	players_label.text = "Players"
	players_label.add_theme_color_override("font_color", Palette.TEXT_MUTED)
	vb.add_child(players_label)
	_list_box = VBoxContainer.new()
	vb.add_child(_list_box)

	_start_btn = _btn(vb, "Start Race", _on_start)          # gold primary, host only
	_start_btn.visible = false
	_btn(vb, "Back", _on_back, "ButtonGhost")

	Net.player_list_changed.connect(_refresh)
	Net.connection_failed.connect(_on_conn_failed)
	Net.server_disconnected.connect(_on_server_gone)
	Net.start_race.connect(_on_start_race)
	_refresh()


func _btn(parent: Node, text: String, cb: Callable, variation := "") -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(180, 48)
	b.focus_mode = Control.FOCUS_NONE
	if variation != "":
		b.theme_type_variation = variation
	b.pressed.connect(cb)
	parent.add_child(b)
	return b


func _on_host() -> void:
	if Net.host():
		_status.text = ("Hosting on port %d. Same Wi-Fi: share your local IP:%d. " +
			"Over the internet: run a playit.gg UDP tunnel and send that address (see README). " +
			"Then wait for players and Start Race.") % [Net.DEFAULT_PORT, Net.DEFAULT_PORT]
		_lock_connect_ui(true)
	else:
		_status.text = "Could not host — is port %d already in use?" % Net.DEFAULT_PORT


func _on_join() -> void:
	var parts := _addr_edit.text.strip_edges().split(":")
	var address: String = parts[0] if parts.size() > 0 and parts[0] != "" else "127.0.0.1"
	var port: int = int(parts[1]) if parts.size() > 1 else Net.DEFAULT_PORT
	if Net.join(address, port):
		_status.text = "Connecting to %s:%d…" % [address, port]
		_lock_connect_ui(false)
	else:
		_status.text = "Could not start the connection."


func _on_start() -> void:
	Net.host_start_race()


func _on_back() -> void:
	Net.leave()
	Game.goto_menu()


## Disable Host/Join + the address box once a session is opening; reveal Start
## Race only to the host.
func _lock_connect_ui(is_host: bool) -> void:
	_host_btn.disabled = true
	_join_btn.disabled = true
	_addr_edit.editable = false
	_start_btn.visible = is_host


func _refresh() -> void:
	for c in _list_box.get_children():
		c.queue_free()
	for pid in Net.players:
		var l := Label.new()
		var who: String = String(Net.players[pid].get("name", "Player"))
		l.text = "•  %s%s" % [who, "   (you)" if pid == Net.local_id() else ""]
		_list_box.add_child(l)


func _on_conn_failed() -> void:
	_status.text = "Connection failed. Check the address and that the host is running."
	_unlock_connect_ui()


func _on_server_gone() -> void:
	_status.text = "The host closed the lobby."
	_unlock_connect_ui()
	_start_btn.visible = false


func _unlock_connect_ui() -> void:
	_host_btn.disabled = false
	_join_btn.disabled = false
	_addr_edit.editable = true


func _on_start_race() -> void:
	get_tree().change_scene_to_file(Game.SCENE_RACE)
