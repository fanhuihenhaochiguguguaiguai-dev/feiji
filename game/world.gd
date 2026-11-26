extends Node3D

const SIZE := 256
const STEP := 6.0
const TILE := SIZE * STEP
const APRON_HEIGHT := 150.0
const MAX_JOBS := 3
const STREAM_INTERVAL := 0.12
const UPLOAD_BUDGET := 2
const RADIUS := 2
const RESIDENT_MIN := Vector2i(-20, -24)
const RESIDENT_SIDE := 48
const RESIDENT_SHADER = preload("res://shaders/terrain_resident.gdshader")
const SKY = preload("res://shaders/sky.gdshader")
const Ocean = preload("res://game/ocean.gd")
const ROCK = preload("res://assets/environment/rock-height.webp")
const LOWLAND = preload("res://assets/environment/sand-height.webp")
const NORMAL_ROCK = preload("res://assets/environment/rock-rough.webp")
const NORMAL_LOWLAND = preload("res://assets/environment/sand-rough.webp")
const ATMOSPHERE = preload("res://assets/environment/air-scattering.png")
const AIR_COLUMN = preload("res://assets/environment/air-column.png")
const PANORAMA_RANGE := 2.34
const FIELDS := {413:"bay", 704:"frost"}
const FINE_PACK_MAGIC := 0x34465453
const FINE_TILE_BYTES := 4 + SIZE * SIZE * 2
static var relief_ready := {}

const CLOUD_SIZE := Vector2i(96, 64)
const CLOUD_LAYERS := 32
const CLOUD_PERIOD := Vector2(10100.0, 7450.0)
static var cloud_slices: Array[Image] = []
static var cloud_field: ImageTexture3D

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
var publish_interval := STREAM_INTERVAL
var background_budget := UPLOAD_BUDGET
var completed_tiles: Dictionary = {}
var neutral_control: Image
var neutral_color: Image
var relief_color: Image
var fine_tiles := {}
var prefetch_centre := Vector2i.MAX
var prefetch_here := Vector2i.MAX
var prefetch_heading := Vector2i.MAX
var candidate_tiles: Array[Vector2i] = []
var upload_cost_usec := 0.0
var coast_job: Thread
var coast_cell := Vector2i.MAX
var coast_corner := Vector2.ZERO
var coast_enabled := false
var cloud_material: ShaderMaterial
var flight_environment: Environment
var cloud_drift := Vector2.ZERO
var local_cloud := 0.0
var flight_view: Camera3D
var resident: Node3D
var residency: Image
var detailed_regions: ImageTexture

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
	flight_view = camera
	RenderingServer.global_shader_parameter_set("cloud_drift", Vector2.ZERO)
	coast_enabled = DisplayServer.get_name() != "headless"
	seed_value = int(theatre.seed)
	prepare_relief(seed_value)
	fine_tiles = fine_tile_index(seed_value)
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
	# Let the baked geology carry distant structure. The alpine scan repeats at the scale of individual rocks.
	terrain.assets.set_texture_asset(1, _surface("裸露岩层", Color("#d9dfe5") if snow else (Color("#a4b2c0") if coast else Color("#a6aaa5")), 0.57 if snow else 0.155, ROCK, NORMAL_ROCK))
	# The overlay collects on flatter surfaces. Exposed faces use the scan in slot 1.
	var exposed_rock := coast or snow
	terrain.material.set_shader_param("auto_base_texture", 1 if exposed_rock else 0)
	terrain.material.set_shader_param("auto_overlay_texture", 0 if exposed_rock else 1)
	if exposed_rock:
		terrain.material.set_shader_param("auto_slope", 3.55 if snow else 2.7)
		terrain.material.set_shader_param("auto_height_reduction", 0.0 if snow else 0.026)
	terrain.set_clipmap_target(rider)
	for coord in opening_tiles(start):
		var heights: PackedFloat32Array = prepared[coord] if prepared.has(coord) else read_tile(coord, seed_value, fine_tiles)
		_activate(coord, heights)
	terrain.data.update_maps()
	terrain.set_camera(camera)
	terrain.snap()
	if coast_enabled:
		_add_resident_ground()
	_make_sea(camera)
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
		var parameters := {"panorama":image, "panorama_range":PANORAMA_RANGE, "density":_load_cloud_field(), "scattering":ATMOSPHERE,
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
	env.fog_density = 0.000064 if storm else 0.000037
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
		fill.light_color = Color("#d5e4f2")
		fill.light_energy = 0.76
		host.add_child(fill)
		fill.rotation_degrees = Vector3(-31, -42, 0)
	return env

static func _load_cloud_field() -> ImageTexture3D:
	if cloud_field:
		return cloud_field
	var atlas := (load("res://assets/environment/cloud-volume.png") as Texture2D).get_image()
	atlas.convert(Image.FORMAT_R8)
	for layer in CLOUD_LAYERS:
		cloud_slices.append(atlas.get_region(Rect2i(Vector2i(layer % 8, layer / 8) * CLOUD_SIZE, CLOUD_SIZE)))
	cloud_field = ImageTexture3D.new()
	cloud_field.create(Image.FORMAT_R8, CLOUD_SIZE.x, CLOUD_SIZE.y, CLOUD_LAYERS, false, cloud_slices)
	return cloud_field

func _update_cloud_visibility(at: Vector3, dt: float) -> void:
	cloud_drift += Vector2(8.0, 4.0) * dt
	RenderingServer.global_shader_parameter_set("cloud_drift", cloud_drift)
	var storm := seed_value == 116
	var height := (at.y - (680.0 if storm else 1080.0)) / (1260.0 if storm else 820.0)
	var sample_density := 0.0
	if height > 0.0 and height < 1.0:
		var point := (Vector2(at.x, at.z) + Vector2(origin) * TILE + cloud_drift) / CLOUD_PERIOD
		var coords := Vector2i((point.posmodv(Vector2.ONE) * Vector2(CLOUD_SIZE)).floor())
		var level := height * (CLOUD_LAYERS - 1)
		var index := floori(level)
		var raw := lerpf(cloud_slices[index].get_pixelv(coords).r, cloud_slices[index + 1].get_pixelv(coords).r, level - index)
		sample_density = smoothstep(0.20, 0.66, raw * (1.34 if storm else 1.0))
	local_cloud = lerpf(local_cloud, sample_density, 1.0 - exp(-dt * 4.5))
	var clear_fog := 0.000064 if storm else 0.000037
	flight_environment.fog_density = clear_fog * lerpf(1.0, 0.58, smoothstep(1800.0, 4500.0, at.y)) + local_cloud * 0.00135

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

static func fine_tile_index(seed_id: int) -> Dictionary:
	var file := FileAccess.open("res://assets/environment/detail-%d.terrainpack" % seed_id, FileAccess.READ)
	if not file or file.get_32() != FINE_PACK_MAGIC or file.get_16() != SIZE or file.get_16() != int(STEP):
		return {}
	var count := file.get_32()
	var payload := 12 + count * 12
	if count > 512 or payload > file.get_length():
		return {}
	var index := {}
	for i in count:
		var coord := Vector2i(file.get_32(), file.get_32())
		var size := file.get_32()
		if size == 0 or size > FINE_TILE_BYTES + 1024 or payload + size > file.get_length():
			return {}
		index[coord] = Vector2i(payload, size)
		payload += size
	return index

static func read_tile(coord: Vector2i, seed_id: int, index: Dictionary) -> PackedFloat32Array:
	if index.has(coord):
		var file := FileAccess.open("res://assets/environment/detail-%d.terrainpack" % seed_id, FileAccess.READ)
		if file:
			var entry: Vector2i = index[coord]
			file.seek(entry.x)
			var data := file.get_buffer(entry.y).decompress(FINE_TILE_BYTES, FileAccess.COMPRESSION_ZSTD)
			if data.size() == FINE_TILE_BYTES:
				return ClassDB.class_call_static("SkyTerrainKernel", "decode_tile", data, SIZE, data.size())
	return bake_tile(coord, seed_id)

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

func _make_sea(camera: Camera3D) -> void:
	ocean = Ocean.new()
	add_child(ocean)
	ocean.setup(climate, camera)
	_set_aerial_transport(ocean.material)
	ocean.track(rider.position, Vector2(origin) * TILE, Vector3.ZERO, false)

func _add_resident_ground() -> void:
	var compiled := load("res://assets/environment/world-%d.scn" % seed_value) as PackedScene
	resident = compiled.instantiate() as Node3D
	var material := ShaderMaterial.new()
	material.shader = RESIDENT_SHADER
	_set_aerial_transport(material)
	material.set_shader_parameter("first_region", Vector2(RESIDENT_MIN))
	material.set_shader_parameter("region_span", TILE)
	residency = Image.create_empty(RESIDENT_SIDE, RESIDENT_SIDE, false, Image.FORMAT_R8)
	detailed_regions = ImageTexture.create_from_image(residency)
	material.set_shader_parameter("detailed_regions", detailed_regions)
	for chunk: MeshInstance3D in resident.get_children():
		chunk.material_override = material
	add_child(resident)
	_sync_resident_ground()

func _set_aerial_transport(material: ShaderMaterial) -> void:
	material.set_shader_parameter("air_column", AIR_COLUMN)
	material.set_shader_parameter("air_color", flight_environment.fog_light_color)
	material.set_shader_parameter("solar_color", cloud_material.get_shader_parameter("sun_color"))
	material.set_shader_parameter("solar_direction", cloud_material.get_shader_parameter("sun_direction"))
	material.set_shader_parameter("aerosol_extinction", 0.000043 if seed_value == 116 else 0.000024)

func _sync_resident_ground() -> void:
	if not resident:
		return
	resident.position = Vector3(-origin.x * TILE, 0.0, -origin.y * TILE)
	residency.fill(Color.BLACK)
	for tile: Vector2i in current:
		var index := tile - RESIDENT_MIN
		if index.x >= 0 and index.y >= 0 and index.x < RESIDENT_SIDE and index.y < RESIDENT_SIDE:
			residency.set_pixelv(index, Color.RED)
	detailed_regions.update(residency)

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
			region.color_map = colors.get_region(Rect2i(6, 6, SIZE, SIZE))
	region.calc_height_range()
	terrain.data.add_region(region, false)
	current[coord] = region
	cache[coord] = heights

func follow(p: Vector3, velocity: Vector3, dt := 1.0 / 90.0) -> Vector3:
	var here := cell(p)
	var runway_time := lerpf(3.3, 5.0, smoothstep(130.0, 415.0, velocity.length()))
	var load_margin := minf(1.8, upload_cost_usec * 0.00032)
	target = cell(p + velocity.limit_length(510.0) * (runway_time + load_margin))
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
		_sync_resident_ground()
		ocean.defer_compute = true
	rider.position = p - delta
	ocean.track(rider.position, Vector2(origin) * TILE, velocity, true)
	stream_clock += dt
	if stream_clock >= publish_interval:
		var update_span := stream_clock
		stream_clock = 0.0
		if delta == Vector3.ZERO:
			_publish_and_prefetch(here)
		if coast_enabled:
			_update_shallows(rider.position)
		_update_cloud_visibility(rider.position, update_span)
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

func set_background_budget(over_budget: bool, hot: bool) -> void:
	publish_interval = 0.18 if hot else (0.15 if over_budget else STREAM_INTERVAL)
	background_budget = 1 if hot or over_budget else UPLOAD_BUDGET

func _publish_and_prefetch(here: Vector2i) -> void:
	var changed := false
	var upload_started := Time.get_ticks_usec()
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
		if published >= (1 if upload_cost_usec > 3000.0 else background_budget):
			break
		if not current.has(coord):
			_activate(coord, completed_tiles[coord])
			published += 1
			changed = true
		completed_tiles.erase(coord)
	var direction := Vector2(-flight_view.basis.z.x, -flight_view.basis.z.z).normalized()
	var heading_bucket := Vector2i((direction * 2.0).round())
	if target != prefetch_centre or here != prefetch_here or heading_bucket != prefetch_heading:
		prefetch_centre = target
		prefetch_here = here
		prefetch_heading = heading_bucket
		candidate_tiles.clear()
		for z in range(-RADIUS, RADIUS + 1):
			for x in range(-RADIUS, RADIUS + 1):
				var relative := Vector2i(x, z)
				for centre: Vector2i in [here, target]:
					var tile := centre + relative
					if not candidate_tiles.has(tile):
						candidate_tiles.append(tile)
		candidate_tiles.sort_custom(func(a: Vector2i, b: Vector2i):
			var ascore := minf((a - here).length_squared(), 1.2 + (a - target).length_squared()) - Vector2(a - here).dot(direction) * 0.62
			var bscore := minf((b - here).length_squared(), 1.2 + (b - target).length_squared()) - Vector2(b - here).dot(direction) * 0.62
			return ascore < bscore)
	for key in candidate_tiles:
		if jobs.size() + completed_tiles.size() >= MAX_JOBS:
			break
		if (key - here).length_squared() > 21 or current.has(key) or jobs.has(key) or completed_tiles.has(key):
			continue
		if cache.has(key):
			completed_tiles[key] = cache[key]
		else:
			var task := Thread.new()
			if task.start(read_tile.bind(key, seed_value, fine_tiles)) == OK:
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
		_sync_resident_ground()
		ocean.defer_compute = true
		var upload_usec := float(Time.get_ticks_usec() - upload_started) / maxf(1.0, published)
		upload_cost_usec = lerpf(upload_cost_usec, upload_usec, 0.20)

func _exit_tree() -> void:
	for task in jobs.values():
		task.wait_to_finish()
	if coast_job:
		coast_job.wait_to_finish()
