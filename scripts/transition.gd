extends CanvasLayer
## Autoload "Transition": the sweep between screens. `change_scene(path)` slides
## a curtain of the menus' cobalt stripes in from the right (its stripes line up
## and drift with `HudStyle.add_backdrop`'s), swaps the scene while the screen is
## covered, waits for the new screen to settle, then slides on off to the left.
## A thin gold edge on an INK line leads it. `Game.goto_*` and `start_level` all
## come through here; pass `animate = false` to switch at once (the main menu's
## redirects on the way in).
##
## The game also starts covered and sweeps open once its first screen has
## settled, picking up from the Reddit page's loader (the same stripes). While
## the curtain moves it swallows taps, so a double tap cannot start two
## changes. Headless runs (the tests) switch scenes at once, with no curtain.

const COVER_TIME := 0.26
const REVEAL_TIME := 0.32

var _curtain: Curtain
var _busy := false


func _ready() -> void:
	layer = 30   # above the HUD, the thumb pads and the mute button (20)
	process_mode = Node.PROCESS_MODE_ALWAYS
	_curtain = Curtain.new()
	_curtain.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_curtain.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_curtain.visible = false
	add_child(_curtain)
	if _instant():
		return
	_busy = true
	_curtain.p = 1.0
	_curtain.visible = true
	_curtain.mouse_filter = Control.MOUSE_FILTER_STOP
	_open_when_settled()


## True while the curtain is on screen.
func is_busy() -> bool:
	return _busy


## Goes to the scene at `path`, behind the curtain unless `animate` is false.
func change_scene(path: String, animate := true) -> void:
	if not animate or _instant():
		get_tree().change_scene_to_file(path)
		return
	if _busy:
		return   # a second tap while the curtain moves
	_busy = true
	_curtain.mouse_filter = Control.MOUSE_FILTER_STOP
	_curtain.p = 0.0
	_curtain.visible = true
	UiFeel.sound("whoosh")
	var tw := create_tween()
	tw.tween_property(_curtain, "p", 1.0, COVER_TIME).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)
	await tw.finished
	get_tree().change_scene_to_file(path)
	_open_when_settled()


## Waits until the same screen has been current for a couple of frames (a
## screen may send the player straight on elsewhere), then opens the curtain.
func _open_when_settled() -> void:
	var tree := get_tree()
	var last: Node = null
	var steady := 0
	while steady < 2:
		await tree.process_frame
		var now := tree.current_scene
		steady = steady + 1 if now != null and now == last else 0
		last = now
	UiFeel.intro(last)
	var tw := create_tween()
	tw.tween_property(_curtain, "p", 2.0, REVEAL_TIME).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	await tw.finished
	_curtain.visible = false
	_curtain.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_busy = false


static func _instant() -> bool:
	return DisplayServer.get_name() == "headless"


## The curtain. `p` runs 0 -> 1 while it covers the screen (its edge moving
## right to left) and 1 -> 2 while it uncovers it (moving on to the left).
class Curtain extends Control:
	const SLANT := 0.3      # the edge leans this much of the screen height
	const EDGE_INK := 10.0
	const EDGE_GOLD := 4.0

	var p := 0.0:
		set(value):
			p = value
			queue_redraw()

	func _process(_delta: float) -> void:
		if visible:
			queue_redraw()   # the stripes drift

	func _draw() -> void:
		if p <= 0.001 or p >= 1.999:
			return
		var w := size.x
		var h := size.y
		var skew := h * SLANT
		var travel := w + skew
		var far := skew + 12.0
		# The moving edge runs from (edge + skew, 0) down to (edge, h).
		var edge: float
		var cover: PackedVector2Array
		if p <= 1.0:
			edge = w - p * travel
			cover = PackedVector2Array([Vector2(edge + skew, 0), Vector2(w + far, 0), Vector2(w + far, h), Vector2(edge, h)])
		else:
			edge = w - (p - 1.0) * travel
			cover = PackedVector2Array([Vector2(-far, 0), Vector2(edge + skew, 0), Vector2(edge, h), Vector2(-far, h)])
		draw_colored_polygon(cover, Palette.BG)
		# The backdrop's stripes, clipped to the curtain and in step with the
		# menus' (HudStyle.Backdrop draws the same bands as wide lines).
		var stripe := HudStyle.STRIPE
		var step := HudStyle.STRIPE_PERIOD * sqrt(2.0)
		var reach := h + stripe * 2.0
		var half := Vector2(1.0, 1.0).normalized() * stripe * 0.5
		var x := HudStyle.stripe_shift()
		while x < w + reach:
			var a := Vector2(x + stripe, -stripe)
			var b := a + Vector2(-reach, reach)
			var band := PackedVector2Array([a + half, b + half, b - half, a - half])
			for piece: PackedVector2Array in Geometry2D.intersect_polygons(band, cover):
				draw_colored_polygon(piece, Palette.BG_STRIPE)
				var outline := piece.duplicate()
				outline.append(piece[0])
				draw_polyline(outline, Palette.BG_STRIPE, 1.0, true)
			x += step
		var top := Vector2(edge + skew, 0.0)
		var bottom := Vector2(edge, h)
		draw_line(top, bottom, Palette.INK, EDGE_INK, true)
		draw_line(top, bottom, Palette.GOLD, EDGE_GOLD, true)
