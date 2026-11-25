extends SceneTree

const GAME = preload("res://scenes/main.tscn")

func _initialize() -> void:
	run.call_deferred()

func run() -> void:
	var args := OS.get_cmdline_user_args()
	var destination := "/tmp/skyblade-environment"
	for arg in args:
		if arg.begins_with("--output="):
			destination = arg.trim_prefix("--output=")
	DirAccess.make_dir_recursive_absolute(destination)
	seed(183)
	RenderingServer.viewport_set_measure_render_time(root.get_viewport_rid(), true)
	var shell := GAME.instantiate()
	root.add_child(shell)
	shell.set_process(false)
	shell.profile.state.settings.mute = true
	root.scaling_3d_scale = 0.85
	var stats := {"adapter":RenderingServer.get_video_adapter_name()}
	var samples := 4 if "--quick" in args else 20
	var additional := 4 if "--quick" in args else 12
	for i in 8:
		await RenderingServer.frame_post_draw
	stats.lobby = await _take(destination.path_join("lobby.png"), samples)
	shell._start_campaign(1)
	while shell.loading:
		await process_frame
	var battle = shell.current_battle
	battle.set_physics_process(false)
	battle.set_process(false)
	battle.audio.stop_all()
	battle.time = 4.0
	var world = battle.world
	var materials: Array = [world.terrain.assets.get_texture_asset(0), world.terrain.assets.get_texture_asset(1)]
	var p := Vector3(11450, 460, 5250)
	await _pose(battle, p, Vector3(-0.25, -0.04, -1))
	stats.mid = await _take(destination.path_join("mid.png"), samples)
	if "--diagnose" in args:
		var original := []
		for texture in materials:
			original.append([texture.get_detiling_rotation(), texture.get_detiling_shift(), texture.get_normal_depth()])
			texture.set_detiling_rotation(0.0)
			texture.set_detiling_shift(0.0)
		await _take(destination.path_join("no-detile.png"), 3)
		for i in materials.size():
			materials[i].set_detiling_rotation(original[i][0])
			materials[i].set_detiling_shift(original[i][1])
			materials[i].set_normal_depth(0.0)
		await _take(destination.path_join("no-normal.png"), 3)
		for i in materials.size():
			materials[i].set_normal_depth(original[i][2])
		world.terrain.material.set_shader_param("auto_overlay_texture", 0)
		await _take(destination.path_join("no-mix.png"), 3)
		world.terrain.material.set_shader_param("auto_overlay_texture", 1)
		world.terrain.material.set_dual_scaling_enabled(false)
		await _take(destination.path_join("no-dual.png"), 3)
		world.terrain.material.set_dual_scaling_enabled(true)
		root.scaling_3d_scale = 1.0
		await _take(destination.path_join("native-resolution.png"), 3)
		root.scaling_3d_scale = 0.85
	await _pose(battle, Vector3(11760, 28, 5600), Vector3(-0.20, 0.045, -1))
	stats.sea = await _take(destination.path_join("sea.png"), additional)
	await _pose(battle, Vector3(12160, 375, 3790), Vector3(0.55, -0.015, -0.83))
	stats.ridge = await _take(destination.path_join("ridge.png"), additional)
	await _pose(battle, Vector3(11450, 1490, 5220), Vector3(-0.25, -0.12, -1))
	stats.cloud = await _take(destination.path_join("cloud.png"), additional)
	await _pose(battle, Vector3(11600, 3100, 5360), Vector3(-0.28, -0.36, -1))
	stats.high = await _take(destination.path_join("high.png"), additional)
	var output := FileAccess.open(destination.path_join("stats.json"), FileAccess.WRITE)
	output.store_string(JSON.stringify(stats, "\t"))
	shell.queue_free()
	await process_frame
	quit()

func _pose(battle: Node, at: Vector3, heading: Vector3) -> void:
	var pilot = battle.player
	pilot.reset(battle.world.local_position(at), heading, 255.0, pilot.max_hp)
	battle.camera_fresh = true
	battle.target = null
	battle._render_pose(1.0 / 30.0)
	battle.world.follow(pilot.position, pilot.velocity, 0.12)
	for i in 4:
		await RenderingServer.frame_post_draw
	battle.world.follow(pilot.position, pilot.velocity, 0.12)

func _take(path: String, frames: int) -> Dictionary:
	var cpu := PackedFloat64Array()
	var gpu := PackedFloat64Array()
	var started := Time.get_ticks_usec()
	for i in frames:
		await RenderingServer.frame_post_draw
		cpu.append(RenderingServer.viewport_get_measured_render_time_cpu(root.get_viewport_rid()))
		gpu.append(RenderingServer.viewport_get_measured_render_time_gpu(root.get_viewport_rid()))
	cpu.sort()
	gpu.sort()
	root.get_texture().get_image().save_png(path)
	print(path, " GPU ms ", gpu[frames / 2])
	return {"cpu_ms_median":cpu[frames / 2], "gpu_ms_median":gpu[frames / 2], "wall_ms_per_frame":(Time.get_ticks_usec() - started) / float(frames * 1000), "static_bytes":Performance.get_monitor(Performance.MEMORY_STATIC), "video_bytes":Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED)}
