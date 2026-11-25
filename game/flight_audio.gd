extends Node

const PRIORITY := {"gun":1.0,"scrape":2.0,"missile":3.0,"water":3.0,"blast":4.0,"fracture":5.0,"wave":5.0,
	"counter":6.0,"lock":6.0,"warn":7.0,"victory":8.0}
var last_cue := {}

var cues := {}
var available: Array[AudioStreamPlayer3D] = []
var speaking := {}
var motor: AudioStreamPlayer
var wind: AudioStreamPlayer
var mute := false

func _ready() -> void:
	if DisplayServer.get_name() == "headless":
		return
	for kind in PRIORITY:
		cues[kind] = load("res://assets/audio/%s.wav" % kind)
	for i in 18:
		var emitter := AudioStreamPlayer3D.new()
		emitter.max_distance = 5400.0
		emitter.unit_size = 170.0
		emitter.max_db = -6
		add_child(emitter)
		emitter.finished.connect(_release.bind(emitter))
		available.append(emitter)
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
	if mute or not cues.has(cue):
		return
	var now := Time.get_ticks_msec()
	var gap := 420 if cue in ["warn", "lock", "wave"] else (38 if cue == "gun" else 70)
	if now - int(last_cue.get(cue, -2000)) < gap:
		return
	var camera := get_viewport().get_camera_3d()
	var distance := camera.global_position.distance_to(at) if camera else 0.0
	if distance > 5400.0:
		return
	var rating: float = float(PRIORITY.get(cue, 1.0)) - distance / 5200.0
	var channel: AudioStreamPlayer3D
	if not available.is_empty():
		channel = available.pop_back()
	else:
		var threshold := rating - 0.45
		for emitter in speaking:
			if speaking[emitter] < threshold:
				channel = emitter
				threshold = speaking[emitter]
		if not channel:
			return
		channel.stop()
	speaking[channel] = rating
	channel.global_position = at
	channel.stream = cues[cue]
	channel.pitch_scale = randf_range(0.92, 1.08) if cue in ["gun", "blast", "scrape"] else 1.0
	last_cue[cue] = now
	channel.play()

func _release(emitter: AudioStreamPlayer3D) -> void:
	if speaking.erase(emitter):
		emitter.stream = null
		available.append(emitter)

func rebase(delta: Vector3) -> void:
	for emitter in speaking:
		emitter.position -= delta

func stop_all() -> void:
	for emitter in speaking.keys():
		emitter.stop()
		_release(emitter)
	for player in [motor, wind]:
		if player:
			player.stop()
			player.stream = null

func _exit_tree() -> void:
	stop_all()
