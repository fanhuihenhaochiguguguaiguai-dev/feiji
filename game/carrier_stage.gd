extends Node3D

const GEOMETRY = preload("res://assets/studio/carrier-stage.glb")
const SAMPLE = preload("res://assets/studio/reference-fighter.glb")
const WORLD = preload("res://game/world.gd")
const OCEAN = preload("res://game/ocean.gd")
const DECK_Y := 12.4

var sea: MeshInstance3D

func setup(camera: Camera3D, theatre: Dictionary) -> void:
	var bearing := Vector3(-0.70, 0.081, -0.70).normalized()
	var sky := ShaderMaterial.new()
	sky.shader = preload("res://shaders/carrier_sky.gdshader")
	sky.set_shader_parameter("panorama",preload("res://assets/studio/carrier-sunset.hdr"))
	sky.set_shader_parameter("sun_direction",bearing)
	sky.set_shader_parameter("panorama_offset",0.6123047 - (atan2(bearing.x,-bearing.z)/TAU+0.5))
	var environment := WORLD.add_environment(self, theatre, sky)
	environment.ambient_light_energy = 1.16
	environment.ambient_light_sky_contribution = 0.82
	environment.tonemap_exposure = 1.02
	environment.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	environment.fog_enabled = true
	environment.fog_sky_affect = 0.0
	environment.fog_light_color = Color("#9ab7d5")
	environment.fog_density = 0.000031
	environment.fog_aerial_perspective = 0.14
	var lights := find_children("*", "DirectionalLight3D", false, false)
	var key := lights[0] as DirectionalLight3D
	key.look_at_from_position(bearing * 100.0, Vector3.ZERO)
	key.light_energy = 1.58
	key.light_color = Color("#ffbd7a")
	key.directional_shadow_max_distance = 145.0
	var sky_fill := lights[1] as DirectionalLight3D
	sky_fill.light_energy = 1.13
	sky_fill.light_color = Color("#d3e1f1")
	sky_fill.look_at_from_position(Vector3(0.72, 0.65, 0.28) * 12.0, Vector3.ZERO)
	var stage := GEOMETRY.instantiate() as Node3D
	stage.name = "CarrierArchitecture"
	stage.position.y = DECK_Y
	add_child(stage)
	var deck := stage.find_child("Flight deck", true, false) as MeshInstance3D
	if deck:
		var wet := ShaderMaterial.new()
		wet.shader = preload("res://shaders/carrier_deck.gdshader")
		wet.set_shader_parameter("scan_color", preload("res://assets/studio/tarmac.webp"))
		wet.set_shader_parameter("scan_normal", preload("res://assets/studio/tarmac-normal.png"))
		wet.set_shader_parameter("scan_orm", preload("res://assets/studio/tarmac-orm.png"))
		deck.material_override = wet
		deck.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var coast := stage.find_child("SurveyedCoastline", true, false) as Node3D
	if coast:
		coast.reparent(self, false)
		for ridge: MeshInstance3D in coast.find_children("*", "MeshInstance3D", true, false):
			ridge.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	sea = OCEAN.new()
	sea.name = "CarrierOcean"
	add_child(sea)
	sea.setup(theatre, camera, false)
	var water: ShaderMaterial = sea.material
	water.set_shader_parameter("air_column", WORLD.AIR_COLUMN)
	water.set_shader_parameter("air_color", Color("#9caac2"))
	water.set_shader_parameter("solar_direction", bearing)
	water.set_shader_parameter("solar_color", key.light_color)
	sea.set_process(false)
	var dome := ReflectionProbe.new()
	dome.name = "FlightDeckReflection"
	dome.position = Vector3(0, DECK_Y + 5.2, 0)
	dome.size = Vector3(84, 35, 124)
	dome.box_projection = true
	dome.max_distance = 185.0
	dome.cull_mask = 1
	dome.intensity = 0.81
	add_child(dome)
	_practical(Vector3(-23.8, DECK_Y + 6.1, 19.7), Color("#76ccff"), 7.2, 13.0)
	_practical(Vector3(-24.1, DECK_Y + 4.65, 5.3), Color("#ffd098"), 8.3, 16.2)
	_practical(Vector3(2.4, DECK_Y + 1.17, -7.2), Color("#629fff"), 1.8, 13.8)

func follow_view(point: Vector3) -> void:
	sea.track(point, Vector2.ZERO, Vector3.ZERO, false)

func _practical(at: Vector3, tint: Color, power: float, radius: float) -> void:
	var fixture := OmniLight3D.new()
	fixture.position = at
	fixture.light_color = tint
	fixture.light_energy = power
	fixture.omni_range = radius
	add_child(fixture)
