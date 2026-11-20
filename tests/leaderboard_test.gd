extends SceneTree
# Headless check of the Reddit leaderboard path, with a stand-in for the Devvit
# server: what the game asks for, how it reads the answers, and what the
# Leaderboard screen then shows. Also the mute setting. Run:
#   godot --headless --path . -s tests/leaderboard_test.gd
#
# The real page bridge (JavaScriptBridge) only exists in a browser, so this
# covers everything up to `Reddit.request()`; reddit/src/server/daily.test.ts
# covers the server's side of the same messages.
# It finishes one race to check the Reddit results card, then puts the save
# file back exactly as it was; it restores the mute setting it flips too.
# This folder is .gdignore'd.

var _failures := 0
var _calls: Array = []      # [method, path, body] of every request the game made
var _logged_in := true
var _flair_refuse := false
var _avatar_asks: Array = []   # every URL the game asked the page to load
const SNOO := "https://i.redd.it/snoovatar/avatars/apex.png"


func _initialize() -> void:
	_run.call_deferred()


func _check(label: String, ok: bool, detail := "") -> void:
	if ok:
		print("  ok    ", label)
	else:
		_failures += 1
		print("  FAIL  ", label, "  ", detail)


func _frames(n: int) -> void:
	for i in n:
		await process_frame


## Answers like reddit/src/server/daily.ts would, from fixed data.
func _server(method: String, path: String, body: Dictionary, done: Callable) -> void:
	_calls.append([method, path, body])
	if method == "POST" and path == "/api/run":
		done.call({
			"accepted": _logged_in, "improved": _logged_in, "countsForDay": true,
			"me": {"rank": 3, "name": "local_driver", "timeMs": 61500} if _logged_in else null,
			"players": 41, "streak": {"current": 4, "best": 6} if _logged_in else {"current": 0, "best": 0},
			"nextCircuitInMs": 5 * 3_600_000 + 30_000,
		})
	elif method == "POST" and path == "/api/flair":
		if _flair_refuse:
			done.call({"on": false, "text": null, "error": "Couldn't change your flair in this subreddit."})
		else:
			done.call({"on": bool(body.get("on", false)), "text": "🔥 4-day streak" if body.get("on", false) else null})
	elif path.begins_with("/api/leaderboard?board=day"):
		done.call({
			"kind": "day", "players": 41, "mapsDone": 3, "mapsTotal": 5,
			"top": [
				{"rank": 1, "name": "apex_hunter", "timeMs": 58020},
				{"rank": 2, "name": "crabwalk", "timeMs": 60110},
				{"rank": 3, "name": "local_driver", "timeMs": 61500},
			],
			"me": {"rank": 3, "name": "local_driver", "timeMs": 61500},
		})
	elif path.begins_with("/api/leaderboard?board=overall"):
		done.call({
			"kind": "overall", "levelId": null, "players": 2, "mapsDone": 3, "mapsTotal": 5,
			"top": [
				{"rank": 1, "name": "apex_hunter", "timeMs": 301000, "avatar": SNOO},
				{"rank": 2, "name": "local_driver", "timeMs": 322500},
			],
			"me": {"rank": 2, "name": "local_driver", "timeMs": 322500},
		})
	elif path.begins_with("/api/leaderboard?board=level"):
		done.call({
			"kind": "level", "players": 1, "mapsDone": 3, "mapsTotal": 5,
			"top": [{"rank": 1, "name": "crabwalk", "timeMs": 61930}], "me": null,
		})
	else:
		done.call(null)


## Answers like the page's FWS.avatar (reddit/src/client/avatar-image.ts): a
## small PNG in base64 for the one picture it can load, "" for anything else.
func _page_avatar(url: String, done: Callable) -> void:
	_avatar_asks.append(url)
	if url != SNOO:
		done.call("")
		return
	var image := Image.create(8, 8, false, Image.FORMAT_RGBA8)
	image.fill(Color.ORANGE_RED)
	done.call(Marshalls.raw_to_base64(image.save_png_to_buffer()))


## The avatar badge (scripts/avatar_badge.gd) in each row of the Leaderboard
## screen, top to bottom. Found by its method: naming the class here would
## compile it before the autoloads it uses exist.
func _row_badges(screen: Node) -> Array:
	var badges: Array = []
	for line in screen._rows_box.get_children():
		for node in line.find_children("*", "Control", true, false):
			if node.has_method("has_picture"):
				badges.append(node)
	return badges


func _run() -> void:
	# Untyped on purpose: autoloads are looked up at run time here.
	var game = root.get_node("/root/Game")
	var reddit = root.get_node("/root/Reddit")
	var board = root.get_node("/root/Leaderboard")

	print("outside Reddit")
	_check("no Reddit link on desktop", not reddit.is_available())
	_check("so there is no overall board", not board.has_overall())

	print("inside a Reddit post")
	reddit.transport = _server
	reddit.avatar_transport = _page_avatar
	reddit.apply_init({"username": "local_driver", "day": 2, "levelId": game.level_id(1)})
	_check("the link reads as available", reddit.is_available() and board.configured() and board.has_overall())
	_check("it knows the player and today's level",
		reddit.username == "local_driver" and reddit.daily_level_id == game.level_id(1))
	var last: int = game.level_count() - 1
	reddit.apply_init({"username": "local_driver", "day": 5, "levelId": game.level_id(last)})
	_check("the day's featured level is playable even while locked", game.is_unlocked(last))
	reddit.apply_init({"username": "local_driver", "day": 2, "levelId": game.level_id(1)})

	var loaded: Array = []
	board.scores_loaded.connect(func(level: int, rows: Array) -> void: loaded.append([level, rows]))
	var failed: Array = []
	board.request_failed.connect(func(message: String) -> void: failed.append(message))

	board.fetch_top(board.OVERALL, 25)
	_check("asks the server for the overall board",
		_calls.size() == 1 and _calls[0][0] == "GET" and _calls[0][1] == "/api/leaderboard?board=overall&limit=25",
		str(_calls))
	_check("lowest total is first", loaded.size() == 1 and loaded[0][0] == board.OVERALL
		and loaded[0][1].size() == 2 and loaded[0][1][0]["name"] == "apex_hunter"
		and loaded[0][1][0]["time_ms"] == 301000, str(loaded))
	_check("rows carry the avatar URL, or \"\" for none",
		loaded[0][1][0]["avatar"] == SNOO and loaded[0][1][1]["avatar"] == "", str(loaded))
	_check("it reports the player's own place and maps done",
		board.last_info.get("me_rank") == 2 and board.last_info.get("maps_done") == 3
		and board.last_info.get("maps_total") == 5, str(board.last_info))

	board.fetch_top(game.level_id(0), 25)
	_check("a level board is asked for by the level's permanent id",
		_calls[-1][1] == "/api/leaderboard?board=level&level=%d&limit=25" % game.level_id(0), str(_calls[-1]))

	var sent: Array = []   # an Array, because a lambda cannot change an outer int
	board.score_submitted.connect(func() -> void: sent.append(true))
	board.submit_score("ignored on reddit", game.level_id(3), 78123)
	_check("a finished race is posted with the level id and the time",
		_calls[-1][0] == "POST" and _calls[-1][1] == "/api/run"
		and _calls[-1][2] == {"levelId": game.level_id(3), "timeMs": 78123}, str(_calls[-1]))
	_check("an accepted time is announced", sent.size() == 1 and failed.is_empty())
	_logged_in = false
	board.submit_score("", game.level_id(3), 78123)
	_check("a refused time (logged out) reports why", sent.size() == 1 and failed.size() == 1, str(failed))
	_logged_in = true

	print("leaderboard screen")
	root.size = Vector2i(1280, 720)
	change_scene_to_file("res://scenes/Leaderboard.tscn")
	await _frames(4)
	var screen = current_scene
	_check("OVERALL is the first board, then TODAY, then one per level",
		screen._boards.size() == game.level_count() + 2 and screen._board_title(0) == "OVERALL"
		and screen._board_title(1) == "TODAY", str(screen._boards))
	_check("it opens on OVERALL with both rows", screen._board == 0 and screen._rows_box.get_child_count() == 2,
		"rows=%d" % screen._rows_box.get_child_count())
	_check("the summary explains the ranking and the player's place",
		"added up" in screen._status.text and "#2" in screen._status.text, screen._status.text)
	var badges := _row_badges(screen)
	_check("every row has an avatar badge", badges.size() == 2, "badges=%d" % badges.size())
	_check("a player with a snoovatar shows the picture; one without shows their initial",
		badges.size() == 2 and badges[0].has_picture() and not badges[1].has_picture())
	_check("the page was asked for that one picture only", _avatar_asks == [SNOO], str(_avatar_asks))
	screen._select(0)
	await _frames(2)
	_check("a picture already loaded is not asked for again",
		_avatar_asks == [SNOO] and _row_badges(screen)[0].has_picture(), str(_avatar_asks))
	var badge_script: GDScript = load("res://scripts/avatar_badge.gd")
	_check("the badge colour is the same for the same name",
		badge_script.color_for("crabwalk") == badge_script.color_for("crabwalk"))
	screen._select(1)
	await _frames(2)
	_check("TODAY asks for the day board and shows its rows",
		_calls[-1][1].begins_with("/api/leaderboard?board=day") and screen._rows_box.get_child_count() == 3
		and "#3 of 41" in screen._status.text, screen._status.text)
	screen._select(2)
	await _frames(2)
	_check("picking Level 1 shows that level's board", screen._rows_box.get_child_count() == 1
		and "Best time on this map" in screen._status.text, screen._status.text)
	root.size = Vector2i(390, 760)
	await _frames(4)
	_check("the phone layout keeps the same boards", current_scene._boards.size() == game.level_count() + 2)

	print("results card on Reddit")
	const SAVE_PATH := "user://save.json"
	var had_save := FileAccess.file_exists(SAVE_PATH)
	var save_before := FileAccess.get_file_as_string(SAVE_PATH) if had_save else ""
	root.size = Vector2i(1280, 720)
	game.current_level = 1
	change_scene_to_file("res://scenes/Main.tscn")
	await _frames(4)
	var race = current_scene
	var hud = race.get_node("HUD")
	race._elapsed = 61.5
	race._best_lap_run = 20.1
	race._finish()   # a real finish: records the run, posts it, fills the card
	await _frames(2)
	var chips: Array = hud._daily_chips.get_children().map(func(c: Label) -> String: return c.text)
	_check("the card shows the place on today's board, on the gold plate", hud._rank_plate.visible
		and not hud._daily_rank.visible and hud._rank_num.text == "#3"
		and hud._rank_caption.text == "TODAY'S RANK" and hud._rank_of.text == "of 41 racers",
		"%s / %s / %s" % [hud._rank_num.text, hud._rank_caption.text, hud._rank_of.text])
	_check("... a new-best chip and the streak", chips == ["NEW BEST", "4-DAY STREAK"], str(chips))
	_check("... and a countdown to the next circuit", hud._daily_next.text.begins_with("NEXT CIRCUIT IN 5:00:"),
		hud._daily_next.text)
	_check("its gold button is Leaderboard, not Next",
		hud._results_board.visible and not hud._results_next.visible)
	_check("streak flair is offered, and off until chosen", hud._flair_btn.visible
		and hud._flair_btn.text == "SHOW MY STREAK AS FLAIR" and not reddit.flair_on, hud._flair_btn.text)
	hud._flair_btn.pressed.emit()
	await _frames(2)
	_check("turning it on asks the server and says it is on", _calls[-1][1] == "/api/flair"
		and _calls[-1][2] == {"on": true} and reddit.flair_on and hud._flair_btn.text.begins_with("STREAK FLAIR ON"),
		hud._flair_btn.text)
	hud._flair_btn.pressed.emit()
	await _frames(2)
	_check("pressing again turns it off", _calls[-1][2] == {"on": false} and not reddit.flair_on
		and hud._flair_btn.text == "SHOW MY STREAK AS FLAIR", hud._flair_btn.text)
	_flair_refuse = true
	hud._flair_btn.pressed.emit()
	await _frames(2)
	_check("if Reddit refuses, it stays off and says so", not reddit.flair_on
		and hud._flair_btn.text.begins_with("FLAIR UNAVAILABLE"), hud._flair_btn.text)
	_flair_refuse = false
	hud.show_daily_result({"accepted": false, "next_ms": 1000, "at_msec": Time.get_ticks_msec()})
	await _frames(2)
	_check("logged out, it asks the player to log in", hud._daily_rank.text == "LOG IN TO RANK"
		and hud._daily_rank.visible and not hud._rank_plate.visible
		and hud._daily_chips.get_child_count() == 0 and not hud._flair_btn.visible, hud._daily_rank.text)
	hud.show_daily_result({})
	_check("no answer from Reddit is said plainly", hud._daily_rank.text == "COULDN'T REACH REDDIT")
	hud.ui_action.emit("leaderboard")
	await _frames(4)
	_check("Leaderboard opens on TODAY", current_scene.has_method("_board_title")
		and current_scene._board_title(current_scene._board) == "TODAY")
	# Put the player's save back exactly as it was.
	if had_save:
		var f := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
		f.store_string(save_before)
		f.close()
	else:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(SAVE_PATH))
	game.load_progress()
	_check("the save file was put back", (FileAccess.get_file_as_string(SAVE_PATH) if had_save else "") == save_before)

	print("level select")
	var diagram_script := load("res://scripts/track_diagram.gd")
	for size in [Vector2i(1280, 720), Vector2i(390, 760)]:
		root.size = size
		change_scene_to_file("res://scenes/LevelSelect.tscn")
		await _frames(4)
		var maps: Array = current_scene.find_children("*", "Control", true, false).filter(
			func(n: Node) -> bool: return n.get_script() == diagram_script)
		var buttons: Array = current_scene.find_children("*", "Button", true, false)
		var texts: Array = buttons.map(func(b: Button) -> String: return b.text)
		_check("on Reddit (%dx%d) it shows only today's circuit, as a diagram" % [size.x, size.y],
			maps.size() == 1 and maps[0].track == game.get_level(1)["track"], "maps=%d" % maps.size())
		_check("... with DRIVE, How to Play and Back, and no other level", texts.size() == 3
			and "DRIVE" in texts and "?  HOW TO PLAY" in texts and "Back" in texts, str(texts))
	_check("a finished daily circuit offers no next level", not game.has_next_level(1))

	print("opening a Reddit post")
	reddit.start_handled = false
	reddit.start_screen = ""
	change_scene_to_file("res://scenes/MainMenu.tscn")
	await _frames(4)
	_check("the game opens straight on Today's Circuit", current_scene.scene_file_path == "res://scenes/LevelSelect.tscn",
		current_scene.scene_file_path)
	change_scene_to_file("res://scenes/MainMenu.tscn")
	await _frames(4)
	_check("Back from there shows the menu (no bounce, no forced How to Play)",
		current_scene.scene_file_path == "res://scenes/MainMenu.tscn", current_scene.scene_file_path)
	reddit.start_handled = false
	reddit.start_screen = "leaderboard"
	change_scene_to_file("res://scenes/MainMenu.tscn")
	await _frames(4)
	_check("the post's Leaderboard button opens the boards", current_scene.scene_file_path == "res://scenes/Leaderboard.tscn",
		current_scene.scene_file_path)
	reddit.start_screen = ""

	print("mute")
	var was_muted: bool = game.is_muted()
	var bus_before := AudioServer.is_bus_mute(0)
	game.set_muted(true)
	_check("muting silences the master bus", AudioServer.is_bus_mute(0) and game.is_muted())
	game.set_muted(false)
	_check("unmuting restores it", not AudioServer.is_bus_mute(0) and not game.is_muted())
	_check("the mute button exists on top of every screen",
		root.get_node_or_null("/root/MuteButton") != null and root.get_node("/root/MuteButton").layer > 1)
	game.set_muted(was_muted)
	_check("the setting was put back", game.is_muted() == was_muted and AudioServer.is_bus_mute(0) == bus_before)

	reddit.transport = Callable()
	reddit.avatar_transport = Callable()
	reddit.daily_level_id = -1
	root.size = Vector2i(1280, 720)
	change_scene_to_file("res://scenes/LevelSelect.tscn")
	await _frames(4)
	_check("off Reddit, level select builds a card per level",
		current_scene.find_children("*", "Button", true, false).size() >= game.level_count() + 1)
	_check("... and a finished level offers the next one", game.has_next_level(0))
	print("")
	print("RESULT: ", "ALL PASSED" if _failures == 0 else "%d FAILED" % _failures)
	quit(1 if _failures > 0 else 0)
