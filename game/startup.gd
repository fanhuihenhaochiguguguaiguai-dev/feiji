extends CanvasLayer

const Screen = preload("res://game/loading_screen.gd")
const Data = preload("res://game/catalogue.gd")
const Pilot = preload("res://game/profile.gd")
const MAIN := "res://scenes/main.tscn"

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
	presentation.set_status("")
	presentation.meter.value = 0.0
	await get_tree().process_frame
	var catalogue := Data.new()
	var profile := Pilot.new(catalogue)
	var selected := str(profile.state.selected)
	var aircraft := Data.mesh_path(selected)
	if ResourceLoader.load_threaded_request(aircraft, "PackedScene") != OK:
		_show_failure()
		return
	var progress: Array = []
	var state := ResourceLoader.load_threaded_get_status(aircraft, progress)
	while state == ResourceLoader.THREAD_LOAD_IN_PROGRESS:
		presentation.meter.value = maxf(presentation.meter.value, float(progress[0]))
		await get_tree().process_frame
		state = ResourceLoader.load_threaded_get_status(aircraft, progress)
	if state != ResourceLoader.THREAD_LOAD_LOADED:
		_show_failure()
		return
	catalogue.scenes[selected] = ResourceLoader.load_threaded_get(aircraft)
	presentation.meter.value = 1.0
	await get_tree().process_frame
	# Load the scripted scene on the main thread, after the aircraft's imported asset.
	var game_scene := load(MAIN) as PackedScene
	if not game_scene:
		_show_failure()
		return
	presentation.meter.value = 2.0
	await get_tree().process_frame
	var game := game_scene.instantiate()
	if not game.has_method("_open"):
		game.free()
		_show_failure()
		return
	game.catalogue = catalogue
	game.profile = profile
	get_tree().root.add_child(game)
	presentation.meter.value = 3.0
	get_tree().current_scene = game
	queue_free()

func _show_failure() -> void:
	presentation.set_status("加载失败，请重试")
	retry.show()
