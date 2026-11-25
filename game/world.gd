extends Node3D

const SIZE := 256
const STEP := 6.0
const TILE := SIZE * STEP
const APRON_HEIGHT := 150.0
const MAX_JOBS := 5
const RADIUS := 2
const SKY = preload("res://shaders/sky.gdshader")
const SEA = preload("res://shaders/sea.gdshader")
const ROCK = preload("res://assets/surface/rock-grain.png")
const NORMAL_ROCK = preload("res://assets/surface/terrain-normal.png")
const DENSITY = preload("res://assets/surface/cloud-density.png")
const WATER_DETAIL = preload("res://assets/surface/water.png")

var terrain: Terrain3D
var rider: Node3D
var ocean: MeshInstance3D
var ocean_material: ShaderMaterial
var climate := {}
var seed_value := 413
var origin := Vector2i.ZERO
var current: Dictionary = {}
var cache: Dictionary = {}
var jobs: Dictionary = {}
var target := Vector2i.ZERO
var snapped_center := Vector2(INF, INF)
var seeded := false
var start_changed := false

func configure(theatre: Dictionary, camera: Camera3D, start: Vector3, showcase := false) -> void:
	climate = theatre
	seed_value = int(theatre.seed)
	_add_environment(showcase)
	rider = Node3D.new()
	add_child(rider)
	rider.position = start
	terrain = Terrain3D.new()
	terrain.region_size = SIZE
	terrain.vertex_spacing = STEP
	terrain.mesh_size = 48
	terrain.mesh_lods = 8
	terrain.collision_mode = 0
	terrain.free_editor_textures = false
	add_child(terrain)
	terrain.material.world_background = 1
	terrain.material.set_auto_shader_enabled(true)
	terrain.material.set_dual_scaling_enabled(true)
	terrain.material.texture_filtering = 1
	terrain.assets.set_texture_asset(0, _surface("侵蚀岩层", Color("#74726a"), 0.44))
	terrain.assets.set_texture_asset(1, _surface("高地", Color("#b0b9c1") if theatre.snow else Color("#4f5945"), 0.28))
	terrain.set_clipmap_target(rider)
	var centre := cell(start)
	var south := 3 if showcase else 2
	for z in range(-2, south):
		for x in range(-2, 3):
			var coord := centre + Vector2i(x, z)
			var heights := _bake(coord, seed_value)
			if showcase:
				var corner := Vector2(coord) * TILE
				var apron := Vector2(start.x, start.z) - corner
				for row in SIZE:
					for column in SIZE:
						var distance := apron.distance_to(Vector2(column * STEP, row * STEP))
						var f := smoothstep(135.0, 1180.0, distance)
						var idx := row * SIZE + column
						heights[idx] = lerpf(APRON_HEIGHT - 0.35, minf(heights[idx], APRON_HEIGHT + distance * 0.083), f)
			_activate(coord, heights)
	terrain.data.update_maps()
	terrain.set_camera(camera)
	terrain.snap()
	_make_sea()
	if not showcase:
		_make_runway()
	seeded = true

func _add_environment(showcase: bool) -> void:
	var light_color := Color(climate.light[0], climate.light[1], climate.light[2])
	var sunset: bool = not climate.snow and seed_value != 116
	var direction := Vector3(-0.56, 0.145, -0.82).normalized() if sunset else Vector3(climate.sun[0], climate.sun[1], climate.sun[2]).normalized()
	if showcase:
		direction = Vector3(0.38, 0.15, 0.91).normalized()
	var env_node := WorldEnvironment.new()
	env_node.environment = Environment.new()
	var environment := env_node.environment
	var panorama := ShaderMaterial.new()
	panorama.shader = SKY
	panorama.set_shader_parameter("panorama", load("res://assets/surface/probe-%s.hdr" % ("dusk" if sunset else ("day" if climate.snow else "storm"))))
	panorama.set_shader_parameter("density", DENSITY)
	panorama.set_shader_parameter("dusk_sky", preload("res://assets/surface/dusk-panorama.webp"))
	panorama.set_shader_parameter("sun_direction", direction)
	panorama.set_shader_parameter("sun_color", light_color)
	panorama.set_shader_parameter("storm", float(seed_value == 116))
	panorama.set_shader_parameter("sunset", float(sunset))
	environment.background_mode = Environment.BG_SKY
	environment.sky = Sky.new()
	environment.sky.process_mode = Sky.PROCESS_MODE_INCREMENTAL
	environment.sky.sky_material = panorama
	environment.sky.radiance_size = Sky.RADIANCE_SIZE_128
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	environment.ambient_light_sky_contribution = 0.9
	environment.ambient_light_energy = 0.76 if showcase else 0.66
	environment.tonemap_mode = Environment.TONE_MAPPER_ACES
	environment.tonemap_exposure = 1.15
	environment.glow_enabled = false
	environment.glow_intensity = 0.37
	environment.glow_hdr_threshold = 1.4
	environment.fog_enabled = true
	environment.fog_light_color = Color("#8a9bb3") if not sunset else Color("#8295ad")
	environment.fog_sun_scatter = 0.09
	environment.fog_density = 0.000132 if not showcase else 0.000161
	environment.fog_aerial_perspective = 0.52
	add_child(env_node)
	var sun := DirectionalLight3D.new()
	sun.light_color = light_color
	sun.light_energy = 1.8 if sunset else 1.65
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 160.0 if showcase else 450.0
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS
	add_child(sun)
	sun.look_at_from_position(direction * 100.0, Vector3.ZERO)
	if showcase:
		var fill := DirectionalLight3D.new()
		fill.light_color = Color("#9ecbff")
		fill.light_energy = 0.68
		add_child(fill)
		fill.rotation_degrees = Vector3(-36, -34, 0)

func _surface(label: String, tint: Color, texture_scale: float) -> Terrain3DTextureAsset:
	var asset := Terrain3DTextureAsset.new()
	asset.set_asset_name(label)
	asset.set_albedo_texture(ROCK)
	asset.set_normal_texture(NORMAL_ROCK)
	asset.set_albedo_color(tint)
	asset.set_uv_scale(texture_scale)
	asset.set_detiling_rotation(0.68)
	asset.set_detiling_shift(0.55)
	asset.set_normal_depth(1.25)
	return asset

static func _bake(coord: Vector2i, seed_id: int) -> PackedFloat32Array:
	return ClassDB.class_call_static("SkyTerrainKernel", "height_tile", coord.x * TILE, coord.y * TILE, SIZE, STEP, seed_id)

func cell(local_point: Vector3) -> Vector2i:
	return origin + Vector2i(floori(local_point.x / TILE), floori(local_point.z / TILE))

func height(local_point: Vector3) -> float:
	if is_runway(local_point):
		return 26.2
	if terrain and terrain.data.has_region(cell(local_point) - origin):
		var loaded: float = terrain.data.get_height(local_point)
		if is_finite(loaded):
			return loaded
	return float(ClassDB.class_call_static("SkyTerrainKernel", "height_m", origin.x * TILE + local_point.x, origin.y * TILE + local_point.z, seed_value))

func is_runway(p: Vector3) -> bool:
	return absf(p.x + origin.x * TILE + 340.0) < 27.0 and absf(p.z + origin.y * TILE - 350.0) < 430.0

func obstruction(from: Vector3, to: Vector3) -> bool:
	for i in range(1, 8):
		var p := from.lerp(to, i / 8.0)
		if height(p) + 4.0 > p.y:
			return true
	return false

func _make_runway() -> void:
	var strip := MeshInstance3D.new()
	var carpet := PlaneMesh.new()
	carpet.size = Vector2(54, 860)
	strip.mesh = carpet
	var asphalt := StandardMaterial3D.new()
	asphalt.albedo_texture = preload("res://assets/studio/tarmac.webp")
	asphalt.uv1_scale = Vector3(4, 55, 1)
	asphalt.roughness = 0.57
	strip.material_override = asphalt
	strip.position = Vector3(-340.0, 26.2, 350.0)
	strip.name = "Runway"
	add_child(strip)
	var paint := StandardMaterial3D.new()
	paint.albedo_color = Color("#cbd2c7")
	for n in range(-9, 10):
		var line := MeshInstance3D.new()
		var dash := PlaneMesh.new()
		dash.size = Vector2(1.1, 15)
		line.mesh = dash
		line.material_override = paint
		line.position = Vector3(0.0, 0.03, n * 39.0)
		strip.add_child(line)

func _make_sea() -> void:
	ocean = MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(23000, 23000)
	plane.subdivide_width = 220
	plane.subdivide_depth = 220
	ocean.mesh = plane
	ocean_material = ShaderMaterial.new()
	ocean_material.shader = SEA
	ocean_material.set_shader_parameter("shore_noise", WATER_DETAIL)
	ocean.material_override = ocean_material
	ocean.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(ocean)

func _activate(coord: Vector2i, heights: PackedFloat32Array) -> void:
	var region := Terrain3DRegion.new()
	region.region_size = SIZE
	region.vertex_spacing = STEP
	region.location = coord - origin
	region.height_map = Image.create_from_data(SIZE, SIZE, false, Image.FORMAT_RF, heights.to_byte_array())
	region.sanitize_maps()
	region.calc_height_range()
	terrain.data.add_region(region, false)
	current[coord] = region
	cache[coord] = heights

func follow(p: Vector3, velocity: Vector3) -> Vector3:
	var here := cell(p)
	target = cell(p + velocity.limit_length(350.0) * 2.2)
	var delta := Vector3.ZERO
	if absi(here.x - origin.x) >= 3 or absi(here.y - origin.y) >= 3:
		var shift := here - origin
		delta = Vector3(shift.x * TILE, 0.0, shift.y * TILE)
		for coord in current:
			terrain.data.remove_regionl(coord - origin, false)
		var old_cells := current.keys()
		current.clear()
		origin = here
		for coord in old_cells:
			if Vector2i(coord - here).length_squared() <= 18:
				_activate(coord, cache[coord])
		if has_node("Runway"):
			get_node("Runway").position -= delta
		terrain.data.update_maps()
		terrain.snap()
	rider.position = p - delta
	var actual := Vector2(rider.position.x, rider.position.z)
	if actual.distance_squared_to(snapped_center) > 420.0 * 420.0:
		snapped_center = (actual / 220.0).floor() * 220.0
		ocean.position = Vector3(snapped_center.x, 0.0, snapped_center.y)
		ocean_material.set_shader_parameter("world_offset", Vector2(origin) * TILE)
	var changed := false
	for coord in jobs.keys():
		var thread: Thread = jobs[coord]
		if thread.is_alive():
			continue
		var heights: PackedFloat32Array = thread.wait_to_finish()
		jobs.erase(coord)
		if Vector2i(coord - here).length_squared() <= 21 and not current.has(coord):
			_activate(coord, heights)
			changed = true
	var candidates: Array[Vector2i] = []
	for z in range(-RADIUS, RADIUS + 1):
		for x in range(-RADIUS, RADIUS + 1):
			var key := target + Vector2i(x, z)
			if not current.has(key) and not jobs.has(key):
				candidates.append(key)
	candidates.sort_custom(func(a: Vector2i, b: Vector2i): return (a - target).length_squared() < (b - target).length_squared())
	if jobs.size() < MAX_JOBS and not candidates.is_empty():
		var key := candidates[0]
		if cache.has(key):
			_activate(key, cache[key])
			changed = true
		else:
			var task := Thread.new()
			if task.start(_bake.bind(key, seed_value)) == OK:
				jobs[key] = task
	for key in current.keys():
		if (key - here).length_squared() > 20:
			terrain.data.remove_regionl(key - origin, false)
			current.erase(key)
			changed = true
	if cache.size() > 56:
		for key in cache.keys():
			if (key - here).length_squared() > 32:
				cache.erase(key)
	if changed:
		terrain.data.update_maps()
	return delta

func _exit_tree() -> void:
	for task in jobs.values():
		task.wait_to_finish()
