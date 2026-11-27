extends SceneTree

const Entry := preload("res://scenes/startup.tscn")
const Startup := preload("res://game/startup.gd")
const Loading := preload("res://game/loading_screen.gd")

var screenshots := ""
var failures: Array[String] = []
var performance := {}

func _initialize() -> void:
	if "--orbit" in OS.get_cmdline_user_args():
		RenderingServer.set_debug_generate_wireframes(true)
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
	var deadline := Time.get_ticks_msec() + 90000
	while not is_instance_valid(launcher) or current_scene == launcher:
		if Time.get_ticks_msec() > deadline or (is_instance_valid(launcher) and launcher.retry.visible):
			_check(false, "Startup failed to reach the lobby. Completed stages: %s" % str(stages))
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
	var stage: Node3D = game.showcase_stage
	_check(stage != null and stage.get_node_or_null("CarrierArchitecture") != null and
		stage.get_node_or_null("SurveyedCoastline") != null and stage.get_node_or_null("CarrierOcean") != null,
		"Lobby did not build the live carrier, the terrain and the ocean")
	_check(game.preview_camera.get_viewport() == root, "Carrier is not using the whole gameplay viewport")
	var specimen: Node3D = game.showcase_aircraft.get_child(0)
	if game.preview_id == "j20":
		_check(specimen.scene_file_path == "res://assets/studio/reference-fighter.glb", "The approved sample did not replace the menu preview")
	var menu: Control = game.lobby_screen
	await _capture("03_lobby")
	if "--orbit" in args and not screenshots.is_empty():
		await _orbit_proof(game)
	if "--baseline-pose" in args and not screenshots.is_empty():
		var saved_angles := Vector2(game.orbit_spin,game.orbit_tilt)
		var saved_zoom: float = game.orbit_scale
		# Replay the old lobby's relative yaw, pitch and camera distance.
		game.orbit_spin = -2.269
		game.orbit_tilt = 0.212
		game.orbit_scale = saved_zoom * 1.04
		game.preview_camera.h_offset = -1.08
		game.preview_camera.v_offset = -0.97
		game._tick_orbit(0.0,true)
		await _capture("baseline-pose")
		game.orbit_spin = saved_angles.x
		game.orbit_tilt = saved_angles.y
		game.orbit_scale = saved_zoom
		game._sync_showcase_stage()
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
	_check(game.route == "hangar" and displayed == game.showcase_aircraft.get_child(0) and stage == game.showcase_stage,
		"Hangar did not share the same carrier and display object")
	await _capture("04_hangar")
	game._toggle_mods()
	await _capture("05_modifications")
	game._toggle_mods()
	for route in ["pilot", "settings", "campaign", "training"]:
		game._open("lobby")
		game.lobby_screen.actions[route].pressed.emit()
		_check(game.route == route, "Carrier button did not open " + route)
		await _capture(route)
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
		if not performance.is_empty():
			var timing := FileAccess.open(screenshots.path_join("frame-time.json"), FileAccess.WRITE)
			timing.store_string(JSON.stringify(performance))
	if "--aspects" in args and not screenshots.is_empty():
		await _wide_proof(game)
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
		for frame in 3:
			await RenderingServer.frame_post_draw
		var frame := root.get_texture().get_image()
		if name in ["01_splash","02_battle_loading","03_lobby"] or name.ends_with("-startup") or name.ends_with("-loading"):
			for x in [2,frame.get_width()-3]:
				var a := frame.get_pixel(x,roundi(frame.get_height()*0.18))
				var b := frame.get_pixel(x,roundi(frame.get_height()*0.68))
				_check(absf(a.get_luminance()-b.get_luminance()) > 0.006, name+" has a flat screen edge")
		frame.save_png(screenshots.path_join(name + ".png"))

func _orbit_proof(game: Node) -> void:
	var start: float = game.orbit_spin
	var directory := screenshots.path_join("orbit")
	DirAccess.make_dir_recursive_absolute(directory)
	var points: Array[Vector2] = []
	var viewport := root.get_viewport_rid()
	RenderingServer.viewport_set_measure_render_time(viewport,true)
	var cpu: Array[float] = []
	var gpu: Array[float] = []
	for i in 18:
		await RenderingServer.frame_post_draw
		if i >= 4:
			cpu.append(RenderingServer.viewport_get_measured_render_time_cpu(viewport))
			gpu.append(RenderingServer.viewport_get_measured_render_time_gpu(viewport))
	cpu.sort()
	gpu.sort()
	performance={"engine":RenderingServer.get_video_adapter_name(),"window":[root.size.x,root.size.y],
		"samples":cpu.size(),"cpu_ms_median":cpu[cpu.size()/2],"gpu_ms_median":gpu[gpu.size()/2],
		"draw_calls":root.get_render_info(Viewport.RENDER_INFO_TYPE_VISIBLE,Viewport.RENDER_INFO_DRAW_CALLS_IN_FRAME)}
	for i in 64:
		game.orbit_spin = start + TAU * float(i) / 64.0
		game._tick_orbit(0.0, true)
		await RenderingServer.frame_post_draw
		var frame := root.get_texture().get_image()
		frame.save_png(directory.path_join("%03d.png" % i))
		if i % 8 == 0:
			frame.save_png(screenshots.path_join("orbit-%d.png" % (i/8+1)))
			points.append(game.preview_camera.unproject_position(Vector3(-27,22,16)))
	_check(points[0].distance_to(points[2]) > 70.0 and points[2].distance_to(points[4]) > 70.0,
		"The island landmark did not move with the viewpoint")
	game.orbit_spin=start
	game._tick_orbit(0.0,true)
	root.debug_draw=Viewport.DEBUG_DRAW_WIREFRAME
	await _capture("wireframe")
	root.debug_draw=Viewport.DEBUG_DRAW_DISABLED

func _wide_proof(game: Node) -> void:
	var ratios := {"18-9":Vector2i(720,360),"19.5-9":Vector2i(780,360),
		"20-9":Vector2i(800,360),"22-9":Vector2i(880,360)}
	for ratio: String in ratios:
		var resolution: Vector2i = ratios[ratio]
		root.size = resolution
		await process_frame
		await process_frame
		_check(root.size == resolution,"Viewport did not apply ratio "+ratio)
		game._open("lobby")
		var boot := Loading.new()
		var overlay := CanvasLayer.new()
		overlay.layer=95
		root.add_child(overlay)
		overlay.add_child(boot)
		boot.configure(Startup.artwork(),game.font,"")
		boot.meter.ratio=175.0/394.0
		await _capture(ratio+"-startup")
		overlay.free()
		game._show_loading(str(game.catalogue.source.campaign[0].name))
		game.loading_screen.meter.ratio=506.0/676.0
		game.loading_screen.set_status("正在装配战场")
		await _capture(ratio+"-loading")
		for page: String in ["lobby","hangar","campaign","training","pilot","settings"]:
			game._open(page)
			var menu: Control = game.lobby_screen
			var safe := menu.get_global_rect().grow(0.5)
			for click: Button in menu.actions.values():
				_check(safe.encloses(click.get_global_rect()),ratio+" "+page+" has a displaced button: "+click.name)
			await _capture(ratio+"-"+page)
			if page == "hangar":
				game._toggle_mods()
				await _capture(ratio+"-modifications")
				game._toggle_mods()

func _report() -> void:
	print(JSON.stringify({"failures":failures}))
	if is_instance_valid(current_scene):
		current_scene.queue_free()
		await process_frame
		if DisplayServer.get_name() != "headless":
			await RenderingServer.frame_post_draw
	quit(int(not failures.is_empty()))
