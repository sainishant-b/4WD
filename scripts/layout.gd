extends Node
## Autoload `Layout`: fits the UI to the window's shape and the input device.
##
## The project stretches one logical resolution over the window (canvas_items /
## expand). A single 1280x720 base shrinks everything to a third of its size on
## a portrait phone, so this swaps the base with the window's orientation:
##   landscape -> 1280x720  (desktop, as the UI was designed)
##   portrait  ->  430x760  (about one logical px per CSS px on a phone)
## With "expand" those are minimums: a portrait screen is always at least
## 430 wide and 760 tall in logical px, which is what the portrait layouts
## assume.
##
## Screens read `portrait` / `touch` while building and build again on `changed`.

signal changed

const LANDSCAPE_SIZE := Vector2i(1280, 720)
const PORTRAIT_SIZE := Vector2i(430, 760)

## Narrowest a portrait screen can be, minus a 16 px gutter each side.
const PORTRAIT_CONTENT_WIDTH := 398.0

## True when the window is taller than it is wide.
var portrait: bool = false
## True while the thumb pads are in use (shown, and named in the hints). Fixed
## on phones. Elsewhere it starts on in a browser that reports a touchscreen,
## turns on with a touch, or with a mouse click in a phone-shaped window (a
## desktop browser's mobile view, where the mouse then drives the pads), and
## turns off again when a key is pressed.
var touch: bool = false

var _touch_only: bool = false


func _ready() -> void:
	_touch_only = (
		OS.has_feature("mobile") or OS.has_feature("web_android") or OS.has_feature("web_ios")
	)
	touch = _touch_only or (OS.has_feature("web") and DisplayServer.is_touchscreen_available())
	get_tree().root.size_changed.connect(_fit)
	_fit()


func _input(event: InputEvent) -> void:
	if _touch_only:
		return
	if event is InputEventScreenTouch and not touch:
		_set_touch(true)
	elif (
		event is InputEventMouseButton and event.pressed and portrait and not touch
		and event.device != InputEvent.DEVICE_ID_EMULATION   # a real mouse, not a touch
	):
		_set_touch(true)
	elif event is InputEventKey and event.pressed and touch:
		_set_touch(false)


func _set_touch(on: bool) -> void:
	touch = on
	changed.emit()


## Logical size of the screen right now.
func view_size() -> Vector2:
	return get_tree().root.get_visible_rect().size


## Frees every child of `screen` so it can build itself again for a new layout.
func clear(screen: Node) -> void:
	for child in screen.get_children():
		screen.remove_child(child)
		child.queue_free()


func _fit() -> void:
	var window := get_tree().root
	var now_portrait := window.size.y > window.size.x
	var base := PORTRAIT_SIZE if now_portrait else LANDSCAPE_SIZE
	if window.content_scale_size != base:
		window.content_scale_size = base
	if now_portrait != portrait:
		portrait = now_portrait
		changed.emit()
