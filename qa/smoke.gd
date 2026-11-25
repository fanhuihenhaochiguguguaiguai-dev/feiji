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
	var battle := Battle.new()
	root.add_child(battle)
	battle.setup(catalogue, profile, "free", {"name":"自由空战", "region":0}, false)
	battle.paused = true
	check(battle.fleet.size() == 7 and battle.alive_enemies() == 6, "Free air combat roster is not fixed")
	var jet := battle.fleet[1]
	var deaths := battle.respawns
	battle._destroy(jet, battle.player)
	battle._destroy(battle.player, jet)
	check(battle.player_kills == 1 and battle.respawns == deaths + 1 and not battle.ended, "Free combat knockdown ended the sortie")
	battle.time = 4.5
	battle.paused = false
	battle._physics_process(1.0 / 90.0)
	battle.paused = true
	check(battle.player.hp > 0.0 and jet.hp > 0.0 and battle.alive_enemies() == 6, "Free combat did not respawn the fixed roster")
	var origin_before: Vector2i = battle.world.origin
	var rebase: Vector3 = battle.world.follow(Vector3(6000, 1000, 0), Vector3.FORWARD * 200.0)
	check(origin_before != battle.world.origin and rebase.x > 0.0, "Floating origin did not rebase")
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
	check(drones == 2 and battle.alive_enemies() == 3, "Chapter 3 squad and drones are incorrect")
	battle.queue_free()
	await process_frame
	print("Native regression suite. Aircraft: ", catalogue_ids, ", campaign: ", catalogue.source.campaign.size(), ", failures: ", problems.size())
	quit(0 if problems.is_empty() else 1)
