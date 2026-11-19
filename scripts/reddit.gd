extends Node
## Autoload "Reddit": the game's link to the Devvit server when it runs inside a
## Reddit post (the web export loaded by reddit/public/game.html).
##
## That page exposes a small object, `window.FWS` (see reddit/src/client/game.ts):
## the text of GET /api/init, the screen to open first, and `request()` to call
## the server. This autoload reads it through JavaScriptBridge.get_interface;
## never JavaScriptBridge.eval, which Reddit's content policy blocks.
##
## Everywhere else (desktop, Android, a plain web export) `available` is false
## and nothing here does anything, so callers just check `is_available()`.

## The day's data arrived (username, today's level, ...).
signal init_loaded

var available: bool = false     ## Running inside the Reddit wrapper (or its local stand-in).
var username: String = ""       ## The player's Reddit name; "" when logged out.
var day: int = 0                ## Daily Circuit number of the post.
var daily_level_id: int = -1    ## Permanent id of the level that is today's circuit.
var is_today: bool = true       ## False on an older day's post (still playable, no streak).
var start_screen: String = ""   ## "leaderboard" when the post asked to open there; read once.

## Test hook: when set, `request()` hands (method, path, body, done) to this
## instead of the page, and `is_available()` reads true.
var transport: Callable = Callable()

const INIT_RETRIES := 40        # the page fetches /api/init while the engine boots
const INIT_RETRY_SECONDS := 0.25

var _bridge: JavaScriptObject = null
var _pending: Dictionary = {}   # request id -> JS callback, kept alive until it fires
var _next_id: int = 0
var _init_tries: int = 0


func _ready() -> void:
	if not OS.has_feature("web"):
		return
	_bridge = JavaScriptBridge.get_interface("FWS")
	if _bridge == null:
		return   # a plain web export, not inside the Reddit wrapper
	available = true
	var screen: Variant = _bridge.screen
	start_screen = screen if screen is String else ""
	_read_init()


func is_available() -> bool:
	return available or transport.is_valid()


## The page fills in `FWS.init` when its request returns, which may be after the
## game has started; poll for it briefly.
func _read_init() -> void:
	var text: Variant = _bridge.init
	if not (text is String) or text == "":
		_init_tries += 1
		if _init_tries < INIT_RETRIES:
			get_tree().create_timer(INIT_RETRY_SECONDS).timeout.connect(_read_init)
		return
	apply_init(JSON.parse_string(text))


## Takes the parsed body of GET /api/init.
func apply_init(data: Variant) -> void:
	if not (data is Dictionary):
		return
	var name: Variant = data.get("username")
	username = name if name is String else ""
	day = int(data.get("day", 0))
	daily_level_id = int(data.get("levelId", -1))
	is_today = bool(data.get("isToday", true))
	init_loaded.emit()


## Calls the Devvit server. `done` receives the parsed JSON body (a Dictionary),
## or null if the call failed. `body` is sent as JSON; pass {} for a GET.
func request(method: String, path: String, body: Dictionary, done: Callable) -> void:
	if transport.is_valid():
		transport.call(method, path, body, done)
		return
	if _bridge == null:
		done.call(null)
		return
	var id := _next_id
	_next_id += 1
	var callback := JavaScriptBridge.create_callback(func(args: Array) -> void:
		var text: String = args[0] if args.size() > 0 and args[0] is String else ""
		_forget.call_deferred(id)   # not while the callback itself is running
		done.call(JSON.parse_string(text) if text != "" else null)
	)
	_pending[id] = callback
	_bridge.request(method, path, "" if body.is_empty() else JSON.stringify(body), callback)


func _forget(id: int) -> void:
	_pending.erase(id)
