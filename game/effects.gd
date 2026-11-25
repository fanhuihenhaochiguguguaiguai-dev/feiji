extends Node3D

const PROJECTILE_CAPACITY := 192
const PARTICLE = preload("res://shaders/particle.gdshader")
const PRESSURE = preload("res://shaders/pressure.gdshader")
const TRAIL = preload("res://shaders/trail.gdshader")
const FIRE = preload("res://assets/surface/combustion.webp")
const SMOKE = preload("res://assets/surface/soot.webp")
const SPARK = preload("res://assets/surface/spark.webp")

const MISSILE_VISUALS := 28
const RIBBON_SPAN := 2.35
var missile_visuals := {}
var missile_pool: Array[MeshInstance3D] = []
var tracers := MultiMesh.new()
var spent_ribbons: Array[Dictionary] = []
var ribbon_clock := 0.0
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
var ribbon_mesh := ImmediateMesh.new()
var puff_quad := QuadMesh.new()

func emissive(color: Color, strength: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.emission_enabled = true
	m.emission = color
	m.emission_energy_multiplier = strength
	return m

func pool() -> void:
	tracer = emissive(Color(1.0, 0.74, 0.34), 6.0)
	glow = emissive(Color(0.38, 0.59, 1.0), 5.8)
	var ribbon_material := ShaderMaterial.new()
	ribbon_material.shader = TRAIL
	ribbon_material.set_shader_parameter("grain", preload("res://assets/surface/cloud-density.png"))
	var stream := MeshInstance3D.new()
	stream.mesh = ribbon_mesh
	stream.material_override = ribbon_material
	stream.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(stream)
	puff_quad.size = Vector2(2, 2)
	_prepare_projectiles()
	_prepare_impacts()
	for atlas in [SMOKE, FIRE, SPARK]:
		var material := ShaderMaterial.new()
		material.shader = PARTICLE
		material.set_shader_parameter("flipbook", atlas)
		puff_materials.append(material)
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
	impact(at, 2, wet)
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

func puff(at: Vector3, vel: Vector3, size: float, span: float, kind: int, opacity := 1.0) -> void:
	var item := puffs[cursor]
	active_puffs[cursor] = true
	cursor = (cursor + 1) % puffs.size()
	var fire := kind == 1
	var spark := kind == 2
	var water := kind == 3
	var tint := Color(1.0, 0.66, 0.36, opacity) if fire else (Color(1.0, 0.86, 0.57, opacity) if spark else Color(0.68, 0.74, 0.8, opacity))
	if kind == 4:
		tint = Color(0.33, 0.36, 0.39, opacity)
	item.node.position = at
	item.node.scale = Vector3.ONE * size
	item.node.visible = true
	var material := 1 if fire else (2 if spark else 0)
	if item.kind != material:
		item.kind = material
		item.node.material_override = puff_materials[material]
	item.node.set_instance_shader_parameter("atlas", not water)
	item.node.set_instance_shader_parameter("hidden", float(water))
	item.node.set_instance_shader_parameter("tint", tint)
	item.node.set_instance_shader_parameter("emission_gain", 5.5 if fire else (6.0 if spark else 0.0))
	item.left = span
	item.total = span
	item.uv_shift = randf() * 0.1
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
	puff(at, Vector3.ZERO, 0.12, 0.05, 1)
	update_heat(at, Quaternion.IDENTITY, true)
	heat_wake.scale = Vector3.ONE * 0.055

func end_prime(camera: Camera3D) -> void:
	tracers.visible_instance_count = 0
	heat_wake.visible = false
	tick(0.10, [], camera)

func impact(at: Vector3, power: int, water := false) -> void:
	_emit_burst(at, power, water)
	var count := [3, 8, 13][clampi(power, 0, 2)] as int
	var radius := [3.0, 12.0, 24.0][clampi(power, 0, 2)] as float
	for i in count:
		var flow := Vector3(randf_range(-1, 1), randf_range(0.12, 1), randf_range(-1, 1)) * radius
		var kind := 3 if water else (2 if power == 0 else (1 if i < ceili(count * 0.48) else 0))
		puff(at + flow * 0.27, flow * (3.1 if power == 0 else 0.73), radius * randf_range(0.24, 0.68), randf_range(0.24, 0.55) if kind == 2 else randf_range(0.7, 1.9), kind)
	if power == 0:
		return
	for layer in (3 if power == 2 else 2):
		var item := impacts[impact_slot]
		active_impacts[impact_slot] = true
		impact_slot = (impact_slot + 1) % impacts.size()
		item.light.position = at
		item.light.visible = layer == 0
		item.light.light_energy = 8.0
		item.wave.position = at
		item.wave.scale = Vector3.ONE
		item.wave.visible = true
		item.total = 0.81 + layer * 0.11
		item.left = item.total
		item.radius = radius * (6.5 - layer * 1.23)
		item.wave.set_instance_shader_parameter("amplitude", 0.88 - layer * 0.19)

func _prepare_projectiles() -> void:
	var beam := CylinderMesh.new()
	beam.top_radius = 0.035
	beam.bottom_radius = 0.105
	beam.height = 16.0
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
	for i in MISSILE_VISUALS:
		var shell := MeshInstance3D.new()
		shell.mesh = body
		shell.visible = false
		shell.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(shell)
		missile_pool.append(shell)

func _prepare_impacts() -> void:
	if DisplayServer.get_name() == "headless":
		return
	var spark := BoxMesh.new()
	spark.size = Vector3(0.09, 0.40, 0.07)
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

func _emit_burst(at: Vector3, power: int, water: bool) -> void:
	if burst_pool.is_empty() or water:
		return
	var emitter := burst_pool[burst_slot]
	burst_slot = (burst_slot + 1) % burst_pool.size()
	emitter.position = at
	emitter.amount_ratio = 0.52 if power == 0 else 1.0
	emitter.restart()

func projectile(slot: int, at: Vector3, direction: Vector3, missile: bool) -> void:
	if not missile or missile_pool.is_empty():
		return
	var mesh := missile_pool.pop_back() as MeshInstance3D
	missile_visuals[slot] = mesh
	mesh.visible = true
	move_projectile(slot, at, direction)

func move_projectile(slot: int, at: Vector3, direction: Vector3) -> void:
	var body: MeshInstance3D = missile_visuals.get(slot)
	if body:
		body.position = at
		body.quaternion = Quaternion(Vector3.UP, direction)

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

func sync_tracers(shots: Array[Dictionary], alpha: float, camera: Camera3D) -> void:
	var visible := 0
	for shot in shots:
		if shot.missile:
			continue
		var at: Vector3 = shot.previous.lerp(shot.position, alpha)
		if at.distance_squared_to(camera.position) > 4350.0 * 4350.0:
			continue
		var nose: Vector3 = shot.nose
		tracers.set_instance_transform(visible, Transform3D(Basis(Quaternion(Vector3.UP, nose)), at))
		visible += 1
	tracers.visible_instance_count = visible

func tick(dt: float, shots: Array[Dictionary], camera: Camera3D) -> void:
	var drag := exp(-dt * 1.51)
	for slot in active_puffs.keys():
		var item := puffs[slot]
		item.left -= dt
		if item.left <= 0.0:
			item.node.visible = false
			active_puffs.erase(slot)
			continue
		var t: float = 1.0 - item.left / item.total
		item.node.position += item.vel * dt
		item.vel *= drag
		item.node.scale = Vector3.ONE * item.size * (1.0 + t * (0.4 if item.spark else 1.65))
		var fading: Color = item.tint
		fading.a *= pow(1.0 - t, 0.9)
		item.node.set_instance_shader_parameter("life", t + item.uv_shift)
		item.node.set_instance_shader_parameter("tint", fading)
	for slot in active_impacts.keys():
		var item := impacts[slot]
		item.left -= dt
		var t := clampf(1.0 - item.left / item.total, 0, 1)
		item.wave.scale = Vector3.ONE * maxf(0.03, item.radius * pow(t, 0.59))
		item.wave.set_instance_shader_parameter("amplitude", 0.95 * pow(1.0 - t, 1.28))
		if item.light.visible:
			if t > 0.24:
				item.light.visible = false
			else:
				item.light.light_energy = 7.0 * exp(-t * 13.0)
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
	if ribbon_clock < 0.047:
		return
	ribbon_clock = 0.0
	ribbon_mesh.clear_surfaces()
	var active := false
	for shot in shots:
		if not shot.missile or shot.trail.size() < 2:
			continue
		if not active:
			ribbon_mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLES)
			active = true
		_draw_ribbon(shot.trail, camera.position, int(shot.sample_count), 0.0, shot.position)
	for trail in spent_ribbons:
		if not active:
			ribbon_mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLES)
			active = true
		_draw_ribbon(trail.points, camera.position, int(trail.samples), RIBBON_SPAN - float(trail.left))
	if active:
		ribbon_mesh.surface_end()

func _draw_ribbon(points: Array, eye: Vector3, samples: int, settled: float, tip := Vector3.INF) -> void:
	var has_tip := tip.is_finite()
	var rows := points.size() + int(has_tip)
	var previous := Vector3.ZERO
	var previous_trim := Vector3.ZERO
	var previous_alpha := 0.0
	var first := samples - points.size()
	var opacity := pow(1.0 - settled / RIBBON_SPAN, 1.35)
	for i in rows:
		var point: Vector3 = points[i] if i < points.size() else tip
		var before: Vector3 = points[maxi(0, i - 1)]
		var after: Vector3 = tip if has_tip and i + 1 >= points.size() else points[mini(i + 1, points.size() - 1)]
		var tangent := (after - before).normalized()
		var side := tangent.cross(eye - point).normalized()
		if side.length_squared() < 0.01:
			side = previous_trim.normalized() if i > 0 else tangent.cross(Vector3.UP).normalized()
		elif i > 0 and side.dot(previous_trim) < 0.0:
			side = -side
		var phase := float(first + i) * 0.22
		var age := float(rows - 1 - i) * 0.03 + settled
		var billow := 0.5 + 0.5 * sin(phase * 1.63 + age * 2.7)
		var spread := smoothstep(0.02, 1.65, age)
		var shift := Vector3(sin(phase), 0.2 + billow, cos(phase * 0.68))
		point += shift * spread * (0.62 + settled * 0.88)
		var width := 0.24 + (1.65 + billow * 1.82) * spread + settled * (0.58 + billow * 0.39)
		var trim := side * width
		var alpha := opacity * smoothstep(0.0, minf(8.0, float(rows - 1)), float(i)) * (0.65 - spread * 0.35 + billow * 0.1)
		if i > 0:
			var previous_phase := phase - 0.22
			_ribbon_point(previous - previous_trim, previous_phase, 0.0, previous_alpha)
			_ribbon_point(previous + previous_trim, previous_phase, 1.0, previous_alpha)
			_ribbon_point(point + trim, phase, 1.0, alpha)
			_ribbon_point(previous - previous_trim, previous_phase, 0.0, previous_alpha)
			_ribbon_point(point + trim, phase, 1.0, alpha)
			_ribbon_point(point - trim, phase, 0.0, alpha)
		previous = point
		previous_trim = trim
		previous_alpha = alpha

func _ribbon_point(point: Vector3, along: float, across: float, opacity: float) -> void:
	ribbon_mesh.surface_set_uv(Vector2(along, across))
	ribbon_mesh.surface_set_color(Color(0.64, 0.67, 0.72, opacity))
	ribbon_mesh.surface_add_vertex(point)

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
