extends SceneTree

const Battle = preload("res://game/battle.gd")
const Data = preload("res://game/catalogue.gd")
const Profile = preload("res://game/profile.gd")
const Hud = preload("res://game/hud.gd")
const STEP := 1.0 / 90.0

var output := ""
var failures: Array[String] = []

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--output="):
			output = arg.trim_prefix("--output=")
	if not output.is_empty():
		DirAccess.make_dir_recursive_absolute(output)
	seed(183)
	var catalogue := Data.new()
	var profile := Profile.new(catalogue)
	profile.state.selected = "j20"
	profile.state.settings.mute = true
	var battle := Battle.new()
	root.add_child(battle)
	battle.set_process(false)
	battle.set_physics_process(false)
	battle.setup(catalogue, profile, "campaign", catalogue.source.campaign[0], false)
	# An explicit fixture option for software Vulkan with a separated
	# render thread. The production flight scene keeps its normal FFT path.
	if "--compat-water" in OS.get_cmdline_user_args():
		battle.world.ocean.set_process(false)
	var hud := Hud.new()
	hud.fight = battle
	hud.typeface = preload("res://assets/locale/PilotSC.otf")
	var layer := CanvasLayer.new()
	root.add_child(layer)
	layer.add_child(hud)
	hud.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	await process_frame
	_check(battle.player.rig.fins.size() == 2, "Reference wing surfaces were not attached to the animated rig")
	_check(battle.player.rig.gear.size() == 3, "Flight rig lost a landing gear track")
	for track in battle.player.rig.gear:
		_check(not track.hinge.visible, "Airborne spawn still exposes a stowed landing wheel")
		catalogue.set_gear([track], 1.0, true)
		_check(track.hinge.visible, "Deployed landing wheel is hidden")
		catalogue.set_gear([track], 0.0, true)
	var pilot := battle.player
	var spawn := pilot.position
	pilot.gear = 1.0
	pilot.gear_target = 1.0
	battle.launched_from_runway = true
	battle._update_player(STEP)
	_check(pilot.gear_target == 0.0 and pilot.gear < 1.0, "A climb away from the runway did not retract the gear")
	battle.launched_from_runway = false
	pilot.reset(spawn, Vector3.FORWARD, pilot.type.trim, pilot.max_hp)
	_check(battle.player.rig.breakup.get_child_count() == 5, "Missing derived breakup geometry")
	if "--model-only" in OS.get_cmdline_user_args():
		hud.hide()
		await _model_views(battle, catalogue)
		await _finish(layer, battle)
		return
	var at := Vector3(11450, 460, 5250)
	_pose(battle, at, Vector3(-0.25, -0.04, -1).normalized())
	var target = battle.fleet[1]
	target.reset(battle.player.position + battle.player.forward * 1380.0 + Vector3(36, 16, 0),
		Vector3.FORWARD, 190.0, target.max_hp)
	target.model.visible = true
	battle.time = 19.0
	for i in 80:
		battle.time += STEP
		battle._targeting(STEP)
	battle._refresh_fire_control()
	battle._render_pose(0.025)
	_check(battle.is_locked(), "Existing fire control did not lock the sighted target")
	await _capture("coast-hud")
	var view: Button = hud.input_actions.view
	view.pressed.emit()
	battle._render_pose(0.025)
	_check(battle.manual_cockpit and battle.player.rig.cockpit.visible,
		"First-person button did not enable its existing cockpit")
	await _capture("first-person")
	view.pressed.emit()
	battle._render_pose(0.025)
	_check(not battle.manual_cockpit and battle.player.rig.levels.Exterior.visible, "Chase view did not return")
	var threat = battle.fleet[2]
	threat.reset(battle.player.position - battle.player.forward * 760.0 + Vector3(15, 0, 0),
		battle.player.forward, 250.0, threat.max_hp)
	_check(battle._fire(threat, true, battle.player), "Hostile missile fixture could not use the real launch path")
	for i in ceili(battle.MISSILE_ARM_TIME / STEP) + 2:
		battle.time += STEP
		battle._update_shots(STEP)
	_check(battle.warning, "Missile warning did not observe a real guided projectile")
	await _capture("incoming")
	var moved_from := battle.player.position
	for i in 9:
		battle._physics_process(STEP)
	battle._render_pose(STEP)
	_check(battle.player.position.distance_to(moved_from) > 1.0, "Aircraft did not advance under flight simulation")
	hud.hide()
	_pose(battle, Vector3(11520, 1710, 5310), Vector3(-0.23, -0.24, -0.95).normalized())
	await _capture("coast-high")
	_pose(battle, Vector3(11760, 55, 5600), Vector3(-0.2, 0.045, -1).normalized())
	await _capture("coast-low")
	await _model_views(battle, catalogue)
	await _finish(layer, battle)

func _model_views(battle: Battle, catalogue: Data) -> void:
	_pose(battle, Vector3(11450, 3100, 5250), Vector3.FORWARD)
	var plane: Node3D = battle.player.model
	catalogue.set_gear(battle.player.rig.gear, 1.0, true)
	for plume: Node3D in battle.player.rig.exhausts:
		plume.hide()
	battle.camera.fov = 16.0
	battle.camera.h_offset = 0.0
	battle.camera.v_offset = 0.0
	battle.camera.make_current()
	var views := {"side": Vector3.LEFT, "front": Vector3.FORWARD,
		"rear": Vector3.BACK, "top": Vector3.UP}
	for label: String in views:
		var axis: Vector3 = views[label]
		var up := Vector3.RIGHT if label == "top" else Vector3.UP
		battle.camera.global_position = plane.global_position + plane.global_basis * axis * 62.0
		battle.camera.look_at(plane.global_position, plane.global_basis * up)
		await _capture("flight-model-" + label)
	battle.camera.global_position = plane.global_position + plane.global_basis * Vector3(-35.0, -13.0, 45.0)
	battle.camera.look_at(plane.global_position)
	await _capture("wheels-down")
	battle.player.gear = 0.0
	battle.player.rig.last_gear = -1.0
	catalogue.set_gear(battle.player.rig.gear, 0.0, true)
	await _capture("wheels-up")

func _finish(layer: CanvasLayer, battle: Battle) -> void:
	print(JSON.stringify({"failures": failures, "display": str(root.size), "renderer": RenderingServer.get_video_adapter_name()}))
	layer.queue_free()
	battle.queue_free()
	await process_frame
	quit(int(not failures.is_empty()))

func _pose(battle: Battle, at: Vector3, heading: Vector3) -> void:
	var pilot = battle.player
	pilot.reset(battle.world.local_position(at), heading, 255.0, pilot.max_hp)
	battle.camera_fresh = true
	battle.target = null
	battle._render_pose(1.0 / 30.0)
	battle.world.follow(pilot.position, pilot.velocity, 0.12)

func _capture(name: String) -> void:
	if output.is_empty() or DisplayServer.get_name() == "headless":
		return
	for frame in 3:
		await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(output.path_join(name + ".png"))

func _check(condition: bool, error: String) -> void:
	if not condition:
		failures.append(error)
