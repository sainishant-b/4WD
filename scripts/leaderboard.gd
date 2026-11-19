extends Node
## Autoload "Leaderboard": the online time leaderboard. Submits a time when a
## race finishes and fetches ranked times for the Leaderboard screen. It talks
## to whichever backend is present:
##
##  - **Reddit** (the game inside a Reddit post, via the `Reddit` autoload): the
##    Devvit server keeps a board per level, an OVERALL board, which adds up
##    each player's best time on every level and ranks the lowest total first,
##    and a DAY board for the day's circuit. Players are their Reddit usernames.
##    A finished race's answer (place today, streak, countdown) goes out on
##    `run_recorded` for the results card.
##  - **Appwrite** (everywhere else, if its IDs below are filled in): a tiny REST
##    client, one board per level, names typed on the Leaderboard screen.
##
## With neither, `configured()` is false and the game simply skips the network.
## Boards are keyed by a level's PERMANENT id (`Game.level_id()`), not its slot.
##
## APPWRITE SETUP (one-time, in the Appwrite console): create a project and a
## `scores` collection with attributes name:string(24), level:integer,
## time_ms:integer, and grant role "Any" the Create + Read permissions. Then
## paste your four IDs below.

signal scores_loaded(level: int, rows: Array)
signal request_failed(message: String)
signal score_submitted()
## Reddit only: the server's answer to a finished race, for the results card.
## `info` is {} when no answer came, else { accepted, improved, rank, players,
## streak, best_streak, next_ms, at_msec }: `rank` of `players` on the day's
## board (0 = not on it), the player's streak in days, and `next_ms` until the
## next circuit as of `at_msec` (Time.get_ticks_msec() when the answer arrived).
signal run_recorded(info: Dictionary)

## Board id for "all maps combined". Only the Reddit backend has it.
const OVERALL := -1
## Board id for the day's circuit (fastest today). Only the Reddit backend has it.
const DAY := -2

## Set before opening the Leaderboard screen to start it on the DAY board
## (the results card's Leaderboard button). The screen clears it.
var open_on_day: bool = false

# --- Appwrite config — FILL THESE IN ---------------------------------------
const ENDPOINT := ""        # e.g. "https://nyc.cloud.appwrite.io/v1"  (no trailing slash)
const PROJECT_ID := ""      # Appwrite project ID
const DATABASE_ID := ""     # Appwrite database ID
const COLLECTION_ID := ""   # the "scores" collection ID

# We over-fetch then sort/trim client-side, so the board is correct even if the
# server-side ordering query is ignored by a given Appwrite version.
const FETCH_LIMIT := 100

## About the board last loaded: { players, me_rank, me_time_ms, maps_done,
## maps_total }. `me_rank` is 0 when the player is not on it. Reddit only.
var last_info: Dictionary = {}

var _http_fetch: HTTPRequest
var _http_submit: HTTPRequest
var _last_level: int = 0


func _ready() -> void:
	_http_fetch = HTTPRequest.new()
	add_child(_http_fetch)
	_http_fetch.request_completed.connect(_on_fetch_done)
	_http_submit = HTTPRequest.new()
	add_child(_http_submit)
	_http_submit.request_completed.connect(_on_submit_done)


func configured() -> bool:
	return Reddit.is_available() or _appwrite_configured()


## True when there is an OVERALL board to show.
func has_overall() -> bool:
	return Reddit.is_available()


func _appwrite_configured() -> bool:
	return ENDPOINT != "" and PROJECT_ID != "" and DATABASE_ID != "" and COLLECTION_ID != ""


func _headers() -> PackedStringArray:
	return PackedStringArray([
		"Content-Type: application/json",
		"X-Appwrite-Project: " + PROJECT_ID,
	])


func _documents_url() -> String:
	return "%s/databases/%s/collections/%s/documents" % [ENDPOINT, DATABASE_ID, COLLECTION_ID]


# --- Submit ----------------------------------------------------------------

## Reports a finished race. `level` is the level's permanent id. On Reddit the
## name is ignored: the server uses the logged-in account.
func submit_score(player_name: String, level: int, time_ms: int) -> void:
	if Reddit.is_available():
		Reddit.request("POST", "/api/run", {"levelId": level, "timeMs": time_ms}, _on_reddit_run)
		return
	if not _appwrite_configured():
		return
	var nm := player_name.strip_edges()
	if nm == "":
		nm = "Player"
	var body := {
		"documentId": "unique()",
		"data": {"name": nm.substr(0, 24), "level": level, "time_ms": time_ms},
	}
	var err := _http_submit.request(_documents_url(), _headers(), HTTPClient.METHOD_POST, JSON.stringify(body))
	if err != OK:
		request_failed.emit("submit request error %d" % err)


func _on_reddit_run(result: Variant) -> void:
	if not (result is Dictionary):
		request_failed.emit("no answer from Reddit")
		run_recorded.emit({})
		return
	var me: Variant = result.get("me")
	var streak: Variant = result.get("streak")
	var accepted := bool(result.get("accepted", false))
	run_recorded.emit({
		"accepted": accepted,
		"improved": bool(result.get("improved", false)),
		"rank": int(me.get("rank", 0)) if me is Dictionary else 0,
		"players": int(result.get("players", 0)),
		"streak": int(streak.get("current", 0)) if streak is Dictionary else 0,
		"best_streak": int(streak.get("best", 0)) if streak is Dictionary else 0,
		"next_ms": int(result.get("nextCircuitInMs", 0)),
		"at_msec": Time.get_ticks_msec(),
	})
	if accepted:
		score_submitted.emit()
	else:
		request_failed.emit("time not recorded: log in to Reddit to rank")


func _on_submit_done(_result: int, code: int, _h: PackedStringArray, _body: PackedByteArray) -> void:
	if code == 200 or code == 201:
		score_submitted.emit()
	else:
		request_failed.emit("submit failed (HTTP %d)" % code)


# --- Fetch -----------------------------------------------------------------

## Loads the ranked top times for `level` (a permanent level id, OVERALL or
## DAY); emits scores_loaded(level, rows) where each row is { name, level,
## time_ms }, fastest first and trimmed to `limit`. For OVERALL, `time_ms` is
## the total.
func fetch_top(level: int, limit: int = 25) -> void:
	_last_level = level
	last_info = {}
	if Reddit.is_available():
		var path := "/api/leaderboard?board=overall&limit=%d" % limit
		if level == DAY:
			path = "/api/leaderboard?board=day&limit=%d" % limit
		elif level != OVERALL:
			path = "/api/leaderboard?board=level&level=%d&limit=%d" % [level, limit]
		Reddit.request("GET", path, {}, func(result: Variant) -> void: _on_reddit_board(level, result))
		return
	if not _appwrite_configured() or level < 0:
		scores_loaded.emit(level, [])
		return
	_http_fetch.cancel_request()  # drop any in-flight request (e.g. fast level toggling)
	# Appwrite REST queries are JSON-encoded objects passed as queries[] params.
	var queries := [
		{"method": "equal", "attribute": "level", "values": [level]},
		{"method": "orderAsc", "attribute": "time_ms"},
		{"method": "limit", "values": [FETCH_LIMIT]},
	]
	var qs := ""
	for q in queries:
		qs += ("&" if qs != "" else "?") + "queries[]=" + JSON.stringify(q).uri_encode()
	var err := _http_fetch.request(_documents_url() + qs, _headers(), HTTPClient.METHOD_GET)
	if err != OK:
		request_failed.emit("fetch request error %d" % err)


func _on_reddit_board(level: int, result: Variant) -> void:
	if level != _last_level:
		return   # the player has already moved to another board
	if not (result is Dictionary):
		request_failed.emit("no answer from Reddit")
		return
	var rows: Array = []
	for entry in result.get("top", []):
		rows.append({
			"name": String(entry.get("name", "?")),
			"level": level,
			"time_ms": int(entry.get("timeMs", 0)),
		})
	var me: Variant = result.get("me")
	last_info = {
		"players": int(result.get("players", rows.size())),
		"me_rank": int(me.get("rank", 0)) if me is Dictionary else 0,
		"me_time_ms": int(me.get("timeMs", 0)) if me is Dictionary else 0,
		"maps_done": int(result.get("mapsDone", 0)),
		"maps_total": int(result.get("mapsTotal", 0)),
	}
	scores_loaded.emit(level, rows)


func _on_fetch_done(_result: int, code: int, _h: PackedStringArray, body: PackedByteArray) -> void:
	if code != 200:
		request_failed.emit("fetch failed (HTTP %d)" % code)
		return
	var parsed: Variant = JSON.parse_string(body.get_string_from_utf8())
	if typeof(parsed) != TYPE_DICTIONARY or not parsed.has("documents"):
		request_failed.emit("unexpected leaderboard response")
		return
	var rows: Array = []
	for doc in parsed["documents"]:
		# Defensive: filter by level client-side too, in case the query was ignored.
		if int(doc.get("level", -1)) != _last_level:
			continue
		rows.append({
			"name": String(doc.get("name", "Player")),
			"level": int(doc.get("level", 0)),
			"time_ms": int(doc.get("time_ms", 0)),
		})
	rows.sort_custom(func(a, b): return a["time_ms"] < b["time_ms"])
	if rows.size() > 25:
		rows = rows.slice(0, 25)
	scores_loaded.emit(_last_level, rows)
