extends Node3D

signal wreck_breakup(at: Vector3, wet: bool)

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
const COMBUSTION_GRID = preload("res://assets/surface/combustion-volume.png")
const COMBUSTION_SHADER = preload("res://shaders/combustion_volume.gdshader")
const PLUME_SHADER = preload("res://shaders/exhaust.gdshader")
const MISSILE_PLUME := Vector3(0.79, 4.7, 0.79)

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
var volume_pool: Array[MeshInstance3D] = []
var active_volumes := {}
var active_fragments := {}
var wrecks := {}
var puff_materials: Array[ShaderMaterial] = []
var debris_cursor := 0
var pressure_material := ShaderMaterial.new()
static var combustion_field: ImageTexture3D
var heat_wake := MeshInstance3D.new()
var cursor := 0
var impact_slot := 0
var tracer: StandardMaterial3D
var glow: StandardMaterial3D
var ribbon_segments := MultiMesh.new()
var segment_count := 0
var puff_quad := QuadMesh.new()
var view: Camera3D
var plume_mesh := BoxMesh.new()
var plume_materials := {}

func emissive(color: Color, strength: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.emission_enabled = true
	m.emission = color
	m.emission_energy_multiplier = strength
	return m

func jet_plume(extent: Vector3, missile := false) -> MeshInstance3D:
	if not plume_materials.has(missile):
		var material := ShaderMaterial.new()
		material.shader = PLUME_SHADER
		material.set_shader_parameter("tint", Color("#ff8652") if missile else Color("#496ee5"))
		material.set_shader_parameter("intensity", 4.15 if missile else 2.65)
		plume_materials[missile] = material
	var plume := MeshInstance3D.new()
	plume.mesh = plume_mesh
	plume.material_override = plume_materials[missile]
	plume.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	plume.scale = extent
	return plume

func pool(sky: ShaderMaterial, camera: Camera3D) -> void:
	view = camera
	tracer = emissive(Color(1.0, 0.74, 0.34), 6.0)
	glow = emissive(Color(0.38, 0.59, 1.0), 5.8)
	var ribbon_material := ShaderMaterial.new()
	ribbon_material.shader = TRAIL
	ribbon_material.set_shader_parameter("smoke_volume", SMOKE)
	ribbon_segments.transform_format = MultiMesh.TRANSFORM_3D
	ribbon_segments.use_custom_data = true
	var section := CylinderMesh.new()
	section.height = 1.0
	section.radial_segments = 8
	section.rings = 0
	section.cap_top = false
	section.cap_bottom = false
	ribbon_segments.mesh = section
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
	if DisplayServer.get_name() != "headless":
		var combustion_material := ShaderMaterial.new()
		combustion_material.shader = COMBUSTION_SHADER
		combustion_material.set_shader_parameter("combustion", _load_combustion())
		combustion_material.set_shader_parameter("daylight", sky.get_shader_parameter("sun_color"))
		var volume_shape := BoxMesh.new()
		for i in 10:
			var volume := MeshInstance3D.new()
			volume.mesh = volume_shape
			volume.material_override = combustion_material
			volume.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			volume.visible = false
			add_child(volume)
			volume_pool.append(volume)
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

static func _load_combustion() -> ImageTexture3D:
	if combustion_field:
		return combustion_field
	var atlas := COMBUSTION_GRID.get_image()
	atlas.convert(Image.FORMAT_RGBA8)
	var slices: Array[Image] = []
	for layer in 192:
		slices.append(atlas.get_region(Rect2i(layer % 8 * 32, layer / 8 * 32, 32, 32)))
	combustion_field = ImageTexture3D.new()
	combustion_field.create(Image.FORMAT_RGBA8, 32, 32, slices.size(), false, slices)
	return combustion_field

func _emit_volume(at: Vector3, drift: Vector3, extent: Vector3, span: float, heat: float, density: float, priority: int) -> bool:
	if volume_pool.is_empty():
		return false
	var distance := maxf(1.0, view.position.distance_to(at))
	var screen_span := extent[extent.max_axis_index()] * view.get_viewport().get_visible_rect().size.y / (
		2.0 * tan(deg_to_rad(view.fov * 0.5)) * distance)
	if screen_span < 9.0 or view.is_position_behind(at):
		return false
	var slot := -1
	var victim_score := float(priority)
	for index in volume_pool.size():
		if not active_volumes.has(index):
			slot = index
			break
		var existing: Dictionary = active_volumes[index]
		var remaining := float(existing.left) / float(existing.span)
		var score := float(existing.priority) + remaining * 0.9
		if score < victim_score:
			slot = index
			victim_score = score
	if slot < 0:
		return false
	var node := volume_pool[slot]
	var steps := 5.0 if screen_span < 36.0 else (7.0 if screen_span < 125.0 else 9.0)
	var state := Vector4(0.0, heat, density, steps)
	node.position = at
	node.rotation.y = fposmod(at.x * 0.21 + at.z * 0.17, TAU)
	node.scale = extent
	node.set_instance_shader_parameter("volume_state", state)
	node.visible = true
	active_volumes[slot] = {"state":state, "extent":extent, "span":span, "left":span,
		"drift":drift, "priority":priority}
	return true

func damaged_plume(at: Vector3, velocity: Vector3, severity: float) -> void:
	var burning := severity > 0.48
	var size := 0.72 + severity * 1.7
	if _emit_volume(at, velocity * 0.36 + Vector3.UP * 6.0, Vector3(2.5, 3.1, 2.5) * size,
			1.4, 0.64 if burning else 0.0, 0.80 + severity * 0.59, 0):
		return
	puff(at, velocity * 0.15 + Vector3.UP * 8.0, size, 1.4, 4 if severity > 0.44 else 0, 0.77)
	if burning:
		puff(at, velocity * 0.35, 0.60 + severity * 0.66, 0.40, BURNING)

func muzzle_flash(at: Vector3, direction: Vector3) -> void:
	if not _emit_volume(at, direction * 22.0, Vector3(2.8, 3.0, 2.8),
			0.10, 1.35, 0.45, 0):
		puff(at, direction * 22.0, 1.35, 0.09, BURNING)

func missile_ignition(at: Vector3, direction: Vector3) -> void:
	if not _emit_volume(at - direction * 3.2, -direction * 15.0,
			Vector3(6.9, 5.0, 6.9), 0.78, 1.0, 0.84, 0):
		puff(at - direction * 2.1, -direction * 18.0, 1.25, 0.15, BURNING)
		puff(at - direction * 4.0, -direction * 14.0, 2.6, 0.82, 0, 0.62)

func start_wreck(hull: Node3D, airframe: Node3D, at: Vector3, velocity: Vector3, roll: float, wet: bool, contact_shown := false, span := 12.0) -> void:
	if not airframe:
		hull.visible = false
		impact(at, 2, wet, velocity, Vector3.ZERO, span)
		wreck_breakup.emit(at, wet)
		return
	hull.visible = true
	airframe.visible = true
	if not contact_shown:
		impact(at, 1, wet, velocity, Vector3.ZERO, span)
	wrecks[hull] = {"airframe":airframe, "velocity":velocity, "left":0.72,
		"roll":roll, "smoke_due":0.0, "span":span}

func finish_wreck(hull: Node3D, wet: bool) -> void:
	var wreck: Dictionary = wrecks.get(hull, {})
	if wreck.is_empty():
		return
	wrecks.erase(hull)
	impact(hull.position, 2, wet, wreck.velocity, Vector3.ZERO, wreck.span)
	_breakup(wreck.velocity, wreck.airframe)
	hull.visible = false
	wreck_breakup.emit(hull.position, wet)

func _breakup(carried_velocity: Vector3, airframe: Node3D) -> void:
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
	if not volume_pool.is_empty():
		var volume := volume_pool[0]
		volume.position = at
		volume.scale = Vector3.ONE * 0.12
		volume.set_instance_shader_parameter("volume_state", Vector4(1.0, 1.0, 1.0, 7.0))
		volume.visible = true

func end_prime() -> void:
	tracers.visible_instance_count = 0
	heat_wake.visible = false
	if not volume_pool.is_empty():
		volume_pool[0].visible = false
	tick(0.10, [])

static func explosion_radius(span: float, distance: float, view_fov: float, destroyed: bool) -> float:
	var body_scale := maxf(33.0, span * 2.65) if destroyed else maxf(15.0, span * 1.24)
	var projection := maxf(4.0, distance) * tan(deg_to_rad(view_fov * 0.5))
	var legibility := projection * (0.19 if destroyed else 0.11)
	return minf(maxf(body_scale, legibility), 99.0 if destroyed else 60.0)

func impact(at: Vector3, power: int, water := false, carried := Vector3.ZERO, normal := Vector3.ZERO, airframe_span := 12.0) -> void:
	var direction := normal if normal != Vector3.ZERO else Vector3.UP
	_emit_burst(at, power, water, direction)
	if power == 0:
		var eye_ray := view.position - at
		var size := clampf(eye_ray.length() * 0.0075, 1.65, 6.5)
		# The cue still belongs to the confirmed contact. Lift the glare just off the opaque hull.
		var flare := at + eye_ray.normalized() * minf(0.85, size * 0.38)
		puff(flare, carried * 0.86, size * 0.90, 0.105, 8)
		puff(at + direction * 0.38, carried * 0.58 + direction * 31.0, size, 0.23, 2)
		puff(at + direction * 0.58, carried * 0.69 + direction * 11.0, size * 0.34, 0.29, 4, 0.52, 0.025)
		return
	var destroyed := power == 2
	var radius := explosion_radius(airframe_span, view.position.distance_to(at), view.fov, destroyed)
	# Lift the proxy so the hot portion of the baked volume starts on the contact.
	var layered_volume := (not water and _emit_volume(at + Vector3.UP * radius * 0.34,
		carried * 0.66 + Vector3.UP * 6.5, Vector3(3.05, 1.94, 3.05) * radius,
		1.65 if destroyed else 1.05, 1.56 if destroyed else 1.24, 1.40 if destroyed else 1.15, 2 if destroyed else 1))
	if layered_volume and destroyed and active_volumes.size() < 5:
		_emit_volume(at + Vector3.UP * radius * 0.38, carried * 0.43 + Vector3.UP * 13.0,
			Vector3(1.65, 2.10, 1.65) * radius, 2.25, 0.0, 1.43, 1)
	if water:
		for i in (8 if destroyed else 5):
			var spread := Vector3(randf_range(-0.70, 0.70), randf_range(0.8, 1.8), randf_range(-0.70, 0.70))
			puff(at + spread * 2.0, spread * radius * 1.65, radius * randf_range(0.35, 0.62), randf_range(0.72, 1.5), 3)
	else:
		puff(at + direction * 0.35, carried * 0.45, radius * 0.54, 0.16 if destroyed else 0.10, 6)
		if destroyed:
			puff(at, carried * 0.58, radius * 0.75, 0.14, 8)
		for i in (0 if layered_volume else (4 if destroyed else 2)):
			var flow := Vector3(randf_range(-1, 1), randf_range(-0.43, 0.85), randf_range(-1, 1)) + direction * 0.30
			var span := randf_range(0.63, 0.91) if destroyed and i > 1 else randf_range(0.27, 0.53)
			var kind := BURNING if destroyed and i > 1 else 1
			puff(at + flow * radius * 0.24, carried * 0.49 + flow * radius * 1.18, radius * randf_range(0.40, 0.72), span, kind, 0.93)
		var smoke_layers := 0 if layered_volume else (5 if destroyed else 2)
		for i in smoke_layers:
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
	item.wave.visible = not water
	item.total = 0.47 if destroyed else 0.27
	item.left = item.total
	item.radius = radius * (2.5 if destroyed else 1.85)
	item.wave_strength = 0.33 if destroyed else 0.13
	item.wave.set_instance_shader_parameter("amplitude", item.wave_strength)

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
	for i in MISSILE_VISUALS:
		var shell := MeshInstance3D.new()
		shell.mesh = body
		shell.visible = false
		shell.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		var plume := jet_plume(MISSILE_PLUME, true)
		plume.rotation.z = PI
		plume.visible = false
		shell.add_child(plume)
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
		if plume.visible:
			var flare := 1.0 - smoothstep(0.04, 0.36, plume_age)
			plume.scale = MISSILE_PLUME * Vector3(1.0 + flare * 0.65, 1.0 + flare * 0.38, 1.0 + flare * 0.65)
			plume.position.y = -1.65 - plume.scale.y * 0.5

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
		var width := clampf(at.distance_to(camera.position) * 0.0034, 1.0, 3.5)
		var pose := Basis(Quaternion(Vector3.UP, nose)).scaled_local(Vector3(width, 1.0, width))
		tracers.set_instance_transform(visible, Transform3D(pose, at - nose * (TRACER_LENGTH * 0.5)))
		visible += 1
	tracers.visible_instance_count = visible

func tick(dt: float, shots: Array[Dictionary], landscape: Node3D = null) -> void:
	for hull: Node3D in wrecks.keys():
		var wreck: Dictionary = wrecks[hull]
		wreck.left -= dt
		wreck.velocity.y -= 21.0 * dt
		var next: Vector3 = hull.position + wreck.velocity * dt
		var floor_m := maxf(0.0, landscape.height(next)) if landscape else 0.0
		var grounded := next.y <= floor_m + 1.0
		next.y = maxf(next.y, floor_m + 1.0)
		hull.position = next
		hull.rotate_object_local(Vector3.FORWARD, wreck.roll * dt)
		hull.rotate_object_local(Vector3.RIGHT, -0.29 * dt)
		if grounded or wreck.left <= 0.0:
			finish_wreck(hull, grounded and floor_m < 0.5)
			continue
		wreck.smoke_due -= dt
		if wreck.smoke_due <= 0.0:
			wreck.smoke_due = 0.15
			var wake := hull.position + hull.basis.z * 4.0
			damaged_plume(wake, wreck.velocity, 0.88)
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
			item.wave.set_instance_shader_parameter("amplitude", item.wave_strength * pow(1.0 - t, 1.65))
		if item.light.visible:
			if t > 0.54:
				item.light.visible = false
			else:
				item.light.light_energy = item.energy * exp(-t * 9.0)
		if t >= 1.0:
			item.wave.visible = false
			active_impacts.erase(slot)
	for slot in active_volumes.keys():
		var item: Dictionary = active_volumes[slot]
		var volume := volume_pool[slot]
		item.left -= dt
		if item.left <= 0.0:
			volume.visible = false
			active_volumes.erase(slot)
			continue
		var age := 1.0 - float(item.left) / float(item.span)
		volume.position += item.drift * dt
		item.drift *= drag
		volume.scale = item.extent * (1.0 + 1.30 * pow(age, 0.74))
		var state: Vector4 = item.state
		state.x = age
		volume.set_instance_shader_parameter("volume_state", state)
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
	for hull: Node3D in wrecks:
		hull.position -= delta
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
	for slot in active_volumes:
		volume_pool[slot].position -= delta
