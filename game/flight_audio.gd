extends Node

var cues := {}
var voices: Array[AudioStreamPlayer3D] = []
var motor: AudioStreamPlayer
var wind: AudioStreamPlayer
var mute := false

func _ready() -> void:
	if DisplayServer.get_name() == "headless":
		return
	for kind in ["gun", "missile", "blast", "scrape", "fracture", "water", "counter", "lock", "warn", "wave", "victory"]:
		cues[kind] = load("res://assets/audio/%s.wav" % kind)
	for i in 18:
		var emitter := AudioStreamPlayer3D.new()
		emitter.max_distance = 5400.0
		emitter.unit_size = 170.0
		emitter.max_db = -6
		add_child(emitter)
		voices.append(emitter)
	motor = _ambience(preload("res://assets/audio/engine.wav"))
	wind = _ambience(preload("res://assets/audio/wind.wav"))

func _ambience(wav: AudioStreamWAV) -> AudioStreamPlayer:
	var source: AudioStreamWAV = wav.duplicate()
	source.loop_mode = AudioStreamWAV.LOOP_FORWARD
	source.loop_begin = 0
	source.loop_end = int(source.get_length() * source.mix_rate)
	var node := AudioStreamPlayer.new()
	node.stream = source
	node.volume_db = -80.0
	add_child(node)
	node.play()
	return node

func engine(dt: float, throttle: float, speed: float, boost: float, propeller: bool, active: bool) -> void:
	if motor == null:
		return
	var audible := active and not mute
	var level := (0.017 + throttle * 0.032 + boost * 0.044) if audible else 0.0
	var air := (minf(0.075, speed * 0.00024) + boost * 0.025) if audible else 0.0
	motor.volume_db = lerpf(motor.volume_db, linear_to_db(maxf(0.0001, level)), 1.0 - exp(-dt / 0.09))
	wind.volume_db = lerpf(wind.volume_db, linear_to_db(maxf(0.0001, air)), 1.0 - exp(-dt / 0.15))
	var freq := 37.0 + throttle * 37.0 if propeller else 49.0 + speed * 0.18 + boost * 46.0
	motor.pitch_scale = lerpf(motor.pitch_scale, freq / 64.0, 1.0 - exp(-dt / 0.11))
	wind.pitch_scale = clampf((280.0 + speed * 3.1) / 740.0, 0.4, 2.5)

func play_at(cue: String, at: Vector3) -> void:
	if mute:
		return
	for emitter in voices:
		if emitter.playing:
			continue
		emitter.global_position = at
		emitter.stream = cues[cue]
		emitter.play()
		break

func stop_all() -> void:
	for emitter in voices:
		emitter.stop()
		emitter.stream = null
	for player in [motor, wind]:
		if player:
			player.stop()
			player.stream = null

func _exit_tree() -> void:
	stop_all()
