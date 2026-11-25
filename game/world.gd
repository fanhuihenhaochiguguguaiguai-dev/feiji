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
const ROCK = preload("res://assets/environment/rock-height.webp")
const LOWLAND = preload("res://assets/environment/sand-height.webp")
const NORMAL_ROCK = preload("res://assets/environment/rock-rough.webp")
const NORMAL_LOWLAND = preload("res://assets/environment/sand-rough.webp")
const ATMOSPHERE = preload("res://assets/environment/air-scattering.png")
const PANORAMA_RANGE := 2.34
const FIELDS := {413:"bay", 704:"frost"}
static var relief_ready := {}

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
var relief_color: Image
var prefetch_centre := Vector2i.MAX
var candidate_tiles: Array[Vector2i] = []
var coast_job: Thread
var coast_cell := Vector2i.MAX
var coast_corner := Vector2.ZERO
var coast_enabled := false
var cloud_material: ShaderMaterial
var flight_environment: Environment

static func opening_tiles(start: Vector3) -> Array[Vector2i]:
	var centre := Vector2i(floori(start.x / TILE), floori(start.z / TILE))
	var coordinates: Array[Vector2i] = []
	for z in range(-2, 2):
		for x in range(-2, 3):
			coordinates.append(centre + Vector2i(x, z))
	return coordinates

func local_position(absolute_position: Vector3) -> Vector3:
	return absolute_position - Vector3(origin.x * TILE, 0.0, origin.y * TILE)

func configure(theatre: Dictionary, camera: Camera3D, start: Vector3, prepared := {}) -> void:
	climate = theatre
	coast_enabled = DisplayServer.get_name() != "headless"
	seed_value = int(theatre.seed)
	prepare_relief(seed_value)
	if FIELDS.has(seed_value):
		relief_color = (load("res://assets/environment/%s-color.png" % FIELDS[seed_value]) as Texture2D).get_image()
	flight_environment = add_environment(self, theatre)
	cloud_material = flight_environment.sky.sky_material
	rider = Node3D.new()
	add_child(rider)
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
	terrain.material.world_background = Terrain3DMaterial.NONE
	terrain.material.set_auto_shader_enabled(true)
	terrain.material.set_dual_scaling_enabled(false)
	terrain.material.set_shader_param("blend_sharpness", 0.26)
	terrain.material.texture_filtering = Terrain3DMaterial.LINEAR_ANISOTROPIC
	var snow: bool = theatre.snow
	var coast := seed_value == 413
	var ground: Texture2D = load("res://assets/environment/snow-height.webp") if snow else LOWLAND
	terrain.assets.set_texture_asset(0, _surface("积雪" if snow else "砂砾地表", Color("#fafcff") if snow else (Color("#a5b2b9") if coast else Color("#b3b9a8")), 0.14, ground, NORMAL_LOWLAND, 0.19 if snow else 0.45))
	terrain.assets.set_texture_asset(1, _surface("裸露岩层", Color("#a8b6ca") if snow else (Color("#a4b2c0") if coast else Color("#a6aaa5")), 0.155, ROCK, NORMAL_ROCK))
	# Terrain3D's automatic overlay weight rises on flatter surfaces. Alpine rock exposure is baked.
	terrain.material.set_shader_param("auto_base_texture", 1 if coast else 0)
	terrain.material.set_shader_param("auto_overlay_texture", 0 if snow or coast else 1)
	if coast:
		terrain.material.set_shader_param("auto_slope", 2.7)
		terrain.material.set_shader_param("auto_height_reduction", 0.026)
	terrain.set_clipmap_target(rider)
	for coord in opening_tiles(start):
		var heights: PackedFloat32Array = prepared[coord] if prepared.has(coord) else bake_tile(coord, seed_value)
		_activate(coord, heights)
	terrain.data.update_maps()
	terrain.set_camera(camera)
	terrain.snap()
	_make_sea()
	_make_runway()

static func prepare_relief(seed_id: int) -> void:
	if relief_ready.has(seed_id) or not FIELDS.has(seed_id):
		return
	const BYTES := 1025 * 1025 * 2
	var elevations := FileAccess.get_file_as_bytes("res://assets/environment/%s.height" % FIELDS[seed_id]).decompress(BYTES, FileAccess.COMPRESSION_GZIP)
	if elevations.size() == BYTES:
		ClassDB.class_call_static("SkyTerrainKernel", "load_relief", elevations, elevations.size(), seed_id)
		relief_ready[seed_id] = true

static func add_environment(host: Node3D, theatre: Dictionary, studio := false) -> Environment:
	var storm: bool = int(theatre.seed) == 116
	var daylight: bool = theatre.snow
	var light := Color(1.0, 0.81, 0.65) if studio else (Color(1.0, 0.956, 0.88) if daylight else Color(1.0, 0.87, 0.73))
	if storm:
		light = Color(0.76, 0.83, 0.95)
	var air := Color("#9eb9d2") if daylight else (Color("#788eaa") if storm else Color("#849cb5"))
	var bearing := Vector3(-0.88, 0.31, -0.36).normalized()
	var photo_sun := 0.595
	if daylight:
		bearing = Vector3(-0.74, 0.59, 0.33).normalized()
		photo_sun = 0.595
	elif storm:
		bearing = Vector3(0.50, 0.218, -0.84).normalized()
		photo_sun = 0.59
	if studio:
		bearing = Vector3(0.47, 0.11, 0.876).normalized()
		photo_sun = 0.600
	var yaw := photo_sun - (atan2(bearing.x, -bearing.z) / TAU + 0.5)
	var image: Texture2D = load("res://assets/environment/%s.png" % ("sunset" if studio else ("dusk" if storm else "day")))
	var env_node := WorldEnvironment.new()
	var env := Environment.new()
	env_node.environment = env
	env.background_mode = Environment.BG_SKY
	env.sky = Sky.new()
	env.sky.process_mode = Sky.PROCESS_MODE_QUALITY if studio else Sky.PROCESS_MODE_INCREMENTAL
	env.sky.radiance_size = Sky.RADIANCE_SIZE_128
	if studio:
		var photo := PanoramaSkyMaterial.new()
		photo.panorama = image
		photo.energy_multiplier = 0.34 * PANORAMA_RANGE
		env.sky.sky_material = photo
		env.sky_rotation.y = yaw * TAU
	else:
		var panorama := ShaderMaterial.new()
		panorama.shader = SKY
		var parameters := {"panorama":image, "panorama_range":PANORAMA_RANGE, "density":DENSITY, "scattering":ATMOSPHERE,
			"sun_direction":bearing, "sun_color":light, "air_color":air, "panorama_offset":yaw, "storm":float(storm)}
		for key in parameters:
			panorama.set_shader_parameter(key, parameters[key])
		env.sky.sky_material = panorama
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_sky_contribution = 0.83
	env.ambient_light_energy = 0.82 if studio else (0.70 if daylight else 0.78)
	env.tonemap_mode = Environment.TONE_MAPPER_ACES
	env.tonemap_exposure = 0.97 if studio else 1.02
	env.fog_enabled = not studio
	env.fog_light_color = air
	env.fog_sun_scatter = 0.045
	env.fog_density = 0.00008
	env.fog_aerial_perspective = 0.46
	host.add_child(env_node)
	var sun := DirectionalLight3D.new()
	sun.light_color = light
	sun.light_energy = (0.78 if storm else 1.34) if not studio else 1.18
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 160.0 if studio else 450.0
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS
	host.add_child(sun)
	sun.look_at_from_position(bearing * 100.0, Vector3.ZERO)
	if studio:
		var fill := DirectionalLight3D.new()
		fill.light_color = Color("#b9d7fa")
		fill.light_energy = 0.59
		host.add_child(fill)
		fill.rotation_degrees = Vector3(-31, -42, 0)
	return env

func _surface(label: String, tint: Color, texture_scale: float, albedo: Texture2D, surface_normal: Texture2D, normal_strength := 0.45) -> Terrain3DTextureAsset:
	var asset := Terrain3DTextureAsset.new()
	asset.set_asset_name(label)
	asset.set_albedo_texture(albedo)
	asset.set_normal_texture(surface_normal)
	asset.set_albedo_color(tint)
	asset.set_uv_scale(texture_scale)
	asset.set_detiling_rotation(0.0)
	asset.set_detiling_shift(0.0)
	asset.set_normal_depth(normal_strength)
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
	ocean.setup(climate)
	ocean.material.set_shader_parameter("air_color", flight_environment.fog_light_color)
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
	if relief_color:
		const SAMPLES := SIZE / 4
		var source := Rect2i(coord * SAMPLES + Vector2i(255, 255), Vector2i.ONE * (SAMPLES + 2))
		if Rect2i(Vector2i.ZERO, relief_color.get_size()).encloses(source):
			var colors := relief_color.get_region(source)
			colors.resize(SIZE + 8, SIZE + 8, Image.INTERPOLATE_BILINEAR)
			region.color_map = colors.get_region(Rect2i(2, 2, SIZE, SIZE))
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
		flight_environment.fog_density = 0.00008 + 0.00017 * in_cloud
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
	cloud_material.set_shader_parameter("cloud_samples", 3 if scale_value < 0.74 else 4)
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
