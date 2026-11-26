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
	results.append(_check_target_continuity(fight))
	results.append(_check_hidden_contact(fight))
	results.append(_check_wreck(fight))
	results.append(_check_cannon(fight, true, false))
	results.append(_check_cannon(fight, true, true))
	results.append(_check_cannon(fight, false, false))
	var normal_radius := BATTLE.Effects.explosion_radius(14.0, 480.0, 50.0, false)
	var destruction_radius := BATTLE.Effects.explosion_radius(14.0, 480.0, 50.0, true)
	var long_radius := BATTLE.Effects.explosion_radius(14.0, 930.0, 50.0, false)
	var scaled := normal_radius > 8.5 and destruction_radius > normal_radius * 1.6 and long_radius > normal_radius
	failed += int(not scaled)
	results.append({"scenario":"visual_explosion_radius","normal_m":normal_radius,"destroyed_m":destruction_radius,
		"mid_range_normal_m":long_radius,"passed":scaled})
	fight.queue_free()
	await process_frame
	print(JSON.stringify({"scenarios":results,"failures":failed}, "\t"))
	quit(0 if failed == 0 else 1)

func _check_cannon(fight: BATTLE, locked: bool, evade: bool) -> Dictionary:
	while not fight.shots.is_empty():
		fight._expire(fight.shots.back())
	var start := Vector3(730.0, 1900.0, 630.0)
	var mark := fight.fleet[1]
	fight.player.reset(start, Vector3.FORWARD, 232.0, 4200.0)
	mark.reset(start + Vector3(0.5, 0.0, -570.0), Vector3.FORWARD, 0.0, 3000.0)
	mark.velocity = Vector3(39.0, 0.0, 32.0)
	fight.time = 31.0
	fight.target = mark
	fight.locked_time = float(fight.missile.acquire) if locked else 0.0
	var mount: Array = fight.player.type.guns[fight.total_fired % fight.player.type.guns.size()]
	var muzzle := start + fight.player.attitude * Vector3(mount[0], mount[1], mount[2])
	var solution := fight._gun_solution(muzzle, mark)
	fight._refresh_gun_marker()
	var marker_matches := fight.lead.is_equal_approx(solution.point)
	fight._fire(fight.player, false, mark)
	var cast := fight.shots[0]
	var nominal: Vector3 = solution.direction
	var spread: Vector3 = cast.scatter
	var same_launch := (nominal + spread).normalized().dot(cast.nose) > 0.99999
	var budget := float(cast.assist_budget)
	var hit_before := fight.shots_hit
	var successful_turn := false
	var max_step := 0.0
	for step in 100:
		if not cast.active:
			break
		fight.time += STEP
		mark.previous = mark.position
		if evade and step == 8:
			mark.evade_until = fight.time + 1.0
		mark.velocity.x += (14.0 if evade else 0.28) if step >= 8 else 0.0
		mark.position += mark.velocity * STEP
		var previous: Vector3 = cast.velocity.normalized()
		fight._update_shots(STEP)
		max_step = maxf(max_step, rad_to_deg(previous.angle_to((cast.velocity as Vector3).normalized())))
		if not evade:
			successful_turn = successful_turn or float(cast.assist_budget) < budget
	var hit := fight.shots_hit > hit_before
	var correct_mode := budget > 0.0 if locked else budget == 0.0
	var behavior: bool = (successful_turn and hit) if locked and not evade else (not hit if evade else cast.assist_budget == 0.0)
	var ok: bool = marker_matches and same_launch and correct_mode and behavior and max_step < 0.19
	failed += int(not ok)
	return {"scenario":"cannon_evasion" if evade else ("cannon_assisted" if locked else "cannon_unlocked"),
		"marker_matches_shot":marker_matches and same_launch,"hit":hit,"assist_budget_deg":rad_to_deg(budget),
		"max_step_deg":max_step,"used_correction":successful_turn,"passed":ok}

func _check_wreck(fight: Node) -> Dictionary:
	var opponent = fight.fleet[1]
	var previous_id: String = opponent.type.id
	fight._change_plane(opponent, "j20")
	var prefractured = opponent.rig.breakup
	var at := Vector3(730.0, 1950.0, 550.0)
	opponent.reset(at, Vector3.FORWARD, 220.0, 50.0)
	var kills: int = fight.player.kills
	var shown: Array[Vector3] = []
	var on_breakup := func(point: Vector3, _wet: bool) -> void: shown.append(point)
	fight.effects.wreck_breakup.connect(on_breakup)
	fight._destroy(opponent, fight.player, at + Vector3(0.5, 0.3, -2.0))
	var immediate: bool = opponent.hp == 0.0 and fight.player.kills == kills + 1
	var retained: bool = opponent.model.visible and fight.effects.wrecks.has(opponent.model)
	fight.effects.tick(0.2, fight.world)
	var drifted: bool = opponent.model.position.distance_to(at) > 20.0 and opponent.model.visible and shown.is_empty()
	fight.effects.tick(0.6, fight.world)
	var detached: bool = not opponent.model.visible and not fight.effects.wrecks.has(opponent.model) and not fight.effects.active_fragments.is_empty()
	var event_at_wreck: bool = shown.size() == 1 and shown[0].is_equal_approx(opponent.model.position)
	fight.effects.wreck_breakup.disconnect(on_breakup)
	var pieces_match: bool = prefractured != null and prefractured.get_child_count() == 5 and fight.effects.active_fragments.size() == 5
	fight._change_plane(opponent, previous_id)
	var ok := immediate and retained and drifted and detached and event_at_wreck and pieces_match
	failed += int(not ok)
	return {"scenario":"wreck_lifecycle","uses_prefractured_meshes":pieces_match, "counts_immediately":immediate, "visible_after_kill":retained,
		"moves_before_breakup":drifted, "releases_components":detached, "breakup_event_at_wreck":event_at_wreck, "passed":ok}

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
	var tip: Vector3 = fight.effects.trails.closing_tip
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

func _check_target_continuity(fight: Node) -> Dictionary:
	var at: Vector3 = fight.world.local_position(Vector3(11450.0, 1900.0, 5150.0))
	var original = fight.fleet[1]
	var entrant = fight._make_plane("j10", 1)
	fight.player.reset(at, Vector3.FORWARD, 240.0, 4200.0)
	original.reset(at + Vector3(106, 10, -960), Vector3.LEFT, 210.0, 3000.0)
	entrant.reset(at + Vector3(450, -20, -610), Vector3.LEFT, 210.0, 3000.0)
	fight._reset_player_spawn()
	fight.seek_due = 0.0
	fight._targeting(STEP)
	var acquired: bool = fight.target == original and not fight.is_locked()
	entrant.position = at + Vector3(2, -2, -490)
	for i in 120:
		fight.time += STEP
		fight._targeting(STEP)
	var held: bool = fight.target == original and fight.is_locked()
	original.reset(at + Vector3(350, 10, -510), Vector3.LEFT, 210.0, 3000.0)
	var dropped: bool = fight.target == null and not fight.is_locked()
	fight.time += 0.09
	fight._targeting(STEP)
	var reacquired: bool = fight.target == entrant and not fight.is_locked()
	var ok := acquired and held and dropped and reacquired
	if not ok:
		failed += 1
	return {"scenario":"target_continuity", "captures_original":acquired,"resists_switching":held,
		"rejects_reused_airframe":dropped,"starts_new_capture":reacquired,"passed":ok}

func _check_hidden_contact(fight: Node) -> Dictionary:
	var at: Vector3 = fight.world.local_position(Vector3(11450.0, 2300.0, 5150.0))
	var mark = fight.fleet[1]
	fight.player.reset(at, Vector3.FORWARD, 240.0, 4200.0)
	mark.reset(at + Vector3(50, 0, -700), Vector3.LEFT, 200.0, 3000.0)
	for i in range(2, fight.fleet.size()):
		fight.fleet[i].hp = 0.0
	fight._reset_player_spawn()
	fight.seek_due = 0.0
	for i in 100:
		fight.time += STEP
		fight._targeting(STEP)
	var locked: bool = fight.is_locked()
	var original: Vector3 = mark.position
	mark.position = at + Vector3(530, 0, -610)
	fight.time += 0.09
	fight._targeting(STEP)
	var held: bool = fight.target == mark and not fight.is_locked()
	mark.position = original
	fight.time += 0.10
	fight._targeting(STEP)
	var recovered: bool = fight.target == mark and fight.is_locked()
	fight.steering_amount = 0.9
	mark.position = at + Vector3(530, 0, -610)
	fight.time += STEP
	fight._targeting(STEP)
	var released: bool = fight.target == null and not fight.is_locked()
	var ok := locked and held and recovered and released
	if not ok:
		failed += 1
	return {"scenario":"hidden_contact", "locked":locked,"retains_brief_loss":held,
		"reacquires_same_contact":recovered,"manual_breaks_tracking":released,"passed":ok}
