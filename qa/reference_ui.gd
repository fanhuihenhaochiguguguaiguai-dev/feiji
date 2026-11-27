extends SceneTree

const Entry := preload("res://scenes/startup.tscn")
const Startup := preload("res://game/startup.gd")
const Loading := preload("res://game/loading_screen.gd")

var screenshots := ""
var failures: Array[String] = []

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var args := OS.get_cmdline_user_args()
	if not args.is_empty() and DisplayServer.get_name() != "headless":
		screenshots = args[0]
		DirAccess.make_dir_recursive_absolute(screenshots)
		var boot := Loading.new()
		root.add_child(boot)
		boot.configure(Startup.artwork(), load("res://assets/locale/PilotSC.otf"), "")
		# Golden frame uses the measured relative fill length of the supplied master.
		boot.meter.ratio = 175.0 / 394.0
		await _capture("01_splash")
		boot.free()
	var launcher := Entry.instantiate()
	root.add_child(launcher)
	current_scene = launcher
	var stages: Array[float] = []
	launcher.presentation.meter.value_changed.connect(func(value: float): stages.append(value))
	var deadline := Time.get_ticks_msec() + 20000
	while not is_instance_valid(launcher) or current_scene == launcher:
		if Time.get_ticks_msec() > deadline or (is_instance_valid(launcher) and launcher.retry.visible):
			_check(false, "Startup failed to reach the lobby")
			_report()
			return
		await process_frame
		if not is_instance_valid(launcher):
			break
	var game := current_scene
	_check(game != null and game.route == "lobby", "Startup did not publish an interactive lobby")
	if game == null or game.lobby_screen == null:
		_report()
		return
	_check(not stages.is_empty() and stages[-1] == 3.0 and stages == _ordered(stages), "Startup progress did not follow completed stages")
	_check(not is_instance_valid(game.showcase_stage), "Carrier startup built the legacy 3D hangar")
	var menu: Control = game.lobby_screen
	await _capture("03_lobby")
	if not screenshots.is_empty():
		var first := root.get_texture().get_image().get_data()
		await RenderingServer.frame_post_draw
		await RenderingServer.frame_post_draw
		_check(first == root.get_texture().get_image().get_data(), "Idle carrier frame changed between renders")
	var positions := {}
	for id in menu.actions:
		var button: Button = menu.actions[id]
		positions[id] = [button.position.x, button.position.y, button.size.x, button.size.y]
		_check(menu.blocks_orbit(button.get_global_rect().get_center()), "Lobby button lost its hit zone: " + id)
	var centre: Vector2 = menu.frame.get_global_rect().get_center()
	_check(not menu.blocks_orbit(centre), "Carrier display cannot be orbited")
	var displayed: Node = game.showcase_aircraft.get_child(0)
	var old_pose: Transform3D = game.preview_camera.transform
	game._orbit_drag(Vector2(37, 0))
	game._tick_orbit(0.0, true)
	_check(game.preview_camera.transform != old_pose, "Carrier aircraft did not respond to orbit")
	game.lobby_screen.actions.hangar.pressed.emit()
	_check(game.route == "hangar" and displayed == game.showcase_aircraft.get_child(0), "Hangar lost the existing aircraft model")
	for route in ["pilot", "settings", "campaign", "training"]:
		game._open("lobby")
		game.lobby_screen.actions[route].pressed.emit()
		_check(game.route == route, "Carrier button did not open " + route)
	var saved: Dictionary = game.profile.state.duplicate(true)
	game.profile.state.selected = game.catalogue.source.startingFleet[1]
	game.profile.state.credits = 4837
	game.profile.state.xp = 481
	game._open("lobby")
	var texts: Array[String] = []
	for child in game.lobby_screen.frame.get_children():
		if child is Label:
			texts.append(child.text)
	var featured: Dictionary = game.catalogue.aircraft(game.profile.state.selected)
	_check("4837" in texts and str(featured.name) in texts and game.preview_id == featured.id,
		"Carrier did not use the current pilot and aircraft state")
	game.profile.state = saved
	game._open("lobby")
	game._show_loading(str(game.catalogue.source.campaign[0].name))
	var loading: Control = game.loading_screen
	loading.set_status("正在装配战场")
	loading.meter.ratio = 0.003
	_check(loading.fill.size.x < 3.0, "The progress bar exaggerated a small progress value")
	loading.meter.ratio = 506.0 / 676.0
	await _capture("02_battle_loading")
	if not screenshots.is_empty():
		var file := FileAccess.open(screenshots.path_join("layout.json"), FileAccess.WRITE)
		file.store_string(JSON.stringify(positions))
	if "--screenshots-only" in args:
		_report()
		return
	game._open("lobby")
	game.lobby_screen.actions.start.pressed.emit()
	var in_flight: Control = game.loading_screen
	root.size_changed.emit()
	_check(in_flight == game.loading_screen and in_flight.is_inside_tree(), "Resizing replaced the battle loading screen")
	deadline = Time.get_ticks_msec() + 30000
	while game.loading and Time.get_ticks_msec() < deadline:
		await process_frame
	_check(game.route == "battle" and not game.loading and is_instance_valid(game.active_hud), "Start button did not complete a real sortie")
	if game.route == "battle":
		game._abort_battle()
	_check(is_instance_valid(game.lobby_screen), "Returning from a sortie did not restore the carrier")
	_report()

func _ordered(values: Array[float]) -> Array[float]:
	var copy := values.duplicate()
	copy.sort()
	return copy

func _check(passed: bool, problem: String) -> void:
	if not passed:
		failures.append(problem)

func _capture(name: String) -> void:
	if not screenshots.is_empty():
		for frame in 4:
			await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(screenshots.path_join(name + ".png"))

func _report() -> void:
	print(JSON.stringify({"failures":failures}))
	quit(int(not failures.is_empty()))
