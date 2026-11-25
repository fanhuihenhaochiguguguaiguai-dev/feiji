extends Control

var fight: Node3D
var typeface: Font
var artifacts := []
var top_left := Color("#d8edf2")
var cyan := Color("#67d7ee")
var pink := Color("#ff6e73")
var cream := Color("#efdaaa")
var touch_origin := Vector2.ZERO
var touch_index := -3
var steer_touch := false
var paused := false
var throttle_bar: HSlider
var input_actions := {}
var input_pad := Rect2()

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	for data in [["反制导弹", "counter","shield",0], ["加速","boost","boost",1], ["躲避","evade","evade",2], ["航炮","gun","gun",0], ["导弹","missile","missile",1]]:
		var button := Button.new()
		button.flat = true
		button.focus_mode = Control.FOCUS_NONE
		button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		button.tooltip_text = data[0]
		if data[1] == "missile":
			button.disabled = fight.player.type.rails.is_empty()
		button.button_down.connect(func(): fight.action[data[1]] = true)
		if data[1] in ["gun", "missile"]:
			button.button_up.connect(func(): fight.action[data[1]] = false)
		button.pressed.connect(func(): queue_redraw())
		add_child(button)
		artifacts.append({"button":button,"label":data[0],"action":data[1],"icon":data[2],"slot":data[3]})
	for entry in [["Ⅱ", "pause"], ["◉", "view"]]:
		var button := Button.new()
		button.text = entry[0]
		button.focus_mode = Control.FOCUS_NONE
		button.pressed.connect(func():
			if entry[1] == "pause":
				paused = not paused
				fight.paused = paused
				fight.action.clear()
				fight.stick = Vector2.ZERO
				get_parent().get_parent().get_parent().show_pause(paused)
			else:
				fight.manual_cockpit = not fight.manual_cockpit
				fight.camera_fresh = true)
		button.modulate = Color(0.86, 0.94, 1, 0.83)
		button.add_theme_font_override("font", typeface)
		add_child(button)
		input_actions[entry[1]] = button
	throttle_bar = HSlider.new()
	throttle_bar.max_value = 1.0
	throttle_bar.step = 0.01
	throttle_bar.value = fight.throttle
	throttle_bar.focus_mode = Control.FOCUS_NONE
	throttle_bar.value_changed.connect(func(value): fight.throttle = value)
	add_child(throttle_bar)

func _process(delta: float) -> void:
	if not is_instance_valid(fight):
		return
	if not steer_touch and fight.stick.length_squared() > 0.0001:
		fight.stick = fight.stick.lerp(Vector2.ZERO, 1.0 - exp(-delta * 9.0))
	queue_redraw()

func _unhandled_input(event: InputEvent) -> void:
	if not is_instance_valid(fight) or paused:
		return
	var i := -3
	var pos := Vector2.ZERO
	var pressed := false
	var button := false
	if event is InputEventScreenTouch:
		i = event.index
		pos = event.position
		pressed = event.pressed
		button = true
	elif event is InputEventScreenDrag:
		i = event.index
		pos = event.position
	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		i = -1
		pos = event.position
		pressed = event.pressed
		button = true
	elif event is InputEventMouseMotion:
		i = -1
		pos = event.position
	elif event is InputEventKey and event.pressed and not event.echo:
		match event.physical_keycode:
			KEY_E: fight.action.evade = true
			KEY_Q: fight.action.counter = true
			KEY_SHIFT: fight.action.boost = true
			KEY_G: fight.action.gear = true
			KEY_ESCAPE: input_actions.pause.pressed.emit()
		return
	if button:
		if pressed and input_pad.has_point(pos) and not steer_touch:
			steer_touch = true
			touch_index = i
			touch_origin = pos
			get_viewport().set_input_as_handled()
		elif not pressed and touch_index == i:
			steer_touch = false
			touch_index = -3
	elif steer_touch and i == touch_index:
		var drive := (pos - touch_origin) / maxf(78.0, size.y * 0.17)
		drive.y *= 1.0 if fight.profile.state.settings.invert else -1.0
		fight.stick = (drive * fight.profile.state.settings.sensitivity).limit_length()
		get_viewport().set_input_as_handled()

func _draw() -> void:
	if not is_instance_valid(fight) or not fight.ready_for_play:
		return
	var w := size.x
	var h := size.y
	var center := size * 0.5
	var now: float = fight.time
	var jet: RefCounted = fight.player
	input_pad = Rect2(117, 89, w - 253, h - 160)
	_panel(Rect2(27, 18, 257, 131), 12.0, Color("#142437cf"), Color("#51758a88"))
	_text(Vector2(45, 44), "机体  %d" % ceili(jet.hp), 18, top_left)
	draw_rect(Rect2(45, 54, 198, 4), Color("#638b9c60"))
	draw_rect(Rect2(45, 54, 198 * jet.hp / jet.max_hp, 4), Color("#7ce5c4"))
	_text(Vector2(45, 82), "空速    %d 公里/时" % int(jet.velocity.length() * 3.6), 15, top_left)
	_text(Vector2(45, 105), "高度    %d 米" % int(jet.position.y), 15, top_left)
	_text(Vector2(45, 128), "航向    %03d°" % int(fposmod(rad_to_deg(atan2(jet.forward.x, -jet.forward.z)), 360)), 15, top_left)
	_text(Vector2(35, 171), fight.task.name, 16, cream)
	var progress: String
	var clock := int(now)
	if fight.mode == "campaign":
		progress = "波次 %d / %d    ·    剩余敌机 %d" % [fight.wave, fight.task.engagement.waves.size(), fight.alive_enemies()]
	elif fight.mode == "free":
		progress = "击落 %d   ·   死亡 %d   ·   在场 %d/%d" % [fight.player_kills, fight.respawns, fight.alive_enemies() + int(jet.hp > 0.0), fight.fleet.size()]
		clock = ceili(maxf(0.0, fight.FREE_LENGTH - now))
	else:
		progress = fight.task.detail
	_panel(Rect2(w * 0.5 - 192, 14, 384, 34), 12.0, Color("#122337d0"), Color("#678b9a8c"))
	_center_text(Vector2(w * 0.5, 37), "%s    |    %02d:%02d" % [progress, clock / 60, clock % 60], 15, top_left)
	if fight.warning:
		_center_text(Vector2(w * 0.5, 78), "⚠ 敌机导弹来袭", 19, pink)
	var radar := Vector2(w - 93, 92)
	draw_circle(radar, 63.0, Color("#091b2baa"), true, -1.0, true)
	for radius in [21, 42, 63]:
		draw_arc(radar, radius, 0, TAU, 64, Color("#7bbbd27c"), 1.0, true)
	draw_line(radar - Vector2(63, 0), radar + Vector2(63, 0), Color("#5995b67a"))
	draw_line(radar - Vector2(0, 63), radar + Vector2(0, 63), Color("#5995b67a"))
	draw_colored_polygon(PackedVector2Array([radar + Vector2(0, -5), radar + Vector2(4, 5), radar + Vector2(-4, 5)]), cyan)
	_center_text(radar + Vector2(0, -68), "N", 12, top_left)
	for other in fight.fleet:
		if other == jet or other.hp <= 0.0:
			continue
		var vector: Vector3 = jet.attitude.inverse() * (other.position - jet.position)
		var p: Vector2 = Vector2(vector.x, vector.z) / fight.radar_range
		if p.length() <= 1.0:
			draw_circle(radar + p * 61.0, 3.1 if other == fight.target else 2.1, pink if other == fight.target else cream, true, -1, true)
	input_actions.pause.position = Vector2(w - 65, 172)
	input_actions.pause.size = Vector2(38, 32)
	input_actions.view.position = Vector2(w - 65, 210)
	input_actions.view.size = Vector2(38, 32)
	var aim := _aim_at(jet.position + jet.forward * 1200.0)
	var p1 := _aim_at(jet.position + jet.forward.rotated(jet.attitude * Vector3.UP, fight.LOCK_ANGLE) * 1200.0)
	var radius := clampf(aim.distance_to(p1), 68.0, h * 0.33)
	var circle_color := Color(cyan, 0.45 if fight.target else 0.24)
	for n in 48:
		var start: float = n * TAU / 48.0
		draw_arc(aim, radius, start, start + 0.085, 3, circle_color, 1.1, true)
	var reticle: Vector2 = _aim_at(fight.lead) if fight.target else aim
	draw_arc(reticle, 17, 0.0, TAU, 36, Color(cyan, 0.69), 1.0, true)
	for n in 4:
		var a := Vector2.RIGHT.rotated(n * PI * 0.5)
		draw_line(reticle + a * 14, reticle + a * 25, cyan, 1, true)
	draw_circle(reticle, 2.1, Color(cyan, 0.74), true, -1, true)
	for other in fight.fleet:
		if other == jet or other.hp <= 0.0 or jet.position.distance_to(other.position) > fight.radar_range:
			continue
		var p := _aim_at(other.position)
		if fight.camera.is_position_behind(other.position) or not Rect2(132, 85, w - 265, h - 152).has_point(p):
			if other == fight.target or other.index == 1:
				var off: Vector2 = p - center
				if fight.camera.is_position_behind(other.position):
					off = -off
				var n := off.normalized()
				var pointer := center + n * minf(h * 0.34, 178.0)
				draw_colored_polygon(PackedVector2Array([pointer + n * 10, pointer - n.rotated(0.62) * 7, pointer - n.rotated(-0.62) * 7]), Color(pink, 0.75))
			continue
		if fight.world.obstruction(jet.position, other.position):
			continue
		var lock: bool = other == fight.target and fight.is_locked()
		var tint := pink if lock else Color(top_left, 0.64)
		if lock:
			draw_polyline(PackedVector2Array([p + Vector2(0, -15), p + Vector2(15, 0), p + Vector2(0, 15), p + Vector2(-15, 0), p + Vector2(0, -15)]), tint, 1.3, true)
		for corner in [Vector2(-1,-1), Vector2(1,-1), Vector2(-1,1), Vector2(1,1)]:
			var base: Vector2 = p + corner * 19.0
			draw_line(base, base - Vector2(corner.x * 8, 0), tint, 1.1, true)
			draw_line(base, base - Vector2(0, corner.y * 8), tint, 1.1, true)
		if other == fight.target:
			_center_text(p + Vector2(0, 42), "%s   %.2f 公里" % [other.type.name, jet.position.distance_to(other.position) / 1000.0], 14, tint)
	for item in artifacts:
		_draw_action(item)
	_panel(Rect2(27, h - 59, 326, 39), 8.0, Color("#10263bdc"), Color("#456a7880"))
	_text(Vector2(44, h - 34), "油门 %d%%" % roundi(fight.throttle * 100.0), 15, top_left)
	throttle_bar.position = Vector2(135, h - 52)
	throttle_bar.size = Vector2(192, 28)
	if now < 13.0:
		_center_text(Vector2(w * 0.5, h - 28), "‹‹   滑动空白区域控制飞行   ››", 15, Color(cyan, 0.75))
	if jet.hp <= 0.0 and fight.mode == "free":
		_center_text(Vector2(w * 0.5, h - 77), "%d 秒后复活" % ceili(maxf(0.0, jet.until_respawn - now)), 22, cream)

func _draw_action(item: Dictionary) -> void:
	var slot: int = item.slot
	var name: String = item.action
	var side := name in ["gun", "missile"]
	var jet: RefCounted = fight.player
	var radius := 50.0 if name == "missile" else (42.0 if side else 35.0)
	var at := Vector2(size.x - 84.0, size.y - (110.0 if slot == 1 else 227.0)) if side else Vector2(72.0, size.y * 0.49 + slot * 77.0)
	item.button.position = at - Vector2.ONE * radius
	item.button.size = Vector2.ONE * radius * 2.0
	var active: bool = item.button.button_pressed
	var color := Color("#8ae7ff") if name == "missile" and fight.is_locked() else Color("#a8c5d8")
	var label := Color(top_left, 0.40) if item.button.disabled else top_left
	if item.button.disabled:
		color.a *= 0.4
	var cool := 0.0
	match name:
		"missile": cool = (jet.missile_at - fight.time) / fight.MISSILE_CYCLE
		"counter": cool = (jet.counter_at - fight.time) / fight.COUNTER_CYCLE
		"boost": cool = (fight.boost_at - fight.time) / fight.BOOST_CYCLE
		"evade": cool = (jet.evade_at - fight.time) / fight.EVADE_CYCLE
	if side:
		draw_circle(at, radius, Color("#143044d9") if active else Color("#0e1e30c2"), true, -1, true)
		draw_arc(at, radius, 0, TAU, 65, Color(color, 0.72), 1.2, true)
		if name == "missile" and fight.is_locked():
			draw_arc(at, radius - 2, -PI * 0.58, PI * 0.16, 30, cyan, 3.0, true)
	else:
		_panel(Rect2(at - Vector2.ONE * radius, Vector2.ONE * radius * 2.0), 9.0, Color("#153249e0") if active else Color("#0e1e30bf"), Color(color, 0.43))
	_symbol(at + Vector2(0, -10), item.icon, color)
	_center_text(at + Vector2(0, 21), item.label, 16, label)
	if cool > 0.0:
		var step_count := ceili(clampf(cool, 0, 1) * 42.0)
		var wedge := PackedVector2Array([at])
		for i in range(step_count + 1):
			wedge.append(at + Vector2.UP.rotated(TAU * minf(cool, i / 42.0)) * (radius - 1.0))
		if wedge.size() >= 3:
			draw_colored_polygon(wedge, Color("#050d19d9"))

func _symbol(at: Vector2, icon: String, color: Color) -> void:
	match icon:
		"shield":
			draw_polyline(PackedVector2Array([at+Vector2(-11,-9),at+Vector2(0,-15),at+Vector2(11,-9),at+Vector2(9,4),at+Vector2(0,11),at+Vector2(-9,4),at+Vector2(-11,-9)]),color,2.1,true)
			draw_line(at-Vector2(0,8),at+Vector2(0,3),color,2.0,true)
		"boost":
			for y in [-6, 3]:
				draw_polyline(PackedVector2Array([at+Vector2(-10,y+5),at+Vector2(0,y-3),at+Vector2(10,y+5)]), color, 2.6, true)
		"evade":
			draw_polyline(PackedVector2Array([at+Vector2(-12,8),at+Vector2(-2,-1),at+Vector2(3,0),at+Vector2(11,-11),at+Vector2(4,-9)]),color,2.5,true)
		"gun", "missile":
			for shift in ([0] if icon == "gun" else [-5, 6]):
				var p := at + Vector2(shift, 0)
				draw_line(p+Vector2(-12,9),p+Vector2(10,-10),color,3,true)
				draw_colored_polygon(PackedVector2Array([p+Vector2(7,-10),p+Vector2(15,-14),p+Vector2(12,-6)]), color)
				draw_line(p+Vector2(-12,3),p+Vector2(-7,9),color,2.5,true)

func _aim_at(p: Vector3) -> Vector2:
	return fight.camera.unproject_position(p)

func _panel(rect: Rect2, cut: float, fill: Color, trim: Color) -> void:
	var p := rect.position
	var e := rect.end
	var polygon := PackedVector2Array([p + Vector2(cut, 0), Vector2(e.x, p.y), e - Vector2(cut, 0), Vector2(p.x, e.y)])
	draw_colored_polygon(polygon, fill)
	polygon.append(polygon[0])
	draw_polyline(polygon, trim, 1.0, true)

func _text(at: Vector2, s: String, n: int, c: Color) -> void:
	draw_string(typeface, at, s, HORIZONTAL_ALIGNMENT_LEFT, -1, n, c)

func _center_text(at: Vector2, s: String, n: int, c: Color) -> void:
	_text(at - Vector2(typeface.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, n).x * 0.5, 0), s, n, c)
