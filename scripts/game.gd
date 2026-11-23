extends Node2D
## Race controller. Builds the circuit for the selected level, runs the countdown
## and the race (checkpoints in order, crossing the start/finish gate = a lap),
## awards a medal on finish, tracks best lap, and provides a manual pause.
##
## The mode comes from `Game.casual` (see game_data.gd): a ranked race is ONE
## lap with the wall-hit limit, and its time is recorded, medalled and sent
## to the leaderboard; a casual race is THREE laps with no wall-hit limit, and
## only its time is kept, as a casual personal best.
##
## Wall-hit limit (ranked): every new touch of a track wall is counted across
## the race. The first four get a warning; the fifth (`MAX_WALL_TOUCHES`) ends
## the race as GAME OVER, with nothing saved and the next level not unlocked.
## The HUD pips, How to Play and the level screen all read the limit from here.
## Single-player only (the hidden multiplayer has no fail flow).

const CheckpointScene := preload("res://scenes/Checkpoint.tscn")
const CarScene := preload("res://scenes/Car.tscn")

enum State { COUNTDOWN, RACING, FINISHED }

# The touch that ends the race. 3 until 2026-11-21, when the user found the
# game "still very difficult" and asked for 5.
const MAX_WALL_TOUCHES := 5

@onready var _cars := $Cars
@onready var _hud := $HUD
@onready var _touch := $TouchControls

var _car: Node = null              # the LOCAL player's car (set after it spawns)

var _checkpoints: Array = []
var _next_index: int = 1          # gate 0 = start/finish; race begins heading to gate 1
var _state: State = State.COUNTDOWN
var _elapsed: float = 0.0
var _countdown_t: float = 3.0
var _go_hide_t: float = 0.0
var _paused: bool = false
var _level_idx: int = 0
var _sfx_checkpoint: AudioStreamPlayer
var _sfx_finish: AudioStreamPlayer
var _sfx_beep: AudioStreamPlayer
var _sfx_go: AudioStreamPlayer
var _sfx_warn: AudioStreamPlayer
var _last_count: int = -1
var _wall_touches: int = 0
var _casual: bool = false          # this race is casual (see the header)

var _laps: int = 3
var _lap: int = 1
var _lap_start: float = 0.0
var _best_lap_run: float = 0.0
var _cur_splits: Dictionary = {}   # gate index -> lap time at pass (current lap)
var _best_splits: Dictionary = {}  # splits of the best lap so far this session (delta reference)

# --- Multiplayer spawn state ---
var _lv: Dictionary = {}
var _built: Dictionary = {}
var _cars_ready: bool = false      # the local car exists -> the countdown may run
var _cars_spawned: bool = false    # server: cars already dealt out this race
var _ready_peers: Dictionary = {}  # server: peer_id -> reported its race scene is ready


func _ready() -> void:
	_level_idx = Game.current_level
	_lv = Game.active_race()   # MP -> the wide shared track; else the chosen level
	_laps = int(_lv.get("laps", 3))
	_casual = Game.casual and not Net.is_multiplayer

	_built = TrackBuilder.build(_lv["track"], $Track, $Checkpoints, CheckpointScene, $Obstacles)
	_checkpoints = _built["checkpoints"]
	for cp in _checkpoints:
		cp.passed.connect(_on_checkpoint_passed)

	_hud.set_track(_built["centerline"], _built["gate_points"])   # the mini map
	_set_active(_next_index)
	_hud.ui_action.connect(_on_ui_action)
	_hud.set_level_name(String(_lv["name"]) + (" · CASUAL" if _casual else ""))
	_hud.set_lap(1, _laps)
	_hud.set_best(Game.casual_best(_level_idx) if _casual else Game.best_time(_level_idx))
	_hud.set_best_lap(Game.casual_best_lap(_level_idx) if _casual else Game.best_lap(_level_idx))
	_hud.set_speed_max(_lv["max_speed"])
	_hud.set_wall_touches(0, 0 if Net.is_multiplayer or _casual else MAX_WALL_TOUCHES)
	_hud.show_countdown("3")

	_sfx_checkpoint = _make_sfx("res://audio/checkpoint.wav")
	_sfx_finish = _make_sfx("res://audio/finish.wav")
	_sfx_beep = _make_sfx("res://audio/beep.wav")
	_sfx_go = _make_sfx("res://audio/go.wav")
	_sfx_warn = _make_sfx("res://audio/beep.wav")   # the countdown beep, pitched down

	# Single-player: one local car right now. Multiplayer: the server deals one car
	# per peer once everyone's race scene is ready (see the spawn handshake below).
	if Net.is_multiplayer:
		_begin_multiplayer_spawn()
	else:
		_spawn_car(1, _built["car_start_pos"], _built["car_start_rot"])
		_cars_ready = true


func _make_sfx(path: String) -> AudioStreamPlayer:
	var p := AudioStreamPlayer.new()
	var s: Resource = load(path)
	if s != null:
		p.stream = s
	add_child(p)
	return p


# --- Car spawning ----------------------------------------------------------

## Builds a car for peer `pid` at its grid slot: level config, network authority,
## transform replication, and (for the local player) the active camera + the
## `_car` reference. Frozen until GO.
func _spawn_car(pid: int, pos: Vector2, rot: float) -> void:
	var is_local := (pid == Net.local_id())
	var car := CarScene.instantiate()
	car.name = "Car_%d" % pid
	car.position = pos
	car.rotation = rot
	# Set the replication config before the synchronizer enters the tree.
	(car.get_node("Sync") as MultiplayerSynchronizer).replication_config = _make_car_repl()
	# Only the local player's camera drives the viewport; disable the others
	# before they enter the tree so they don't grab "current".
	var cam := car.get_node("Camera2D") as Camera2D
	cam.enabled = is_local
	_cars.add_child(car, true)
	car.set_multiplayer_authority(pid)   # recursive: covers the Sync child too
	car.max_speed = _lv["max_speed"]
	car.accel_force = _lv["accel_force"]
	car.boost_meter = 1.0
	if is_local:
		cam.make_current()
		_car = car
		_hud.set_car(pos, rot)
		car.wall_touched.connect(_on_wall_touched)
		car.set_physics_process(false)   # frozen until the countdown hits GO


## What the synchronizer replicates from the authority to everyone else.
func _make_car_repl() -> SceneReplicationConfig:
	var cfg := SceneReplicationConfig.new()
	for p in [".:position", ".:rotation", ".:front_steer", ".:rear_steer", ".:boost_meter", ".:_boosting"]:
		var np := NodePath(p)
		cfg.add_property(np)
		cfg.property_set_spawn(np, true)
		cfg.property_set_sync(np, true)
	return cfg


# --- Multiplayer spawn handshake -------------------------------------------
# The server deals the cars, but only after every player's race scene exists, so
# the spawn RPCs can't arrive before a peer is ready to receive them.

func _begin_multiplayer_spawn() -> void:
	if multiplayer.is_server():
		_ready_peers[1] = true
		_try_deal_cars()
	else:
		_report_ready.rpc_id(1)


@rpc("any_peer", "call_remote", "reliable")
func _report_ready() -> void:
	if not multiplayer.is_server():
		return
	_ready_peers[multiplayer.get_remote_sender_id()] = true
	_try_deal_cars()


func _try_deal_cars() -> void:
	if _cars_spawned or not multiplayer.is_server():
		return
	for pid in Net.players:
		if not _ready_peers.has(pid):
			return   # still waiting on someone's scene
	_cars_spawned = true
	var grid := _grid_positions(_built["car_start_pos"], _built["car_start_rot"], Net.players.size())
	var i := 0
	for pid in Net.players:
		_deal_car.rpc(int(pid), grid[i]["pos"], grid[i]["rot"])
		i += 1


@rpc("authority", "call_local", "reliable")
func _deal_car(pid: int, pos: Vector2, rot: float) -> void:
	_spawn_car(pid, pos, rot)
	if pid == Net.local_id():
		_cars_ready = true   # my car exists -> my countdown can start


## Side-by-side slots across the (wide) start line, centered on the centerline.
func _grid_positions(base_pos: Vector2, base_rot: float, count: int) -> Array:
	var across := Vector2.from_angle(base_rot)   # the car's right = across the road
	var spacing := 46.0
	var out: Array = []
	for i in count:
		var lateral := (float(i) - (count - 1) / 2.0) * spacing
		out.append({"pos": base_pos + across * lateral, "rot": base_rot})
	return out


func _process(delta: float) -> void:
	if _paused:
		return
	match _state:
		State.COUNTDOWN:
			if not _cars_ready:
				return   # MP: wait until the local car has been dealt
			_countdown_t -= delta
			if _countdown_t > 0.0:
				var cn := int(ceil(_countdown_t))
				if cn != _last_count:
					_last_count = cn
					if _sfx_beep.stream != null:
						_sfx_beep.play()
				_hud.show_countdown(str(cn))
			else:
				_begin_race()
		State.RACING:
			_elapsed += delta
			_hud.set_timer(_elapsed)
			_hud.set_lap_time(_elapsed - _lap_start)
			if _car != null:
				_hud.set_speed(_car.velocity.length())
				_hud.set_boost(_car.boost_meter)
				_hud.set_car(_car.global_position, _car.rotation)
				_update_arrow()
			if _go_hide_t > 0.0:
				_go_hide_t -= delta
				if _go_hide_t <= 0.0:
					_hud.hide_countdown()


func _begin_race() -> void:
	_state = State.RACING
	if _car != null:
		_car.set_physics_process(true)
	_elapsed = 0.0
	_lap_start = 0.0
	_go_hide_t = 0.6
	_hud.show_countdown("GO!")
	if _sfx_go.stream != null:
		_sfx_go.play()


func _update_arrow() -> void:
	var cp: Node2D = _checkpoints[_next_index]
	var rel: float = (cp.global_position - _car.global_position).angle() - (_car.rotation - PI / 2.0)
	_hud.set_arrow(true, rel)


func _on_checkpoint_passed(index: int, body: Node) -> void:
	# Online, each peer counts only its OWN car's gates (remote cars are puppets
	# that also trip the gate locally).
	if Net.is_multiplayer and body != _car:
		return
	if _state != State.RACING or index != _next_index:
		return
	_checkpoints[index].pop()
	_record_split(index)
	if index == 0:
		_complete_lap()
		if _state == State.RACING:
			_next_index = 1
			_set_active(_next_index)
	else:
		_next_index = index + 1
		if _next_index >= _checkpoints.size():
			_next_index = 0  # next target is the start/finish gate
		_set_active(_next_index)
		if _sfx_checkpoint.stream != null:
			_sfx_checkpoint.play()


## Stores the current lap's time at gate `index` and, if we have a reference best
## lap, pops the live +/- delta against its split at the same gate.
func _record_split(index: int) -> void:
	var lap_t := _elapsed - _lap_start
	_cur_splits[index] = lap_t
	if _best_splits.has(index):
		_hud.show_delta(lap_t - float(_best_splits[index]))


func _complete_lap() -> void:
	var lap_time := _elapsed - _lap_start
	if _best_lap_run <= 0.0 or lap_time < _best_lap_run:
		_best_lap_run = lap_time
		_best_splits = _cur_splits.duplicate()  # this lap becomes the delta reference
		_hud.set_best_lap(_best_lap_run)
		_hud.flash_best_lap()
	_lap_start = _elapsed
	_lap += 1
	_cur_splits = {}  # reset splits for the next lap
	if _lap > _laps:
		_finish()
	else:
		_hud.set_lap(_lap, _laps)
		if _sfx_checkpoint.stream != null:
			_sfx_checkpoint.play()


## A new wall touch from the local car (car.gd has already merged scrapes and
## bounces into single touches). Casual races have no limit, so it is ignored.
func _on_wall_touched() -> void:
	if _state != State.RACING or Net.is_multiplayer or _casual:
		return
	_wall_touches += 1
	_hud.set_wall_touches(_wall_touches, MAX_WALL_TOUCHES)
	if _wall_touches >= MAX_WALL_TOUCHES:
		_game_over()
		return
	_hud.show_wall_warning(_wall_touches, MAX_WALL_TOUCHES)
	if _sfx_warn.stream != null:
		_sfx_warn.pitch_scale = 0.75
		_sfx_warn.play()


## Third wall touch: the race ends here. Nothing is recorded, so no best time,
## no medal, no leaderboard entry, and the next level stays locked.
func _game_over() -> void:
	_state = State.FINISHED
	if _car != null:
		_car.set_physics_process(false)
	_touch.set_enabled(false)
	_hud.set_arrow(false, 0.0)
	_hud.hide_countdown()
	if _sfx_warn.stream != null:
		_sfx_warn.pitch_scale = 0.45
		_sfx_warn.play()
	_hud.show_game_over(_wall_touches, mini(_lap, _laps), _laps, _elapsed)


func _finish() -> void:
	_state = State.FINISHED
	if _car != null:
		_car.set_physics_process(false)
	_touch.set_enabled(false)   # the results card owns the screen now
	_hud.set_arrow(false, 0.0)
	if _sfx_finish.stream != null:
		_sfx_finish.play()
	if Net.is_multiplayer:
		# No medals/unlocks online — just show the time (race-flow polish is later).
		_hud.show_results(_elapsed, "none", 0.0, _best_lap_run, false, _laps)
		return
	if _casual:
		# Casual: just the time. A personal best per map; no medal, no unlock,
		# nothing sent to the leaderboard.
		var improved := Game.record_casual(_level_idx, _elapsed, _best_lap_run)
		_hud.show_results(
			_elapsed, "none", Game.casual_best(_level_idx), Game.casual_best_lap(_level_idx),
			Game.has_next_level(_level_idx), _laps, improved
		)
		return
	var medal := Game.record_result(_level_idx, _elapsed, _best_lap_run)
	_hud.show_results(
		_elapsed, medal, Game.best_time(_level_idx), Game.best_lap(_level_idx),
		Game.has_next_level(_level_idx), _laps
	)
	# On Reddit the card waits for the server's answer (place today, streak,
	# countdown). Connected before submitting: the answer may come at once.
	if Reddit.is_available():
		_hud.show_daily_pending()
		Leaderboard.run_recorded.connect(_hud.show_daily_result, CONNECT_ONE_SHOT)
	# Upload the time to the online leaderboard (no-op until Appwrite is configured).
	Leaderboard.submit_score(Game.get_player_name(), Game.level_id(_level_idx), int(round(_elapsed * 1000.0)))


func _set_active(idx: int) -> void:
	for i in _checkpoints.size():
		_checkpoints[i].set_state("active" if i == idx else "pending")
	_hud.set_next_gate(idx)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.physical_keycode == KEY_ESCAPE or event.physical_keycode == KEY_P:
			if _state == State.RACING or _paused:
				_toggle_pause()


func _toggle_pause() -> void:
	_paused = not _paused
	if _car != null:
		_car.set_physics_process(not _paused)
	_touch.set_enabled(not _paused)
	_hud.show_pause(_paused)


func _on_ui_action(action: String) -> void:
	# Online, Retry/Menu both leave the session cleanly (a shared re-race is later).
	if Net.is_multiplayer and action in ["retry", "menu"]:
		Net.leave()
		Game.goto_menu()
		return
	match action:
		"pause":   # the HUD's on-screen button (touch has no Esc)
			if _state == State.RACING and not _paused:
				_toggle_pause()
		"resume":
			if _paused:
				_toggle_pause()
		"retry":
			Game.start_level(_level_idx)
		"next":
			if Game.has_next_level(_level_idx):
				Game.start_level(_level_idx + 1)
		"leaderboard":   # Reddit's results card: open on today's board
			Leaderboard.open_on_day = true
			Game.goto_leaderboard()
		"menu":
			Game.goto_menu()
