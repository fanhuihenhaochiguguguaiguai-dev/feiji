extends Node3D

signal finished(result: Dictionary)

const Pilot = preload("res://addons/harfang_pilot/pilot.gd")
const Data = preload("res://game/catalogue.gd")
const Airframe = preload("res://game/flight_body.gd")
const Landscape = preload("res://game/world.gd")
const FlightAudio = preload("res://game/flight_audio.gd")
const ExhaustShader = preload("res://shaders/exhaust.gdshader")
const Effects = preload("res://game/effects.gd")
const MISSILE_CYCLE := 0.96
const COUNTER_CYCLE := 4.4
const EVADE_CYCLE := 3.6
const BOOST_CYCLE := 5.8
const LOCK_ANGLE := 0.195
const CONTACT_DISTANCE := [100.0,200.0,300.0,500.0,750.0,1000.0,1500.0,2000.0,3000.0,4000.0,5000.0,6000.0]
const CONTACT_PIXELS := [80.0,60.0,52.0,44.0,38.0,32.0,28.0,24.0,20.0,16.0,14.0,12.0]
const FREE_ROSTER := ["f16", "j10", "mirage", "gripen", "hornet", "mig21", "su35", "j20", "a10", "f16", "j10"]
const FREE_LENGTH := 600.0
const FREE_RESPAWN := 3.0
const CAMPAIGN_CAPACITY := 6
const AUTO_TRACK_GAIN := 0.85
const MISSILE_ARM_TIME := 0.085
const TRAIL_SAMPLE_TIME := 0.03

var catalogue: RefCounted
var profile: RefCounted
var task := {}
var mode := ""
var player: Airframe
var fleet: Array[Airframe] = []
var target_life := -1
var target: Airframe:
	get:
		return target if target and target.hp > 0.0 and target.life_id == target_life else null
	set(contact):
		var life := contact.life_id if contact else -1
		if target != contact or target_life != life:
			target = contact
			target_life = life
			locked_time = 0.0
var locked_time := 0.0
var queued_missile_target: Airframe
var queued_missile_life := -1
var seek_due := 0.0
var launched_from_runway := false
var participated := false
var incoming_heading := Vector3.ZERO
var closest_incoming := INF
var countered_until := 0.0
var lead := Vector3.ZERO
var missile: Dictionary
var radar_range := 6000.0
var time := 0.0
var wave := 0
var next_wave := 0.0
var failure_due := 0.0
var respawns: int:
	get:
		return player.deaths if player else 0
var player_kills: int:
	get:
		return player.kills if player else 0
var shots_hit := 0
var hit_position := Vector3.ZERO
var hit_time := -INF
var hit_destroyed := false
var total_fired := 0
var miles := 0.0
var paused := false
var ended := false
var camera := Camera3D.new()
var world := Landscape.new()
var effects := Effects.new()
var audio := FlightAudio.new()
var shots: Array[Dictionary] = []
var shot_slots: Array[int] = []
var damage_modifiers := Vector3.ONE
var action := {}
var stick := Vector2.ZERO
var camera_anchor := Vector3.ZERO
var boost_at := -10.0
var boost_until := 0.0
var manual_cockpit := false
var look_toward := Vector3.FORWARD
var camera_speed := Vector3.ZERO
var exhaust_geometry := {}
var exhaust_materials: Array[Material] = []
var camera_fresh := true
var camera_lock := 0.0
var steering_amount := 0.0
var exhaust_phase := 0.0
var effects_phase := 0.0
var warning := false
var ready_for_play := false
var free_centre := Vector3.ZERO
var assign_at := 0.0
var runway_course := Vector3.FORWARD

static func start_position(selected_mode: String, operation: Dictionary, use_runway: bool) -> Vector3:
	if use_runway:
		return Vector3(-340.0, 29.7, 590.0)
	return Vector3(11450.0, maxf(190.0, operation.engagement.altitude) if selected_mode == "campaign" else 435.0, 5150.0)

func setup(db: RefCounted, save: RefCounted, selected_mode: String, operation: Dictionary, use_runway: bool, prepared := {}) -> void:
	catalogue = db
	profile = save
	mode = selected_mode
	task = operation
	missile = Data.MISSILES[profile.selected_weapon()]
	radar_range += profile.level_of("radar") * Data.RADAR_DISPLAY_GAIN
	for slot in range(Effects.PROJECTILE_CAPACITY - 1, -1, -1):
		shot_slots.append(slot)
	damage_modifiers = Vector3(1.0 + profile.level_of("weapons") * Data.UPGRADE_GAINS.weapons,
		1.0 + profile.level_of("warhead") * Data.UPGRADE_GAINS.warhead,
		1.0 - profile.level_of("armor") * Data.UPGRADE_GAINS.armor)
	add_child(world)
	add_child(effects)
	add_child(audio)
	audio.mute = profile.state.settings.mute
	add_child(camera)
	camera.far = 20000.0
	camera.near = 0.55
	camera.fov = 53.0
	camera.current = true
	var absolute_start := start_position(selected_mode, operation, use_runway)
	world.configure(catalogue.source.theatres[int(task.get("region", 0))], camera, absolute_start, prepared)
	effects.pool(world.cloud_material)
	var p := world.local_position(absolute_start)
	player = _make_plane(str(profile.state.selected), 0)
	p.y = world.height(p) + player.type.gearClearance + 0.12 if use_runway else maxf(p.y, world.height(p) + 175.0)
	_spawn_aircraft(player, p, Vector3.FORWARD, 0.0 if use_runway else player.type.trim, player.type.durability, use_runway)
	player.engine = 1.0 + profile.level_of("engine") * Data.UPGRADE_GAINS.engine
	player.handling = 1.0 + profile.level_of("maneuver") * Data.UPGRADE_GAINS.maneuver
	launched_from_runway = use_runway
	if use_runway:
		runway_course = _departure_course(p)
	var bot_count := FREE_ROSTER.size() if mode == "free" else (CAMPAIGN_CAPACITY if mode == "campaign" else 1)
	var opening_roster: Array = task.engagement.roster if mode == "campaign" else ["j10"]
	for i in bot_count:
		var id: String = FREE_ROSTER[i] if mode == "free" else opening_roster[i % opening_roster.size()]
		var bot := _make_plane(id, i + 1 if mode == "free" else 1)
		bot.model.visible = false
	if mode == "free":
		free_centre = player.position
		for i in range(1, fleet.size()):
			_spawn_free(fleet[i], true)
	elif mode == "campaign" or task.get("lesson", "") != "flight":
		_spawn_wave()
	ready_for_play = true
	_render_pose(0.016)

func _make_plane(id: String, side: int) -> Airframe:
	var jet := Airframe.new()
	jet.type = catalogue.aircraft(id)
	jet.side = side
	jet.index = fleet.size()
	jet.model = Node3D.new()
	add_child(jet.model)
	_change_plane(jet, id)
	fleet.append(jet)
	return jet

func _change_plane(jet: Airframe, id: String) -> void:
	if not jet.rig.is_empty() and jet.type.id == id:
		return
	jet.type = catalogue.aircraft(id)
	jet.hit_extent = Vector3(jet.type.span * 0.39, jet.type.span * 0.21, jet.type.length * 0.45)
	for old in jet.model.get_children():
		jet.model.remove_child(old)
		old.queue_free()
	jet.rig.clear()
	var model: Node3D = catalogue.mesh(id)
	jet.model.add_child(model)
	var exhausts: Array[Node3D] = []
	for mount in jet.type.engine:
		if not jet.type.props.is_empty():
			break
		var root := Node3D.new()
		root.position = Vector3(mount[0], mount[1], mount[2])
		jet.model.add_child(root)
		exhausts.append(root)
		_jet_exhaust(root, jet.type.span)
	jet.rig = {"meshes":model, "exhausts":exhausts, "lod":"Exterior", "gear":catalogue.gear_tracks(model), "fins":[]}
	var exterior := model.get_node_or_null("Exterior")
	jet.rig.levels = {"Exterior":exterior, "Combat":model.get_node_or_null("Combat"), "LOD":model.get_node_or_null("LOD")}
	jet.rig.cockpit = model.get_node_or_null("Cockpit")
	jet.rig.last_gear = -1.0
	if exterior:
		for node in exterior.find_children("*", "Node3D", true, false):
			if str(node.name).begins_with("Aileron") or str(node.name).begins_with("Canard") or str(node.name).begins_with("Rudder"):
				jet.rig.fins.append({"node":node, "rot":node.rotation})

func _jet_exhaust(root: Node3D, span: float) -> void:
	if not exhaust_geometry.has(span):
		exhaust_geometry[span] = _exhaust_meshes(span)
	var entries: Array = exhaust_geometry[span]
	for entry in entries:
		var layer := MeshInstance3D.new()
		layer.mesh = entry[0]
		layer.rotation.x = PI * 0.5
		layer.position.z = entry[1]
		layer.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		root.add_child(layer)

func _exhaust_meshes(span: float) -> Array:
	if exhaust_materials.is_empty():
		for k in 2:
			var flame := ShaderMaterial.new()
			flame.shader = ExhaustShader
			flame.set_shader_parameter("flame_flipbook", Effects.SUSTAINED_FIRE)
			flame.set_shader_parameter("tint", Color("#6688fb") if k == 0 else Color("#ffd694"))
			flame.set_shader_parameter("intensity", 1.18 if k == 0 else 2.65)
			flame.set_shader_parameter("bias", 0.13 if k == 0 else 0.55)
			exhaust_materials.append(flame)
		exhaust_materials.append(effects.emissive(Color("#adc7ff"), 2.7))
	var models := []
	for k in 2:
		var cone := CylinderMesh.new()
		cone.top_radius = 0.04 if k == 0 else 0.0
		cone.bottom_radius = span * (0.042 if k == 0 else 0.018)
		cone.height = span * (0.34 if k == 0 else 0.47)
		cone.radial_segments = 12
		cone.rings = 0
		cone.material = exhaust_materials[k]
		models.append([cone, cone.height * 0.5])
	for k in 3:
		var disc := TorusMesh.new()
		disc.inner_radius = span * (0.030 - k * 0.004)
		disc.outer_radius = span * (0.036 - k * 0.004)
		disc.rings = 12
		disc.ring_segments = 6
		disc.material = exhaust_materials[2]
		models.append([disc, span * (0.09 + k * 0.095)])
	return models

func _spawn_aircraft(jet: Airframe, at: Vector3, heading: Vector3, airspeed: float, health: float, runway := false) -> void:
	jet.reset(at, heading, airspeed, health, runway)
	jet.model.visible = true

func _spawn_free(jet: Airframe, opening: bool) -> void:
	var angle := (jet.index - 1) * TAU / FREE_ROSTER.size() + (0.0 if opening else time * 0.34)
	var at := _free_spawn_point(jet, angle, 1260.0 + (jet.index % 3) * 260.0, float(jet.index % 5 - 2) * 115.0)
	var inward := free_centre - at
	inward.y = 0.0
	# Angled entries avoid pointing all eleven noses at the same crossing point.
	var heading := inward.normalized().rotated(Vector3.UP, 0.58 if jet.index % 2 == 0 else -0.58)
	_spawn_aircraft(jet, at, heading, jet.type.trim * 0.83, 290.0)
	jet.missile_at = time + (4.5 if opening else 1.7) + (jet.index % 4) * 0.3

func _spawn_wave() -> void:
	assign_at = time
	if wave > 0:
		while not shots.is_empty():
			_expire(shots.back())
		locked_time = 0.0
		target = null
		audio.play_at("wave", player.position)
	var plan: Dictionary = task.get("engagement", {})
	var numbers: Array = plan.get("waves", [1])
	var amount: int = int(numbers[wave])
	wave += 1
	var roster: Array = plan.get("roster", ["j10"])
	var course := Vector3(player.forward.x, 0.0, player.forward.z).normalized()
	if course.length_squared() < 0.01:
		course = Vector3.FORWARD
	var right := course.cross(Vector3.UP)
	for i in range(1, fleet.size()):
		var jet := fleet[i]
		if i > amount:
			jet.hp = 0.0
			jet.model.visible = false
			continue
		var ace := i == amount and wave == numbers.size() and plan.has("ace")
		var drones: int = int(plan.get("drones", 0))
		var id: String = plan.ace if ace else ("shade-drone" if drones > 0 and i < amount and i >= amount - drones else roster[(i + wave - 1) % roster.size()])
		_change_plane(jet, id)
		var tier := int(plan.get("tier", 0))
		var distance: float = float(plan.get("distance", 720.0)) + (wave - 1) * 210.0 + (i - 1) * 155.0
		var section: float = 1.65 if plan.get("formation") == "pincer" else 1.0
		var lateral: float = (i - 1) * (1.0 if i % 2 == 0 else -1.0) * float(plan.get("spacing", 155.0)) * section
		var at := player.position + course * distance + right * lateral
		at.y = maxf(world.height(at) + 130.0, player.position.y + (i - 1) * (126.0 if plan.get("formation") == "stack" else 48.0))
		var heading := -course if mode == "campaign" and i == 1 else course.rotated(Vector3.UP, 0.11 if i % 2 == 0 else -0.09)
		var life := 359.0 + clampf(float(task.get("campaign", 1)) - 1.0, 0.0, 59.0) * 2.3 + (92.0 + float(task.get("campaign", 1)) * 1.25 if ace else 0.0)
		if mode == "training":
			life = 110.0
		_spawn_aircraft(jet, at, heading, jet.type.trim * (0.67 if mode == "training" else 0.84), life)
		jet.handling = 0.66 + tier * 0.075 + (0.16 if ace else 0.0)
		jet.missile_at = time + 3.7 + i * 0.95
	next_wave = 0.0

func _physics_process(dt: float) -> void:
	if paused or ended or not ready_for_play:
		return
	time += dt
	if failure_due > 0.0 and time >= failure_due:
		finish(false)
		return
	if mode == "free" and time >= FREE_LENGTH - 0.000001:
		time = FREE_LENGTH
		finish(false)
		return
	var drift := world.follow(player.position, player.velocity, dt)
	if drift != Vector3.ZERO:
		free_centre -= drift
		for jet in fleet:
			jet.position -= drift
			jet.previous -= drift
		for shot in shots:
			shot.position -= drift
			shot.previous -= drift
			for n in shot.trail.size():
				shot.trail[n] -= drift
		camera.position -= drift
		camera_anchor -= drift
		hit_position -= drift
		effects.rebase(drift)
		audio.rebase(drift)
	if player.hp > 0:
		_targeting(dt)
		_update_player(dt)
	elif mode == "free" and time >= player.until_respawn:
		var at := _free_spawn_point(player, time * 0.61, 790.0, 25.0)
		_spawn_aircraft(player, at, Vector3.FORWARD, player.type.trim, player.type.durability)
		_reset_player_spawn()
	if mode != "training" and time >= assign_at:
		assign_at = time + 0.63
		Pilot.assign(fleet, floori(time / 8.5) if mode == "campaign" else 0)
	for i in range(1, fleet.size()):
		var jet := fleet[i]
		if jet.hp > 0.0:
			_update_bot(jet, dt)
		elif mode == "free" and time >= jet.until_respawn:
			_spawn_free(jet, false)
	_update_shots(dt)
	if mode == "campaign":
		var count := alive_enemies()
		if count == 0 and next_wave == 0.0:
			next_wave = time + 1.7
		if next_wave > 0.0 and time >= next_wave and not ended and failure_due == 0.0:
			if wave >= task.engagement.waves.size():
				finish(true)
			else:
				_spawn_wave()

func _free_spawn_point(pilot: Airframe, angle: float, radius: float, altitude: float) -> Vector3:
	var at := free_centre
	for attempt in 6:
		var bearing := angle + float(attempt) * 2.39996
		at = free_centre + Vector3(sin(bearing) * radius, altitude, -cos(bearing) * radius)
		at.y = maxf(world.height(at) + 260.0, at.y)
		var clear := true
		for jet in fleet:
			if jet != pilot and jet.hp > 0.0 and jet.position.distance_squared_to(at) < 360.0 * 360.0:
				clear = false
				break
		if clear:
			return at
	at.y += 320.0
	return at

func _departure_course(at: Vector3) -> Vector3:
	var course := Vector3.FORWARD
	var lowest := INF
	var climb_out := at + Vector3.FORWARD * 395.0 + Vector3.UP * 187.0
	for angle in [0.0, -0.54, 0.54, -0.85, 0.85, -1.1, 1.1]:
		var heading := Vector3.FORWARD.rotated(Vector3.UP, angle)
		var score := absf(angle) * 91.0
		for distance in [240.0, 420.0, 610.0, 830.0, 1080.0]:
			score += maxf(0.0, world.height(climb_out + heading * distance) - distance * 0.42 - climb_out.y + 45.0)
		if score < lowest:
			lowest = score
			course = heading
	return course

func _targeting(dt: float) -> void:
	var was_locked := is_locked()
	var held := target
	if held and player.forward.dot((held.position - player.position).normalized()) < cos(LOCK_ANGLE * (1.34 if was_locked else 1.19)):
		target = null
		held = null
		seek_due = time
	if time >= seek_due:
		seek_due = time + 0.085
		var range_m: float = float(missile.range) + profile.level_of("radar") * Data.UPGRADE_GAINS.radar
		if held and (player.position.distance_to(held.position) > range_m or world.obstruction(player.position, held.position)):
			target = null
			held = null
		if not held:
			var best: Airframe
			var score := -INF
			for jet in fleet:
				if jet.side == player.side or jet.hp <= 0.0:
					continue
				var offset: Vector3 = jet.position - player.position
				var distance := offset.length()
				if distance < 1.0 or distance > range_m:
					continue
				var align := player.forward.dot(offset / distance)
				if align < cos(LOCK_ANGLE):
					continue
				var rank := align * 2.7 - distance / 6300.0
				if rank > score and not world.obstruction(player.position, jet.position):
					best = jet
					score = rank
			target = best
	_refresh_lead(dt, was_locked and target == held)

func _refresh_lead(dt: float, was_locked: bool) -> void:
	if target:
		locked_time = minf(missile.acquire, locked_time + dt)
		if not was_locked and is_locked():
			audio.play_at("lock", player.position)
		var offset: Vector3 = target.position - player.position
		var speed := float(player.type.cannon[1])
		var rel: Vector3 = target.velocity - player.velocity * 0.60
		var a := rel.length_squared() - speed * speed
		var b := 2.0 * offset.dot(rel)
		var disc := maxf(0.0, b * b - 4.0 * a * offset.length_squared())
		var travel := clampf((-b - sqrt(disc)) / minf(-1.0, 2.0 * a), 0.0, 3.5)
		lead = target.position + rel * travel + Vector3.UP * (4.905 * travel * travel)
	else:
		lead = player.position + player.forward * 650.0

func lock_fraction() -> float:
	return clampf(locked_time / float(missile.acquire), 0.0, 1.0) if target else 0.0

func set_weapon_trigger(weapon: String, pressed: bool) -> void:
	action[weapon] = pressed
	if pressed:
		action[weapon + "_queued"] = time + 0.19
		if weapon == "missile":
			queued_missile_target = target if is_locked() else null
			queued_missile_life = queued_missile_target.life_id if queued_missile_target else -1

func _trigger_held(weapon: String, key: Key) -> bool:
	return bool(action.get(weapon, false)) or time <= float(action.get(weapon + "_queued", -1.0)) or Input.is_physical_key_pressed(key)

func _reset_player_spawn() -> void:
	camera_fresh = true
	camera_lock = 0.0
	steering_amount = 0.0
	hit_time = -INF
	target = null
	locked_time = 0.0
	queued_missile_target = null
	countered_until = 0.0
	boost_until = 0.0
	boost_at = time
	action.clear()
	stick = Vector2.ZERO

func is_locked() -> bool:
	return target != null and target.hp > 0.0 and locked_time >= missile.acquire

static func flight_input(raw: Vector2) -> Vector2:
	var amount := raw.length()
	var response := pow(clampf((amount - 0.025) / 0.975, 0.0, 1.0), 1.56)
	return raw * (response / maxf(amount, 0.025))

func _update_player(dt: float) -> void:
	var keyboard := Vector2(float(Input.is_physical_key_pressed(KEY_D) or Input.is_physical_key_pressed(KEY_RIGHT)) - float(Input.is_physical_key_pressed(KEY_A) or Input.is_physical_key_pressed(KEY_LEFT)),
		float(Input.is_physical_key_pressed(KEY_W) or Input.is_physical_key_pressed(KEY_UP)) - float(Input.is_physical_key_pressed(KEY_S) or Input.is_physical_key_pressed(KEY_DOWN)))
	var steering := (stick + keyboard).limit_length()
	steering_amount = steering.length()
	var response := flight_input(steering)
	var control := Vector3(response.y, response.x, 0.0)
	if is_locked() and not player.grounded and time >= player.evade_until:
		var follow_gain := AUTO_TRACK_GAIN * (1.0 - smoothstep(0.015, 0.095, steering_amount))
		var vector: Vector3 = player.attitude.inverse() * (target.position + target.velocity * 0.23 - player.position).normalized()
		control += Vector3(clampf(vector.y * 0.48, -0.17, 0.17), clampf(vector.x * 0.47, -0.17, 0.17), 0.0) * follow_gain
	if action.get("evade", false):
		action.erase("evade")
		if time >= player.evade_at:
			player.evade_side = signf(steering.x) if absf(steering.x) > 0.12 else (-1.0 if player.evade_side > 0.0 else 1.0)
			player.evade_until = time + 0.78
			player.evade_at = time + EVADE_CYCLE
	if time < player.evade_until:
		control = Vector3(0.23 + control.x * 0.24, player.evade_side * 0.77, -player.evade_side * 0.83)
	if action.get("boost", false):
		action.erase("boost")
		if time >= boost_at:
			boost_at = time + BOOST_CYCLE
			boost_until = time + 2.1
	if action.get("counter", false):
		action.erase("counter")
		if time >= player.counter_at:
			player.counter_at = time + COUNTER_CYCLE
			player.counter_until = time + 0.83
			audio.play_at("counter", player.position)
	if action.get("gear", false):
		action.erase("gear")
		if not player.type.gearFixed and not player.grounded and (player.gear_target > 0.0 or player.velocity.length() < player.type.trim * 1.22):
			player.gear_target = 1.0 - player.gear_target
	var floor_m := world.height(player.position)
	if player.grounded:
		control.x = 0.42 if player.velocity.length() > player.type.stall * 1.12 else 0.0
		control.y = clampf(control.y, -0.23, 0.23)
	elif launched_from_runway:
		if player.position.y > floor_m + 22.0 and not player.type.gearFixed:
			player.gear_target = 0.0
		var look := player.forward * maxf(280.0, player.velocity.length() * 4.6)
		var high_ground := maxf(floor_m, maxf(world.height(player.position + look * 0.55), world.height(player.position + look)))
		var clearance := player.position.y - high_ground
		if steering.length_squared() < 0.014 and player.position.y > 205.0 and time < 8.0:
			var local := player.attitude.inverse() * runway_course
			control.y = clampf(atan2(local.x, -local.z) * 1.8, -0.62, 0.62)
		if clearance < 155.0:
			control.x = maxf(control.x, clampf((155.0 - clearance) * 0.0031, 0.13, 0.59))
		elif mode != "training" or task.get("lesson") != "flight":
			launched_from_runway = false
	player.move(dt, control, 1.0, time < boost_until, floor_m, world.is_runway(player.position), time < player.evade_until)
	miles += player.position.distance_to(player.previous)
	var floor_after := world.height(player.position)
	if not player.grounded and player.position.y < maxf(0.0, floor_after) + 1.2:
		var flat: bool = world.is_runway(player.position) and player.gear > 0.85 and player.velocity.y > -15.0 and player.velocity.length() < player.type.stall * 1.9
		if flat:
			player.grounded = true
			player.position.y = floor_after + player.type.gearClearance
		else:
			_destroy(player, null)
			return
	if _trigger_held("gun", KEY_SPACE) and time >= player.shot_at:
		action.erase("gun_queued")
		_fire(player, false, target)
	if _trigger_held("missile", KEY_F) and time >= player.missile_at:
		var intended := target if is_locked() else null
		if time <= float(action.get("missile_queued", -1.0)) and queued_missile_target:
			if queued_missile_target.hp > 0.0 and queued_missile_target.life_id == queued_missile_life:
				intended = queued_missile_target
		if _fire(player, true, intended):
			action.erase("missile_queued")
			queued_missile_target = null
	if mode == "training" and task.lesson == "flight" and time >= 15.0 and miles >= 320.0 and not player.grounded:
		finish(true)

func _update_bot(jet: Airframe, dt: float) -> void:
	var ground := world.height(jet.position)
	var controls: Vector3
	var power: float
	if mode == "training":
		controls = Pilot.steer(jet, Vector3.FORWARD.rotated(Vector3.UP, sin(time * 0.19) * 0.11),
			maxf(player.position.y + 15.0, world.height(jet.position + jet.forward * 350.0) + 135.0))
		power = 0.59
		if task.lesson in ["counter", "evade"] and time >= jet.missile_at and player.hp > 0.0:
			_fire(jet, true, player)
	else:
		var order := Pilot.command(jet, fleet, free_centre if mode == "free" else player.position, world, ground, time, dt)
		controls = order.control
		power = order.throttle
		if order.gun:
			_fire(jet, false, jet.target)
		if order.missile and _fire(jet, true, jet.target):
			jet.ai_lock = 0.0
	jet.move(dt, controls, power, false, ground, false, time < jet.evade_until)
	if jet.position.y < maxf(world.height(jet.position), 0.0) + 2.0:
		_destroy(jet, null)

func _fire(originator: Airframe, guided: bool, intended: Airframe) -> bool:
	if shot_slots.is_empty():
		return false
	var setup: Dictionary = missile if originator == player else Data.MISSILES.interceptor
	var guns: Array = originator.type.rails if guided else originator.type.guns
	if guns.is_empty():
		if originator == player:
			return false
		guns = [[0, -0.45, -3]]
	var slot: int = shot_slots.pop_back()
	var mount: Array = guns[total_fired % guns.size()]
	var n: Vector3 = originator.forward
	if guided and mode == "training" and originator != player and intended:
		n = (intended.position - originator.position).normalized()
	var start := originator.position + originator.attitude * Vector3(mount[0], mount[1], mount[2])
	var power := 0.0
	var velocity := Vector3.ZERO
	if not guided:
		var gun: Array = originator.type.cannon
		if originator == player and intended and start.distance_to(intended.position) < 1650.0:
			var aim := (lead - start).normalized()
			if aim.dot(n) > 0.9984:
				n = n.lerp(aim, 0.63).normalized()
		if originator != player and intended:
			n = n.lerp((intended.position + intended.velocity * 0.25 - start).normalized(), 0.34).normalized()
		n = (n + Vector3(randf_range(-gun[2], gun[2]), randf_range(-gun[2], gun[2]), randf_range(-gun[2], gun[2]))).normalized()
		velocity = n * float(gun[1]) + originator.velocity * 0.60
		power = gun[3] * originator.type.gunPower * (damage_modifiers.x if originator == player else 0.6)
		originator.shot_at = time + (float(gun[0]) if originator == player else 0.30)
		effects.puff(start + n * 1.8, n * 22.0, 1.35, 0.09, Effects.BURNING)
	else:
		if intended and originator == player and start.distance_squared_to(intended.position) > 420.0 * 420.0:
			# Clear the side of the airframe on launch, then settle into autonomous tracking.
			n = n.rotated(originator.attitude * Vector3.UP, -signf(float(mount[0])) * 0.085)
		velocity = n * (maxf(0.0, originator.velocity.dot(n)) + 78.0)
		var factor := 1.11 if originator.type.era == "cold" else (0.96 if originator.type.era == "stealth" else (1.06 if originator.type.id == "a10" else 1.0))
		power = float(setup.damage) * factor * (damage_modifiers.y if originator == player else 0.61)
		originator.missile_at = time + (MISSILE_CYCLE if originator == player else (8.0 if mode == "training" else 12.0 + (originator.index % 3) * 0.42))
	if originator == player:
		total_fired += 1
	shots.append({"active":true, "active_index":shots.size(), "slot":slot, "owner":originator, "target":intended, "position":start, "previous":start, "velocity":velocity, "nose":n,
		"missile":guided, "target_life":intended.life_id if intended else -1, "profile":setup, "damage":power, "fuel":setup.life if guided else 2.1,
		"age":0.0, "trail":[], "sample_count":0, "soon":MISSILE_ARM_TIME, "decoy":false})
	effects.projectile(slot, start, n, guided)
	audio.play_at("missile" if guided else "gun", start)
	return true

func _update_shots(dt: float) -> void:
	var warning_before := warning
	warning = false
	closest_incoming = INF
	for i in range(shots.size() - 1, -1, -1):
		var cast := shots[i]
		cast.age += dt
		cast.fuel -= dt
		if cast.fuel <= 0.0:
			_expire(cast)
			continue
		var at: Vector3 = cast.position
		var velocity: Vector3 = cast.velocity
		var speed := velocity.length()
		var direction := velocity / maxf(speed, 0.001)
		var guided: bool = cast.missile
		if guided and cast.age > MISSILE_ARM_TIME:
			var mark: Airframe = cast.target
			if mark and mark.hp > 0.0 and mark.life_id == cast.target_life and not cast.decoy:
				var offset: Vector3 = mark.position - at
				var distance := offset.length()
				var alignment := direction.dot(offset) / maxf(distance, 0.001)
				if mark == player and distance < 1600.0:
					warning = true
					if distance < closest_incoming:
						closest_incoming = distance
						incoming_heading = (at - player.position).normalized()
				if distance < 340.0 and mark != player and mode != "training" and time >= mark.evade_at and (mark.index + wave) % 7 == 0:
					mark.evade_until = time + 0.71
					mark.evade_at = time + 21.0
					mark.evade_side = -1.0 if mark.index % 2 == 0 else 1.0
				if mark == player and distance < 820.0 and time < mark.counter_until:
					cast.decoy = true
					participated = true
					countered_until = time + 0.95
					effects.impact(at, 0)
					_expire(cast)
					if mode == "training" and task.lesson == "counter":
						finish(true)
					continue
				if mark == player and time < mark.evade_until and alignment < 0.35 and distance < 110.0:
					cast.decoy = true
					if mode == "training" and task.lesson == "evade":
						finish(true)
				if not cast.decoy:
					direction = _track_missile(cast, direction, speed, offset, mark.velocity, dt)
			velocity = direction * minf(cast.profile.speed, speed + cast.profile.accel * dt)
			if cast.age >= cast.soon:
				cast.soon += TRAIL_SAMPLE_TIME
				cast.sample_count += 1
				cast.trail.append(at)
				if cast.trail.size() > 62:
					cast.trail.pop_front()
				if cast.sample_count == 1:
					effects.puff(at - direction * 2.1, -direction * 18.0, 1.25, 0.15, Effects.BURNING)
					effects.puff(at - direction * 4.0, -direction * 14.0, 2.6, 0.82, 0, 0.62)
		elif not guided:
			velocity.y -= 9.81 * dt
		var toward := at + velocity * dt
		var minimum := at.min(toward) - Vector3.ONE * 29.0
		var maximum := at.max(toward) + Vector3.ONE * 29.0
		var first_hit := INF
		var victim: Airframe
		var surface := Vector3.ZERO
		for jet in fleet:
			if jet.hp <= 0.0 or jet.side == cast.owner.side:
				continue
			var point := jet.position
			if point.x < minimum.x or point.x > maximum.x or point.y < minimum.y or point.y > maximum.y or point.z < minimum.z or point.z > maximum.z:
				continue
			var inverse := jet.attitude.inverse()
			var start := inverse * (at - jet.previous)
			var end := inverse * (toward - jet.position)
			var hit := _hull_entry(start / jet.hit_extent, end / jet.hit_extent)
			if hit < first_hit:
				first_hit = hit
				victim = jet
				surface = start.lerp(end, hit)
		var clearance := toward.y - maxf(0.0, world.height(toward))
		if clearance < 0.0:
			var from_clearance := maxf(0.0, at.y - maxf(0.0, world.height(at)))
			var ground_hit := from_clearance / (from_clearance - clearance)
			if ground_hit < first_hit:
				first_hit = ground_hit
				victim = null
		if first_hit <= 1.0:
			var contact := at.lerp(toward, first_hit)
			if guided:
				cast.trail.append(contact)
				cast.sample_count += 1
			if victim:
				_apply_hit(cast, victim, contact, surface)
			else:
				if guided:
					effects.impact(contact, 1, contact.y <= 1.0)
				_expire(cast)
			continue
		cast.previous = at
		cast.position = toward
		cast.velocity = velocity
		cast.nose = direction
		if guided:
			effects.move_projectile(int(cast.slot), toward, direction, cast.age > MISSILE_ARM_TIME)
	if warning and not warning_before:
		audio.play_at("warn", player.position)

static func _hull_entry(start: Vector3, end: Vector3) -> float:
	var c := start.length_squared() - 1.0
	if c <= 0.0:
		return 0.0
	var step := end - start
	var a := step.length_squared()
	var b := start.dot(step)
	var discriminant := b * b - a * c
	if a < 0.000001 or b >= 0.0 or discriminant < 0.0:
		return INF
	var hit := c / (-b + sqrt(discriminant))
	return hit if hit <= 1.0 else INF

static func _track_missile(cast: Dictionary, nose: Vector3, speed: float, offset: Vector3, drift: Vector3, dt: float) -> Vector3:
	if offset.length_squared() < 0.0001:
		return nose
	var predicted_speed := minf(cast.profile.speed, speed + float(cast.profile.accel) * 0.55)
	var margin := predicted_speed * predicted_speed - drift.length_squared()
	var closing := offset.dot(drift)
	var seconds := offset.length() / maxf(1.0, predicted_speed)
	if margin > 1.0:
		seconds = (closing + sqrt(closing * closing + margin * offset.length_squared())) / margin
	var aim := (offset + drift * clampf(seconds, 0.0, 1.55)).normalized()
	var angle := nose.angle_to(aim)
	if angle < 0.0001:
		return nose
	var axis := nose.cross(aim)
	if axis.length_squared() < 0.000001:
		axis = nose.cross(Vector3.UP if absf(nose.y) < 0.95 else Vector3.RIGHT)
	var authority := lerpf(0.45, 1.0, smoothstep(MISSILE_ARM_TIME, 0.25, cast.age))
	return nose.rotated(axis.normalized(), minf(angle, float(cast.profile.turn) * dt * authority)).normalized()

func _apply_hit(cast: Dictionary, jet: Airframe, closest: Vector3, local: Vector3) -> void:
	var guided: bool = cast.missile
	if cast.owner == player:
		shots_hit += 1
		participated = true
	var hit_power := float(cast.damage)
	if jet == player:
		hit_power *= damage_modifiers.z
	jet.hp = maxf(0.0, jet.hp - hit_power)
	if cast.owner == player:
		hit_position = closest
		hit_time = time
		hit_destroyed = jet.hp <= 0.0
	var zone := Vector3(maxf(0.0, -local.x), maxf(0.0, local.x), 3.3 if local.z > 0.0 else 1.0).normalized()
	jet.damage = (jet.damage + zone * hit_power / jet.max_hp * 1.4).clamp(Vector3.ZERO, Vector3.ONE)
	if jet.hp > 0.0:
		var panel := (0 if local.x < 0.0 else 1) if absf(local.x) > jet.hit_extent.x * 0.38 else 2
		var previous_mark: Vector4 = jet.surface_hits.get(panel, Vector4.ZERO)
		jet.surface_hits[panel] = Vector4(local.x, local.y, local.z, minf(1.0, previous_mark.w + hit_power / jet.max_hp))
		var normal: Vector3 = jet.attitude * (local / (jet.hit_extent * jet.hit_extent)).normalized()
		effects.impact(closest, int(guided), false, jet.velocity, normal)
	audio.play_at("blast" if guided else "scrape", closest)
	_expire(cast)
	if jet.hp <= 0.0:
		_destroy(jet, cast.owner, closest)
	if mode == "training" and cast.owner == player and task.lesson == ("missile" if guided else "gun"):
		finish(true)

func _expire(cast: Dictionary) -> void:
	if not cast.active:
		return
	cast.active = false
	var tail: Dictionary = shots.pop_back()
	var index: int = cast.active_index
	if index < shots.size():
		shots[index] = tail
		tail.active_index = index
	shot_slots.append(cast.slot)
	if cast.missile:
		effects.release_projectile(int(cast.slot), cast.trail, int(cast.sample_count))

func _destroy(jet: Airframe, who: Airframe, contact := Vector3.INF) -> void:
	jet.hp = 0.0
	jet.deaths += 1
	jet.until_respawn = time + FREE_RESPAWN if mode == "free" else 0.0
	var structure: Node3D = jet.rig.levels.Exterior
	jet.model.transform = Transform3D(Basis(jet.attitude), jet.position)
	jet.rig.meshes.scale = Vector3.ONE
	effects.breakup(contact if contact.is_finite() else jet.position, jet.velocity, jet.position.y < 8.0, structure)
	jet.model.visible = false
	audio.play_at("water" if jet.position.y < 8.0 else "fracture", jet.position)
	if who and who != jet:
		who.kills += 1
	if jet == player:
		target = null
		locked_time = 0.0
		if mode != "free":
			failure_due = time + 2.35

func alive_enemies() -> int:
	var count := 0
	for jet in fleet:
		if jet != player and jet.hp > 0:
			count += 1
	return count

func finish(win: bool) -> void:
	if ended:
		return
	if mode == "free":
		if time < FREE_LENGTH:
			return
		ended = true
		_finish_free()
		return
	ended = true
	var total: int = int(task.get("engagement", {}).get("waves", [1]).reduce(func(a, b): return a + b, 0))
	var progress := clampf(player_kills / float(maxi(1, total)), 0.0, 1.0) if mode == "campaign" else clampf(time / 180.0, 0.0, 1.0)
	var precision := minf(1.0, shots_hit / float(maxi(1, total_fired)))
	var score := roundi((3600 if win else 450) + progress * 3100.0 + player_kills * 180.0 + player.hp / player.max_hp * 1650.0 + precision * 1850.0)
	var eligible := win or participated or player_kills > 0
	var result := _sortie_result(win, eligible)
	result.merge({"outcome":"victory" if win else "defeat", "score":score,
		"grade":"王牌" if score >= 10800 else ("优秀" if score >= 8300 else ("合格" if score >= 5100 else "待精进")),
		"credits":roundi(score * 0.105 + (450 if win else 60)) if eligible else 0, "xp":roundi(48 + player_kills * 20 + progress * 112 + (88 if win else 0) + score / 57.0 + float(task.get("threat", 0)) * 13.0) if eligible else 0})
	finished.emit(result)

func _finish_free() -> void:
	var ranking := []
	for jet in fleet:
		ranking.append({"slot":jet.index, "aircraft":str(jet.type.name), "kills":jet.kills, "deaths":jet.deaths})
	ranking.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if a.kills != b.kills:
			return a.kills > b.kills
		if a.deaths != b.deaths:
			return a.deaths < b.deaths
		return a.slot < b.slot)
	var previous_place := 0
	var player_place := 0
	for i in ranking.size():
		var row: Dictionary = ranking[i]
		if i == 0 or row.kills != ranking[i - 1].kills or row.deaths != ranking[i - 1].deaths:
			previous_place = i + 1
		row.place = previous_place
		if row.slot == player.index:
			player_place = previous_place
	var eligible := participated or player_kills > 0
	var credits := (fleet.size() + 1 - player_place) * 55 + player_kills * 70 + maxi(0, player_kills - respawns) * 25 if eligible else 0
	var result := _sortie_result(player_place == 1, eligible)
	result.merge({"score":credits, "place":player_place, "ranking":ranking, "grade":"第 %d 名" % player_place,
		"credits":credits, "xp":48 + player_kills * 20 + (88 if player_place == 1 else 0) if eligible else 0})
	finished.emit(result)

func _sortie_result(win: bool, eligible: bool) -> Dictionary:
	return {"id":task.get("id", ""), "mode":mode, "campaign":task.get("campaign", 0), "name":task.name,
		"aircraft":player.type.id, "kills":player_kills, "deaths":respawns, "seconds":time, "distance":miles,
		"win":win, "eligible":eligible}

func _process(dt: float) -> void:
	if not ready_for_play:
		return
	audio.engine(dt, player.throttle, player.velocity.length(), player.boost, not player.type.props.is_empty(), not paused and player.hp > 0.0)
	if paused:
		return
	_render_pose(minf(dt, 0.05))
	effects.sync_tracers(shots, Engine.get_physics_interpolation_fraction(), camera)
	effects_phase += dt
	if effects_phase >= 0.023 or effects.ribbon_dirty:
		effects.tick(minf(effects_phase, 0.07), shots, camera)
		effects_phase = 0.0

func _render_pose(dt: float) -> void:
	var alpha := Engine.get_physics_interpolation_fraction()
	var pose := player.previous_attitude.slerp(player.attitude, alpha)
	var origin := player.previous.lerp(player.position, alpha)
	var forward := pose * Vector3.FORWARD
	var up := pose * Vector3.UP
	var speed := player.velocity.length()
	var span: float = player.type.span
	effects.update_heat(origin - forward * (float(player.type.length) * 0.5 + 3.6), pose, player.hp > 0.0 and player.boost > 0.5 and not manual_cockpit)
	var focus := origin + forward * (span * 3.1) - Vector3.UP * (span * 0.23)
	var chase := origin - forward * (span * 1.46 + player.boost * 1.35) + Vector3.UP * (span * 0.37) + up * (span * 0.08)
	var tracking := is_locked() and not manual_cockpit and not player.grounded and time >= player.evade_until
	var manual_weight := 1.0 - smoothstep(0.04, 0.46, steering_amount)
	var zoom_request := lerpf(0.30, 1.0, manual_weight) if tracking else 0.0
	camera_lock = 0.0 if manual_cockpit else lerpf(camera_lock, zoom_request, 1.0 - exp(-dt * 6.0))
	if tracking:
		var contact := target.previous.lerp(target.position, alpha)
		var normal_view := focus - chase
		var target_view := (contact - chase).normalized() * normal_view.length()
		focus = chase + normal_view.slerp(target_view, camera_lock * manual_weight * 0.80)
	if manual_cockpit:
		var eye: Array = player.type.eye
		chase = origin + pose * Vector3(eye[0], eye[1], eye[2])
		focus = chase + forward * 35.0
	else:
		chase.y = maxf(chase.y, maxf(0.0, world.height(chase)) + 2.3)
	if camera_fresh or manual_cockpit:
		camera.position = chase
		camera_speed = Vector3.ZERO
		look_toward = (focus - camera.position).normalized()
		camera_fresh = false
	else:
		camera.position += origin - camera_anchor
		var error := camera.position - chase
		var response := 10.5 * 0.85
		var term := (camera_speed + response * error) * dt
		var decay := exp(-response * dt)
		camera.position = chase + (error + term) * decay
		camera_speed = (camera_speed - response * term) * decay
		look_toward = look_toward.slerp((focus - camera.position).normalized(), 1.0 - exp(-dt * 13.0 * 0.85))
	camera_anchor = origin
	camera.look_at(camera.position + look_toward, up if manual_cockpit else Vector3.UP.slerp(up, 0.24 * 0.85).normalized())
	var view_fov := 52.0 + clampf((speed - player.type.trim) / 90.0, -1.0, 4.0) - 10.0 * camera_lock
	camera.fov = lerpf(camera.fov, view_fov, 1.0 - exp(-dt * 7.0))
	var projection := 2.0 * tan(deg_to_rad(camera.fov * 0.5))
	for jet in fleet:
		if jet.hp <= 0.0:
			continue
		jet.model.position = jet.previous.lerp(jet.position, alpha)
		jet.model.quaternion = jet.previous_attitude.slerp(jet.attitude, alpha)
		var distance := camera.position.distance_to(jet.position)
		var px := maxf(float(jet.type.length), float(jet.type.span)) * 576.0 / maxf(1.0, distance * projection)
		if jet == player:
			var cockpit: Node3D = jet.rig.cockpit
			jet.rig.levels.Exterior.visible = not manual_cockpit
			if cockpit:
				var eye: Array = jet.type.eye
				cockpit.visible = manual_cockpit
				cockpit.position = Vector3(eye[0], eye[1], eye[2])
		else:
			# This scale applies only to imported meshes. The aircraft state, hitbox and terrain remain in metres.
			var projected_floor := _contact_size(distance) * 1.6
			var visual_scale := maxf(1.0, projected_floor / maxf(0.05, px))
			jet.rig.meshes.scale = Vector3.ONE * visual_scale
		var lod: String = jet.rig.lod
		if jet != player:
			if px < 12.0 and lod != "LOD":
				lod = "LOD"
			elif px > 16.0 and px < 48.0:
				lod = "Combat"
			elif px > 62.0:
				lod = "Exterior"
			if lod != jet.rig.lod and is_instance_valid(jet.rig.levels[lod]):
				jet.rig.levels[jet.rig.lod].visible = false
				jet.rig.levels[lod].visible = true
				jet.rig.lod = lod
		if jet.rig.lod == "Exterior" and absf(jet.gear - jet.rig.last_gear) > 0.001:
			catalogue.set_gear(jet.rig.gear, jet.gear)
			jet.rig.last_gear = jet.gear
		for part in jet.rig.fins:
			part.node.rotation.x = part.rot.x + clampf(jet.angular.x * 0.12, -0.29, 0.29)
		for plume in jet.rig.exhausts:
			plume.visible = distance < 1850.0 and jet.throttle > 0.67
			plume.scale = Vector3(0.68 + jet.boost * 0.36, 0.68 + jet.boost * 0.36,
				0.62 + jet.boost * 1.23 + sin(time * 71.0 + jet.index) * 0.046 - jet.damage.z * 0.19)
	exhaust_phase += dt
	if exhaust_phase > 0.082:
		exhaust_phase = 0.0
		for jet in fleet:
			if jet.hp <= 0.0 or camera.position.distance_squared_to(jet.position) > 1450.0 * 1450.0:
				continue
			var at: Vector3 = jet.position - jet.forward * float(jet.type.length) * 0.49
			for hit: Vector4 in jet.surface_hits.values():
				if hit.w < 0.21:
					continue
				var wound: Vector3 = jet.position + jet.attitude * Vector3(hit.x, hit.y, hit.z)
				effects.puff(wound, jet.velocity * 0.15 + Vector3.UP * 8.0, 0.72 + hit.w * 1.7, 1.4, 4 if hit.w > 0.44 else 0, 0.77)
				if hit.w > 0.48:
					effects.puff(wound, jet.velocity * 0.35, 0.60 + hit.w * 0.66, 0.40, Effects.BURNING)
			if jet.load_g > 2.1 or jet.position.y > 1950.0 and speed > 210.0:
				for sign_side in [-1, 1]:
					var tip: Vector3 = at + (jet.attitude * Vector3.RIGHT) * float(jet.type.span) * 0.46 * sign_side
					effects.puff(tip, -jet.forward * 7.0, 0.67, 0.64, 3, 0.32)

func _exit_tree() -> void:
	for jet in fleet:
		jet.target = null
	shots.clear()
	target = null

func _contact_size(distance: float) -> float:
	if distance <= CONTACT_DISTANCE[0]:
		return lerpf(0.0, CONTACT_PIXELS[0], smoothstep(0.0, CONTACT_DISTANCE[0], distance))
	for i in range(1, CONTACT_DISTANCE.size()):
		if distance <= CONTACT_DISTANCE[i]:
			return lerpf(CONTACT_PIXELS[i - 1], CONTACT_PIXELS[i], smoothstep(CONTACT_DISTANCE[i - 1], CONTACT_DISTANCE[i], distance))
	return lerpf(CONTACT_PIXELS.back(), 0.0, smoothstep(CONTACT_DISTANCE.back(), radar_range + 2400.0, distance))
