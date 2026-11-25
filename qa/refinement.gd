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
	fight.action.turn = true
	var nose := Vector3(fight.player.forward.x, 0.0, fight.player.forward.z).normalized()
	for i in 306:
		fight._physics_process(1.0 / 90.0)
	var turn := rad_to_deg(nose.angle_to(Vector3(fight.player.forward.x, 0.0, fight.player.forward.z).normalized()))
	check(turn > 148.0, "Preserved reversal did not complete")
	shell.active_hud.input_actions.pause.pressed.emit()
	var actions: Control = shell.pause_ui.body
	check(fight.paused and actions.get_child_count() == 5, "Pause actions are missing")
	(actions.get_node("飞行设置") as Button).pressed.emit()
	check(shell.pause_ui.body.has_node("返回暂停"), "Flight settings did not open")
	(shell.pause_ui.body.get_node("返回暂停") as Button).pressed.emit()
	(shell.pause_ui.body.get_node("继续飞行") as Button).pressed.emit()
	check(not fight.paused, "Resume did not unpause the battle")
	shell.queue_free()
	await process_frame
	print(JSON.stringify({"failures":failures,"bank_peak":rad_to_deg(largest_bank),"climb_peak":rad_to_deg(highest_pitch),"dive_peak":rad_to_deg(lowest_pitch),"reverse_degrees":turn,"pursuit_cap":cap,"concurrent_targets":active}))
	quit(0 if failures == 0 else 1)
