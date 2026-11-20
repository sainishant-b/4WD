extends Area2D
## A single time-trial gate. The car must pass through these in index order.
## game.gd connects to `passed` and tells each checkpoint how to look via set_state().
##
## Drawn in `_draw()`: a thin painted line across the road (the node is rotated
## to face the travel direction, so local x = along the road, local y = across
## it). The gate you must hit next is gold and spills a soft glow up and down
## the road; gate 0, the start/finish line, is a chequered strip instead.

signal passed(index: int, body: Node)

const BAR_DEPTH := 7.0     # thickness of the painted line
const GLOW_DEPTH := 30.0   # how far the active gate's glow reaches either side
const CHECK := 8.0         # one square of the start line's chequer

@export var index: int = 0

var _state: String = "pending"
var _width: float = 150.0

@onready var _label: Label = $Label


func _ready() -> void:
	_label.text = str(index + 1)
	_label.visible = index != 0   # the chequered line already says "start/finish"
	_label.add_theme_font_size_override("font_size", 44)
	_label.pivot_offset = _label.size * 0.5
	body_entered.connect(_on_body_entered)
	set_state("pending")


## A quick scale-pop + bright flash when the gate is passed.
func pop() -> void:
	var tw := create_tween()
	tw.tween_property(self, "scale", Vector2.ONE * 1.5, 0.07)
	tw.tween_property(self, "scale", Vector2.ONE, 0.16)
	modulate = Color(1.6, 1.6, 1.6)
	create_tween().tween_property(self, "modulate", Color(1, 1, 1), 0.25)


## Size the gate to span ACROSS the road. The collision box stays deep enough to
## reliably detect a fast car, but the VISUAL is a thin line so the gate reads
## as a checkpoint line, not a wall.
func configure_gate(width: float, collision_depth: float) -> void:
	var shape := RectangleShape2D.new()
	shape.size = Vector2(collision_depth, width)
	$CollisionShape2D.shape = shape
	_width = width
	_label.rotation = -rotation  # keep the number upright despite the gate's rotation
	queue_redraw()


## "active" = the gate to hit next (gold, matching the HUD arrow), "done" =
## already cleared (a faint dark line), anything else = not yet reachable
## (a faint white line).
func set_state(state: String) -> void:
	_state = state
	# Painted-on-the-road numbers: flat, no outline, faint until it is their turn.
	HudStyle.style_panel_label(_label, Palette.GOLD if state == "active" else Color(Palette.TEXT_LIGHT, 0.4))
	queue_redraw()


func _draw() -> void:
	var half := _width * 0.5
	if _state == "active":
		var core := Color(Palette.GOLD, 0.4)
		var clear := Color(Palette.GOLD, 0.0)
		for dir in [-1.0, 1.0]:
			draw_polygon(
				PackedVector2Array([
					Vector2(0, -half), Vector2(dir * GLOW_DEPTH, -half),
					Vector2(dir * GLOW_DEPTH, half), Vector2(0, half),
				]),
				PackedColorArray([core, clear, clear, core])
			)

	if index == 0:
		_draw_chequer(half)
		return
	var color := Color(Palette.TEXT_LIGHT, 0.3)
	if _state == "active":
		color = Color(Palette.GOLD, 0.92)
	elif _state == "done":
		color = Color(Palette.BLACK, 0.2)
	# A thick anti-aliased line rather than a rect, so its long edges stay smooth.
	draw_line(Vector2(0, -half), Vector2(0, half), color, BAR_DEPTH, true)


## Two rows of alternating squares spanning the road: the start/finish line.
func _draw_chequer(half: float) -> void:
	var columns := maxi(2, roundi(_width / CHECK))
	var cell := _width / columns
	for row in 2:
		var x := (row - 0.5) * CHECK
		for col in columns:
			var light := (row + col) % 2 == 0
			# Each square is a short thick anti-aliased line running across the
			# road, which keeps the strip's outer edges smooth.
			draw_line(
				Vector2(x, -half + col * cell), Vector2(x, -half + (col + 1) * cell),
				Palette.TEXT_LIGHT if light else Palette.BLACK, CHECK, true
			)


func _on_body_entered(body: Node) -> void:
	if body.is_in_group("car"):
		passed.emit(index, body)
