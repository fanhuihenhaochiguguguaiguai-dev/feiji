extends Node3D

enum Style { MISSILE, SOOT, VAPOUR }

const SLOTS := 72
const POINTS := 64
const LIFETIME := [3.10, 2.65, 0.92]
const SAMPLE_INTERVAL := [0.039, 0.058, 0.044]
const SHADER = preload("res://shaders/trail.gdshader")

class Trail:
	var key: int
	var row: int
	var style: int
	var pressure: float
	var first := 0
	var count := 0
	var tip := Vector3.ZERO
	var touched := -INF
	var sampled := -INF
	var closed := false

var emitters: Dictionary[int, Trail] = {}
var slots: Array[Trail] = []
var free_slots: Array[int] = []
var point_image: Image
var point_texture: ImageTexture
var material: ShaderMaterial
var instances: MultiMesh
var now := 0.0
var shift := Vector3.ZERO
var closing_tip := Vector3.INF
var pending := false
var urgent := false
var elapsed := 0.0

func setup(density: Texture3D, daylight: Color, sun: Vector3) -> void:
	slots.resize(SLOTS)
	for i in range(SLOTS - 1, -1, -1):
		free_slots.append(i)
	if DisplayServer.get_name() == "headless":
		return
	point_image = Image.create_empty(POINTS + 3, SLOTS, false, Image.FORMAT_RGBAF)
	point_texture = ImageTexture.create_from_image(point_image)
	material = ShaderMaterial.new()
	material.shader = SHADER
	material.set_shader_parameter("wake_points", point_texture)
	material.set_shader_parameter("density_field", density)
	material.set_shader_parameter("daylight", daylight)
	material.set_shader_parameter("sun_direction", sun)
	instances = MultiMesh.new()
	instances.transform_format = MultiMesh.TRANSFORM_3D
	instances.mesh = BoxMesh.new()
	instances.instance_count = SLOTS * POINTS
	for i in instances.instance_count:
		instances.set_instance_transform(i, Transform3D.IDENTITY)
	instances.visible_instance_count = 0
	instances.custom_aabb = AABB(Vector3(-25000, -6500, -25000), Vector3(50000, 20000, 50000))
	var draw := MultiMeshInstance3D.new()
	draw.multimesh = instances
	draw.material_override = material
	draw.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(draw)

func extend(key: int, at: Vector3, style: int, pressure: float) -> void:
	var trail := emitters.get(key) as Trail
	var point := at + shift
	var interval: float = SAMPLE_INTERVAL[style]
	if trail and style != Style.MISSILE and (now - trail.touched > interval * 3.5
			or trail.tip.distance_squared_to(point) > 110.0 * 110.0):
		close(key)
		trail = null
	if not trail:
		if free_slots.is_empty() or (style != Style.MISSILE and free_slots.size() <= 16):
			return
		trail = Trail.new()
		trail.key = key
		trail.row = free_slots.pop_back()
		trail.style = style
		trail.pressure = pressure
		slots[trail.row] = trail
		emitters[key] = trail
		urgent = true
	trail.tip = point
	trail.touched = now
	if now - trail.sampled >= interval:
		_sample(trail)
	pending = true

func close(key: int, contact := Vector3.INF) -> void:
	var trail := emitters.get(key) as Trail
	if not trail:
		return
	if contact.is_finite():
		trail.tip = contact + shift
		trail.touched = now
		closing_tip = contact
	trail.closed = true
	emitters.erase(key)
	urgent = true
	pending = true

func _sample(trail: Trail) -> void:
	if point_image:
		var x := (trail.first + trail.count) % POINTS
		var p := trail.tip
		point_image.set_pixel(x, trail.row, Color(p.x, p.y, p.z, now))
	if trail.count < POINTS:
		trail.count += 1
	else:
		trail.first = (trail.first + 1) % POINTS
	trail.sampled = now

func advance(dt: float) -> void:
	now += dt
	if free_slots.size() == SLOTS and not pending:
		return
	elapsed += dt
	if instances:
		material.set_shader_parameter("wake_clock", now)
	if elapsed < 1.0 / 30.0 and not urgent:
		return
	elapsed = 0.0
	urgent = false
	var dense := 0
	for trail in slots:
		if not trail:
			continue
		if not trail.closed and trail.style != Style.MISSILE and now - trail.touched > 0.22:
			emitters.erase(trail.key)
			trail.closed = true
		if trail.closed and now - trail.touched >= LIFETIME[trail.style]:
			free_slots.append(trail.row)
			slots[trail.row] = null
			pending = true
			continue
		if point_image and trail.count > 0:
			if pending:
				point_image.set_pixel(POINTS, trail.row, Color(trail.first, trail.count, trail.style, trail.pressure))
				var p := trail.tip
				point_image.set_pixel(POINTS + 1, trail.row, Color(p.x, p.y, p.z, trail.touched))
				point_image.set_pixel(POINTS + 2, dense, Color(trail.row, 0, 0, 0))
			dense += 1
	if instances and pending:
		if dense > 0:
			point_texture.update(point_image.duplicate() as Image)
		instances.visible_instance_count = dense * POINTS
	pending = false

func rebase(delta: Vector3) -> void:
	shift += delta
	if closing_tip.is_finite():
		closing_tip -= delta
	if material:
		material.set_shader_parameter("world_shift", shift)

func prime(at: Vector3) -> void:
	if instances:
		extend(-1, at, Style.MISSILE, 0.04)
		extend(-1, at + Vector3.FORWARD * 0.18, Style.MISSILE, 0.04)
		advance(0.0)

func end_prime() -> void:
	if not emitters.has(-1):
		return
	var trail := emitters[-1]
	emitters.erase(-1)
	slots[trail.row] = null
	free_slots.append(trail.row)
	urgent = true
	pending = true
	advance(0.0)
