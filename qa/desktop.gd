extends SceneTree

const GAME = preload("res://scenes/main.tscn")
const STEP := 1.0 / 90.0

func _initialize() -> void:
	run.call_deferred()

func run() -> void:
	var destination := "/tmp/skyblade-desktop"
	var pause_capture := false
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--output="):
			destination = arg.trim_prefix("--output=")
		elif arg == "--pause":
			pause_capture = true
	DirAccess.make_dir_recursive_absolute(destination)
	var shell := GAME.instantiate()
	root.add_child(shell)
	var test_profile = shell.profile
	test_profile.state.settings.mute = true
	for i in 10:
		await process_frame
	var lobby := await _measure(48)
	lobby["nodes"] = shell.showcase.get_child_count()
	await _snapshot(destination.path_join("lobby.png"))
	shell._start_campaign(1)
	while shell.loading:
		await process_frame
	var fight = shell.current_battle
	if pause_capture:
		while fight.time < 0.45:
			await process_frame
		shell.active_hud.input_actions.pause.pressed.emit()
		await _snapshot(destination.path_join("pause.png"))
		shell._resume()
	var combat := await _measure(48)
	await _snapshot(destination.path_join("combat.png"))
	var out := FileAccess.open(destination.path_join("render.json"), FileAccess.WRITE)
	out.store_string(JSON.stringify({"lobby":lobby,"combat":combat,"gpu":RenderingServer.get_video_adapter_name(),"display":str(root.size)}, "\t"))
	if "--missile" in OS.get_cmdline_user_args() and DisplayServer.get_name() != "headless":
		await _missile_frames(shell, destination)
	fight.paused = true
	fight.audio.stop_all()
	shell.queue_free()
	await process_frame
	quit()

func _measure(frames: int) -> Dictionary:
	var samples := PackedFloat64Array()
	var start := Time.get_ticks_usec()
	var total := 0.0
	for i in frames:
		await process_frame
		var next := Time.get_ticks_usec()
		var elapsed := (next - start) / 1000.0
		samples.append(elapsed)
		total += elapsed
		start = next
	samples.sort()
	return {"frames":frames,"mean_ms":total / frames,"p50_ms":samples[frames / 2],"p95_ms":samples[int(frames * 0.95)],"memory_bytes":Performance.get_monitor(Performance.MEMORY_STATIC),"video_bytes":Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED)}

func _snapshot(path: String) -> void:
	if DisplayServer.get_name() != "headless":
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(path)

func _missile_frames(shell: Node, destination: String) -> void:
	var fight = shell.current_battle
	fight.set_physics_process(false)
	fight.set_process(false)
	var at: Vector3 = fight.player.position
	at.y = 1950.0
	fight.player.reset(at, Vector3.FORWARD, 195.0, 4200.0)
	var mark = fight.fleet[1]
	mark.reset(at + Vector3(110, 25, -1160), Vector3.LEFT, 0.0, 3000.0)
	mark.velocity = Vector3(176, 6, 10)
	for i in range(2, fight.fleet.size()):
		fight.fleet[i].hp = 0.0
		fight.fleet[i].model.visible = false
	fight._reset_player_spawn()
	for i in 83:
		fight.time += STEP
		fight._targeting(STEP)
	fight.set_weapon_trigger("missile", true)
	fight._update_player(STEP)
	fight.set_weapon_trigger("missile", false)
	for i in 170:
		fight.time += STEP
		if i > 42:
			mark.velocity = mark.velocity.rotated(Vector3.UP, 1.1 * STEP)
		mark.previous = mark.position
		mark.position += mark.velocity * STEP
		fight._update_shots(STEP)
		if i % 20 == 0:
			fight._render_pose(1.0 / 30.0)
			fight.camera.position = at + Vector3(-125, 115, 108)
			fight.camera.look_at(at + Vector3(90, 10, -475))
			fight.camera.fov = 49.0
			fight.effects.tick(0.065, fight.shots, fight.camera)
			await _snapshot(destination.path_join("missile-%03d.png" % i))
