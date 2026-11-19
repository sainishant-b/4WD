extends Area2D
## A track cone. Two behaviours, picked by configure(solid):
##  - SOFT (default): you can plow through it — it bleeds your speed (car.hit_cone)
##    and scatters out of the way.
##  - SOLID: a little wall you must avoid (its StaticBody blocks the car).

var solid: bool = false


func _ready() -> void:
	body_entered.connect(_on_body_entered)


func configure(is_solid: bool) -> void:
	solid = is_solid
	if solid:
		monitoring = false                # no soft trigger
		$Solid.collision_layer = 1        # blocks the car (same layer as walls)
		$Visual.color = Palette.DANGER_DEEP
	else:
		monitoring = true
		$Solid.collision_layer = 0        # no blocking; soft scatter instead
		$Visual.color = Palette.WARNING
	HudStyle.feather($Visual)             # smooth edge, in the colour just chosen


func _on_body_entered(body: Node) -> void:
	if solid or not body.is_in_group("car"):
		return
	if body.has_method("hit_cone"):
		body.hit_cone()
	_scatter()


func _scatter() -> void:
	monitoring = false
	var dir := Vector2.RIGHT.rotated(randf() * TAU) * 42.0
	var tw := create_tween()
	tw.tween_property(self, "position", position + dir, 0.22)
	tw.parallel().tween_property(self, "rotation", rotation + randf_range(-2.0, 2.0), 0.22)
	tw.parallel().tween_property(self, "modulate:a", 0.0, 0.4)
	tw.tween_callback(queue_free)
