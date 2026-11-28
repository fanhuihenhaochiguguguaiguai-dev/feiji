extends CanvasLayer

const Screen = preload("res://game/loading_screen.gd")
const Data = preload("res://game/catalogue.gd")
const Pilot = preload("res://game/profile.gd")
const MAIN := "res://scenes/main.tscn"
const STUDIO := "res://assets/studio/carrier-stage.glb"

var presentation := Screen.new()
var retry := Button.new()

static func artwork() -> Texture2D:
	var image := Image.new()
	var pixels := FileAccess.get_file_as_bytes(ProjectSettings.get_setting("application/boot_splash/image"))
	return ImageTexture.create_from_image(image) if image.load_png_from_buffer(pixels) == OK else null

func _ready() -> void:
	var face: Font = load("res://assets/locale/PilotSC.otf")
	add_child(presentation)
	presentation.configure(artwork(), face if face else ThemeDB.fallback_font, "")
	presentation.meter.max_value = 3.0
	retry.hide()
	retry.text = "重试"
	retry.add_theme_font_override("font", presentation.typeface)
	retry.position = Vector2(581.0, 575.0)
	retry.size = Vector2(118.0, 40.0)
	retry.pressed.connect(_load_game)
	presentation.frame.add_child(retry)
	_load_game.call_deferred()

func _load_game() -> void:
	retry.hide()
	presentation.set_status("正在加载航母")
	presentation.meter.value = 0.0
	await get_tree().process_frame
	var catalogue := Data.new()
	var profile := Pilot.new(catalogue)
	var geometry := await Data.load_scene(get_tree(), STUDIO, func(ratio: float):
		presentation.meter.value = ratio)
	if not geometry:
		_show_failure("航母场景", STUDIO)
		return
	presentation.meter.value = 1.0
	await get_tree().process_frame
	var game_scene := load(MAIN) as PackedScene
	if not game_scene or not game_scene.can_instantiate():
		_show_failure("游戏场景", MAIN)
		return
	var selected: String = profile.state.selected
	var aircraft_path := Data.mesh_path(selected)
	presentation.set_status("正在加载展示战机")
	var aircraft := await Data.load_scene(get_tree(), aircraft_path, func(ratio: float):
		presentation.meter.value = 1.0 + ratio)
	if not aircraft:
		_show_failure("展示战机", aircraft_path)
		return
	catalogue.scenes[selected] = aircraft
	presentation.meter.value = 2.0
	presentation.set_status("正在启动大厅")
	await get_tree().process_frame
	var game := game_scene.instantiate()
	if not game or not game.has_method("_open"):
		if game:
			game.free()
		_show_failure("游戏场景", MAIN)
		return
	game.catalogue = catalogue
	game.profile = profile
	get_tree().root.add_child(game)
	var stage := game.get("showcase_stage") as Node
	var display := game.get("showcase_aircraft") as Node
	if (not is_instance_valid(game.get("lobby_screen"))
			or not stage or not stage.has_node("CarrierOcean")
			or not display or display.get_child_count() == 0):
		game.queue_free()
		_show_failure("大厅", MAIN)
		return
	geometry = null
	presentation.meter.value = 3.0
	get_tree().current_scene = game
	queue_free()

func _show_failure(stage: String, path: String) -> void:
	push_error("Startup could not open %s: %s" % [stage, path])
	presentation.set_status("%s加载失败，请重试" % stage)
	retry.show()
