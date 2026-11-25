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
	results.append(_check_contact(fight))
	results.append(_check_lock_camera(fight))
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
		opponent.previous = opponent.position
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

func _check_contact(fight: Node) -> Dictionary:
	while not fight.shots.is_empty():
		fight._expire(fight.shots.back())
	var at: Vector3 = fight.world.local_position(Vector3(11450.0, 1900.0, 5150.0))
	var mark = fight.fleet[1]
	fight.player.reset(at, Vector3.FORWARD, 240.0, 4200.0)
	mark.reset(at + Vector3.FORWARD * 200.0, Vector3.FORWARD, 0.0, 3000.0)
	var shape: Vector3 = mark.hit_extent
	var impact_before: int = fight.effects.impact_slot
	fight._fire(fight.player, true, null)
	var shot: Dictionary = fight.shots.back()
	shot.position = mark.position + Vector3(shape.x + 0.5, 0.0, 16.0)
	shot.velocity = Vector3.FORWARD * 925.0
	shot.age = 0.16
	fight._update_shots(STEP)
	fight._update_shots(STEP)
	fight._update_shots(STEP)
	var clean_miss: bool = shot.active and fight.effects.impact_slot == impact_before and mark.hp == 3000.0
	shot.position = mark.position + Vector3(0.0, 0.0, shape.z + 4.0)
	shot.velocity = Vector3.FORWARD * 925.0
	fight._update_shots(STEP)
	var tip: Vector3 = shot.trail.back()
	var hull: float = ((tip - mark.position) / shape).length()
	var immediate: bool = mark.hp < 3000.0 and not shot.active and fight.effects.impact_slot != impact_before and fight.hit_time == fight.time
	var ok := clean_miss and immediate and absf(hull - 1.0) < 0.002
	if not ok:
		failed += 1
	return {"scenario":"contact_and_particle_timing", "no_effect_on_near_miss":clean_miss, "impact_on_same_step":immediate,"trail_tip_hull_ratio":hull,"passed":ok}

func _check_lock_camera(fight: Node) -> Dictionary:
	var at: Vector3 = fight.world.local_position(Vector3(11450.0, 1900.0, 5150.0))
	var mark = fight.fleet[1]
	fight.player.reset(at, Vector3.FORWARD, 240.0, 4200.0)
	mark.reset(at + Vector3(160.0, 11.0, -980.0), Vector3.FORWARD, 0.0, 3000.0)
	fight._reset_player_spawn()
	fight.seek_due = 0.0
	for i in 80:
		fight._render_pose(STEP)
	var normal_fov: float = fight.camera.fov
	var ordinary_angle: float = (-fight.camera.basis.z).angle_to((mark.position - fight.camera.position).normalized())
	for i in 140:
		fight.time += STEP
		fight._targeting(STEP)
		fight._render_pose(STEP)
	var locked_fov: float = fight.camera.fov
	var tracked_angle: float = (-fight.camera.basis.z).angle_to((mark.position - fight.camera.position).normalized())
	var followed: bool = fight.is_locked() and locked_fov < normal_fov - 8.0 and tracked_angle < ordinary_angle * 0.38
	fight.stick = Vector2(0.9, 0.0)
	fight._update_player(STEP)
	for i in 75:
		fight._render_pose(STEP)
	var manual_angle: float = (-fight.camera.basis.z).angle_to((mark.position - fight.camera.position).normalized())
	var input_priority := manual_angle > tracked_angle * 2.0
	fight.target = null
	for i in 120:
		fight._render_pose(STEP)
	var recovered: bool = absf(fight.camera.fov - normal_fov) < 0.4
	var ok := followed and input_priority and recovered
	if not ok:
		failed += 1
	return {"scenario":"lock_camera", "normal_fov":normal_fov,"locked_fov":locked_fov,"tracking_error_degrees":rad_to_deg(tracked_angle),"input_has_priority":input_priority,"recovers_after_unlock":recovered,"passed":ok}
