extends Node
## Autoload "Game": the spine that ties the scenes together.
## Holds the level table, the currently selected level and mode, saved progress
## (best times, medals; a level unlocks once the one before it has been
## finished), and settings (volume). Also owns the scene navigation helpers so
## menus and the race scene don't duplicate paths.
##
## Two ways to race (the user's design):
##  - **Ranked** (`casual` false): ONE lap, five wall hits and out. Its times
##    are the records: medals, unlocks, the online leaderboard and the Daily
##    Circuit.
##  - **Casual** (`casual` true): THREE laps on any map, no wall-hit limit, just
##    the time. Kept apart as a personal best per map; never on a leaderboard.

const SAVE_PATH := "user://save.json"

const MEDAL_NONE := "none"
const MEDAL_BRONZE := "bronze"
const MEDAL_SILVER := "silver"
const MEDAL_GOLD := "gold"

const RANKED_LAPS := 1
const CASUAL_LAPS := 3
## Level n is the Daily Circuit on weekday n (Monday easiest, Sunday hardest).
const WEEKDAYS := ["MONDAY", "TUESDAY", "WEDNESDAY", "THURSDAY", "FRIDAY", "SATURDAY", "SUNDAY"]

const SCENE_MENU := "res://scenes/MainMenu.tscn"
const SCENE_LEVEL_SELECT := "res://scenes/LevelSelect.tscn"
const SCENE_RACE := "res://scenes/Main.tscn"
const SCENE_INSTRUCTIONS := "res://scenes/Instructions.tscn"
const SCENE_LOBBY := "res://scenes/Lobby.tscn"
const SCENE_LEADERBOARD := "res://scenes/Leaderboard.tscn"

## The circuits, one for each day of the week (Monday easiest, Sunday hardest).
## Each is a closed loop of waypoints plus a road width; the TrackBuilder turns
## it into the road (the waypoints guide a smoothed centre line, they are not
## the exact road). `boost_pads` places the boost pads by their fraction of the
## way round the centre line; they sit at the start of the longer straights,
## with room to brake after (tests/track_test.gd checks). Preview any of them, or all seven on one sheet, with
## `python tools/preview_track.py t1..t7|all`, and keep that tool's presets in
## step with these.
const TRACK_1 := {   # Monday, the easiest: wide and flowing; a broad sweep into the infield, a long S up the left
	"centerline": [
		Vector2(936, 676), Vector2(1534, 572), Vector2(1880, 650), Vector2(2100, 1080),
		Vector2(2450, 1180), Vector2(2720, 820), Vector2(3146, 832), Vector2(3250, 1300),
		Vector2(2990, 1612), Vector2(3198, 1924), Vector2(2652, 2028), Vector2(2080, 1840),
		Vector2(1508, 2028), Vector2(1014, 1820), Vector2(780, 1560), Vector2(1200, 1290),
		Vector2(780, 1000),
	],
	"road_width": 114.0,
	"boost_pads": [0.02, 0.63],
	"checkpoint_count": 9,
}

const TRACK_2 := {   # Tuesday: tight and twisty; a hairpin tongue down into the infield
	"centerline": [
		Vector2(1145, 708), Vector2(1700, 681), Vector2(2050, 700), Vector2(2100, 1150),
		Vector2(2240, 1260), Vector2(2380, 1150), Vector2(2430, 760), Vector2(2700, 800),
		Vector2(2924, 989), Vector2(2690, 1223), Vector2(2970, 1457), Vector2(2736, 1691),
		Vector2(2830, 1925), Vector2(2362, 1954), Vector2(1941, 1785), Vector2(1566, 1972),
		Vector2(1192, 1832), Vector2(864, 1598), Vector2(1098, 1317), Vector2(845, 1074),
		Vector2(1061, 849),
	],
	"road_width": 98.0,
	"boost_pads": [0.02, 0.59],
	"checkpoint_count": 10,
}

const TRACK_3 := {   # Wednesday: narrow esses; an S-shaped loop through the infield
	"centerline": [
		Vector2(1066, 728), Vector2(1664, 650), Vector2(1950, 760), Vector2(1900, 1060),
		Vector2(2120, 1260), Vector2(2380, 1060), Vector2(2330, 760), Vector2(2756, 676),
		Vector2(3068, 1066), Vector2(2704, 1326), Vector2(3094, 1638), Vector2(2704, 1924),
		Vector2(2184, 1846), Vector2(1742, 1976), Vector2(1300, 1794), Vector2(988, 1924),
		Vector2(806, 1456), Vector2(1196, 1222), Vector2(832, 936),
	],
	"road_width": 94.0,
	"boost_pads": [0.015, 0.605],
	"checkpoint_count": 10,
}

const TRACK_4 := {   # Thursday: esses along the top, a two-hairpin switchback, a hairpin tongue up from the bottom
	"centerline": [
		Vector2(910, 624), Vector2(1235, 520), Vector2(1560, 689), Vector2(1885, 520),
		Vector2(2210, 650), Vector2(3029, 728), Vector2(3198, 1040), Vector2(3068, 1287),
		Vector2(2665, 1313), Vector2(2327, 1326), Vector2(2197, 1424), Vector2(2327, 1521),
		Vector2(2730, 1534), Vector2(3094, 1573), Vector2(3224, 1716), Vector2(3094, 1859),
		Vector2(2808, 1976), Vector2(2535, 1807), Vector2(2262, 1989), Vector2(1820, 1900),
		Vector2(1720, 1300), Vector2(1560, 1130), Vector2(1400, 1300), Vector2(1350, 1900),
		Vector2(884, 1846), Vector2(702, 1495), Vector2(910, 1170), Vector2(702, 910),
	],
	"road_width": 88.0,
	"boost_pads": [0.40, 0.82],
	"checkpoint_count": 11,
}

const TRACK_5 := {   # Friday: two hairpin tongues off the top, esses along the bottom, a double switchback up the left
	"centerline": [
		Vector2(910, 676), Vector2(1118, 585), Vector2(1352, 741), Vector2(1586, 598),
		Vector2(1820, 832), Vector2(1820, 1235), Vector2(1924, 1443), Vector2(2028, 1235),
		Vector2(2028, 832), Vector2(2210, 650), Vector2(2500, 620), Vector2(2600, 900),
		Vector2(2620, 1300), Vector2(2760, 1450), Vector2(2900, 1300), Vector2(2900, 760),
		Vector2(3100, 760), Vector2(3211, 1000), Vector2(3094, 1248), Vector2(3224, 1560),
		Vector2(3068, 1859), Vector2(2795, 1989), Vector2(2509, 1820), Vector2(2223, 2002),
		Vector2(1950, 1872), Vector2(1625, 1950), Vector2(1391, 1820), Vector2(1352, 1365),
		Vector2(1222, 1170), Vector2(1092, 1365), Vector2(1092, 1664), Vector2(962, 1833),
		Vector2(832, 1664), Vector2(741, 1443), Vector2(884, 1235), Vector2(767, 1027),
	],
	"road_width": 83.0,
	"boost_pads": [0.087, 0.29],
	"checkpoint_count": 13,
}

const TRACK_6 := {   # Saturday: a chicane, kinked hairpin rows across the middle, bottom esses, a switchback up the left
	"centerline": [
		Vector2(1150, 575), Vector2(1600, 660), Vector2(1850, 540), Vector2(2250, 600),
		Vector2(2700, 560), Vector2(3150, 700), Vector2(3300, 1000), Vector2(3100, 1250),
		Vector2(2780, 1170), Vector2(2480, 1290), Vector2(2220, 1160), Vector2(2050, 1300),
		Vector2(2180, 1520), Vector2(2480, 1580), Vector2(2780, 1480), Vector2(3100, 1560),
		Vector2(3350, 1800), Vector2(3150, 2100), Vector2(2700, 2150), Vector2(2400, 1900),
		Vector2(2100, 2150), Vector2(1750, 1950), Vector2(1450, 2150), Vector2(1050, 2100),
		Vector2(800, 1850), Vector2(850, 1650), Vector2(1150, 1570), Vector2(1480, 1660),
		Vector2(1640, 1500), Vector2(1500, 1380), Vector2(1200, 1430), Vector2(950, 1340),
		Vector2(800, 1150), Vector2(900, 900), Vector2(840, 680),
	],
	"road_width": 81.0,
	"boost_pads": [0.42, 0.69],
	"checkpoint_count": 13,
}

const TRACK_7 := {   # Sunday, the hardest: deep top esses, kinked hairpin rows, two tongues along the bottom, a switchback up the left
	"centerline": [
		Vector2(900, 600), Vector2(1250, 500), Vector2(1500, 700), Vector2(1750, 500),
		Vector2(2000, 700), Vector2(2400, 560), Vector2(2800, 600), Vector2(3200, 700),
		Vector2(3350, 1000), Vector2(3200, 1250), Vector2(2950, 1140), Vector2(2700, 1250),
		Vector2(2500, 1060), Vector2(2300, 1180), Vector2(2400, 1420), Vector2(2700, 1500),
		Vector2(2950, 1400), Vector2(3200, 1520), Vector2(3400, 1750), Vector2(3250, 2050),
		Vector2(2900, 2100), Vector2(2700, 1850), Vector2(2500, 1650), Vector2(2300, 1850),
		Vector2(2250, 2150), Vector2(1900, 2200), Vector2(1600, 2050), Vector2(1650, 1700),
		Vector2(1500, 1450), Vector2(1300, 1600), Vector2(1250, 1950), Vector2(1000, 2150),
		Vector2(750, 1950), Vector2(760, 1700), Vector2(1050, 1500), Vector2(1120, 1250),
		Vector2(850, 1150), Vector2(760, 900),
	],
	"road_width": 78.0,
	"boost_pads": [0.49, 0.965],
	"checkpoint_count": 14,
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
	"name": "Multiplayer", "track": TRACK_MP, "max_speed": 416.0, "accel_force": 128.0, "laps": 3,
}

## Per-level: which track, car speed, and medal targets for ONE lap (the
## ranked race, seconds). Targets come from a simple bot's lap (gold ~ +10%,
## silver ~ +40%, bronze ~ +80%): retune after real laps. Last set 2026-11-23
## after the steering fix (turns no longer add speed, less lock at cruise): the
## bot lapped in 30.6 / 30.6 / 32.5 / 39.0 / 42.1 / 43.5 / 46.9 s and hit no
## walls in all seven (before it: 27.9 ... 41.9 s, 1 wall).
##
## `id` is the level's PERMANENT identity: saved records and the online
## leaderboard are keyed by it, so levels can be reordered or dropped without
## times landing on the wrong track. Never renumber or reuse one; give a new
## track the next unused number. (0-9 belonged to retired tracks: 1, 2, 3, 8 and
## 9 were the five 3-lap circuits before they grew by half on 2026-11-20; 10-16
## were these seven before their roads widened by 30%, the cars slowed by 20%
## and the boost pads went in on 2026-11-22.)
##
## Level n is the Daily Circuit on weekday n (Monday = Level 1); the Reddit
## server's LEVEL_IDS lists the same ids in the same order.
const LEVELS := [
	{"id": 17, "name": "Level 1", "track": TRACK_1, "max_speed": 496.0, "accel_force": 153.6, "gold": 33.5, "silver": 43.0, "bronze": 55.0},
	{"id": 18, "name": "Level 2", "track": TRACK_2, "max_speed": 480.0, "accel_force": 147.2, "gold": 33.5, "silver": 43.0, "bronze": 55.0},
	{"id": 19, "name": "Level 3", "track": TRACK_3, "max_speed": 532.0, "accel_force": 163.2, "gold": 36.0, "silver": 45.5, "bronze": 58.5},
	{"id": 20, "name": "Level 4", "track": TRACK_4, "max_speed": 560.0, "accel_force": 171.2, "gold": 43.0, "silver": 54.5, "bronze": 70.0},
	{"id": 21, "name": "Level 5", "track": TRACK_5, "max_speed": 580.0, "accel_force": 177.6, "gold": 46.5, "silver": 59.0, "bronze": 76.0},
	{"id": 22, "name": "Level 6", "track": TRACK_6, "max_speed": 596.0, "accel_force": 182.4, "gold": 48.0, "silver": 61.0, "bronze": 78.5},
	{"id": 23, "name": "Level 7", "track": TRACK_7, "max_speed": 612.0, "accel_force": 187.2, "gold": 51.5, "silver": 65.5, "bronze": 84.5},
]

var current_level: int = 0
var casual: bool = false   ## The mode of the race being picked or run (see the header).
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
## the selected single-player level, with the lap count of the mode (one lap
## ranked, three casual). (game.gd reads this in _ready.)
func active_race() -> Dictionary:
	if Net.is_multiplayer:
		return MP_RACE
	var race := get_level(current_level).duplicate()
	race["laps"] = laps()
	return race


## Laps in a race of the current mode.
func laps() -> int:
	return CASUAL_LAPS if casual else RANKED_LAPS


## The weekday whose Daily Circuit the level in slot `idx` is ("MONDAY"...).
func weekday_of(idx: int) -> String:
	return WEEKDAYS[clampi(idx, 0, WEEKDAYS.size() - 1)]


## The level's permanent id (see LEVELS): the key for saves and the leaderboard.
func level_id(idx: int) -> int:
	return int(get_level(idx)["id"])


## Ranked: Level 1 is always open; each later level opens once the one before
## it has been finished. Derived from the saved records, so it survives
## reordering. Inside a Reddit post the day's featured circuit is always open
## too, so everyone can play the daily challenge. Casual: every map is open.
func is_unlocked(idx: int) -> bool:
	return casual or idx <= 0 or best_time(idx - 1) > 0.0 or Reddit.daily_level_id == level_id(idx)


# --- Progress / save -------------------------------------------------------

func _default_progress() -> Dictionary:
	return {
		"levels": {},
		"settings": {"volume": 0.8, "muted": false, "name": "Player", "controls_hidden": false},
		"seen_instructions": false,
	}


## The game's earlier names. Godot names the user:// folder after the project, so
## after a rename the save is read from the old folder until the next save
## writes it under the new one. (Desktop; the web build's user:// does not depend
## on the name, and Android's went with the old app id.)
const OLD_NAMES := ["Four Wheel Steer"]


func _save_to_load() -> String:
	if FileAccess.file_exists(SAVE_PATH):
		return SAVE_PATH
	var folder := OS.get_user_data_dir().get_base_dir()
	for old: String in OLD_NAMES:
		var path := folder.path_join(old).path_join("save.json")
		if FileAccess.file_exists(path):
			return path
	return ""


func load_progress() -> void:
	progress = _default_progress()
	var path := _save_to_load()
	if path.is_empty():
		return
	var f := FileAccess.open(path, FileAccess.READ)
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
		progress["settings"]["controls_hidden"] = bool(data["settings"].get("controls_hidden", false))
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


## Ranked inside a Reddit post is one circuit a day, so there is no next level
## there; casual always offers the next map.
func has_next_level(idx: int) -> bool:
	return idx + 1 < LEVELS.size() and (casual or not Reddit.is_available())


## Casual: the best 3-lap time on the map in slot `idx` (0 = none yet).
func casual_best(idx: int) -> float:
	return float(_level_record(idx).get("casual_best", 0.0))


## Casual: the best single lap driven in casual on that map (0 = none yet).
func casual_best_lap(idx: int) -> float:
	return float(_level_record(idx).get("casual_lap", 0.0))


## Records a finished CASUAL run: keeps the best 3-lap time and best lap, apart
## from the ranked records (no medal, no unlock). Returns true if the time is a
## new best.
func record_casual(idx: int, total: float, lap: float) -> bool:
	var levels: Dictionary = progress["levels"]
	var key := str(level_id(idx))
	var rec: Dictionary = levels.get(key, {})
	var prev := float(rec.get("casual_best", 0.0))
	var improved := prev <= 0.0 or total < prev
	if improved:
		rec["casual_best"] = total
	var prev_lap := float(rec.get("casual_lap", 0.0))
	if lap > 0.0 and (prev_lap <= 0.0 or lap < prev_lap):
		rec["casual_lap"] = lap
	levels[key] = rec
	save_progress()
	return improved


## Slot of today's featured circuit inside a Reddit post, or -1 (not on Reddit,
## or the day's data has not arrived yet).
func daily_index() -> int:
	for i in LEVELS.size():
		if level_id(i) == Reddit.daily_level_id:
			return i
	return -1


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


## Whether the player hid the race HUD's controls legend (H toggles it).
func is_controls_hidden() -> bool:
	return bool(progress["settings"].get("controls_hidden", false))


func set_controls_hidden(hidden: bool) -> void:
	progress["settings"]["controls_hidden"] = hidden
	save_progress()


func get_player_name() -> String:
	return String(progress["settings"].get("name", "Player"))


func set_player_name(n: String) -> void:
	var clean := n.strip_edges().substr(0, 24)
	progress["settings"]["name"] = clean if clean != "" else "Player"
	save_progress()


# --- Navigation ------------------------------------------------------------

# Every screen change goes behind the Transition curtain; `animate = false`
# switches at once (the main menu's redirects on the way in).

## Starts a race on the level in slot `idx`, in the current mode.
func start_level(idx: int) -> void:
	current_level = idx
	Transition.change_scene(SCENE_RACE)

func goto_menu() -> void:
	get_tree().paused = false
	Transition.change_scene(SCENE_MENU)

## The level screen for ranked races (on Reddit: Today's Circuit).
func goto_level_select(animate := true) -> void:
	casual = false
	Transition.change_scene(SCENE_LEVEL_SELECT, animate)

## The level screen for casual races: every map, three laps, no wall-hit limit.
func goto_casual() -> void:
	casual = true
	Transition.change_scene(SCENE_LEVEL_SELECT)

func goto_lobby() -> void:
	Transition.change_scene(SCENE_LOBBY)

func goto_leaderboard(animate := true) -> void:
	Transition.change_scene(SCENE_LEADERBOARD, animate)

func goto_instructions(animate := true) -> void:
	Transition.change_scene(SCENE_INSTRUCTIONS, animate)

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
