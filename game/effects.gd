extends Node3D

const PROJECTILE_CAPACITY := 192
const PARTICLE = preload("res://shaders/particle.gdshader")
const PRESSURE = preload("res://shaders/pressure.gdshader")
const TRAIL = preload("res://shaders/trail.gdshader")
const FIRE = preload("res://assets/surface/combustion.webp")
const SMOKE = preload("res://assets/surface/soot.webp")
const SMOKE_OPPOSITE = preload("res://assets/surface/soot-negative.webp")
const SUSTAINED_FIRE = preload("res://assets/surface/flame-volume.webp")
const BURNING := 7
const SPARK = preload("res://assets/surface/spark.webp")

const MISSILE_VISUALS := 28
const RIBBON_SPAN := 3.1
const TRACER_LENGTH := 29.0
const RIBBON_SEGMENTS := (MISSILE_VISUALS + 16) * 63
var missile_visuals := {}
var missile_pool: Array[MeshInstance3D] = []
var tracers := MultiMesh.new()
var spent_ribbons: Array[Dictionary] = []
var ribbon_clock := 0.0
var ribbon_dirty := false
var burst_pool: Array[GPUParticles3D] = []
var burst_slot := 0
var puffs: Array[Dictionary] = []
var impacts: Array[Dictionary] = []
var fragments: Array[Dictionary] = []
var active_puffs := {}
var active_impacts := {}
var active_fragments := {}
var puff_materials: Array[ShaderMaterial] = []
var debris_cursor := 0
var pressure_material := ShaderMaterial.new()
var heat_wake := MeshInstance3D.new()
var cursor := 0
var impact_slot := 0
var tracer: StandardMaterial3D
var glow: StandardMaterial3D
var ribbon_segments := MultiMesh.new()
var segment_count := 0
var puff_quad := QuadMesh.new()
var view: Camera3D

func emissive(color: Color, strength: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.emission_enabled = true
	m.emission = color
	m.emission_energy_multiplier = strength
	return m

func pool(sky: ShaderMaterial, camera: Camera3D) -> void:
	view = camera
	tracer = emissive(Color(1.0, 0.74, 0.34), 6.0)
	glow = emissive(Color(0.38, 0.59, 1.0), 5.8)
	var ribbon_material := ShaderMaterial.new()
	ribbon_material.shader = TRAIL
	ribbon_material.set_shader_parameter("smoke_volume", SMOKE)
	ribbon_segments.transform_format = MultiMesh.TRANSFORM_3D
	ribbon_segments.use_custom_data = true
	ribbon_segments.mesh = QuadMesh.new()
	ribbon_segments.instance_count = RIBBON_SEGMENTS
	ribbon_segments.visible_instance_count = 0
	ribbon_segments.custom_aabb = AABB(Vector3(-20000, -2500, -20000), Vector3(40000, 7000, 40000))
	var stream := MultiMeshInstance3D.new()
	stream.multimesh = ribbon_segments
	stream.material_override = ribbon_material
	stream.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(stream)
	puff_quad.size = Vector2(2, 2)
	_prepare_projectiles()
	_prepare_impacts()
	for atlas in [SMOKE, FIRE, SPARK, SUSTAINED_FIRE]:
		var material := ShaderMaterial.new()
		material.shader = PARTICLE
		material.set_shader_parameter("flipbook", atlas)
		puff_materials.append(material)
	var smoke := puff_materials[0]
	smoke.set_shader_parameter("opposite_light", SMOKE_OPPOSITE)
	smoke.set_shader_parameter("relight_smoke", true)
	smoke.set_shader_parameter("sun_direction", sky.get_shader_parameter("sun_direction"))
	smoke.set_shader_parameter("sun_color", sky.get_shader_parameter("sun_color"))
	for i in 104:
		var puff := MeshInstance3D.new()
		puff.mesh = puff_quad
		puff.material_override = puff_materials[0]
		puff.visible = false
		puff.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(puff)
		puffs.append({"node":puff,"kind":0,"left":0.0})
	var sphere := SphereMesh.new()
	sphere.radial_segments = 24
	sphere.rings = 12
	pressure_material.shader = PRESSURE
	heat_wake.mesh = sphere
	var heat := ShaderMaterial.new()
	heat.shader = preload("res://shaders/heat.gdshader")
	heat_wake.material_override = heat
	heat_wake.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	heat_wake.visible = false
	add_child(heat_wake)
	for i in 6:
		var bulb := OmniLight3D.new()
		bulb.visible = false
		bulb.light_color = Color("#ffc576")
		bulb.omni_range = 76.0
		add_child(bulb)
		var wave := MeshInstance3D.new()
		wave.mesh = sphere
		wave.material_override = pressure_material
		wave.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		wave.visible = false
		add_child(wave)
		impacts.append({"light":bulb, "wave":wave, "left":0.0, "radius":1.0})
	for i in 48:
		var fragment := MeshInstance3D.new()
		fragment.visible = false
		fragment.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(fragment)
		fragments.append({"node":fragment, "left":0.0})

func breakup(at: Vector3, carried_velocity: Vector3, wet: bool, airframe: Node3D) -> void:
	impact(at, 2, wet, carried_velocity)
	if not is_instance_valid(airframe):
		return
	var surfaces := airframe.find_children("*", "MeshInstance3D", true, false)
	surfaces = surfaces.filter(func(surface):
		return surface.mesh != null and surface.visible and surface.get_aabb().get_longest_axis_size() > 0.45)
	surfaces.sort_custom(func(a, b): return a.get_aabb().get_longest_axis_size() > b.get_aabb().get_longest_axis_size())
	for i in mini(7, surfaces.size()):
		var surface: MeshInstance3D = surfaces[i]
		var piece := fragments[debris_cursor]
		active_fragments[debris_cursor] = true
		debris_cursor = (debris_cursor + 1) % fragments.size()
		var spread := Vector3(randf_range(-1, 1), randf_range(-0.5, 1), randf_range(-1, 1))
		piece.node.mesh = surface.mesh
		piece.node.material_override = surface.material_override
		piece.node.global_transform = surface.global_transform
		piece.node.visible = true
		piece.left = randf_range(1.7, 4.5) if i > 0 else 6.5
		piece.vel = carried_velocity * 0.71 + spread * (14.0 if i == 0 else 59.0)
		piece.spin = spread * (1.8 if i == 0 else 5.0)
		piece.smoke = i < 2
		piece.core = i == 0
		piece.emit_at = 0.08 * i

func puff(at: Vector3, vel: Vector3, size: float, span: float, kind: int, opacity := 1.0, delay := 0.0) -> void:
	var item := puffs[cursor]
	active_puffs[cursor] = true
	cursor = (cursor + 1) % puffs.size()
	var flash := kind == 6
	var burning := kind == BURNING
	var fire := kind == 1 or flash or burning
	var spark := kind == 2 or kind == 8
	var water := kind == 3
	var tint := Color(1.0, 0.66, 0.36, opacity) if fire else (Color(1.0, 0.86, 0.57, opacity) if spark else Color(0.68, 0.74, 0.8, opacity))
	if kind == 4:
		tint = Color(0.33, 0.36, 0.39, opacity)
	elif kind == 5:
		tint = Color(0.19, 0.17, 0.16, opacity)
	elif flash:
		tint = Color(1.0, 0.96, 0.85, opacity)
	elif burning:
		tint = Color(1.0, 0.89, 0.76, opacity)
	elif kind == 8:
		tint = Color(1.0, 0.96, 0.88, opacity)
	item.node.position = at
	item.node.scale = Vector3.ONE * size
	item.node.visible = delay == 0.0
	var material := 3 if burning else (1 if fire else (2 if spark else 0))
	if item.kind != material:
		item.kind = material
		item.node.material_override = puff_materials[material]
	item.node.set_instance_shader_parameter("atlas", not water)
	item.node.set_instance_shader_parameter("contact_flash", kind == 8)
	item.node.set_instance_shader_parameter("hidden", float(water))
	item.node.set_instance_shader_parameter("tint", tint)
	item.node.set_instance_shader_parameter("life", 0.0)
	item.node.set_instance_shader_parameter("soft_depth", 0.10 if kind == 8 else clampf(size * 0.26, 0.42, 5.0))
	item.node.set_instance_shader_parameter("roll", randf_range(-PI, PI))
	item.node.set_instance_shader_parameter("emission_gain", 5.8 if flash else (3.6 if burning else (3.4 if fire else (6.0 if spark else 0.0))))
	item.left = span
	item.total = span
	item.delay = delay
	item.vel = vel
	item.size = size
	item.tint = tint
	item.fire = fire
	item.spark = spark

func update_heat(at: Vector3, attitude: Quaternion, visible_now: bool) -> void:
	heat_wake.visible = visible_now
	if visible_now:
		heat_wake.transform = Transform3D(Basis(attitude).scaled_local(Vector3(2.3, 2.0, 8.6)), at)

func prime(at: Vector3) -> void:
	tracers.set_instance_transform(0, Transform3D(Basis.IDENTITY.scaled(Vector3.ONE * 0.003), at))
	tracers.visible_instance_count = 1
	ribbon_segments.set_instance_transform(0, Transform3D(Basis.IDENTITY.scaled(Vector3.ONE * 0.003), at))
	ribbon_segments.set_instance_custom_data(0, Color(0.0, 0.0, 3.1, 0.0))
	ribbon_segments.visible_instance_count = 1
	puff(at, Vector3.ZERO, 0.12, 0.05, 1)
	puff(at, Vector3.ZERO, 0.12, 0.05, BURNING)
	puff(at, Vector3.ZERO, 0.12, 0.05, 0)
	puff(at, Vector3.ZERO, 0.12, 0.05, 8)
	update_heat(at, Quaternion.IDENTITY, true)
	heat_wake.scale = Vector3.ONE * 0.055

func end_prime() -> void:
	tracers.visible_instance_count = 0
	heat_wake.visible = false
	tick(0.10, [])

func impact(at: Vector3, power: int, water := false, carried := Vector3.ZERO, normal := Vector3.ZERO) -> void:
	var direction := normal if normal != Vector3.ZERO else Vector3.UP
	_emit_burst(at, power, water, direction)
	if power == 0:
		var eye_ray := view.position - at
		var size := clampf(eye_ray.length() * 0.0060, 1.55, 5.4)
		# The cue still belongs to the confirmed contact. Lift the glare just off the opaque hull.
		var flare := at + eye_ray.normalized() * minf(0.85, size * 0.38)
		puff(flare, carried * 0.86, size * 0.82, 0.105, 8)
		puff(at + direction * 0.38, carried * 0.58 + direction * 31.0, size, 0.21, 2)
		return
	var destroyed := power == 2
	var radius := 21.0 if destroyed else 8.5
	if water:
		for i in (8 if destroyed else 5):
			var spread := Vector3(randf_range(-0.70, 0.70), randf_range(0.8, 1.8), randf_range(-0.70, 0.70))
			puff(at + spread * 2.0, spread * radius * 1.65, radius * randf_range(0.35, 0.62), randf_range(0.72, 1.5), 3)
	else:
		puff(at + direction * 0.35, carried * 0.45, radius * 0.54, 0.16 if destroyed else 0.10, 6)
		if destroyed:
			puff(at, carried * 0.58, radius * 0.75, 0.14, 8)
		for i in (4 if destroyed else 2):
			var flow := Vector3(randf_range(-1, 1), randf_range(-0.43, 0.85), randf_range(-1, 1)) + direction * 0.30
			var span := randf_range(0.63, 0.91) if destroyed and i > 1 else randf_range(0.27, 0.53)
			var kind := BURNING if destroyed and i > 1 else 1
			puff(at + flow * radius * 0.24, carried * 0.49 + flow * radius * 1.18, radius * randf_range(0.40, 0.72), span, kind, 0.93)
		for i in (5 if destroyed else 2):
			var flow := Vector3(randf_range(-1, 1), randf_range(0.13, 1), randf_range(-1, 1))
			puff(at + flow * radius * 0.20, carried * 0.33 + flow * radius * 0.67, radius * randf_range(0.37, 0.68), randf_range(1.35, 2.65), 5, 0.98, 0.11 + 0.036 * i)
	var item := impacts[impact_slot]
	active_impacts[impact_slot] = true
	impact_slot = (impact_slot + 1) % impacts.size()
	item.light.position = at
	item.light.visible = not water
	item.light.light_energy = 7.0 if destroyed else 4.5
	item.light.omni_range = radius * 2.5
	item.energy = item.light.light_energy
	item.wave.position = at
	item.wave.scale = Vector3.ONE
	item.wave.visible = destroyed
	item.total = 0.47 if destroyed else 0.15
	item.left = item.total
	item.radius = radius * 2.5
	item.wave.set_instance_shader_parameter("amplitude", 0.33)

func _prepare_projectiles() -> void:
	var beam := CylinderMesh.new()
	beam.top_radius = 0.072
	beam.bottom_radius = 0.15
	beam.height = TRACER_LENGTH
	beam.radial_segments = 5
	beam.rings = 0
	beam.material = tracer
	tracers.transform_format = MultiMesh.TRANSFORM_3D
	tracers.mesh = beam
	tracers.instance_count = PROJECTILE_CAPACITY
	tracers.visible_instance_count = 0
	var draws := MultiMeshInstance3D.new()
	draws.multimesh = tracers
	draws.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	draws.extra_cull_margin = 10000.0
	add_child(draws)
	var body := CapsuleMesh.new()
	body.radial_segments = 8
	body.rings = 2
	body.radius = 0.15
	body.height = 3.6
	var material := StandardMaterial3D.new()
	material.albedo_color = Color("#b2bacc")
	material.metallic = 0.56
	material.roughness = 0.28
	body.material = material
	var flame := CylinderMesh.new()
	flame.top_radius = 0.19
	flame.bottom_radius = 0.02
	flame.height = 4.7
	flame.radial_segments = 5
	flame.rings = 0
	var plume_material := ShaderMaterial.new()
	plume_material.shader = preload("res://shaders/exhaust.gdshader")
	plume_material.set_shader_parameter("flame_flipbook", SUSTAINED_FIRE)
	plume_material.set_shader_parameter("tint", Color("#ff9750"))
	plume_material.set_shader_parameter("intensity", 4.8)
	plume_material.set_shader_parameter("bias", 0.45)
	flame.material = plume_material
	var core := CylinderMesh.new()
	core.top_radius = 0.105
	core.bottom_radius = 0.022
	core.height = 2.1
	core.radial_segments = 5
	core.rings = 0
	core.material = emissive(Color("#fff4da"), 5.6)
	for i in MISSILE_VISUALS:
		var shell := MeshInstance3D.new()
		shell.mesh = body
		shell.visible = false
		shell.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		var plume := MeshInstance3D.new()
		plume.mesh = flame
		plume.position.y = -4.1
		plume.visible = false
		plume.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		shell.add_child(plume)
		var hot_core := MeshInstance3D.new()
		hot_core.mesh = core
		hot_core.position.y = 1.25
		hot_core.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		plume.add_child(hot_core)
		add_child(shell)
		missile_pool.append(shell)

func _prepare_impacts() -> void:
	if DisplayServer.get_name() == "headless":
		return
	var spark := BoxMesh.new()
	spark.size = Vector3(0.13, 0.52, 0.10)
	spark.material = emissive(Color("#ffc280"), 3.8)
	for index in 8:
		var emitter := GPUParticles3D.new()
		emitter.amount = 20
		emitter.lifetime = 0.32
		emitter.one_shot = true
		emitter.explosiveness = 0.93
		emitter.emitting = false
		emitter.draw_pass_1 = spark
		emitter.local_coords = false
		emitter.visibility_aabb = AABB(Vector3(-65, -65, -65), Vector3(130, 130, 130))
		var motion := ParticleProcessMaterial.new()
		motion.direction = Vector3.UP
		motion.spread = 115.0
		motion.gravity = Vector3(0, -28, 0)
		motion.initial_velocity_min = 14.0
		motion.initial_velocity_max = 62.0
		motion.scale_min = 0.3
		motion.scale_max = 1.0
		emitter.process_material = motion
		add_child(emitter)
		burst_pool.append(emitter)

func _emit_burst(at: Vector3, power: int, water: bool, normal: Vector3) -> void:
	if burst_pool.is_empty() or water:
		return
	var distance := view.position.distance_to(at)
	if distance > 3200.0:
		return
	var emitter := burst_pool[burst_slot]
	burst_slot = (burst_slot + 1) % burst_pool.size()
	emitter.position = at
	emitter.amount_ratio = 0.52 if power == 0 else 1.0
	var motion := emitter.process_material as ParticleProcessMaterial
	motion.direction = normal
	motion.spread = 58.0 if power == 0 else 137.0
	var perceptual_scale := clampf(distance * 0.0075, 1.0, 5.0) if power == 0 else 1.0
	motion.scale_min = 0.39 * perceptual_scale
	motion.scale_max = 1.16 * perceptual_scale
	emitter.restart()

func projectile(slot: int, at: Vector3, direction: Vector3, missile: bool) -> void:
	if not missile or missile_pool.is_empty():
		return
	var mesh := missile_pool.pop_back() as MeshInstance3D
	missile_visuals[slot] = mesh
	mesh.visible = true
	move_projectile(slot, at, direction)

func move_projectile(slot: int, at: Vector3, direction: Vector3, plume_age := -1.0) -> void:
	var body: MeshInstance3D = missile_visuals.get(slot)
	if body:
		body.position = at
		body.quaternion = Quaternion(Vector3.UP, direction)
		var plume := body.get_child(0) as MeshInstance3D
		plume.visible = plume_age >= 0.0
		if plume.visible and plume_age < 0.42:
			var flare := 1.0 - smoothstep(0.04, 0.36, plume_age)
			plume.scale = Vector3(1.0 + flare * 0.65, 1.0 + flare * 0.38, 1.0 + flare * 0.65)

func release_projectile(slot: int, points: Array, sample_count: int) -> void:
	var body: MeshInstance3D = missile_visuals.get(slot)
	if body:
		body.visible = false
		missile_visuals.erase(slot)
		missile_pool.append(body)
	if points.size() >= 2:
		if spent_ribbons.size() >= 16:
			spent_ribbons.pop_front()
		spent_ribbons.append({"points": points, "left":RIBBON_SPAN, "samples":sample_count})
		ribbon_dirty = true

func sync_tracers(shots: Array[Dictionary], alpha: float, camera: Camera3D) -> void:
	var visible := 0
	for shot in shots:
		if shot.missile:
			continue
		var at: Vector3 = shot.previous.lerp(shot.position, alpha)
		if at.distance_squared_to(camera.position) > 4350.0 * 4350.0:
			continue
		var nose: Vector3 = shot.nose
		tracers.set_instance_transform(visible, Transform3D(Basis(Quaternion(Vector3.UP, nose)), at - nose * (TRACER_LENGTH * 0.5)))
		visible += 1
	tracers.visible_instance_count = visible

func tick(dt: float, shots: Array[Dictionary]) -> void:
	var drag := exp(-dt * 1.51)
	for slot in active_puffs.keys():
		var item := puffs[slot]
		var elapsed := maxf(0.0, dt - item.delay)
		item.delay = maxf(0.0, item.delay - dt)
		if elapsed == 0.0:
			continue
		item.left -= elapsed
		if item.left <= 0.0:
			item.node.visible = false
			active_puffs.erase(slot)
			continue
		var t: float = 1.0 - item.left / item.total
		item.node.visible = true
		item.node.position += item.vel * elapsed
		item.vel *= drag
		item.node.scale = Vector3.ONE * item.size * (1.0 + t * (0.4 if item.spark else 1.65))
		var fading: Color = item.tint
		var rise := 1.0 if item.spark or item.fire else smoothstep(0.0, 0.19, t + 0.035)
		fading.a *= rise * pow(1.0 - t, 0.9)
		item.node.set_instance_shader_parameter("life", t)
		item.node.set_instance_shader_parameter("tint", fading)
	for slot in active_impacts.keys():
		var item := impacts[slot]
		item.left -= dt
		var t := clampf(1.0 - item.left / item.total, 0, 1)
		if item.wave.visible:
			item.wave.scale = Vector3.ONE * maxf(0.03, item.radius * pow(t, 0.59))
			item.wave.set_instance_shader_parameter("amplitude", 0.33 * pow(1.0 - t, 1.65))
		if item.light.visible:
			if t > 0.54:
				item.light.visible = false
			else:
				item.light.light_energy = item.energy * exp(-t * 9.0)
		if t >= 1.0:
			item.wave.visible = false
			active_impacts.erase(slot)
	for slot in active_fragments.keys():
		var piece := fragments[slot]
		piece.left -= dt
		if piece.left <= 0.0 or piece.node.position.y < 0.1:
			if piece.core and piece.node.position.y < 0.1:
				var surface: Vector3 = piece.node.position
				surface.y = 0.04
				for i in 5:
					puff(surface + Vector3(randf_range(-4.0, 4.0), i * 1.7, randf_range(-4.0, 4.0)),
						Vector3(randf_range(-9, 9), 24.0 + i * 3.4, randf_range(-8, 8)), 2.1 + i * 0.43, 1.45, 3, 0.82)
				impact(surface, 1, true)
			piece.left = 0.0
			piece.node.visible = false
			piece.node.mesh = null
			active_fragments.erase(slot)
			continue
		piece.vel.y -= 9.81 * dt
		piece.node.position += piece.vel * dt
		piece.node.rotation += piece.spin * dt
		piece.emit_at -= dt
		if piece.smoke and piece.emit_at < 0.0:
			piece.emit_at = 0.18
			puff(piece.node.position, piece.vel * 0.22 + Vector3.UP * 4.0, 0.7, 0.87, 0, 0.42)
	for i in range(spent_ribbons.size() - 1, -1, -1):
		spent_ribbons[i].left -= dt
		if spent_ribbons[i].left <= 0.0:
			spent_ribbons.remove_at(i)
	ribbon_clock += dt
	if ribbon_clock < 0.047 and not ribbon_dirty:
		return
	ribbon_dirty = false
	ribbon_clock = 0.0
	segment_count = 0
	for shot in shots:
		if shot.missile and shot.trail.size() >= 2:
			_write_ribbon(shot.trail, int(shot.sample_count), 0.0, shot.position)
	for trail in spent_ribbons:
		_write_ribbon(trail.points, int(trail.samples), RIBBON_SPAN - float(trail.left))
	if ribbon_segments.visible_instance_count != segment_count:
		ribbon_segments.visible_instance_count = segment_count

func _write_ribbon(points: Array, samples: int, settled: float, tip := Vector3.INF) -> void:
	var has_tip := tip.is_finite()
	var rows := points.size() + int(has_tip)
	var first := samples - points.size()
	for i in range(1, rows):
		if segment_count >= RIBBON_SEGMENTS:
			return
		var p0: Vector3 = points[i - 1]
		var p1: Vector3 = points[i] if i < points.size() else tip
		var delta := p1 - p0
		var length := delta.length()
		if length < 0.001:
			continue
		var basis := Basis(Quaternion(Vector3.RIGHT, delta / length))
		basis.x *= length
		var phase := (first + i - 1) * 0.22
		var age := (rows - i) * 0.03 + settled
		ribbon_segments.set_instance_transform(segment_count, Transform3D(basis, p0))
		ribbon_segments.set_instance_custom_data(segment_count, Color(phase, age, settled, float(i - 1) / minf(8.0, rows - 1.0)))
		segment_count += 1

func rebase(delta: Vector3) -> void:
	for trail in spent_ribbons:
		for i in trail.points.size():
			trail.points[i] -= delta
	for body in missile_visuals.values():
		body.position -= delta
	for slot in active_puffs:
		puffs[slot].node.position -= delta
	for slot in active_fragments:
		fragments[slot].node.position -= delta
	for slot in active_impacts:
		impacts[slot].wave.position -= delta
		impacts[slot].light.position -= delta
