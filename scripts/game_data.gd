extends Node
## Autoload "Game": the spine that ties the scenes together.
## Holds the level table, the currently selected level, saved progress
## (best times, medals; a level unlocks once the one before it has been
## finished), and settings (volume). Also owns the scene navigation helpers so
## menus and the race scene don't duplicate paths.

const SAVE_PATH := "user://save.json"

const MEDAL_NONE := "none"
const MEDAL_BRONZE := "bronze"
const MEDAL_SILVER := "silver"
const MEDAL_GOLD := "gold"

const SCENE_MENU := "res://scenes/MainMenu.tscn"
const SCENE_LEVEL_SELECT := "res://scenes/LevelSelect.tscn"
const SCENE_RACE := "res://scenes/Main.tscn"
const SCENE_INSTRUCTIONS := "res://scenes/Instructions.tscn"
const SCENE_LOBBY := "res://scenes/Lobby.tscn"
const SCENE_LEADERBOARD := "res://scenes/Leaderboard.tscn"

## The circuits. Each is a closed loop of waypoints plus a road width; the
## TrackBuilder turns it into the road (the waypoints guide a smoothed centre
## line, they are not the exact road). Preview any of them, or all five on one
## sheet, with `python tools/preview_track.py t1..t5|all`, and keep that tool's
## presets in step with these.
const TRACK_1 := {   # medium width, flowing, one tight right-hand pair
	"centerline": [
		Vector2(720, 520), Vector2(1180, 440), Vector2(1620, 540), Vector2(2060, 450),
		Vector2(2420, 640), Vector2(2500, 1000), Vector2(2300, 1240), Vector2(2460, 1480),
		Vector2(2040, 1560), Vector2(1600, 1440), Vector2(1160, 1560), Vector2(780, 1400),
		Vector2(600, 1040), Vector2(560, 720),
	],
	"road_width": 88.0,
	"checkpoint_count": 8,
}

const TRACK_2 := {   # the tight twisty circuit
	"centerline": [
		Vector2(881, 545), Vector2(1493, 524), Vector2(1925, 567),
		Vector2(2249, 761), Vector2(2069, 941), Vector2(2285, 1121), Vector2(2105, 1301),
		Vector2(2177, 1481), Vector2(1817, 1503), Vector2(1493, 1373), Vector2(1205, 1517),
		Vector2(917, 1409), Vector2(665, 1229), Vector2(845, 1013), Vector2(650, 826), Vector2(816, 653),
	],
	"road_width": 75.0,
	"checkpoint_count": 9,
}

const TRACK_3 := {   # narrow, with deeper esses on both sides
	"centerline": [
		Vector2(820, 560), Vector2(1280, 500), Vector2(1700, 580), Vector2(2120, 520),
		Vector2(2360, 820), Vector2(2080, 1020), Vector2(2380, 1260), Vector2(2080, 1480),
		Vector2(1680, 1420), Vector2(1340, 1520), Vector2(1000, 1380), Vector2(760, 1480),
		Vector2(620, 1120), Vector2(920, 940), Vector2(640, 720),
	],
	"road_width": 72.0,
	"checkpoint_count": 9,
}

const TRACK_4 := {   # esses along the top, a tight two-hairpin switchback, a chicane along the bottom, esses up the left
	"centerline": [
		Vector2(700, 480), Vector2(950, 400), Vector2(1200, 530), Vector2(1450, 400),
		Vector2(1700, 500), Vector2(2330, 560), Vector2(2460, 800), Vector2(2360, 990),
		Vector2(2050, 1010), Vector2(1790, 1020), Vector2(1690, 1095), Vector2(1790, 1170),
		Vector2(2100, 1180), Vector2(2380, 1210), Vector2(2480, 1320), Vector2(2380, 1430),
		Vector2(2160, 1520), Vector2(1950, 1390), Vector2(1740, 1530), Vector2(1400, 1440),
		Vector2(1000, 1520), Vector2(680, 1420), Vector2(540, 1150), Vector2(700, 900),
		Vector2(540, 700),
	],
	"road_width": 68.0,
	"checkpoint_count": 10,
}

const TRACK_5 := {   # esses into a narrow inlet with a hairpin at its foot, esses along the bottom, a double switchback, a kink up the left
	"centerline": [
		Vector2(700, 520), Vector2(860, 450), Vector2(1040, 570), Vector2(1220, 460),
		Vector2(1400, 640), Vector2(1400, 950), Vector2(1480, 1110), Vector2(1560, 950),
		Vector2(1560, 640), Vector2(1700, 500), Vector2(2000, 460), Vector2(2300, 520),
		Vector2(2470, 720), Vector2(2380, 960), Vector2(2480, 1200), Vector2(2360, 1430),
		Vector2(2150, 1530), Vector2(1930, 1400), Vector2(1710, 1540), Vector2(1500, 1440),
		Vector2(1250, 1500), Vector2(1070, 1400), Vector2(1040, 1050), Vector2(940, 900),
		Vector2(840, 1050), Vector2(840, 1280), Vector2(740, 1410), Vector2(640, 1280),
		Vector2(570, 1110), Vector2(680, 950), Vector2(590, 790),
	],
	"road_width": 64.0,
	"checkpoint_count": 12,
}

## Multiplayer track (the hidden mode): a wide flowing loop so several cars fit
## side-by-side and can trade paint without instantly walling out.
const TRACK_MP := {
	"centerline": [
		Vector2(700, 400), Vector2(1500, 360), Vector2(2200, 460),
		Vector2(2520, 850), Vector2(2350, 1300), Vector2(1750, 1560),
		Vector2(1050, 1560), Vector2(520, 1300), Vector2(330, 850), Vector2(600, 500),
	],
	"road_width": 180.0,
	"checkpoint_count": 6,
}

## Multiplayer race config (no medals/unlocks — it's not part of SP progression).
const MP_RACE := {
	"name": "Multiplayer", "track": TRACK_MP, "max_speed": 520.0, "accel_force": 400.0, "laps": 3,
}

## Per-level: which track, car speed, lap count, and 3-lap medal target totals
## (seconds). Targets are rough — retune after a drive.
##
## `id` is the level's PERMANENT identity: saved records and the online
## leaderboard are keyed by it, so levels can be reordered or dropped without
## times landing on the wrong track. Never renumber or reuse one; give a new
## track the next unused number. (0, 4, 5, 6 and 7 belonged to retired tracks.)
const LEVELS := [
	{"id": 2, "name": "Level 1", "track": TRACK_1, "max_speed": 620.0, "accel_force": 480.0, "laps": 3, "gold": 58.0, "silver": 74.0, "bronze": 98.0},
	{"id": 1, "name": "Level 2", "track": TRACK_2, "max_speed": 600.0, "accel_force": 460.0, "laps": 3, "gold": 56.0, "silver": 72.0, "bronze": 95.0},
	{"id": 3, "name": "Level 3", "track": TRACK_3, "max_speed": 665.0, "accel_force": 510.0, "laps": 3, "gold": 60.0, "silver": 78.0, "bronze": 102.0},
	{"id": 8, "name": "Level 4", "track": TRACK_4, "max_speed": 700.0, "accel_force": 535.0, "laps": 3, "gold": 80.0, "silver": 103.0, "bronze": 133.0},
	{"id": 9, "name": "Level 5", "track": TRACK_5, "max_speed": 725.0, "accel_force": 555.0, "laps": 3, "gold": 85.0, "silver": 110.0, "bronze": 143.0},
]

var current_level: int = 0
var progress: Dictionary = {}


func _ready() -> void:
	load_progress()
	apply_volume()


# --- Level helpers ---------------------------------------------------------

func level_count() -> int:
	return LEVELS.size()


func get_level(idx: int) -> Dictionary:
	return LEVELS[clampi(idx, 0, LEVELS.size() - 1)]


## The race config to load. Multiplayer uses the shared wide MP track; otherwise
## the selected single-player level. (game.gd reads this in _ready.)
func active_race() -> Dictionary:
	return MP_RACE if Net.is_multiplayer else get_level(current_level)


## The level's permanent id (see LEVELS): the key for saves and the leaderboard.
func level_id(idx: int) -> int:
	return int(get_level(idx)["id"])


## Level 1 is always open; each later level opens once the one before it has
## been finished. Derived from the saved records, so it survives reordering.
## Inside a Reddit post the day's featured circuit is always open too, so
## everyone can play the daily challenge.
func is_unlocked(idx: int) -> bool:
	return idx <= 0 or best_time(idx - 1) > 0.0 or Reddit.daily_level_id == level_id(idx)


# --- Progress / save -------------------------------------------------------

func _default_progress() -> Dictionary:
	return {"levels": {}, "settings": {"volume": 0.8, "muted": false, "name": "Player"}, "seen_instructions": false}


func load_progress() -> void:
	progress = _default_progress()
	if not FileAccess.file_exists(SAVE_PATH):
		return
	var f := FileAccess.open(SAVE_PATH, FileAccess.READ)
	if f == null:
		return
	var text := f.get_as_text()
	f.close()
	var data: Variant = JSON.parse_string(text)
	if typeof(data) != TYPE_DICTIONARY:
		return
	if typeof(data.get("levels")) == TYPE_DICTIONARY:
		progress["levels"] = data["levels"]
	if typeof(data.get("settings")) == TYPE_DICTIONARY:
		progress["settings"]["volume"] = float(data["settings"].get("volume", 0.8))
		progress["settings"]["muted"] = bool(data["settings"].get("muted", false))
		progress["settings"]["name"] = String(data["settings"].get("name", "Player"))
	progress["seen_instructions"] = bool(data.get("seen_instructions", false))


func save_progress() -> void:
	var f := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if f == null:
		return
	f.store_string(JSON.stringify(progress))
	f.close()


## Saved record of the level in slot `idx`, stored under its permanent id.
func _level_record(idx: int) -> Dictionary:
	var levels: Dictionary = progress["levels"]
	return levels.get(str(level_id(idx)), {})


func best_time(idx: int) -> float:
	return float(_level_record(idx).get("best_time", 0.0))


func best_lap(idx: int) -> float:
	return float(_level_record(idx).get("best_lap", 0.0))


func best_medal(idx: int) -> String:
	return String(_level_record(idx).get("medal", MEDAL_NONE))


func medal_for(idx: int, time: float) -> String:
	var lv := get_level(idx)
	if time <= float(lv["gold"]):
		return MEDAL_GOLD
	elif time <= float(lv["silver"]):
		return MEDAL_SILVER
	elif time <= float(lv["bronze"]):
		return MEDAL_BRONZE
	return MEDAL_NONE


func medal_rank(m: String) -> int:
	match m:
		MEDAL_GOLD: return 3
		MEDAL_SILVER: return 2
		MEDAL_BRONZE: return 1
		_: return 0


## Records a FINISHED run: saves best time and keeps the highest medal earned.
## Having a best time is what unlocks the next level (see is_unlocked), so a run
## that ends in game over must not come through here. Returns the medal earned
## THIS run.
func record_result(idx: int, total: float, lap: float) -> String:
	var medal := medal_for(idx, total)
	var levels: Dictionary = progress["levels"]
	var key := str(level_id(idx))
	var rec: Dictionary = levels.get(key, {})

	var prev_best := float(rec.get("best_time", 0.0))
	if prev_best <= 0.0 or total < prev_best:
		rec["best_time"] = total
	var prev_lap := float(rec.get("best_lap", 0.0))
	if lap > 0.0 and (prev_lap <= 0.0 or lap < prev_lap):
		rec["best_lap"] = lap
	if medal_rank(medal) > medal_rank(String(rec.get("medal", MEDAL_NONE))):
		rec["medal"] = medal
	elif not rec.has("medal"):
		rec["medal"] = medal
	levels[key] = rec
	save_progress()
	return medal


func has_next_level(idx: int) -> bool:
	return idx + 1 < LEVELS.size()


# --- Settings --------------------------------------------------------------

func get_volume() -> float:
	return float(progress["settings"].get("volume", 0.8))


func set_volume(v: float) -> void:
	progress["settings"]["volume"] = clampf(v, 0.0, 1.0)
	apply_volume()
	save_progress()


func apply_volume() -> void:
	var v := get_volume()
	AudioServer.set_bus_volume_db(0, linear_to_db(v) if v > 0.001 else -80.0)
	AudioServer.set_bus_mute(0, is_muted())


## The corner mute button (MuteButton autoload). Kept apart from the volume, so
## unmuting returns to the level the slider was left at.
func is_muted() -> bool:
	return bool(progress["settings"].get("muted", false))


func set_muted(muted: bool) -> void:
	progress["settings"]["muted"] = muted
	apply_volume()
	save_progress()


func get_player_name() -> String:
	return String(progress["settings"].get("name", "Player"))


func set_player_name(n: String) -> void:
	var clean := n.strip_edges().substr(0, 24)
	progress["settings"]["name"] = clean if clean != "" else "Player"
	save_progress()


# --- Navigation ------------------------------------------------------------

func start_level(idx: int) -> void:
	current_level = idx
	get_tree().change_scene_to_file(SCENE_RACE)

func goto_menu() -> void:
	get_tree().paused = false
	get_tree().change_scene_to_file(SCENE_MENU)

func goto_level_select() -> void:
	get_tree().change_scene_to_file(SCENE_LEVEL_SELECT)

func goto_lobby() -> void:
	get_tree().change_scene_to_file(SCENE_LOBBY)

func goto_leaderboard() -> void:
	get_tree().change_scene_to_file(SCENE_LEADERBOARD)

func goto_instructions() -> void:
	get_tree().change_scene_to_file(SCENE_INSTRUCTIONS)

func has_seen_instructions() -> bool:
	return bool(progress.get("seen_instructions", false))

func mark_instructions_seen() -> void:
	progress["seen_instructions"] = true
	save_progress()


# --- Formatting ------------------------------------------------------------

static func format_time(seconds: float) -> String:
	if seconds <= 0.0:
		return "--"
	var m := int(seconds) / 60
	var s := int(seconds) % 60
	var h := int(seconds * 100.0) % 100
	return "%d:%02d.%02d" % [m, s, h]
