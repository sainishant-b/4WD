extends AudioStreamPlayer
## Engine hum on the Car: loops a short clip and shifts pitch + volume with the
## car's speed. Degrades gracefully (stays silent) if the audio file is missing.

@export var idle_pitch: float = 0.55
@export var max_pitch: float = 2.0

var _car: Node = null


func _ready() -> void:
	_car = get_parent()
	var s: Resource = load("res://audio/engine.wav")
	if s == null:
		return
	if s is AudioStreamWAV:
		s.loop_mode = AudioStreamWAV.LOOP_FORWARD
		s.loop_begin = 0
		s.loop_end = int(s.get_length() * s.mix_rate)
	stream = s
	finished.connect(_on_finished)  # safety net if looping is unavailable
	play()


func _on_finished() -> void:
	if stream != null:
		play()


func _process(_delta: float) -> void:
	if stream == null or _car == null:
		return
	# Silence the engine whenever the car isn't actively racing (countdown, pause,
	# or after the race is finished) — its physics processing is disabled then.
	if not _car.is_physics_processing():
		volume_db = -60.0
		return
	var speed: float = (_car.velocity as Vector2).length()
	var top: float = maxf(_car.max_speed, 1.0)
	var f := clampf(speed / top, 0.0, 1.0)
	pitch_scale = lerpf(idle_pitch, max_pitch, f)
	volume_db = lerpf(-14.0, -3.0, f)
