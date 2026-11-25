extends SceneTree

const BATTLE = preload("res://game/battle.gd")
const DATA = preload("res://game/catalogue.gd")
const PROFILE = preload("res://game/profile.gd")
const HUD = preload("res://game/hud.gd")
const STEP := 1.0 / 90.0
var failed := 0

func _initialize() -> void:
	run.call_deferred()

func run() -> void:
	var catalogue := DATA.new()
	var fight := BATTLE.new()
	root.add_child(fight)
	fight.setup(catalogue, PROFILE.new(catalogue), "training", {"name":"导弹回归", "lesson":"flight", "region":0}, false)
	fight.set_process(false)
	fight.set_physics_process(false)
	var results := []
	for scenario in ["static", "moving", "turning", "owner_turn", "unlocked", "close_crossing"]:
		results.append(_check(fight, scenario))
	results.append(_check_touch_lock(fight))
	fight.queue_free()
	await process_frame
	print(JSON.stringify({"scenarios":results,"failures":failed}, "\t"))
	quit(0 if failed == 0 else 1)

func _check(fight: Node, scenario: String) -> Dictionary:
	while not fight.shots.is_empty():
		fight._expire(fight.shots.back())
	var start := Vector3(730.0, 1900.0, 630.0)
	var opponent = fight.fleet[1]
	fight.player.reset(start, Vector3.FORWARD, 195.0, 4200.0)
	var crossing := scenario == "close_crossing"
	var offset := Vector3(12.0, 10.0, -150.0) if crossing else Vector3(110.0, 25.0, -1160.0)
	opponent.reset(start + offset, Vector3.LEFT, 0.0, 3000.0)
	if scenario != "static":
		opponent.velocity = Vector3(180.0, 6.0, 230.0) if crossing else Vector3(176.0, 6.0, 10.0)
	fight.time = 0.0
	fight.locked_time = 0.0
	fight.seek_due = 0.0
	fight.target = null
	fight._reset_player_spawn()
	var expected_lock := scenario != "unlocked"
	if expected_lock:
		for i in 83:
			fight.time += STEP
			fight._targeting(STEP)
	var lock_seen: bool = fight.is_locked()
	fight.set_weapon_trigger("missile", true)
	fight._update_player(STEP)
	fight.set_weapon_trigger("missile", false)
	var cast: Dictionary = fight.shots[0]
	var bound: bool = cast.target == opponent
	var launch: Vector3 = cast.nose
	var first: Vector3 = cast.position
	var max_turn := 0.0
	var max_step := 0.0
	var max_offset := 0.0
	var hit_before: int = fight.shots_hit
	var last := launch
	for i in (620 if crossing else 360):
		if not cast.active:
			break
		fight.time += STEP
		if (scenario == "turning" and i > 42) or (crossing and i > 32):
			opponent.velocity = opponent.velocity.rotated(Vector3.UP, 1.10 * STEP)
		opponent.position += opponent.velocity * STEP
		if scenario == "owner_turn" and i == 14:
			fight.player.attitude = Quaternion(Vector3.UP, PI)
			fight.player.forward = Vector3.BACK
			fight.target = null
			fight.locked_time = 0.0
		fight._update_shots(STEP)
		var n: Vector3 = cast.nose
		max_turn = maxf(max_turn, rad_to_deg(launch.angle_to(n)))
		max_step = maxf(max_step, rad_to_deg(last.angle_to(n)))
		max_offset = maxf(max_offset, ((cast.position - first) as Vector3).cross(launch).length())
		last = n
	var hit: bool = fight.shots_hit > hit_before
	var ok := lock_seen == expected_lock and bound == expected_lock and hit == expected_lock and max_step < 3.0
	ok = ok and (max_turn > 2.0 and max_offset > 10.0 if expected_lock else max_turn < 0.04 and max_offset < 0.05)
	if not ok:
		failed += 1
	return {"scenario":scenario,"lock":lock_seen,"target_bound":bound,"hit":hit,"turn_deg":max_turn,"step_deg":max_step,"curve_m":max_offset,"passed":ok}

func _check_touch_lock(fight: Node) -> Dictionary:
	while not fight.shots.is_empty():
		fight._expire(fight.shots.back())
	var at := fight.world.local_position(Vector3(11450.0, 1900.0, 5150.0)) as Vector3
	var opponent = fight.fleet[1]
	fight.player.reset(at, Vector3.FORWARD, 240.0, 4200.0)
	opponent.reset(at + Vector3(36, 0, -910), Vector3.LEFT, 230.0, 3000.0)
	fight._reset_player_spawn()
	fight.seek_due = 0.0
	for i in 83:
		fight.time += STEP
		fight._targeting(STEP)
	var displayed_lock: bool = fight.is_locked()
	var hud := HUD.new()
	hud.fight = fight
	hud.typeface = ThemeDB.fallback_font
	hud.size = Vector2(1280, 576)
	root.add_child(hud)
	var touch := InputEventScreenTouch.new()
	touch.index = 2
	touch.position = hud.artifacts[4].centre
	touch.pressed = true
	hud._input(touch)
	touch.pressed = false
	hud._input(touch)
	# A locked contact crosses the cone boundary between the tap and the firing tick.
	opponent.position = at + Vector3(302, 0, -920)
	fight._physics_process(STEP)
	var cast: Dictionary = fight.shots[0] if not fight.shots.is_empty() else {}
	var bound: bool = cast.get("target") == opponent
	var turn := 0.0
	var hit_before: int = fight.shots_hit
	var nose: Vector3 = cast.get("nose", Vector3.FORWARD)
	for i in 240:
		if not cast.get("active", false):
			break
		fight._physics_process(STEP)
		turn = maxf(turn, rad_to_deg(nose.angle_to(cast.nose)))
	var hit: bool = fight.shots_hit > hit_before
	var ok := displayed_lock and bound and turn > 5.0 and hit
	if not ok:
		failed += 1
	hud.free()
	return {"scenario":"touch_lock_lost_before_fire", "displayed_lock":displayed_lock,"target_bound":bound,"turn_deg":turn,"hit":hit,"passed":ok}
