extends Node3D

const SIZE := 256
const STEP := 6.0
const TILE := SIZE * STEP
const APRON_HEIGHT := 150.0
const MAX_JOBS := 3
const STREAM_INTERVAL := 0.12
const UPLOAD_BUDGET := 2
const RADIUS := 2
const SKY = preload("res://shaders/sky.gdshader")
const Ocean = preload("res://game/ocean.gd")
const ROCK = preload("res://assets/surface/scans/rock_color.jpg")
const LOWLAND = preload("res://assets/surface/scans/sand_color.jpg")
const NORMAL_ROCK = preload("res://assets/surface/scans/rock_normal.png")
const NORMAL_LOWLAND = preload("res://assets/surface/scans/sand_normal.png")
const DENSITY = preload("res://assets/surface/cloud-density.png")

var terrain: Terrain3D
var rider: Node3D
var ocean: Ocean
var climate := {}
var seed_value := 413
var origin := Vector2i.ZERO
var current: Dictionary = {}
var cache: Dictionary = {}
var jobs: Dictionary = {}
var target := Vector2i.ZERO
var stream_clock := 0.0
var completed_tiles: Dictionary = {}
var neutral_control: Image
var neutral_color: Image
var prefetch_centre := Vector2i.MAX
var candidate_tiles: Array[Vector2i] = []
var coast_job: Thread
var coast_cell := Vector2i.MAX
var coast_corner := Vector2.ZERO
var coast_enabled := false
var cloud_material: ShaderMaterial
var flight_environment: Environment

static func opening_tiles(start: Vector3, showcase: bool) -> Array[Vector2i]:
	var centre := Vector2i(floori(start.x / TILE), floori(start.z / TILE))
	var coordinates: Array[Vector2i] = []
	for z in range(-2, 3 if showcase else 2):
		for x in range(-2, 3):
			coordinates.append(centre + Vector2i(x, z))
	return coordinates

func local_position(absolute_position: Vector3) -> Vector3:
	return absolute_position - Vector3(origin.x * TILE, 0.0, origin.y * TILE)

func configure(theatre: Dictionary, camera: Camera3D, start: Vector3, showcase := false, prepared := {}) -> void:
	climate = theatre
	coast_enabled = not showcase and DisplayServer.get_name() != "headless"
	seed_value = int(theatre.seed)
	_add_environment(showcase)
	rider = Node3D.new()
	add_child(rider)
	if not showcase:
		origin = Vector2i(floori(start.x / TILE), floori(start.z / TILE))
	cloud_material.set_shader_parameter("terrain_origin", Vector2(origin) * TILE)
	rider.position = local_position(start)
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
	terrain.assets.set_texture_asset(0, _surface("砂砾地表", Color("#b2c1ce") if theatre.snow else Color("#777c64"), 0.33, LOWLAND, NORMAL_LOWLAND))
	terrain.assets.set_texture_asset(1, _surface("裸露岩层", Color("#a1a8b0") if theatre.snow else Color("#85817b"), 0.42, ROCK, NORMAL_ROCK))
	terrain.material.set_shader_param("auto_base_texture", 0)
	terrain.material.set_shader_param("auto_overlay_texture", 1)
	terrain.set_clipmap_target(rider)
	for coord in opening_tiles(start, showcase):
		var heights: PackedFloat32Array = prepared[coord] if prepared.has(coord) else bake_tile(coord, seed_value)
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

func _add_environment(showcase: bool) -> void:
	var light_color := Color(climate.light[0], climate.light[1], climate.light[2])
	var sunset: bool = not climate.snow and seed_value != 116
	var direction := Vector3(-0.56, 0.145, -0.82).normalized() if sunset else Vector3(climate.sun[0], climate.sun[1], climate.sun[2]).normalized()
	if showcase:
		direction = Vector3(0.38, 0.15, 0.91).normalized()
	var env_node := WorldEnvironment.new()
	env_node.environment = Environment.new()
	var environment := env_node.environment
	flight_environment = environment
	var panorama := ShaderMaterial.new()
	cloud_material = panorama
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

func _surface(label: String, tint: Color, texture_scale: float, albedo: Texture2D, surface_normal: Texture2D) -> Terrain3DTextureAsset:
	var asset := Terrain3DTextureAsset.new()
	asset.set_asset_name(label)
	asset.set_albedo_texture(albedo)
	asset.set_normal_texture(surface_normal)
	asset.set_albedo_color(tint)
	asset.set_uv_scale(texture_scale)
	asset.set_detiling_rotation(0.68)
	asset.set_detiling_shift(0.55)
	asset.set_normal_depth(0.82)
	return asset

static func bake_tile(coord: Vector2i, seed_id: int) -> PackedFloat32Array:
	return ClassDB.class_call_static("SkyTerrainKernel", "height_tile", coord.x * TILE, coord.y * TILE, SIZE, STEP, seed_id)

func cell(local_point: Vector3) -> Vector2i:
	return origin + Vector2i(floori(local_point.x / TILE), floori(local_point.z / TILE))

func height(local_point: Vector3) -> float:
	if is_runway(local_point):
		return 26.2
	if terrain:
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
	strip.position = local_position(Vector3(-340.0, 26.2, 350.0))
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
	ocean = Ocean.new()
	add_child(ocean)
	ocean.setup(seed_value == 116)
	ocean.track(rider.position, Vector2(origin) * TILE, Vector3.ZERO, false)

func _activate(coord: Vector2i, heights: PackedFloat32Array) -> void:
	var region := Terrain3DRegion.new()
	region.region_size = SIZE
	region.vertex_spacing = STEP
	region.location = coord - origin
	region.height_map = Image.create_from_data(SIZE, SIZE, false, Image.FORMAT_RF, heights.to_byte_array())
	if neutral_control:
		region.control_map = neutral_control
		region.color_map = neutral_color
	else:
		region.sanitize_maps()
		neutral_control = region.control_map
		neutral_color = region.color_map
	region.calc_height_range()
	terrain.data.add_region(region, false)
	current[coord] = region
	cache[coord] = heights

func follow(p: Vector3, velocity: Vector3, dt := 1.0 / 90.0) -> Vector3:
	var here := cell(p)
	target = cell(p + velocity.limit_length(420.0) * 4.4)
	var delta := Vector3.ZERO
	if absi(here.x - origin.x) >= 4 or absi(here.y - origin.y) >= 4:
		var shift := here - origin
		delta = Vector3(shift.x * TILE, 0.0, shift.y * TILE)
		var previous := current
		current = {}
		for coord in previous:
			terrain.data.remove_regionl(coord - origin, false)
		origin = here
		cloud_material.set_shader_parameter("terrain_origin", Vector2(origin) * TILE)
		for coord in previous:
			if Vector2i(coord - here).length_squared() <= 20:
				var tile: Terrain3DRegion = previous[coord]
				tile.location = coord - origin
				tile.set_deleted(false)
				terrain.data.add_region(tile, false)
				current[coord] = tile
		if has_node("Runway"):
			get_node("Runway").position -= delta
		terrain.data.update_maps()
		terrain.snap()
	rider.position = p - delta
	ocean.track(rider.position, Vector2(origin) * TILE, velocity, true)
	stream_clock += dt
	if stream_clock >= STREAM_INTERVAL:
		stream_clock = 0.0
		_publish_and_prefetch(here)
		if coast_enabled:
			_update_shallows(rider.position)
		var low := 640.0 if seed_value == 116 else 1150.0
		var high := low + (1180.0 if seed_value == 116 else 780.0)
		var in_cloud := smoothstep(low, low + 170.0, p.y) * (1.0 - smoothstep(high - 215.0, high, p.y))
		flight_environment.fog_density = 0.000132 + 0.00019 * in_cloud
	return delta

func _update_shallows(at: Vector3) -> void:
	const PROBE_SIZE := 64
	const PROBE_STEP := 24.0
	const COVERAGE := PROBE_SIZE * PROBE_STEP
	if coast_job and not coast_job.is_alive():
		var image: Image = coast_job.wait_to_finish()
		coast_job = null
		ocean.set_shallows(image, coast_corner, COVERAGE)
	if coast_job or at.y > 1400.0 or jobs.size() >= MAX_JOBS:
		return
	var world_point := Vector2(at.x, at.z) + Vector2(origin) * TILE
	var next := Vector2i((world_point / 384.0).floor())
	if next == coast_cell:
		return
	coast_corner = Vector2(next) * 384.0 - Vector2.ONE * (COVERAGE * 0.5)
	var worker := Thread.new()
	if worker.start(_bake_shallows.bind(coast_corner, PROBE_SIZE, PROBE_STEP, seed_value)) == OK:
		coast_cell = next
		coast_job = worker

static func _bake_shallows(corner: Vector2, side: int, step: float, seed_id: int) -> Image:
	var heights: PackedFloat32Array = ClassDB.class_call_static("SkyTerrainKernel", "height_tile", corner.x, corner.y, side, step, seed_id)
	var depth := PackedByteArray()
	depth.resize(heights.size())
	for i in heights.size():
		depth[i] = clampi(roundi((heights[i] + 32.0) * 4.0), 0, 255)
	return Image.create_from_data(side, side, false, Image.FORMAT_R8, depth)

func set_quality(scale_value: float) -> void:
	cloud_material.set_shader_parameter("cloud_samples", 5 if scale_value < 0.74 else 7)
	ocean.set_quality(scale_value)

func _publish_and_prefetch(here: Vector2i) -> void:
	var changed := false
	for coord in jobs.keys():
		var thread: Thread = jobs[coord]
		if thread.is_alive():
			continue
		var heights: PackedFloat32Array = thread.wait_to_finish()
		jobs.erase(coord)
		if Vector2i(coord - here).length_squared() <= 21 and not current.has(coord):
			completed_tiles[coord] = heights
	var published := 0
	for coord in completed_tiles.keys():
		if Vector2i(coord - here).length_squared() > 21:
			completed_tiles.erase(coord)
			continue
		if published >= UPLOAD_BUDGET:
			break
		if not current.has(coord):
			_activate(coord, completed_tiles[coord])
			published += 1
			changed = true
		completed_tiles.erase(coord)
	if target != prefetch_centre:
		prefetch_centre = target
		candidate_tiles.clear()
		for z in range(-RADIUS, RADIUS + 1):
			for x in range(-RADIUS, RADIUS + 1):
				candidate_tiles.append(target + Vector2i(x, z))
		candidate_tiles.sort_custom(func(a: Vector2i, b: Vector2i): return (a - target).length_squared() < (b - target).length_squared())
	for key in candidate_tiles:
		if jobs.size() + completed_tiles.size() >= MAX_JOBS:
			break
		if (key - here).length_squared() > 21 or current.has(key) or jobs.has(key) or completed_tiles.has(key):
			continue
		if cache.has(key):
			completed_tiles[key] = cache[key]
		else:
			var task := Thread.new()
			if task.start(bake_tile.bind(key, seed_value)) == OK:
				jobs[key] = task
	for key in current.keys():
		if (key - here).length_squared() > 20:
			terrain.data.remove_regionl(key - origin, false)
			current.erase(key)
			changed = true
	if changed and cache.size() > 56:
		var distant: Array = cache.keys()
		distant.sort_custom(func(a: Vector2i, b: Vector2i): return (a - here).length_squared() > (b - here).length_squared())
		for key in distant:
			if cache.size() <= 56:
				break
			if not current.has(key):
				cache.erase(key)
	if changed:
		terrain.data.update_maps()

func _exit_tree() -> void:
	for task in jobs.values():
		task.wait_to_finish()
	if coast_job:
		coast_job.wait_to_finish()
