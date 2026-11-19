extends SceneTree
# Headless check of the Reddit leaderboard path, with a stand-in for the Devvit
# server: what the game asks for, how it reads the answers, and what the
# Leaderboard screen then shows. Also the mute setting. Run:
#   godot --headless --path . -s tests/leaderboard_test.gd
#
# The real page bridge (JavaScriptBridge) only exists in a browser, so this
# covers everything up to `Reddit.request()`; reddit/src/server/daily.test.ts
# covers the server's side of the same messages.
# It restores the mute setting it flips. This folder is .gdignore'd.

var _failures := 0
var _calls: Array = []      # [method, path, body] of every request the game made
var _logged_in := true


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
		done.call({"accepted": _logged_in, "improved": true})
	elif path.begins_with("/api/leaderboard?board=overall"):
		done.call({
			"kind": "overall", "levelId": null, "players": 2, "mapsDone": 3, "mapsTotal": 5,
			"top": [
				{"rank": 1, "name": "apex_hunter", "timeMs": 301000},
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
	_check("OVERALL is the first board, then one per level",
		screen._boards.size() == game.level_count() + 1 and screen._boards[0] == -1, str(screen._boards))
	_check("it opens on OVERALL with both rows", screen._board == 0 and screen._rows_box.get_child_count() == 2,
		"rows=%d" % screen._rows_box.get_child_count())
	_check("the summary explains the ranking and the player's place",
		"added up" in screen._status.text and "#2" in screen._status.text, screen._status.text)
	screen._select(1)
	await _frames(2)
	_check("picking Level 1 shows that level's board", screen._rows_box.get_child_count() == 1
		and "Best time on this map" in screen._status.text, screen._status.text)
	root.size = Vector2i(390, 760)
	await _frames(4)
	_check("the phone layout keeps the same boards", current_scene._boards.size() == game.level_count() + 1)

	print("level select")
	root.size = Vector2i(1280, 720)
	change_scene_to_file("res://scenes/LevelSelect.tscn")
	await _frames(4)
	_check("level select builds a card per level", current_scene.find_children("*", "Button", true, false).size() >= game.level_count())

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
	print("")
	print("RESULT: ", "ALL PASSED" if _failures == 0 else "%d FAILED" % _failures)
	quit(1 if _failures > 0 else 0)
