extends Node3D

const PROJECTILE_CAPACITY := 192
const PARTICLE = preload("res://shaders/particle.gdshader")
const PRESSURE = preload("res://shaders/pressure.gdshader")
const FIRE = preload("res://assets/surface/combustion.webp")
const SMOKE = preload("res://assets/surface/soot.webp")
const SPARK = preload("res://assets/surface/spark.webp")

var ammo_meshes := {}
var shell_list: Array[MeshInstance3D] = []
var puffs: Array[Dictionary] = []
var impacts: Array[Dictionary] = []
var fragments: Array[Dictionary] = []
var debris_cursor := 0
var pressure_material := ShaderMaterial.new()
var cursor := 0
var impact_slot := 0
var tracer: StandardMaterial3D
var glow: StandardMaterial3D
var ribbon_mesh := ImmediateMesh.new()
var ribbon_material: StandardMaterial3D
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
	ribbon_material = StandardMaterial3D.new()
	ribbon_material.vertex_color_use_as_albedo = true
	ribbon_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	ribbon_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	ribbon_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	var stream := MeshInstance3D.new()
	stream.mesh = ribbon_mesh
	stream.material_override = ribbon_material
	stream.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(stream)
	puff_quad.size = Vector2(2, 2)
	for i in PROJECTILE_CAPACITY:
		var shell := MeshInstance3D.new()
		shell.visible = false
		add_child(shell)
		shell_list.append(shell)
	for i in 104:
		var puff := MeshInstance3D.new()
		puff.mesh = puff_quad
		var effect_mat := ShaderMaterial.new()
		effect_mat.shader = PARTICLE
		puff.material_override = effect_mat
		puff.visible = false
		puff.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(puff)
		puffs.append({"node":puff,"mat":effect_mat,"left":0.0})
	var sphere := SphereMesh.new()
	sphere.radial_segments = 24
	sphere.rings = 12
	pressure_material.shader = PRESSURE
	for i in 6:
		var bulb := OmniLight3D.new()
		bulb.visible = false
		bulb.light_color = Color("#ffc576")
		bulb.omni_range = 76.0
		add_child(bulb)
		var wave := MeshInstance3D.new()
		wave.mesh = sphere
		wave.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		wave.visible = false
		add_child(wave)
		impacts.append({"light":bulb, "wave":wave, "left":0.0, "radius":1.0})
	var shard := PrismMesh.new()
	shard.size = Vector3(1.25, 0.18, 0.63)
	var charred := StandardMaterial3D.new()
	charred.albedo_color = Color("#3a3d47")
	charred.metallic = 0.71
	charred.roughness = 0.57
	shard.material = charred
	for i in 48:
		var fragment := MeshInstance3D.new()
		fragment.mesh = shard
		fragment.visible = false
		fragment.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(fragment)
		fragments.append({"node":fragment, "left":0.0})

func breakup(at: Vector3, carried_velocity: Vector3, wet: bool) -> void:
	impact(at, 2, wet)
	for i in (10 if wet else 16):
		var piece := fragments[debris_cursor]
		debris_cursor = (debris_cursor + 1) % fragments.size()
		var spread := Vector3(randf_range(-1, 1), randf_range(-0.5, 1), randf_range(-1, 1))
		piece.node.position = at + spread * 2.8
		piece.node.scale = Vector3.ONE * randf_range(0.35, 2.3)
		piece.node.rotation = Vector3(randf() * TAU, randf() * TAU, randf() * TAU)
		piece.node.visible = true
		piece.left = randf_range(1.7, 4.5)
		piece.vel = carried_velocity * 0.39 + spread * randf_range(21.0, 72.0)
		piece.spin = spread * randf_range(3.0, 10.0)
		piece.smoke = i < 3
		piece.emit_at = 0.08 * i

func puff(at: Vector3, vel: Vector3, size: float, span: float, kind: int, opacity := 1.0) -> void:
	var item := puffs[cursor]
	cursor = (cursor + 1) % puffs.size()
	var fire := kind == 1
	var spark := kind == 2
	var water := kind == 3
	var tint := Color(1.0, 0.66, 0.36, opacity) if fire else (Color(1.0, 0.86, 0.57, opacity) if spark else Color(0.68, 0.74, 0.8, opacity))
	item.node.position = at
	item.node.scale = Vector3.ONE * size
	item.node.visible = true
	item.mat.set_shader_parameter("flipbook", FIRE if fire else (SPARK if spark else SMOKE))
	item.mat.set_shader_parameter("atlas", fire or spark or kind == 0)
	item.mat.set_shader_parameter("hidden", float(water))
	item.mat.set_shader_parameter("tint", tint)
	item.mat.set_shader_parameter("emission_gain", 5.5 if fire else (6.0 if spark else 0.0))
	item.left = span
	item.total = span
	item.uv_shift = randf() * 0.1
	item.vel = vel
	item.size = size
	item.tint = tint
	item.fire = fire
	item.spark = spark

func impact(at: Vector3, power: int, water := false) -> void:
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
		impact_slot = (impact_slot + 1) % impacts.size()
		item.light.position = at
		item.light.visible = layer == 0
		item.light.light_energy = 8.0
		item.wave.position = at
		item.wave.material_override = pressure_material
		item.wave.scale = Vector3.ONE
		item.wave.visible = true
		item.total = 0.81 + layer * 0.11
		item.left = item.total
		item.radius = radius * (6.5 - layer * 1.23)
		item.wave.set_instance_shader_parameter("amplitude", 0.88 - layer * 0.19)

func projectile(slot: int, at: Vector3, direction: Vector3, missile: bool) -> void:
	var node := shell_list[slot]
	if not ammo_meshes.has(missile):
		if missile:
			var body := CapsuleMesh.new()
			body.radial_segments = 8
			body.rings = 2
			body.radius = 0.15
			body.height = 3.6
			var material := StandardMaterial3D.new()
			material.albedo_color = Color("#b2bacc")
			material.metallic = 0.46
			material.roughness = 0.31
			body.material = material
			ammo_meshes[true] = body
		else:
			var beam := CylinderMesh.new()
			beam.top_radius = 0.045
			beam.bottom_radius = 0.105
			beam.height = 16.0
			beam.radial_segments = 5
			beam.rings = 0
			beam.material = tracer
			ammo_meshes[false] = beam
	node.mesh = ammo_meshes[missile]
	node.visible = true
	node.position = at
	node.quaternion = Quaternion(Vector3.UP, direction.normalized())
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

func tick(dt: float, shots: Array[Dictionary], camera: Camera3D) -> void:
	for item in puffs:
		if item.left <= 0.0:
			continue
		item.left -= dt
		if item.left <= 0.0:
			item.node.visible = false
			continue
		var t: float = 1.0 - item.left / item.total
		item.node.position += item.vel * dt
		item.vel *= exp(-dt * 1.51)
		item.node.scale = Vector3.ONE * item.size * (1.0 + t * (0.4 if item.spark else 1.65))
		var fading: Color = item.tint
		fading.a *= pow(1.0 - t, 0.9)
		item.mat.set_shader_parameter("life", t + item.uv_shift)
		item.mat.set_shader_parameter("tint", fading)
	for item in impacts:
		if item.left <= 0.0:
			continue
		item.left -= dt
		var t := clampf(1.0 - item.left / item.total, 0, 1)
		item.wave.scale = Vector3.ONE * maxf(0.03, item.radius * pow(t, 0.59))
		item.wave.set_instance_shader_parameter("amplitude", 0.95 * pow(1.0 - t, 1.28))
		item.light.light_energy = 7.0 * exp(-t * 13.0)
		if t > 0.24:
			item.light.visible = false
		if t >= 1.0:
			item.wave.visible = false
			item.wave.material_override = null
	for piece in fragments:
		if piece.left <= 0.0:
			continue
		piece.left -= dt
		if piece.left <= 0.0 or piece.node.position.y < 0.1:
			piece.left = 0.0
			piece.node.visible = false
			continue
		piece.vel.y -= 9.81 * dt
		piece.node.position += piece.vel * dt
		piece.node.rotation += piece.spin * dt
		piece.emit_at -= dt
		if piece.smoke and piece.emit_at < 0.0:
			piece.emit_at = 0.18
			puff(piece.node.position, piece.vel * 0.22 + Vector3.UP * 4.0, 0.7, 0.87, 0, 0.42)
	ribbon_mesh.clear_surfaces()
	var active := false
	for shot in shots:
		if not shot.get("missile", false) or not shot.active or shot.trail.size() < 2:
			continue
		if not active:
			ribbon_mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLES)
			active = true
		var points: Array = shot.trail
		for i in range(points.size() - 1):
			var a: Vector3 = points[i]
			var b: Vector3 = points[i + 1]
			var axis := (b - a).cross(camera.position - a).normalized()
			var t := i / float(points.size())
			var radius := lerpf(1.45, 0.13, t)
			var c := Color(0.67, 0.73, 0.80, lerpf(0.04, 0.37, sin(t * PI)))
			var points_strip := [a - axis * radius, a + axis * radius, b + axis * radius, a - axis * radius, b + axis * radius, b - axis * radius]
			for point in points_strip:
				ribbon_mesh.surface_set_color(c)
				ribbon_mesh.surface_add_vertex(point)
	if active:
		ribbon_mesh.surface_end()

func rebase(delta: Vector3) -> void:
	for puff_item in puffs:
		if puff_item.left > 0.0:
			puff_item.node.position -= delta
	for piece in fragments:
		if piece.left > 0.0:
			piece.node.position -= delta
	for impact_item in impacts:
		if impact_item.left > 0.0:
			impact_item.wave.position -= delta
			impact_item.light.position -= delta
