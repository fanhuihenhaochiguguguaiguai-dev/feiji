extends Control

const HUD_ART = preload("res://assets/ui/combat-hud.webp")
const Frame = preload("res://game/reference_frame.gd")
const REFERENCE := Vector2(1774, 887)
const TELEMETRY := Rect2(40, 88, 416, 204)
const STATUS := Rect2(558, 86, 655, 74)
const RADAR := Rect2(1410, 79, 231, 209)
const PAUSE := Rect2(1611, 73, 86, 84)
const WARNING := Rect2(605, 666, 537, 118)
const RETICLE_SIDES := [Rect2(480, 191, 223, 395), Rect2(1064, 190, 223, 396)]
const ACTION_ART := {
	"counter": Rect2(73, 376, 270, 127), "boost": Rect2(73, 500, 270, 110),
	"evade": Rect2(73, 606, 270, 128), "gun": Rect2(1455, 350, 187, 162),
	"missile": Rect2(1385, 510, 315, 247),
}

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
var boost_keys := {}
var boost_mouse_held := false
var input_actions := {}
var input_pad := Rect2()
var backdrop := Node2D.new()
var contact_visibility := {}
var contact_revision := -1
var drawn_time := -1.0
var safe_rect := Rect2()
var art_scale := 1.0
var radar_area := Rect2()
var telemetry_area := Rect2()
var status_area := Rect2()

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	for data in [["反制导弹", "counter"], ["加速", "boost"], ["躲避", "evade"], ["机炮", "gun"], ["导弹", "missile"]]:
		var button := Button.new()
		button.flat = true
		button.focus_mode = Control.FOCUS_NONE
		button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		button.tooltip_text = data[0]
		if data[1] == "missile":
			button.disabled = fight.player.type.rails.is_empty()
		if data[1] == "boost":
			button.button_down.connect(_boost_mouse.bind(true))
			button.button_up.connect(_boost_mouse.bind(false))
		else:
			button.button_down.connect(func(): _trigger(data[1], true))
			if data[1] in ["gun", "missile"]:
				button.button_up.connect(func(): _trigger(data[1], false))
		if OS.has_feature("android"):
			button.mouse_filter = Control.MOUSE_FILTER_IGNORE
		button.pressed.connect(func(): queue_redraw())
		add_child(button)
		artifacts.append({"button":button, "action":data[1], "art":ACTION_ART[data[1]]})
	for entry in [["", "pause"], ["视角", "view"]]:
		var button := Button.new()
		button.text = entry[0]
		button.flat = entry[1] == "pause"
		button.tooltip_text = "暂停" if entry[1] == "pause" else "切换视角"
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
	safe_rect = Frame.safe_bounds(self, size)
	art_scale = minf(safe_rect.size.x / REFERENCE.x, safe_rect.size.y / REFERENCE.y)
	var scale_now := maxf(0.001, art_scale)
	telemetry_area = _place(TELEMETRY)
	status_area = _place(STATUS, 0.5)
	radar_area = _place(RADAR, 1.0)
	var pause_area := _place(PAUSE, 1.0)
	input_actions.pause.position = pause_area.position
	input_actions.pause.size = pause_area.size
	var view_size := Vector2(59, 50) * scale_now
	input_actions.view.add_theme_font_size_override("font_size", _points(21))
	input_actions.view.size = view_size
	input_actions.view.position = Vector2(safe_rect.end.x - view_size.x - 12.0 * scale_now, pause_area.end.y + 11.0 * scale_now)
	for item in artifacts:
		var area := _place(item.art, 1.0 if item.action in ["gun", "missile"] else 0.0)
		item.area = area
		item.centre = area.get_center()
		item.button.position = area.position
		item.button.size = area.size
	var left := safe_rect.position.x + 357.0 * scale_now
	var right := safe_rect.end.x - 318.0 * scale_now
	var top := status_area.end.y + 6.0 * scale_now
	input_pad = Rect2(Vector2(left, top), Vector2(maxf(1.0, right - left), maxf(1.0, safe_rect.end.y - top)))
	backdrop.queue_redraw()
	queue_redraw()

func _place(source: Rect2, horizontal := 0.0) -> Rect2:
	var pad := safe_rect.size.x - REFERENCE.x * art_scale
	var x := safe_rect.position.x + source.position.x * art_scale + pad * horizontal
	if horizontal == 1.0:
		x += 58.0 * art_scale
	var y := safe_rect.position.y + source.get_center().y / REFERENCE.y * safe_rect.size.y - source.size.y * art_scale * 0.5
	return Rect2(Vector2(x, y), source.size * art_scale)

func _draw_backdrop() -> void:
	backdrop.draw_texture_rect_region(HUD_ART, telemetry_area, TELEMETRY)
	backdrop.draw_texture_rect_region(HUD_ART, status_area, STATUS)
	backdrop.draw_texture_rect_region(HUD_ART, radar_area, RADAR)
	backdrop.draw_texture_rect_region(HUD_ART, _place(PAUSE, 1.0), PAUSE)
	var label_at := telemetry_area.position + Vector2(8, 227) * art_scale
	backdrop.draw_string(typeface, label_at, fight.task.name, HORIZONTAL_ALIGNMENT_LEFT, -1, _points(18), cream)

func _points(reference_size: float) -> int:
	return maxi(10, roundi(reference_size * art_scale))

func _process(delta: float) -> void:
	if not is_instance_valid(fight):
		return
	if fight.player.hp <= 0.0 and (boost_mouse_held or not boost_keys.is_empty() or "boost" in weapon_fingers.values()):
		_clear_boost()
	if not steer_touch and fight.stick.length_squared() > 0.0001:
		fight.stick = fight.stick.lerp(Vector2.ZERO, 1.0 - exp(-delta * 9.0))
	if fight.time != drawn_time:
		drawn_time = fight.time
		queue_redraw()

func _trigger(action: String, pressed: bool) -> void:
	if action in ["gun", "missile"]:
		fight.set_weapon_trigger(action, pressed)
	elif action == "boost":
		_sync_boost()
	elif pressed:
		fight.action[action] = true

func _boost_mouse(pressed: bool) -> void:
	boost_mouse_held = pressed
	_sync_boost()

func _sync_boost() -> void:
	if not is_instance_valid(fight):
		return
	if not paused and not fight.paused and fight.player.hp > 0.0 and (
			boost_mouse_held or not boost_keys.is_empty() or "boost" in weapon_fingers.values()):
		fight.action.boost = true
	else:
		fight.action.erase("boost")
	queue_redraw()

func _clear_boost() -> void:
	boost_keys.clear()
	boost_mouse_held = false
	for index in weapon_fingers.keys():
		if weapon_fingers[index] == "boost":
			weapon_fingers.erase(index)
	_sync_boost()

func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT:
		_clear_boost()

func clear_input() -> void:
	steer_touch = false
	touch_index = -3
	weapon_fingers.clear()
	_clear_boost()
	if is_instance_valid(fight):
		fight.action.clear()
		fight.stick = Vector2.ZERO

func _input(event: InputEvent) -> void:
	if not is_instance_valid(fight) or not fight.ready_for_play or paused or fight.paused:
		return
	if event is InputEventKey and event.physical_keycode == KEY_SHIFT and not event.echo:
		if event.pressed and fight.player.hp > 0.0:
			boost_keys[event.location] = true
		else:
			boost_keys.erase(event.location)
		_sync_boost()
		get_viewport().set_input_as_handled()
	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and not event.pressed and boost_mouse_held:
		_boost_mouse(false)
	elif event is InputEventScreenTouch and event.pressed and not event.canceled:
		for item in artifacts:
			if not item.button.disabled and (item.action != "boost" or fight.player.hp > 0.0) and item.button.get_global_rect().has_point(event.position):
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
	var vital := telemetry_area.position
	var integrity := clampf(jet.hp / jet.max_hp, 0.0, 1.0)
	_text(vital + Vector2(115, 43) * art_scale, jet.type.name, _points(24), top_left)
	_text(vital + Vector2(286, 65) * art_scale, "机体 %d%%" % roundi(integrity * 100.0), _points(18), cream)
	draw_rect(Rect2(vital + Vector2(54, 60) * art_scale, Vector2(220, 5) * art_scale), Color("#143c52"))
	draw_rect(Rect2(vital + Vector2(54, 60) * art_scale, Vector2(220 * integrity, 4) * art_scale), cyan)
	_text(vital + Vector2(170, 101) * art_scale, "%d 公里/时" % int(jet.velocity.length() * 3.6), _points(23), top_left)
	_text(vital + Vector2(170, 130) * art_scale, "%d 米" % int(jet.position.y), _points(23), top_left)
	_text(vital + Vector2(170, 158) * art_scale, "%03d°" % int(fposmod(rad_to_deg(atan2(jet.forward.x, -jet.forward.z)), 360)), _points(23), top_left)
	var progress: String
	var clock := int(now)
	if fight.mode == "campaign":
		progress = "第 %d / %d 波" % [fight.wave, fight.task.engagement.waves.size()]
	elif fight.mode == "free":
		progress = "击落 %d   ·   死亡 %d   ·   在场 %d/%d" % [fight.player_kills, fight.respawns, fight.alive_enemies() + int(jet.hp > 0.0), fight.fleet.size()]
		clock = ceili(maxf(0.0, fight.FREE_LENGTH - now))
	else:
		progress = fight.task.detail
	var status_y := status_area.position.y + 40.0 * art_scale
	if fight.mode == "campaign":
		_center_text(Vector2(status_area.position.x + 134.0 * art_scale, status_y), progress, _points(25), top_left)
		_center_text(Vector2(status_area.position.x + 344.0 * art_scale, status_y), "剩余敌机 %d" % fight.alive_enemies(), _points(24), cream)
	else:
		_center_text(Vector2(status_area.position.x + 226.0 * art_scale, status_y), progress, _points(20), top_left)
	_center_text(Vector2(status_area.position.x + 570.0 * art_scale, status_y), "%02d:%02d" % [clock / 60, clock % 60], _points(24), top_left)
	if not fight.warning and now < fight.countered_until:
		_center_text(Vector2(w * 0.5, 78), "反制成功", 18, Color("#77e6a3"))
	var radar := radar_area.position + Vector2(115, 105) * art_scale
	var radar_radius := 92.0 * art_scale
	for other in fight.fleet:
		if other == jet or other.hp <= 0.0:
			continue
		var vector: Vector3 = jet.attitude.inverse() * (other.position - jet.position)
		var p: Vector2 = Vector2(vector.x, vector.z) / fight.radar_range
		if p.length() <= 1.0:
			draw_circle(radar + p * radar_radius, 3.1 if other == fight.target else 2.1, pink if other == fight.target else cream, true, -1, true)
	var aim := _aim_at(jet.position + jet.forward * 1200.0)
	var p1 := _aim_at(jet.position + jet.forward.rotated(jet.attitude * Vector3.UP, fight.LOCK_ANGLE) * 1200.0)
	var radius := clampf(aim.distance_to(p1), 68.0, h * 0.33)
	var locked: bool = fight.is_locked()
	var acquired: float = fight.lock_fraction()
	if fight.warning:
		var bearing: Vector3 = jet.attitude.inverse() * fight.incoming_heading
		var edge := Vector2(bearing.x, clampf(bearing.z - bearing.y, -1.0, 1.0)).normalized()
		var blip: Vector2 = radar + Vector2(bearing.x, bearing.z) * (radar_radius * fight.closest_incoming / fight.radar_range)
		draw_arc(blip, 4.4, 0.0, TAU, 16, pink, 1.6, true)
		if edge.length_squared() > 0.0001:
			var p := aim + edge * (radius + 12.0)
			draw_colored_polygon(PackedVector2Array([p - edge * 8.0, p + edge.rotated(0.88) * 7.0, p + edge.rotated(-0.88) * 7.0]), pink)
	var reticle: Vector2 = _aim_at(fight.reticle_point) if not fight.camera.is_position_behind(fight.reticle_point) else aim
	if not fight.manual_cockpit:
		var shell_scale := art_scale * (0.86 if locked else 0.96)
		for trim: Rect2 in RETICLE_SIDES:
			var position := aim + (trim.position - Vector2(884, 394)) * shell_scale
			draw_texture_rect_region(HUD_ART, Rect2(position, trim.size * shell_scale), trim, Color(1, 1, 1, 0.73))
	var reticle_color := Color("#79f0a6") if locked else Color(cyan, 0.69)
	draw_arc(reticle, radius if locked else 17.0, 0.0, TAU, 64 if locked else 36, reticle_color, 1.2, true)
	for n in 4:
		var a := Vector2.RIGHT.rotated(n * PI * 0.5)
		draw_line(reticle + a * 14, reticle + a * 25, reticle_color, 1, true)
	draw_circle(reticle, 2.1, reticle_color, true, -1, true)
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
		var visible_position: Vector3 = other.model.global_position
		var p := _aim_at(visible_position)
		if fight.camera.is_position_behind(visible_position) or not Rect2(132, 85, w - 265, h - 152).has_point(p):
			if other == primary:
				var off: Vector2 = p - center
				if fight.camera.is_position_behind(visible_position):
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
		_draw_action(item, locked)
	if fight.warning:
		_draw_incoming_warning(jet, now)
	if now < 13.0:
		_center_text(Vector2(w * 0.5, h - 28), "滑动控制方向", 15, Color(cyan, 0.75))
	if jet.hp <= 0.0 and fight.mode == "free":
		_center_text(Vector2(w * 0.5, h - 77), "%d 秒后复活" % ceili(maxf(0.0, jet.until_respawn - now)), 22, cream)

func _draw_incoming_warning(jet: RefCounted, now: float) -> void:
	var at := Vector2(size.x * 0.5, size.y * 0.79)
	if not fight.manual_cockpit:
		var tail: Vector3 = jet.model.global_transform * Vector3(0.0, -0.4, float(jet.type.length) * 0.40)
		if not fight.camera.is_position_behind(tail):
			at = _aim_at(tail) + Vector2(0.0, 25.0)
	var label_size := WARNING.size * art_scale
	at.x = clampf(at.x, safe_rect.position.x + label_size.x * 0.5, safe_rect.end.x - label_size.x * 0.5)
	at.y = clampf(at.y, safe_rect.position.y + safe_rect.size.y * 0.60, safe_rect.end.y - label_size.y * 0.48)
	var urgent: float = 1.0 - smoothstep(160.0, 1150.0, fight.closest_incoming)
	var rhythm := 0.5 + 0.5 * sin(now * lerpf(9.0, 15.0, urgent))
	draw_texture_rect_region(HUD_ART, Rect2(at - label_size * 0.5, label_size), WARNING, Color(1, 1, 1, 0.79 + rhythm * 0.21))

func _draw_action(item: Dictionary, locked: bool) -> void:
	var name: String = item.action
	var weapon := name in ["gun", "missile"]
	var jet: RefCounted = fight.player
	var area: Rect2 = item.area
	var at: Vector2 = item.centre
	var active: bool = item.button.button_pressed or name in weapon_fingers.values()
	if name == "boost":
		active = bool(fight.action.get("boost", false))
	var tint := Color(1, 1, 1, 0.42 if item.button.disabled else 1.0)
	if active or (weapon and locked):
		tint = Color(1.14, 1.14, 1.14, tint.a)
	draw_texture_rect_region(HUD_ART, area, item.art, tint)
	var cool := 0.0
	match name:
		"missile": cool = (jet.missile_at - fight.time) / fight.MISSILE_CYCLE
		"counter": cool = (jet.counter_at - fight.time) / fight.COUNTER_CYCLE
		"evade": cool = (jet.evade_at - fight.time) / fight.EVADE_CYCLE
	cool = clampf(cool, 0.0, 1.0)
	if cool < 0.001:
		return
	var shade := Color("#050a14cf")
	if weapon:
		var step_count := maxi(1, ceili(cool * 36.0))
		var wedge := PackedVector2Array([at])
		for i in range(step_count + 1):
			wedge.append(at + Vector2.UP.rotated(TAU * cool * i / step_count) * area.size * 0.40)
		draw_colored_polygon(wedge, shade)
	else:
		var inset := area.size * Vector2(0.12, 0.18)
		var inner := Rect2(area.position + inset, area.size - inset * 2.0)
		var height := inner.size.y * cool
		_panel(Rect2(inner.position, Vector2(inner.size.x, height)), minf(height, 12.0 * art_scale), shade, Color.TRANSPARENT)

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
