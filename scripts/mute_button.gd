extends CanvasLayer
## Autoload "MuteButton": a small speaker button in the top-right corner of
## EVERY screen (menus, the race, and over the pause / results cards). One tap
## silences all sound; the choice is saved with the other settings.
##
## It lives in its own high layer so it survives scene changes and sits above
## each screen's own UI. The race HUD leaves the corner free for it (the pause
## button and the best-times card sit to its left); menus have nothing there.
## `RESERVED_*` is how much room a screen must leave at the right edge.

const SIZE_PORTRAIT := 40.0
const SIZE_LANDSCAPE := 48.0
const EDGE_PORTRAIT := Vector2(18.0, 19.0)    # gap from the right edge, from the top
const EDGE_LANDSCAPE := Vector2(16.0, 12.0)
## Width a screen must keep clear at the top-right corner, button plus its gaps.
const RESERVED_PORTRAIT := SIZE_PORTRAIT + 18.0 + 6.0
const RESERVED_LANDSCAPE := SIZE_LANDSCAPE + 16.0 + 8.0

var _button: Button


func _ready() -> void:
	layer = 20   # above the HUD, the thumb pads and every modal
	_button = Button.new()
	_button.focus_mode = Control.FOCUS_NONE
	_button.tooltip_text = "Sound on / off"
	_button.add_theme_stylebox_override("normal", HudStyle.glass(12))
	_button.add_theme_stylebox_override("hover", HudStyle.glass(12))
	_button.add_theme_stylebox_override("pressed", HudStyle.glass(12, 0.95))
	_button.draw.connect(_draw_icon)
	_button.pressed.connect(_toggle)
	add_child(_button)
	Layout.changed.connect(_place)
	_place()


func _toggle() -> void:
	Game.set_muted(not Game.is_muted())
	_button.queue_redraw()


func _place() -> void:
	var portrait := Layout.portrait
	var side := SIZE_PORTRAIT if portrait else SIZE_LANDSCAPE
	var edge := EDGE_PORTRAIT if portrait else EDGE_LANDSCAPE
	_button.anchor_left = 1.0
	_button.anchor_right = 1.0
	_button.anchor_top = 0.0
	_button.anchor_bottom = 0.0
	_button.offset_left = -edge.x - side
	_button.offset_right = -edge.x
	_button.offset_top = edge.y
	_button.offset_bottom = edge.y + side
	_button.queue_redraw()


## A speaker with two sound waves, or with a red cross when muted.
func _draw_icon() -> void:
	var muted := Game.is_muted()
	var c := _button.size * 0.5
	var u := _button.size.x / 40.0   # the drawing is laid out for a 40 px button
	var ink := Palette.TEXT_MUTED if muted else Palette.TEXT
	var speaker := PackedVector2Array([
		c + Vector2(-10, -3.5) * u, c + Vector2(-6, -3.5) * u, c + Vector2(-0.5, -8.5) * u,
		c + Vector2(-0.5, 8.5) * u, c + Vector2(-6, 3.5) * u, c + Vector2(-10, 3.5) * u,
	])
	_button.draw_colored_polygon(speaker, ink)
	speaker.append(speaker[0])
	_button.draw_polyline(speaker, ink, 1.0, true)   # feathers the edge
	if muted:
		_button.draw_line(c + Vector2(3.5, -5) * u, c + Vector2(11, 5) * u, Palette.DANGER, 2.4 * u, true)
		_button.draw_line(c + Vector2(11, -5) * u, c + Vector2(3.5, 5) * u, Palette.DANGER, 2.4 * u, true)
	else:
		_button.draw_arc(c + Vector2(0.5, 0) * u, 5.0 * u, -0.95, 0.95, 14, ink, 2.0 * u, true)
		_button.draw_arc(c + Vector2(0.5, 0) * u, 9.5 * u, -0.95, 0.95, 18, ink, 2.0 * u, true)
