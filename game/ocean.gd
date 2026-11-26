extends MeshInstance3D

const SURFACE = preload("res://shaders/sea.gdshader")
const CLIPMAP = preload("res://addons/ocean_waves/clipmap_low.obj")
const NOISE = preload("res://assets/surface/water.png")
const WATER_RESPONSE = preload("res://assets/environment/water-response.png")

var material := ShaderMaterial.new()
var fft: WaveGenerator
var maps: Array[WaveCascadeParameters] = []
var displacement: Texture2DArrayRD
var normals: Texture2DArrayRD
var elapsed := 0.0
var warmed := false
var spectrum_available := false
var spectrum_weight := 0.0
var defer_compute := false
var cadence := 0.055
var view: Camera3D
var origin := Vector2.ZERO
var wake := Vector4(0, 0, 1, 0)
var wake_strength := 0.0
var wake_sent := Vector4.ZERO
var strength_sent := 0.0
var shallows: ImageTexture

func setup(theatre: Dictionary, camera: Camera3D) -> void:
	view = camera
	var windy: bool = int(theatre.seed) == 116
	var hue: Array = theatre.sea
	mesh = CLIPMAP
	material.shader = SURFACE
	material.set_shader_parameter("shore_noise", NOISE)
	material.set_shader_parameter("water_response", WATER_RESPONSE)
	material.set_shader_parameter("deep", Color(hue[0] * 0.76, hue[1] * 0.79, hue[2] * 0.79))
	material_override = material
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	extra_cull_margin = 18000.0
	if _supports_fft():
		for i in 2:
			var wave := WaveCascadeParameters.new()
			wave.spectrum_seed = Vector2i(883 + i * 91, -412 + i * 217)
			wave.tile_length = Vector2(160.0, 160.0) if i == 0 else Vector2(39.0, 39.0)
			wave.wind_speed = (14.0 if windy else 10.0) + i * 1.9
			wave.fetch_length = 105.0 if i == 0 else 46.0
			wave.wind_direction = 31.0 + i * 12.0
			wave.detail = 0.84
			wave.whitecap = 0.68
			wave.time = 120.0 + i * PI
			maps.append(wave)
		spectrum_available = true

func _supports_fft() -> bool:
	var device := RenderingServer.get_rendering_device()
	if not device:
		return false
	var usage := RenderingDevice.TEXTURE_USAGE_STORAGE_BIT | RenderingDevice.TEXTURE_USAGE_SAMPLING_BIT
	return device.texture_is_format_supported_for_usage(RenderingDevice.DATA_FORMAT_R16G16B16A16_SFLOAT, usage) and device.limit_get(RenderingDevice.LIMIT_MAX_COMPUTE_WORKGROUP_INVOCATIONS) >= 256

func _start_spectrum() -> void:
	fft = WaveGenerator.new()
	fft.map_size = 128
	add_child(fft)
	fft.init_gpu(maps.size())
	var height_rid: RID = fft.descriptors[&"displacement_map"].rid
	var normal_rid: RID = fft.descriptors[&"normal_map"].rid
	if not height_rid.is_valid() or not normal_rid.is_valid():
		fft.queue_free()
		fft = null
		spectrum_available = false
		return
	displacement = Texture2DArrayRD.new()
	normals = Texture2DArrayRD.new()
	displacement.texture_rd_rid = height_rid
	normals.texture_rd_rid = normal_rid
	material.set_shader_parameter("spectral_displacement", displacement)
	material.set_shader_parameter("spectral_normals", normals)
	fft.update(0.03, maps)
	elapsed = -0.12

func set_quality(scale_value: float) -> void:
	cadence = 0.095 if scale_value < 0.74 else 0.055

func set_shallows(tile: Image, corner: Vector2, size_m: float) -> void:
	if shallows:
		shallows.update(tile)
	else:
		shallows = ImageTexture.create_from_image(tile)
		material.set_shader_parameter("coast_depth", shallows)
	material.set_shader_parameter("coast_area", Vector4(corner.x, corner.y, 1.0 / size_m, 1.0))

func track(chase: Vector3, offset: Vector2, velocity: Vector3, wake_active: bool) -> void:
	var snapped := (Vector2(chase.x, chase.z) / 8.0).floor() * 8.0
	if position.x != snapped.x or position.z != snapped.y:
		position = Vector3(snapped.x, 0.0, snapped.y)
	if origin != offset:
		origin = offset
		material.set_shader_parameter("world_offset", origin)
	var heading := Vector2(velocity.x, velocity.z).normalized()
	wake = Vector4(chase.x + offset.x, chase.z + offset.y, heading.x, heading.y)
	wake_strength = (1.0 - smoothstep(5.0, 32.0, chase.y)) * smoothstep(28.0, 110.0, velocity.length()) if wake_active else 0.0

func _process(dt: float) -> void:
	var postponed := defer_compute
	defer_compute = false
	if wake_strength > 0.0 and not wake_sent.is_equal_approx(wake):
		wake_sent = wake
		material.set_shader_parameter("wake", wake)
	if not is_equal_approx(strength_sent, wake_strength):
		strength_sent = wake_strength
		material.set_shader_parameter("wake_strength", wake_strength)
	if not spectrum_available:
		return
	var height := maxf(0.0, view.position.y)
	var upward := -view.basis.z.y
	var view_weight := 1.0 - smoothstep(0.40, 0.65, upward)
	var visible_weight := (1.0 - smoothstep(820.0, 2400.0, height)) * view_weight
	if not fft:
		if visible_weight <= 0.06 or postponed:
			return
		_start_spectrum()
		if not fft:
			return
	elapsed += dt
	if not warmed and elapsed >= 0.0 and fft.pass_num_cascades_remaining == 0:
		warmed = true
		material.set_shader_parameter("spectral_enabled", true)
	var next_weight := move_toward(spectrum_weight, visible_weight if warmed else 0.0, dt * 2.8)
	if next_weight != spectrum_weight:
		spectrum_weight = next_weight
		material.set_shader_parameter("spectral_weight", spectrum_weight)
	if visible_weight <= 0.01 and spectrum_weight <= 0.01:
		return
	var interval := cadence * lerpf(1.0, 3.2, smoothstep(90.0, 1440.0, height))
	if postponed or elapsed < interval or fft.pass_num_cascades_remaining != 0:
		return
	fft.update(elapsed, maps)
	elapsed = 0.0

func _exit_tree() -> void:
	material.set_shader_parameter("spectral_enabled", false)
	material.set_shader_parameter("spectral_displacement", null)
	material.set_shader_parameter("spectral_normals", null)
	if displacement:
		displacement.texture_rd_rid = RID()
	if normals:
		normals.texture_rd_rid = RID()
