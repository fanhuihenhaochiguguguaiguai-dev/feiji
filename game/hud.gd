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
var weapon_fingers := {}
var input_actions := {}
var input_pad := Rect2()
var backdrop := Node2D.new()
var contact_visibility := {}
var contact_revision := -1
var drawn_time := -1.0

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
		button.button_down.connect(func(): _trigger(data[1], true))
		if data[1] in ["gun", "missile"]:
			button.button_up.connect(func(): _trigger(data[1], false))
		if OS.has_feature("android"):
			button.mouse_filter = Control.MOUSE_FILTER_IGNORE
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
				clear_input()
				get_parent().get_parent().get_parent().show_pause(paused)
			else:
				fight.manual_cockpit = not fight.manual_cockpit
				fight.camera_fresh = true)
		button.modulate = Color(0.86, 0.94, 1, 0.83)
		button.add_theme_font_override("font", typeface)
		add_child(button)
		input_actions[entry[1]] = button

	backdrop.show_behind_parent = true
	backdrop.draw.connect(_draw_backdrop)
	add_child(backdrop)
	resized.connect(_layout)
	_layout()

func _layout() -> void:
	var w := size.x
	var h := size.y
	input_pad = Rect2(117, 89, w - 253, h - 160)
	input_actions.pause.position = Vector2(w - 65, 172)
	input_actions.pause.size = Vector2(38, 32)
	input_actions.view.position = Vector2(w - 65, 210)
	input_actions.view.size = Vector2(38, 32)
	for item in artifacts:
		var weapon: bool = item.action in ["gun", "missile"]
		var radius := 50.0 if item.action == "missile" else (42.0 if weapon else 35.0)
		var centre := Vector2(w - 84.0, h - (110.0 if item.slot == 1 else 227.0)) if weapon else Vector2(72.0, h * 0.49 + item.slot * 77.0)
		item.radius = radius
		item.centre = centre
		item.button.position = centre - Vector2.ONE * radius
		item.button.size = Vector2.ONE * radius * 2.0
	backdrop.queue_redraw()
	queue_redraw()

func _draw_backdrop() -> void:
	var radar := Vector2(size.x - 93, 92)
	_panel(Rect2(27, 18, 257, 131), 12.0, Color("#142437cf"), Color("#51758a88"), backdrop)
	backdrop.draw_rect(Rect2(45, 54, 198, 4), Color("#638b9c60"))
	backdrop.draw_string(typeface, Vector2(35, 171), fight.task.name, HORIZONTAL_ALIGNMENT_LEFT, -1, 16, cream)
	_panel(Rect2(size.x * 0.5 - 192, 14, 384, 34), 12.0, Color("#122337d0"), Color("#678b9a8c"), backdrop)
	backdrop.draw_circle(radar, 63.0, Color("#091b2baa"), true, -1.0, true)
	for radius in [21, 42, 63]:
		backdrop.draw_arc(radar, radius, 0, TAU, 64, Color("#7bbbd27c"), 1.0, true)
	backdrop.draw_line(radar - Vector2(63, 0), radar + Vector2(63, 0), Color("#5995b67a"))
	backdrop.draw_line(radar - Vector2(0, 63), radar + Vector2(0, 63), Color("#5995b67a"))
	backdrop.draw_colored_polygon(PackedVector2Array([radar + Vector2(0, -5), radar + Vector2(4, 5), radar + Vector2(-4, 5)]), cyan)
	var width := typeface.get_string_size("北", HORIZONTAL_ALIGNMENT_LEFT, -1, 12).x
	backdrop.draw_string(typeface, radar - Vector2(width * 0.5, 68), "北", HORIZONTAL_ALIGNMENT_LEFT, -1, 12, top_left)

func _process(delta: float) -> void:
	if not is_instance_valid(fight):
		return
	if not steer_touch and fight.stick.length_squared() > 0.0001:
		fight.stick = fight.stick.lerp(Vector2.ZERO, 1.0 - exp(-delta * 9.0))
	if fight.time != drawn_time:
		drawn_time = fight.time
		queue_redraw()

func _trigger(action: String, pressed: bool) -> void:
	if action in ["gun", "missile"]:
		fight.set_weapon_trigger(action, pressed)
	elif pressed:
		fight.action[action] = true

func clear_input() -> void:
	steer_touch = false
	touch_index = -3
	weapon_fingers.clear()
	if is_instance_valid(fight):
		fight.action.clear()
		fight.stick = Vector2.ZERO

func _input(event: InputEvent) -> void:
	if not is_instance_valid(fight) or not fight.ready_for_play or paused or fight.paused:
		return
	if event is InputEventScreenTouch and event.pressed:
		for item in artifacts:
			if not item.button.disabled and item.button.get_global_rect().has_point(event.position):
				weapon_fingers[event.index] = item.action
				_trigger(item.action, true)
				get_viewport().set_input_as_handled()
				return
	elif event is InputEventScreenTouch and weapon_fingers.has(event.index):
		var action: String = weapon_fingers[event.index]
		weapon_fingers.erase(event.index)
		if action not in weapon_fingers.values():
			_trigger(action, false)
		get_viewport().set_input_as_handled()

func _unhandled_input(event: InputEvent) -> void:
	if not is_instance_valid(fight) or paused or fight.paused:
		return
	var i := -3
	var pos := Vector2.ZERO
	var pressed := false
	var button := false
	if event is InputEventScreenTouch:
		i = event.index
		pos = event.position
		pressed = event.pressed and not event.canceled
		button = true
	elif event is InputEventScreenDrag:
		i = event.index
		pos = event.position
	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.device == InputEvent.DEVICE_ID_EMULATION:
			return
		i = -1
		pos = event.position
		pressed = event.pressed
		button = true
	elif event is InputEventMouseMotion:
		if event.device == InputEvent.DEVICE_ID_EMULATION:
			return
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
			get_viewport().set_input_as_handled()
	elif steer_touch and i == touch_index:
		var drive := (pos - touch_origin) / maxf(78.0, size.y * 0.17)
		drive.y *= 1.0 if fight.profile.state.settings.invert else -1.0
		fight.stick = (drive * (0.8 * fight.profile.state.settings.sensitivity)).limit_length()
		get_viewport().set_input_as_handled()

func _draw() -> void:
	if not is_instance_valid(fight) or not fight.is_inside_tree() or not fight.ready_for_play:
		return
	var w := size.x
	var h := size.y
	var center := size * 0.5
	var now: float = fight.time
	var jet: RefCounted = fight.player
	_text(Vector2(45, 44), "机体  %d" % ceili(jet.hp), 18, top_left)
	draw_rect(Rect2(45, 54, 198 * jet.hp / jet.max_hp, 4), Color("#7ce5c4"))
	_text(Vector2(45, 82), "空速    %d 公里/时" % int(jet.velocity.length() * 3.6), 15, top_left)
	_text(Vector2(45, 105), "高度    %d 米" % int(jet.position.y), 15, top_left)
	_text(Vector2(45, 128), "航向    %03d°" % int(fposmod(rad_to_deg(atan2(jet.forward.x, -jet.forward.z)), 360)), 15, top_left)
	var progress: String
	var clock := int(now)
	if fight.mode == "campaign":
		progress = "波次 %d / %d    ·    剩余敌机 %d" % [fight.wave, fight.task.engagement.waves.size(), fight.alive_enemies()]
	elif fight.mode == "free":
		progress = "击落 %d   ·   死亡 %d   ·   在场 %d/%d" % [fight.player_kills, fight.respawns, fight.alive_enemies() + int(jet.hp > 0.0), fight.fleet.size()]
		clock = ceili(maxf(0.0, fight.FREE_LENGTH - now))
	else:
		progress = fight.task.detail
	_center_text(Vector2(w * 0.5, 37), "%s    |    %02d:%02d" % [progress, clock / 60, clock % 60], 15, top_left)
	if fight.warning:
		_center_text(Vector2(w * 0.5, 78), "导弹来袭", 19, pink)
	elif now < fight.countered_until:
		_center_text(Vector2(w * 0.5, 78), "反制成功", 18, Color("#77e6a3"))
	var radar := Vector2(w - 93, 92)
	for other in fight.fleet:
		if other == jet or other.hp <= 0.0:
			continue
		var vector: Vector3 = jet.attitude.inverse() * (other.position - jet.position)
		var p: Vector2 = Vector2(vector.x, vector.z) / fight.radar_range
		if p.length() <= 1.0:
			draw_circle(radar + p * 61.0, 3.1 if other == fight.target else 2.1, pink if other == fight.target else cream, true, -1, true)
	var aim := _aim_at(jet.position + jet.forward * 1200.0)
	var p1 := _aim_at(jet.position + jet.forward.rotated(jet.attitude * Vector3.UP, fight.LOCK_ANGLE) * 1200.0)
	var radius := clampf(aim.distance_to(p1), 68.0, h * 0.33)
	var locked: bool = fight.is_locked()
	var acquired: float = fight.lock_fraction()
	if fight.warning:
		var bearing: Vector3 = jet.attitude.inverse() * fight.incoming_heading
		var edge := Vector2(bearing.x, clampf(bearing.z - bearing.y, -1.0, 1.0)).normalized()
		if edge.length_squared() > 0.0001:
			var p := aim + edge * (radius + 12.0)
			draw_colored_polygon(PackedVector2Array([p - edge * 8.0, p + edge.rotated(0.88) * 7.0, p + edge.rotated(-0.88) * 7.0]), pink)
	var reticle: Vector2 = _aim_at(fight.lead) if fight.target else aim
	draw_arc(reticle, 17, 0.0, TAU, 36, Color(cyan, 0.69), 1.0, true)
	for n in 4:
		var a := Vector2.RIGHT.rotated(n * PI * 0.5)
		draw_line(reticle + a * 14, reticle + a * 25, cyan, 1, true)
	draw_circle(reticle, 2.1, Color(cyan, 0.74), true, -1, true)
	var revision := floori(now * 14.0)
	if revision != contact_revision:
		contact_visibility.clear()
		contact_revision = revision
	var radar_range_squared: float = fight.radar_range * fight.radar_range
	var primary = fight.target
	if not primary and fight.mode == "campaign":
		var nearest := INF
		for other in fight.fleet:
			if other != jet and other.hp > 0.0:
				var range_squared: float = jet.position.distance_squared_to(other.position)
				if range_squared < nearest:
					nearest = range_squared
					primary = other
	for other in fight.fleet:
		if other == jet or other.hp <= 0.0 or (other != primary and jet.position.distance_squared_to(other.position) > radar_range_squared):
			continue
		var p := _aim_at(other.position)
		if fight.camera.is_position_behind(other.position) or not Rect2(132, 85, w - 265, h - 152).has_point(p):
			if other == primary:
				var off: Vector2 = p - center
				if fight.camera.is_position_behind(other.position):
					off = -off
				var n := off.normalized()
				var pointer := center + n * minf(h * 0.34, 178.0)
				draw_colored_polygon(PackedVector2Array([pointer + n * 10, pointer - n.rotated(0.62) * 7, pointer - n.rotated(-0.62) * 7]), Color(pink, 0.75))
			continue
		if not contact_visibility.has(other.life_id * 32 + other.index):
			contact_visibility[other.life_id * 32 + other.index] = not fight.world.obstruction(jet.position, other.position)
		if not contact_visibility[other.life_id * 32 + other.index]:
			continue
		var selected: bool = other == fight.target
		var tint := (Color("#79f0a6") if locked else pink) if selected else Color(top_left, 0.64)
		var frame_size := lerpf(h * 0.19, 24.0, smoothstep(0.0, 1.0, acquired)) if selected and not locked else 19.0
		var corner_length := maxf(8.0, frame_size * 0.25) if selected else 8.0
		if selected and locked:
			draw_arc(p, radius, 0.0, TAU, 64, Color(tint, 0.48), 1.3, true)
			draw_polyline(PackedVector2Array([p + Vector2(0, -15), p + Vector2(15, 0), p + Vector2(0, 15), p + Vector2(-15, 0), p + Vector2(0, -15)]), tint, 1.3, true)
		for corner in [Vector2(-1,-1), Vector2(1,-1), Vector2(-1,1), Vector2(1,1)]:
			var base: Vector2 = p + corner * frame_size
			draw_line(base, base - Vector2(corner.x * corner_length, 0), tint, 1.8 if selected else 1.1, true)
			draw_line(base, base - Vector2(0, corner.y * corner_length), tint, 1.8 if selected else 1.1, true)
		if selected:
			_center_text(p + Vector2(0, 42), "%s   %.2f 公里" % [other.type.name, jet.position.distance_to(other.position) / 1000.0], 14, tint)
	var since_hit: float = now - fight.hit_time
	var destroyed: bool = fight.hit_destroyed
	if since_hit < (0.68 if destroyed else 0.14) and not fight.camera.is_position_behind(fight.hit_position):
		var contact := _aim_at(fight.hit_position)
		if input_pad.has_point(contact):
			var mark := Color(cream, 1.0 - smoothstep(0.045, 0.68 if destroyed else 0.14, since_hit))
			if destroyed:
				_center_text(contact - Vector2(0, 20), "击毁", 19, mark)
			else:
				for direction in [Vector2(-1,-1), Vector2(1,-1), Vector2(-1,1), Vector2(1,1)]:
					draw_line(contact + direction * 6.0, contact + direction * 10.0, mark, 1.7, true)
	for item in artifacts:
		_draw_action(item)
	if now < 13.0:
		_center_text(Vector2(w * 0.5, h - 28), "滑动控制方向", 15, Color(cyan, 0.75))
	if jet.hp <= 0.0 and fight.mode == "free":
		_center_text(Vector2(w * 0.5, h - 77), "%d 秒后复活" % ceili(maxf(0.0, jet.until_respawn - now)), 22, cream)

func _draw_action(item: Dictionary) -> void:
	var name: String = item.action
	var side := name in ["gun", "missile"]
	var jet: RefCounted = fight.player
	var radius: float = item.radius
	var at: Vector2 = item.centre
	var active: bool = item.button.button_pressed or name in weapon_fingers.values()
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

func _panel(rect: Rect2, cut: float, fill: Color, trim: Color, canvas: CanvasItem = null) -> void:
	canvas = self if canvas == null else canvas
	var p := rect.position
	var e := rect.end
	var polygon := PackedVector2Array([p + Vector2(cut, 0), Vector2(e.x, p.y), e - Vector2(cut, 0), Vector2(p.x, e.y)])
	canvas.draw_colored_polygon(polygon, fill)
	polygon.append(polygon[0])
	canvas.draw_polyline(polygon, trim, 1.0, true)

func _text(at: Vector2, s: String, n: int, c: Color) -> void:
	draw_string(typeface, at, s, HORIZONTAL_ALIGNMENT_LEFT, -1, n, c)

func _center_text(at: Vector2, s: String, n: int, c: Color) -> void:
	_text(at - Vector2(typeface.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, n).x * 0.5, 0), s, n, c)
