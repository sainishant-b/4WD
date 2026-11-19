extends Area2D
## A jump ramp. Driving onto it launches a short fake "hop" on the car (car.jump):
## the car scales up like it's airborne, drops collision so it sails over obstacles,
## then lands. Oriented along the road (local +x = travel direction).

@export var jump_duration: float = 0.55


func _ready() -> void:
	body_entered.connect(_on_body_entered)


func _on_body_entered(body: Node) -> void:
	if body.is_in_group("car") and body.has_method("jump"):
		body.jump(jump_duration)
