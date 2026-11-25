extends SceneTree

const Data = preload("res://game/catalogue.gd")
const Profile = preload("res://game/profile.gd")
const Battle = preload("res://game/battle.gd")
var problems: Array[String] = []

func check(ok: bool, message: String) -> void:
	if not ok:
		problems.append(message)
		printerr(message)

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	var catalogue := Data.new()
	var profile := Profile.new(catalogue)
	check(catalogue.source.campaign.size() == 60, "Campaign catalogue lost a stage")
	for stage in catalogue.source.campaign:
		for count in stage.engagement.waves:
			check(count == 5 or count == 6, "Campaign wave outside the requested squad size")
	check(ClassDB.class_exists("Terrain3D") and ClassDB.class_exists("SkyTerrainKernel"), "Native terrain classes unavailable")
	var source := Vector2(-1536.0, 15360.0)
	var scalar: float = ClassDB.class_call_static("SkyTerrainKernel", "height_m", float(source.x), float(source.y), 413)
	var tile: PackedFloat32Array = ClassDB.class_call_static("SkyTerrainKernel", "height_tile", float(source.x), float(source.y), 128, 12.0, 413)
	check(tile.size() == 128 * 128 and absf(scalar - tile[0]) < 0.001, "Native terrain tile and point disagree")
	var sample: float = ClassDB.class_call_static("SkyTerrainKernel", "height_m", 19875634.5, -10348381.7, 413)
	check(is_finite(sample), "Infinite-coordinate elevation is invalid")
	var catalogue_ids := 0
	for id in catalogue.planes:
		var model: Node3D = catalogue.mesh(id)
		if model and model.get_child_count() > 0:
			catalogue_ids += 1
		if model:
			model.free()
	check(catalogue_ids == catalogue.planes.size(), "A V18 airframe did not import")
	var gear_model := catalogue.mesh("j20")
	root.add_child(gear_model)
	var tracks := catalogue.gear_tracks(gear_model)
	catalogue.set_gear(tracks, 1.0)
	check(tracks.size() == 3 and tracks[0].hinge.quaternion.angle_to(tracks[0].deployed) < 0.001,
		"J-20 did not use its authored deployed landing-gear poses")
	gear_model.queue_free()

	var battle := Battle.new()
	root.add_child(battle)
	battle.setup(catalogue, profile, "free", {"name":"自由空战", "region":0}, false)
	battle.paused = true
	check(battle.fleet.size() == 12 and battle.alive_enemies() == 11, "Free air combat roster is not fixed at twelve")
	var factions := {}
	for participant in battle.fleet:
		factions[participant.side] = true
	check(factions.size() == 12, "Free air combat assigned teammates")
	var jet := battle.fleet[1]
	battle._destroy(jet, battle.player)
	battle._destroy(battle.player, jet)
	check(battle.player_kills == 1 and battle.respawns == 1 and jet.kills == 1 and jet.deaths == 1,
		"Eliminations and deaths were not credited to both pilots")
	battle.finish(false)
	check(not battle.ended and battle.player.until_respawn == 3.0 and jet.until_respawn == 3.0,
		"Early finish or incorrect free air combat respawn delay")
	battle.paused = false
	battle.time = 2.98
	battle._physics_process(0.01)
	check(battle.player.hp <= 0.0 and jet.hp <= 0.0, "A pilot respawned before three seconds")
	battle._physics_process(0.011)
	battle.paused = true
	check(battle.player.hp > 0.0 and jet.hp > 0.0 and battle.alive_enemies() == 11 and jet.kills == 1,
		"Free combat did not respawn the fixed roster with its original stats")
	var origin_before: Vector2i = battle.world.origin
	var rebase: Vector3 = battle.world.follow(Vector3(6000, 1000, 0), Vector3.FORWARD * 200.0)
	check(origin_before != battle.world.origin and rebase.x > 0.0, "Floating origin did not rebase")
	var result := []
	battle.finished.connect(func(value): result.append(value))
	battle.fleet[2].kills = 8
	battle.fleet[2].deaths = 4
	battle.fleet[3].kills = 8
	battle.fleet[3].deaths = 2
	battle.time = 599.999
	battle._physics_process(0.02)
	check(result.is_empty() and battle.time < 600.0, "Pause advanced the countdown")
	battle.paused = false
	battle._physics_process(0.02)
	battle._physics_process(0.02)
	check(result.size() == 1 and battle.ended and battle.time == 600.0, "The ten-minute match did not settle exactly once")
	if result.size() == 1:
		var standings: Array = result[0].ranking
		check(standings.size() == 12 and standings[0].slot == 3 and standings[1].slot == 2,
			"Free ranking did not use kills then deaths")
		check(result[0].place == 3 and standings[3].place == 3 and result[0].credits == 620,
			"Tied pilots or the credit award did not follow the ranking rules")
	battle.queue_free()
	await process_frame
	battle = Battle.new()
	root.add_child(battle)
	var chapter_three: Dictionary = catalogue.source.campaign[22]
	battle.setup(catalogue, profile, "campaign", chapter_three, false)
	battle.paused = true
	var drones := 0
	for enemy in battle.fleet:
		if enemy.hp > 0 and enemy.type.id == "shade-drone":
			drones += 1
	check(drones == 2 and battle.alive_enemies() == 5 and battle.wave == 1, "Chapter 3 first wave or drones are incorrect")
	var first := battle.fleet[1]
	battle._destroy(first, battle.player)
	battle.paused = false
	battle._physics_process(1.0 / 90.0)
	check(battle.wave == 1 and battle.next_wave == 0.0 and battle.alive_enemies() == 4,
		"Campaign sent reinforcements before the remaining squad was cleared")
	for i in range(2, 6):
		battle._destroy(battle.fleet[i], battle.player)
	battle._physics_process(1.0 / 90.0)
	battle.time = battle.next_wave - 0.001
	battle._physics_process(1.0 / 90.0)
	check(battle.wave == 2 and not battle.ended and battle.alive_enemies() == 6,
		"The next wave did not arrive together as a six-aircraft formation")
	battle.queue_free()
	await process_frame
	var shell: Node = load("res://scenes/main.tscn").instantiate()
	root.add_child(shell)
	await process_frame
	var start_button: Control
	var free_button: Control
	for control in shell.view.get_children():
		if control.get_script() != preload("res://game/menu_panel.gd"):
			continue
		if control.title == "开始战斗":
			start_button = control
		elif control.title == "无限空战":
			free_button = control
	check(start_button != null and free_button != null, "Lobby is missing a sortie entry")
	if start_button and free_button:
		check(free_button.position.y >= start_button.position.y + start_button.size.y,
			"Unlimited air combat is not underneath the main sortie")
		var pointer := InputEventMouseButton.new()
		pointer.button_index = MOUSE_BUTTON_LEFT
		pointer.position = free_button.size * 0.5
		pointer.pressed = true
		free_button._gui_input(pointer)
		pointer.pressed = false
		free_button._gui_input(pointer)
		for i in range(4):
			await process_frame
		check(is_instance_valid(shell.current_battle) and shell.current_battle.mode == "free",
			"The lobby's second sortie button does not launch free combat")
	shell.queue_free()
	await process_frame
	print("Native regression suite. Aircraft: ", catalogue_ids, ", campaign: ", catalogue.source.campaign.size(), ", failures: ", problems.size())
	quit(0 if problems.is_empty() else 1)
