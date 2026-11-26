extends SceneTree

const Data = preload("res://game/catalogue.gd")
const Profile = preload("res://game/profile.gd")
const Battle = preload("res://game/battle.gd")
const Terrain = preload("res://game/world.gd")

var failures := 0

func _initialize() -> void:
	run.call_deferred()

func check(rule: bool, label: String) -> void:
	if not rule:
		failures += 1
		push_error(label)

func run() -> void:
	var catalogue := Data.new()
	var folder := "user://qa-%s" % Time.get_ticks_usec()
	DirAccess.make_dir_recursive_absolute(folder)
	var slot := folder + "/profile.json"
	var profile := Profile.new(catalogue, slot)
	check(profile.save(), "Initial checksum envelope")
	check(profile.upgrade("weapons") == "已完成改装", "Upgrade commits")
	check(profile.level_of("weapons") == 1 and profile.state.credits == 2040, "Upgrade price and level")
	var before: Dictionary = profile.state.duplicate(true)
	DirAccess.make_dir_absolute(slot + ".pending")
	check(profile.equip("flarewing") == "存档写入失败", "Blocked save reports purchase failure")
	check(profile.state == before, "Failed purchase rolls back the ledger and mounted item")
	DirAccess.remove_absolute(slot + ".pending")
	profile.abort("campaign")
	check(profile.state.modes.campaign.aborts == 1 and profile.state.credits == before.credits, "Aborted sorties do not pay credits")
	var record := {"id":"training_flight", "mode":"training", "name":"基础飞行", "grade":"完成",
		"score":200, "kills":0, "deaths":0, "credits":250, "xp":50, "win":true, "distance":500.0, "campaign":0}
	check(profile.debrief(record), "Training result saves")
	var paid: int = profile.state.credits
	record.credits = 250
	check(profile.debrief(record) and profile.state.credits == paid, "Repeated training does not pay")
	var loaded := Profile.new(catalogue, slot)
	check(loaded.state.credits == paid and loaded.state.modes.training.sorties == 2, "Mode statistics survive reload")
	var corrupted := FileAccess.open(slot, FileAccess.WRITE)
	corrupted.store_string('{"schema":182,"payload":"tampered","checksum":"invalid"}')
	corrupted.close()
	var recovered := Profile.new(catalogue, slot)
	check(recovered.level_of("weapons") == 1 and recovered.state.modes.training.sorties == 1, "Corrupt primary falls back to valid previous copy")

	var battle := Battle.new()
	root.add_child(battle)
	battle.setup(catalogue, profile, "training", {"name":"基础飞行","lesson":"flight","region":0}, false)
	battle.set_physics_process(false)
	battle.set_process(false)
	battle.set_weapon_trigger("missile", true)
	battle.set_weapon_trigger("missile", false)
	battle._physics_process(1.0 / 90.0)
	var missile := battle.shots[0]
	check(missile.active and missile.missile and missile.target == null and battle.total_fired == 1, "A short tap fires a missile without a lock")
	var launch: Vector3 = missile.nose
	for i in 25:
		battle._physics_process(1.0 / 90.0)
	check(missile.active and missile.nose.dot(launch) > 0.9999, "Unguided missile keeps its launch heading")
	var wake = battle.effects.trails.emitters[int(missile.slot)]
	battle._expire(missile)
	check(wake.closed and battle.effects.trails.slots[wake.row] == wake, "Missile trail survives projectile retirement")
	battle.effects.trails.advance(3.2)
	check(battle.effects.trails.slots[wake.row] == null, "Finished volumetric trail returns its slot")
	check(battle.player.throttle == 1.0, "Fixed full power")
	battle.queue_free()
	await process_frame

	battle = Battle.new()
	root.add_child(battle)
	battle.setup(catalogue, profile, "training", {"name":"基础飞行","lesson":"flight","region":0}, true)
	battle.set_physics_process(false)
	battle.set_process(false)
	var results := []
	battle.finished.connect(func(row): results.append(row))
	for i in 1800:
		battle._physics_process(1.0 / 90.0)
		if battle.ended:
			break
	check(not battle.player.grounded and battle.player.hp > 0.0 and not results.is_empty() and results[0].win,
		"Automatic runway launch and flight training complete without a throttle or flight input")
	battle.queue_free()
	await process_frame
	var tile := Terrain.bake_tile(Vector2i(8, 3), 413)
	var edge: float = ClassDB.class_call_static("SkyTerrainKernel", "height_m", 8 * float(Terrain.TILE), 3 * float(Terrain.TILE), 413)
	check(absf(edge - tile[0]) < 0.001, "Terrain erosion is deterministic across tile coordinates")
	for filename in DirAccess.get_files_at(folder):
		DirAccess.remove_absolute(folder.path_join(filename))
	DirAccess.remove_absolute(folder)
	print("V18.2 acceptance: ", failures, " failures")
	quit(0 if failures == 0 else 1)
