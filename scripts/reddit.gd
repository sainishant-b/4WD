extends Node
## Autoload "Reddit": the game's link to the Devvit server when it runs inside a
## Reddit post (the web export loaded by reddit/public/game.html).
##
## That page exposes a small object, `window.FWS` (see reddit/src/client/game.ts):
## the text of GET /api/init, the screen to open first, `request()` to call
## the server, and `avatar()` to load a player's avatar picture. This autoload reads it through JavaScriptBridge.get_interface;
## never JavaScriptBridge.eval, which Reddit's content policy blocks.
##
## Everywhere else (desktop, Android, a plain web export) `available` is false
## and nothing here does anything, so callers just check `is_available()`.

## The day's data arrived (username, today's level, ...).
signal init_loaded

var available: bool = false     ## Running inside the Reddit wrapper (or its local stand-in).
var username: String = ""       ## The player's Reddit name; "" when logged out.
var avatar_url: String = ""     ## The player's snoovatar image URL; "" when none.
var day: int = 0                ## Daily Circuit number of the post.
var daily_level_id: int = -1    ## Permanent id of the level that is today's circuit.
var is_today: bool = true       ## False on an older day's post (still playable, no streak).
var flair_on: bool = false      ## The player has opted in to showing their streak as user flair.
var start_screen: String = ""   ## "leaderboard" when the post asked to open there.
var start_handled: bool = false ## Set once the main menu has sent the player to their first screen.

## Test hook: when set, `request()` hands (method, path, body, done) to this
## instead of the page, and `is_available()` reads true.
var transport: Callable = Callable()
## Test hook: when set, `avatar()` asks this (url, done) for the base64 PNG
## instead of the page.
var avatar_transport: Callable = Callable()

const INIT_RETRIES := 40        # the page fetches /api/init while the engine boots
const INIT_RETRY_SECONDS := 0.25

var _bridge: JavaScriptObject = null
var _pending: Dictionary = {}   # request id -> JS callback, kept alive until it fires
var _next_id: int = 0
var _avatars: Dictionary = {}   # url -> Texture2D, or null when it could not be shown
var _avatar_waiting: Dictionary = {}   # url -> Array[Callable] while it loads
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
	var picture: Variant = data.get("avatar")
	avatar_url = picture if picture is String else ""
	day = int(data.get("day", 0))
	daily_level_id = int(data.get("levelId", -1))
	is_today = bool(data.get("isToday", true))
	flair_on = bool(data.get("flairOn", false))
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


## A player's avatar picture, from a URL the server sent with the board rows.
## The page loads and crops it (reddit/src/client/avatar-image.ts); `done`
## receives a Texture2D, or null when it cannot be shown. Each URL is loaded
## once. `done` is skipped if its object has gone (a row freed meanwhile).
func avatar(url: String, done: Callable) -> void:
	if _avatars.has(url):
		done.call(_avatars[url])
		return
	if _avatar_waiting.has(url):
		_avatar_waiting[url].append(done)
		return
	if not avatar_transport.is_valid() and _bridge == null:
		done.call(null)
		return
	_avatar_waiting[url] = [done]
	if avatar_transport.is_valid():
		avatar_transport.call(url, func(png: String) -> void: _avatar_arrived(url, png))
		return
	var id := _next_id
	_next_id += 1
	var callback := JavaScriptBridge.create_callback(func(args: Array) -> void:
		var png: String = args[0] if args.size() > 0 and args[0] is String else ""
		_forget.call_deferred(id)
		_avatar_arrived(url, png)
	)
	_pending[id] = callback
	_bridge.avatar(url, callback)


func _avatar_arrived(url: String, png: String) -> void:
	var texture: Texture2D = null
	if png != "":
		var image := Image.new()
		if image.load_png_from_buffer(Marshalls.base64_to_raw(png)) == OK:
			image.generate_mipmaps()
			texture = ImageTexture.create_from_image(image)
	_avatars[url] = texture
	for done: Callable in _avatar_waiting.get(url, []):
		if done.is_valid():
			done.call(texture)
	_avatar_waiting.erase(url)
