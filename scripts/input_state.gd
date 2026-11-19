extends Node
## Autoload singleton that merges keyboard input (desktop) and touch input
## (Android / on-screen controls) into one steering model the car reads.
##
## All three steering values are -1..1 targets:
##   front_steer_input : front wheels  (A / D  or the left thumb pad)
##   rear_steer_input  : rear  wheels  (Left / Right  or the right thumb pad)
##   throttle_input    : drive         (+1 = W / pad up, -1 = S / both pads down)
## `handbrake` is Space or one pad pulled down; `boost` is Shift/C or both pads up.
##
## Keyboard takes priority while a key is held; otherwise the latest touch
## value (set by TouchControls) is used.

var front_steer_input: float = 0.0
var rear_steer_input: float = 0.0
var throttle_input: float = 0.0
var handbrake: bool = false
var boost: bool = false

# Written by TouchControls; read here each frame.
var touch_front: float = 0.0
var touch_rear: float = 0.0
var touch_throttle: float = 0.0
var touch_boost: bool = false
var touch_handbrake: bool = false


func _process(_delta: float) -> void:
	var kf := 0.0
	if Input.is_physical_key_pressed(KEY_A):
		kf -= 1.0
	if Input.is_physical_key_pressed(KEY_D):
		kf += 1.0

	var kr := 0.0
	if Input.is_physical_key_pressed(KEY_LEFT):
		kr -= 1.0
	if Input.is_physical_key_pressed(KEY_RIGHT):
		kr += 1.0

	var kt := 0.0
	if Input.is_physical_key_pressed(KEY_W):
		kt += 1.0
	if Input.is_physical_key_pressed(KEY_S):
		kt -= 1.0

	front_steer_input = kf if kf != 0.0 else touch_front
	rear_steer_input = kr if kr != 0.0 else touch_rear
	throttle_input = kt if kt != 0.0 else touch_throttle
	handbrake = Input.is_physical_key_pressed(KEY_SPACE) or touch_handbrake
	# Boost on either Shift (is_key_pressed catches L/R Shift reliably — physical
	# polling is flaky for modifier keys) or the secondary key, or the touch button.
	boost = Input.is_key_pressed(KEY_SHIFT) or Input.is_physical_key_pressed(KEY_C) or touch_boost
