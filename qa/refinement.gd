extends SceneTree

const Data = preload("res://game/catalogue.gd")
const Flight = preload("res://game/flight_body.gd")
const Battle = preload("res://game/battle.gd")
const Profile = preload("res://game/profile.gd")
var failures := 0

func _initialize() -> void:
	run.call_deferred()

func check(ok: bool, description: String) -> void:
	if not ok:
		failures += 1
		printerr(description)

func touch(shell: Node, index: int, position: Vector2, pressed: bool) -> void:
	var event := InputEventScreenTouch.new()
	event.index = index
	event.position = position
	event.pressed = pressed
	shell._input(event)

func drag(shell: Node, index: int, position: Vector2) -> void:
	var event := InputEventScreenDrag.new()
	event.index = index
	event.position = position
	shell._input(event)

func check_boost(fight: Battle, hud: Control) -> void:
	var boost_button: Button = hud.artifacts[1].button
	var at := boost_button.get_global_rect().get_center()
	touch(hud, 3, at, true)
	touch(hud, 4, at, true)
	touch(hud, 3, Vector2.ZERO, false)
	check(fight.action.get("boost", false), "Releasing one of two boost touches stopped thrust")
	for step in 540:
		fight.time += 1.0 / 90.0
		fight._update_player(1.0 / 90.0)
	check(fight.action.get("boost", false) and fight.player.boost > 0.98, "Holding boost for six seconds timed out")
	var shift := InputEventKey.new()
	shift.physical_keycode = KEY_SHIFT
	shift.pressed = true
	hud._input(shift)
	var cancel := InputEventScreenTouch.new()
	cancel.index = 4
	cancel.canceled = true
	hud._input(cancel)
	check(fight.action.get("boost", false), "Canceling touch canceled a held Shift")
	shift.pressed = false
	hud._input(shift)
	check(not fight.action.has("boost"), "Shift release left boost stuck")
	boost_button.button_down.emit()
	check(fight.action.get("boost", false), "Immediate next boost press was blocked")
	var mouse_up := InputEventMouseButton.new()
	mouse_up.button_index = MOUSE_BUTTON_LEFT
	mouse_up.position = Vector2.ZERO
	hud._input(mouse_up)
	check(not fight.action.has("boost"), "Mouse release outside the boost button left boost stuck")
	touch(hud, 4, at, true)
	hud.notification(NOTIFICATION_APPLICATION_FOCUS_OUT)
	check(not fight.action.has("boost"), "Application focus loss left boost stuck")

	var start := Vector3.UP * 3000.0
	var normal := Flight.new()
	normal.type = fight.player.type
	normal.reset(start, Vector3.FORWARD, 250.0, 4200.0)
	normal.move(1.0 / 90.0, Vector3.ZERO, 1.0, false, 0.0, false)
	var switched := Flight.new()
	switched.type = normal.type
	switched.reset(start, Vector3.FORWARD, 250.0, 4200.0)
	switched.move(1.0 / 90.0, Vector3.ZERO, 1.0, true, 0.0, false)
	check(switched.velocity.dot(Vector3.FORWARD) > normal.velocity.dot(Vector3.FORWARD), "First held physics step did not increase thrust")
	switched.reset(start, Vector3.FORWARD, 250.0, 4200.0)
	switched.boost = 1.0
	switched.move(1.0 / 90.0, Vector3.ZERO, 1.0, false, 0.0, false)
	check(switched.velocity.is_equal_approx(normal.velocity) and switched.boost > 0.0, "Release left residual thrust or snapped the visual transition")

func check_defensive_cooldowns(fight: Battle) -> void:
	var started := fight.time
	fight.action.evade = true
	fight.action.counter = true
	fight._update_player(1.0 / 90.0)
	check(is_equal_approx(fight.player.evade_at - started, 1.0)
		and is_equal_approx(fight.player.counter_at - started, 1.0), "Defensive cooldowns differ from one second")
	check(is_equal_approx(fight.player.evade_until - started, 0.78)
		and is_equal_approx(fight.player.counter_until - started, 0.83), "Defensive effect lengths changed")
	fight.time = started + 0.99
	fight.action.evade = true
	fight.action.counter = true
	fight._update_player(1.0 / 90.0)
	check(is_equal_approx(fight.player.evade_at, started + 1.0)
		and is_equal_approx(fight.player.counter_at, started + 1.0), "A defensive action restarted during its cooldown")
	fight.time = started + 1.0
	fight.action.evade = true
	fight.action.counter = true
	fight._update_player(1.0 / 90.0)
	check(is_equal_approx(fight.player.evade_at, started + 2.0)
		and is_equal_approx(fight.player.counter_at, started + 2.0), "A defensive action missed its one-second restart")

func run() -> void:
	var data := Data.new()
	var plane := Flight.new()
	plane.type = data.aircraft("j20")
	plane.reset(Vector3.UP * 4500.0, Vector3.FORWARD, 250.0, 4200.0)
	var bounds_ok := true
	var largest_bank := 0.0
	var highest_pitch := 0.0
	var lowest_pitch := 0.0
	for input in [Vector3(1, 1, 0), Vector3(-1, -1, 0), Vector3(0, 1, 0)]:
		for i in 300:
			plane.move(1.0 / 90.0, input, 1.0, false, 0.0, false)
			var bank := atan2((plane.attitude * Vector3.RIGHT).y, (plane.attitude * Vector3.UP).y)
			var pitch := asin(plane.forward.y)
			largest_bank = maxf(largest_bank, absf(bank))
			highest_pitch = maxf(highest_pitch, pitch)
			lowest_pitch = minf(lowest_pitch, pitch)
			bounds_ok = bounds_ok and absf(bank) <= Flight.MAX_BANK + 0.0001 and pitch <= Flight.MAX_CLIMB + 0.0001 and pitch >= -Flight.MAX_DIVE - 0.0001
	check(bounds_ok, "Regular flight escaped the calibrated envelope")
	var before := plane.attitude
	plane.move(1.0 / 90.0, Vector3.ZERO, 1.0, false, 0.0, false)
	check(plane.attitude.angle_to(before) < 0.06, "Neutral input snapped the orientation")
	for i in 180:
		plane.move(1.0 / 90.0, Vector3.ZERO, 1.0, false, 0.0, false)
	check(absf((plane.attitude * Vector3.RIGHT).y) < 0.05 and absf(plane.forward.y) < 0.05, "Neutral input failed to recover level")
	check(Battle.flight_input(Vector2(0.2, 0)).x < 0.10 and Battle.flight_input(Vector2.RIGHT).x == 1.0, "Nonlinear input response")

	var shell := load("res://scenes/main.tscn").instantiate() as Node
	root.add_child(shell)
	await process_frame
	var initial_id: int = shell.showcase_aircraft.get_child(0).get_instance_id()
	var original: float = shell.orbit_scale
	var point := Vector2(390, 300)
	touch(shell, 0, point, true)
	touch(shell, 1, point + Vector2(180, 0), true)
	drag(shell, 1, point + Vector2(234, 0))
	check(shell.orbit_scale < original, "Spreading fingers did not zoom in")
	drag(shell, 1, point + Vector2(136, 0))
	check(shell.orbit_scale > original, "Pinching fingers did not zoom out")
	var zoom: float = shell.orbit_scale
	touch(shell, 1, Vector2.ZERO, false)
	var heading: float = shell.orbit_spin
	drag(shell, 0, point + Vector2(80, 50))
	check(shell.orbit_scale == zoom and shell.orbit_spin != heading, "Lifting one finger interrupted or jumped the orbit")
	touch(shell, 7, point + Vector2(290, 0), true)
	check(shell.orbit_scale == zoom, "A new pinch jumped before movement")
	touch(shell, 7, Vector2.ZERO, false)
	touch(shell, 0, Vector2.ZERO, false)
	shell._open("hangar")
	check(shell.showcase_aircraft.get_child(0).get_instance_id() == initial_id and shell.orbit_scale == zoom, "Opening the hangar replaced the same airframe or lost framing")
	touch(shell, 0, Vector2(44, 40), true)
	check(shell.orbit_touches.is_empty(), "Actuating the header was captured by the orbit")
	shell._start_free()
	while shell.loading:
		await process_frame
	var fight := shell.current_battle as Battle
	fight.set_physics_process(false)
	fight.set_process(false)
	var cap := 0
	var active := 0
	for frame in 900:
		fight._physics_process(1.0 / 90.0)
		var groups := {}
		for actor in fight.fleet:
			if actor.hp > 0.0 and actor != fight.player and actor.target and actor.target.hp > 0.0:
				groups[actor.target.index] = groups.get(actor.target.index, 0) + 1
				cap = maxi(cap, groups[actor.target.index])
		active = maxi(active, groups.size())
	check(cap <= 2 and active >= 4, "Free-combat bots clustered around targets")
	var high := fight.player.position
	high.y = 3000.0
	fight.player.reset(high, Vector3.FORWARD, 250.0, 4200.0)
	fight._reset_player_spawn()
	var hud = shell.active_hud
	hud.clear_input()
	var flight_point: Vector2 = hud.input_pad.get_center()
	# Retired gestures and shortcut must not issue a maneuver.
	for tap in 2:
		for pressed in [true, false]:
			var event := InputEventScreenTouch.new()
			event.index = 0
			event.position = flight_point
			event.pressed = pressed
			hud._unhandled_input(event)
	check(fight.action.is_empty() and fight.stick == Vector2.ZERO and not hud.steer_touch, "Double tap still triggers an action or leaves steering active")
	for click in 2:
		for pressed in [true, false]:
			var event := InputEventMouseButton.new()
			event.button_index = MOUSE_BUTTON_LEFT
			event.position = flight_point
			event.pressed = pressed
			event.double_click = click == 1 and pressed
			hud._unhandled_input(event)
	check(fight.action.is_empty() and fight.stick == Vector2.ZERO and not hud.steer_touch, "Double click still triggers an action or leaves steering active")
	var key := InputEventKey.new()
	key.physical_keycode = KEY_R
	key.pressed = true
	hud._unhandled_input(key)
	check(fight.action.is_empty(), "Retired R shortcut still triggers an action")
	var nose := Vector3(fight.player.forward.x, 0.0, fight.player.forward.z).normalized()
	for i in 306:
		fight._update_player(1.0 / 90.0)
	var neutral_heading_change := rad_to_deg(nose.angle_to(Vector3(fight.player.forward.x, 0.0, fight.player.forward.z).normalized()))
	check(neutral_heading_change < 1.0, "Retired inputs still change neutral flight heading")
	var press := InputEventScreenTouch.new()
	press.index = 0
	press.position = flight_point
	press.pressed = true
	hud._unhandled_input(press)
	var motion := InputEventScreenDrag.new()
	motion.index = 0
	motion.position = flight_point + Vector2(70.0, 0.0)
	hud._unhandled_input(motion)
	check(fight.stick.x > 0.0 and hud.steer_touch, "Normal drag steering stopped working")
	press.pressed = false
	press.position = motion.position
	hud._unhandled_input(press)
	check(not hud.steer_touch, "Normal drag release did not clear touch ownership")
	hud.clear_input()
	check_boost(fight, hud)
	check_defensive_cooldowns(fight)
	touch(hud, 4, hud.artifacts[1].button.get_global_rect().get_center(), true)
	shell.active_hud.input_actions.pause.pressed.emit()
	check(not fight.action.has("boost"), "Pausing left boost held")
	var actions: Control = shell.pause_ui.body
	check(fight.paused and actions.get_child_count() == 5, "Pause actions are missing")
	(actions.get_node("飞行设置") as Button).pressed.emit()
	check(shell.pause_ui.body.has_node("返回暂停"), "Flight settings did not open")
	(shell.pause_ui.body.get_node("返回暂停") as Button).pressed.emit()
	(shell.pause_ui.body.get_node("继续飞行") as Button).pressed.emit()
	check(not fight.paused, "Resume did not unpause the battle")
	shell.queue_free()
	await process_frame
	print(JSON.stringify({"failures":failures,"bank_peak":rad_to_deg(largest_bank),"climb_peak":rad_to_deg(highest_pitch),"dive_peak":rad_to_deg(lowest_pitch),"neutral_heading_change_degrees":neutral_heading_change,"pursuit_cap":cap,"concurrent_targets":active}))
	quit(0 if failures == 0 else 1)
