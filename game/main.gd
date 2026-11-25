extends Node3D

const Data = preload("res://game/catalogue.gd")
const Profile = preload("res://game/profile.gd")
const Battle = preload("res://game/battle.gd")
const Landscape = preload("res://game/world.gd")
const Hud = preload("res://game/hud.gd")
const CutButton = preload("res://game/menu_panel.gd")

var catalogue := Data.new()
var profile := Profile.new(catalogue)
var font: Font
var layer := CanvasLayer.new()
var view: Control
var scene_3d: Node3D
var showcase: Node3D
var showcase_aircraft: Node3D
var current_battle: Battle
var debrief: Dictionary = {}
var route := "lobby"
var note := ""
var viewed_plane := "j20"
var takeoff := false
var list_chapter := 0
var selected_mission := 1
var panel_mods := false
var card_scroll := 0
var orbit_spin := -2.279
var orbit_tilt := 0.105
var orbit_scale := 1.0
var orbit_active := false
var orbit_touches := {}
var orbit_span := 0.0
var preview_camera: Camera3D
var active_hud: Control
var last_operation := {}
var light_load_label: Label
var load_meter: ProgressBar
var capture_dir := ""
var capture_free := false
var capture_time := 0.0
var screenshot_pending := false
var fixture_stage := 0
var fixture_marks := []
var frame_wall_samples := PackedFloat64Array()
var last_frame_usec := 0
var loading := false
var pause_ui: Control
var adaptive_clock := 0.0
var frame_average := 0.0
var slow_windows := 0
var fast_windows := 0

func _ready() -> void:
	font = load("res://assets/locale/PilotSC.otf")
	if font == null:
		font = ThemeDB.fallback_font
	Engine.max_fps = int(profile.state.settings.fps)
	get_viewport().scaling_3d_scale = float(profile.state.settings.quality)
	add_child(layer)
	get_viewport().size_changed.connect(func():
		if route != "battle":
			_render_menu())
	viewed_plane = str(profile.state.selected)
	selected_mission = int(profile.state.campaign)
	list_chapter = (selected_mission - 1) / 10
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--capture-dir="):
			capture_dir = arg.trim_prefix("--capture-dir=")
			DirAccess.make_dir_recursive_absolute(capture_dir)
		elif arg == "--capture-free":
			capture_free = true
	_open("lobby")

func _open(page: String) -> void:
	route = page
	note = ""
	if not is_instance_valid(showcase) and route != "battle":
		get_viewport().scaling_3d_scale = float(profile.state.settings.quality)
		_build_showcase()
	elif is_instance_valid(showcase):
		showcase.get_viewport().get_camera_3d().current = true
	if page in ["lobby", "training", "pilot", "settings", "report"]:
		viewed_plane = str(profile.state.selected)
		_set_showcase_aircraft(viewed_plane)
	_render_menu()

func _clear_ui() -> void:
	if is_instance_valid(view):
		layer.remove_child(view)
		view.queue_free()
	view = Control.new()
	view.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	view.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var theme := Theme.new()
	theme.default_font = font
	theme.default_font_size = 17
	view.theme = theme
	layer.add_child(view)

func _rect(nx: float, ny: float, width: float, height: float) -> Rect2:
	return Rect2(get_viewport().get_visible_rect().size * Vector2(nx, ny), Vector2(width, height))

func _panel(area: Rect2, color: Color = Color("#0d2033d9")) -> Panel:
	var p := Panel.new()
	p.position = area.position
	p.size = area.size
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var style := StyleBoxFlat.new()
	style.bg_color = color
	style.set_border_width_all(1)
	style.border_color = Color("#63869e71")
	style.set_corner_radius_all(3)
	p.add_theme_stylebox_override("panel", style)
	view.add_child(p)
	return p

func _text(at: Vector2, s: String, n := 18, color := Color("#e5eff6"), content_width := 0.0) -> Label:
	var item := Label.new()
	item.position = at
	item.text = s
	item.add_theme_font_size_override("font_size", n)
	item.add_theme_color_override("font_color", color)
	item.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if content_width > 0.0:
		item.size.x = content_width
		item.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	view.add_child(item)
	return item

func _cut(area: Rect2, text: String, icon: String, style: int, click: Callable) -> void:
	var button := CutButton.new()
	button.position = area.position
	button.size = area.size
	button.font = font
	button.title = text
	button.icon = icon
	button.variant = style
	button.activate = click
	view.add_child(button)

func _button(area: Rect2, text: String, click: Callable, active := true) -> Button:
	var b := Button.new()
	b.position = area.position
	b.custom_minimum_size = area.size
	b.text = text
	b.size = area.size
	b.disabled = not active
	b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	b.pressed.connect(click)
	for role in ["normal", "hover", "pressed", "disabled"]:
		var style := StyleBoxFlat.new()
		style.bg_color = Color("#142c43e8") if role == "normal" else (Color("#244e69ee") if role != "disabled" else Color("#101a27d0"))
		style.border_color = Color("#57839ca8")
		style.set_border_width_all(1)
		style.set_corner_radius_all(2)
		b.add_theme_stylebox_override(role, style)
	view.add_child(b)
	return b

func _render_menu() -> void:
	_clear_ui()
	var size := get_viewport().get_visible_rect().size
	_panel(Rect2(0, 0, size.x, 65.0), Color("#081726ec"))
	var crest := TextureRect.new()
	crest.texture = preload("res://assets/ui/crest.webp")
	crest.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	crest.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	crest.position = Vector2(26, 10)
	crest.size = Vector2(62, 44)
	crest.mouse_filter = Control.MOUSE_FILTER_IGNORE
	view.add_child(crest)
	_text(Vector2(100, 5), "苍穹锋刃", 33, Color("#e2effa"))
	_button(Rect2(size.x - 420, 12, 165, 41), "个人档案 · 等级 %d" % Data.level(int(profile.state.xp)), _open.bind("pilot"))
	_text(Vector2(size.x - 229, 19), "信用点  %s" % int(profile.state.credits), 19, Color("#f1d392"))
	_button(Rect2(size.x - 86, 12, 64, 41), "设置", _open.bind("settings"))
	for i in 3:
		var pages := ["lobby", "hangar", "campaign"]
		var labels := ["大厅", "战机机库", "战役"]
		var icons := ["home", "hangar", "map"]
		_cut(Rect2(21, size.y * 0.205 + i * 61.0, 166, 52), labels[i], icons[i], 0, _open.bind(pages[i]))
	if route == "lobby":
		var info := Vector2(24, size.y - 78)
		var plane := catalogue.aircraft(str(profile.state.selected))
		_panel(Rect2(info, Vector2(313, 58)), Color("#10273cde"))
		_text(info + Vector2(14, 4), str(plane.name), 26)
		_text(info + Vector2(16, 36), str(plane.role), 14, Color("#aac4d7"))
		_cut(Rect2(size.x - 345, size.y - 169, 321, 66), "开始战斗", "plane", 1, _start_campaign.bind(int(profile.state.campaign)))
		_cut(Rect2(size.x - 328, size.y - 92, 304, 51), "无限空战", "infinite", 2, _start_free)
		_button(Rect2(size.x - 492, size.y - 83, 139, 40), "训练模式", _open.bind("training"))
		return
	var p := Vector2(204, 94)
	var box_w := 426.0
	var sidebar := Vector2(size.x - box_w - 20, 93)
	match route:
		"campaign":
			_panel(Rect2(p, Vector2(size.x - p.x - 21, size.y - p.y - 25)))
			_text(p + Vector2(21, 11), "战区简报", 27)
			for i in 6:
				_button(Rect2(p + Vector2(21 + (i % 3) * 181, 64 + (i / 3) * 40), Vector2(166, 34)), catalogue.source.chapters[i], _select_chapter.bind(i))
			var ops: Array = catalogue.source.campaign
			for j in 10:
				var row: Dictionary = ops[list_chapter * 10 + j]
				var xy: Vector2 = p + Vector2(22 + (j % 2) * 270, 156 + (j / 2) * 49)
				var unlocked: bool = row.campaign <= profile.state.campaign
				_button(Rect2(xy, Vector2(254, 39)), "%02d   %s%s" % [row.campaign, row.name, "" if unlocked else "  ·  未解锁"], _focus_campaign.bind(int(row.campaign)))
			var mission: Dictionary = ops[selected_mission - 1]
			var brief := p + Vector2(596, 157)
			var brief_width := size.x - brief.x - 44.0
			_panel(Rect2(brief - Vector2(16, 12), Vector2(brief_width + 25.0, 247.0)), Color("#142638cd"))
			_text(brief + Vector2(0, 15), str(mission.name), 24, Color("#ecd09a"))
			_text(brief + Vector2(0, 57), mission.detail, 17, Color("#cbd8e4"), brief_width)
			_button(Rect2(brief + Vector2(0, 185), Vector2(minf(220.0, brief_width), 40)), "开始任务" if mission.campaign <= profile.state.campaign else "未解锁", _start_campaign.bind(selected_mission), mission.campaign <= profile.state.campaign)

		"training":
			_panel(Rect2(sidebar, Vector2(box_w, 446)))
			_text(sidebar + Vector2(20, 12), "飞行训练", 26)
			for i in Data.TRAINING.size():
				var lesson: Array = Data.TRAINING[i]
				_button(Rect2(sidebar + Vector2(19, 61 + i * 57), Vector2(380, 38)), "%s   ·   %s" % [lesson[0], lesson[1]], _enter.bind("training", {"id":"training_"+lesson[2],"name":lesson[0],"detail":lesson[1],"lesson":lesson[2],"region":0}, takeoff and i == 0))
			_button(Rect2(sidebar + Vector2(19, 369), Vector2(380, 40)), "起飞方式  ·  %s" % ("跑道" if takeoff else "空中"), _toggle_takeoff)
		"hangar":
			_aircraft_details(sidebar, box_w, size)

		"pilot", "report":
			if route == "report" and debrief.get("mode") == "free":
				_show_free_report(p, size)
				return
			_panel(Rect2(sidebar - Vector2(35, 0), Vector2(box_w + 35, 416)))
			var line := sidebar - Vector2(14, 0)
			if route == "report":
				_text(line + Vector2(0, 12), "任务完成" if debrief.win else "任务失败", 30, Color("#eacf98") if debrief.win else Color("#f0958c"))
				_text(line + Vector2(0, 70), "%s   ·   %s" % [debrief.name, debrief.grade], 24, Color("#ecd29f"))
				_text(line + Vector2(0, 116), "战斗评分    %d\n击落战机    %d\n损失战机    %d\n飞行距离    %.1f 公里\n信用点    +%d\n经验    +%d" % [debrief.score, debrief.kills, debrief.deaths, debrief.distance/1000.0, debrief.credits, debrief.xp], 19)
				if debrief.win:
					_button(Rect2(line + Vector2(0, 349), Vector2(375, 42)), "返回大厅", _open.bind("lobby"))
				else:
					_button(Rect2(line + Vector2(0, 349), Vector2(178, 42)), "重新挑战", _restart_last)
					_button(Rect2(line + Vector2(191, 349), Vector2(184, 42)), "返回大厅", _open.bind("lobby"))
			else:
				_text(line + Vector2(0, 12), "个人档案", 28)
				_text(line + Vector2(0, 65), "等级 %d   ·   经验 %d\n累计出击 %d   ·   击落 %d   ·   胜利 %d" % [Data.level(int(profile.state.xp)), profile.state.xp, profile.state.sorties, profile.state.kills, profile.state.victories], 18)
				var counts: Dictionary = profile.state.modes
				_text(line + Vector2(0, 118), "战役 %d   ·   训练 %d   ·   无限空战 %d" % [
					int(counts.get("campaign", {}).get("sorties", 0)), int(counts.get("training", {}).get("sorties", 0)),
					int(counts.get("free", {}).get("sorties", 0))], 16)
				_text(line + Vector2(0, 155), "历史战绩", 21, Color("#ecd29f"))
				var i := 0
				for record in profile.state.records.slice(0, 6):
					_text(line + Vector2(0, 180 + i * 29), "%s   ·   %s   %d" % [record.name, record.grade, int(record.score)], 16)
					i += 1
		"settings":
			_panel(Rect2(sidebar, Vector2(box_w, 388)))
			_text(sidebar + Vector2(19, 11), "飞行设置", 26)
			var fps := int(profile.state.settings.fps)
			_button(Rect2(sidebar + Vector2(20, 68), Vector2(375, 44)), "帧率目标   %d 帧/秒" % fps, _set_setting.bind("fps", 90 if fps == 60 else 60))
			var scale := float(profile.state.settings.quality)
			_button(Rect2(sidebar + Vector2(20, 126), Vector2(375, 44)), "三维渲染精度   %d%%" % roundi(scale * 100.0), _set_setting.bind("quality", 1.0 if scale < 0.95 and scale > 0.75 else (0.7 if scale > 0.95 else 0.85)))
			_button(Rect2(sidebar + Vector2(20, 184), Vector2(375, 44)), "反转垂直操控   %s" % ("开启" if profile.state.settings.invert else "关闭"), _set_setting.bind("invert", not profile.state.settings.invert))
			_button(Rect2(sidebar + Vector2(20, 242), Vector2(375, 44)), "声音   %s" % ("关闭" if profile.state.settings.mute else "开启"), _set_setting.bind("mute", not profile.state.settings.mute))
	if not note.is_empty():
		_text(Vector2(size.x - 416, size.y - 29), note, 15, Color("#f2d18e"))

func _aircraft_details(sidebar: Vector2, width: float, viewport_size: Vector2) -> void:
	var spec := catalogue.aircraft(viewed_plane)
	_panel(Rect2(sidebar, Vector2(width, 365)))
	_text(sidebar + Vector2(21, 14), str(spec.name), 28)
	_text(sidebar + Vector2(21, 53), "%s · %s" % [spec.origin, spec.role], 16, Color("#a4c4d9"))
	var owned: bool = viewed_plane in profile.state.unlocked
	if not panel_mods or not owned:
		_text(sidebar + Vector2(21, 105), "翼展 %.1f 米   ·   机长 %.1f 米\n最高速度 %d 公里/时\n机体耐久 %d" % [spec.span, spec.length, spec.maxSpeed * 3.6, spec.durability], 18)
		var selection := "已选择" if viewed_plane == profile.state.selected else ("选择战机" if owned else "未解锁 · 1150 信用点")
		_button(Rect2(sidebar + Vector2(21, 227), Vector2(190, 40)), selection, _select_plane, viewed_plane != profile.state.selected)
		if owned and viewed_plane == profile.state.selected:
			_button(Rect2(sidebar + Vector2(226, 227), Vector2(165, 40)), "进入改装", _toggle_mods)
	else:
		_button(Rect2(sidebar + Vector2(295, 49), Vector2(114, 32)), "查看机体", _toggle_mods)
		var index := 0
		for part in Data.UPGRADE_LABELS:
			var rank := profile.level_of(part)
			var gain: float = Data.UPGRADE_GAINS[part]
			var level_text := "%d → %d" % [rank, mini(3, rank + 1)]
			var delta_text := "+%d 米" % int(gain) if part == "radar" else "+%s%%" % snappedf(gain * 100.0, 0.1)
			var caption := "%s %s\n%s · %d 信用点" % [Data.UPGRADE_LABELS[part], level_text, delta_text, 560 + rank * 360]
			_button(Rect2(sidebar + Vector2(17 + (index % 2) * 199, 87 + (index / 2) * 47), Vector2(191, 43)), caption, _upgrade.bind(part), rank < 3)
			index += 1
		index = 0
		for id in Data.MISSILES:
			var item: Dictionary = Data.MISSILES[id]
			var status := "已挂载" if profile.selected_weapon(catalogue) == id else ("挂载" if profile.state.inventory.has(id) else "%d 信用点" % int(item.price))
			_button(Rect2(sidebar + Vector2(18, 232 + index * 36), Vector2(388, 32)), "%s · %s · %.2f 公里" % [item.label, status, item.range / 1000.0], _equip.bind(id), catalogue.missile_compatible(spec, id) and profile.selected_weapon(catalogue) != id)
			index += 1
	var scroll := ScrollContainer.new()
	scroll.position = Vector2(201, viewport_size.y - 97.0)
	scroll.size = Vector2(viewport_size.x - 222.0, 69.0)
	scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	var bar := HBoxContainer.new()
	bar.add_theme_constant_override("separation", 9)
	for plane in catalogue.source.fleet:
		if plane.support:
			continue
		var button := Button.new()
		button.text = "%s\n%s" % [plane.name, "已选择" if plane.id == viewed_plane else ("可使用" if plane.id in profile.state.unlocked else "未解锁")]
		button.custom_minimum_size = Vector2(150, 49)
		button.pressed.connect(_browse_plane.bind(str(plane.id)))
		bar.add_child(button)
	scroll.add_child(bar)
	view.add_child(scroll)
	scroll.set_deferred("scroll_horizontal", card_scroll)
	scroll.get_h_scroll_bar().value_changed.connect(func(value): card_scroll = int(value))

func _toggle_mods() -> void:
	panel_mods = not panel_mods
	_render_menu()

func _show_free_report(at: Vector2, viewport_size: Vector2) -> void:
	var width := viewport_size.x - at.x - 23.0
	_panel(Rect2(at, Vector2(width, viewport_size.y - at.y - 23.0)))
	_text(at + Vector2(20, 13), "无限空战战报", 28)
	_text(at + Vector2(20, 59), "第 %d 名   ·   击落 %d   ·   死亡 %d   ·   信用点 +%d" % [
		debrief.place, debrief.kills, debrief.deaths, debrief.credits], 22, Color("#ecd29f"))
	var col_width := (width - 62.0) * 0.5
	for section in 2:
		var left := at.x + 21.0 + section * (col_width + 18.0)
		var head := at.y + 112.0
		_text(Vector2(left + 7.0, head), "名次", 15, Color("#a9c7d8"))
		_text(Vector2(left + 60.0, head), "飞行员", 15, Color("#a9c7d8"))
		_text(Vector2(left + col_width - 110.0, head), "击落", 15, Color("#a9c7d8"))
		_text(Vector2(left + col_width - 55.0, head), "死亡", 15, Color("#a9c7d8"))
		for slot in 6:
			var row: Dictionary = debrief.ranking[section * 6 + slot]
			var y := head + 29.0 + slot * 34.0
			var local: bool = int(row.slot) == 0
			var name := "玩家" if local else "人机 %02d" % int(row.slot)
			_panel(Rect2(left, y - 2.0, col_width, 31.0), Color("#59462fbd") if local else Color("#142b3dc9"))
			_text(Vector2(left + 9.0, y), str(int(row.place)), 17)
			_text(Vector2(left + 60.0, y), name, 17, Color("#f3dda9") if local else Color("#d6e8f3"))
			_text(Vector2(left + col_width - 106.0, y), str(int(row.kills)), 17)
			_text(Vector2(left + col_width - 51.0, y), str(int(row.deaths)), 17)
	_button(Rect2(at.x + width - 224.0, viewport_size.y - 77.0, 197.0, 41), "返回大厅", _open.bind("lobby"))

func _set_setting(key: String, value: Variant) -> void:
	if not profile.set_option(key, value):
		note = "设置保存失败"
	Engine.max_fps = int(profile.state.settings.fps)
	get_viewport().scaling_3d_scale = float(profile.state.settings.quality)
	_render_menu()

func _toggle_takeoff() -> void:
	takeoff = not takeoff
	_render_menu()

func _select_chapter(index: int) -> void:
	list_chapter = index
	_focus_campaign(index * 10 + 1)

func _focus_campaign(number: int) -> void:
	selected_mission = number
	_render_menu()

func _browse_plane(id: String) -> void:
	panel_mods = false
	viewed_plane = id
	_set_showcase_aircraft(id)
	_render_menu()

func _select_plane() -> void:
	note = profile.select_plane(viewed_plane)
	_render_menu()

func _upgrade(part: String) -> void:
	if viewed_plane != profile.state.selected:
		return
	note = profile.upgrade(part)
	_render_menu()

func _equip(id: String) -> void:
	if viewed_plane != profile.state.selected:
		return
	note = profile.equip(id)
	_render_menu()

func _build_showcase() -> void:
	showcase = Node3D.new()
	add_child(showcase)
	var camera := Camera3D.new()
	preview_camera = camera
	showcase.add_child(camera)
	camera.current = true
	camera.fov = 34.0
	camera.far = 18000.0
	var at := Vector3(-340.0, Landscape.APRON_HEIGHT, 350.0)
	var env := Landscape.new()
	showcase.add_child(env)
	env.configure(catalogue.source.theatres[0], camera, at, true)
	showcase_aircraft = Node3D.new()
	showcase_aircraft.position = at + Vector3(0.0, 1.5, 0.0)
	showcase.add_child(showcase_aircraft)
	var airfield := MeshInstance3D.new()
	var tarmac := PlaneMesh.new()
	tarmac.size = Vector2(260.0, 120)
	airfield.mesh = tarmac
	airfield.position = at + Vector3(0.0, 0.08, 0.0)
	var wet := StandardMaterial3D.new()
	wet.albedo_texture = preload("res://assets/studio/tarmac.webp")
	wet.albedo_color = Color("#929ba4")
	wet.metallic = 0.44
	wet.roughness = 0.36
	wet.normal_enabled = true
	wet.normal_scale = 0.26
	wet.normal_texture = preload("res://assets/studio/tarmac-normal.png")
	wet.uv1_scale = Vector3(5.5, 3.1, 1.0)
	airfield.material_override = wet
	showcase.add_child(airfield)
	var architecture: Node3D = (load("res://assets/studio/hangar-dusk.glb") as PackedScene).instantiate()
	architecture.position = at + Vector3(86.0, 0.3, 12.0)
	architecture.scale = Vector3.ONE * 0.73
	showcase.add_child(architecture)
	var lamps := StandardMaterial3D.new()
	lamps.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	lamps.emission_enabled = true
	lamps.emission = Color("#ffb87e")
	lamps.emission_energy_multiplier = 4.5
	for i in 14:
		var inst := MeshInstance3D.new()
		var lens := SphereMesh.new()
		lens.radius = 0.18
		lens.height = 0.36
		lens.radial_segments = 8
		lens.rings = 4
		lens.material = lamps
		inst.mesh = lens
		inst.position = at + Vector3(4 + i * 4.1, 0.27, -27.0)
		showcase.add_child(inst)
	_set_showcase_aircraft(str(profile.state.selected))

func _set_showcase_aircraft(id: String) -> void:
	for child in showcase_aircraft.get_children():
		showcase_aircraft.remove_child(child)
		child.queue_free()
	var spec := catalogue.aircraft(id)
	var plane: Node3D = catalogue.mesh(id)
	showcase_aircraft.add_child(plane)
	catalogue.set_gear(catalogue.gear_tracks(plane), 1.0)
	showcase_aircraft.position.y = Landscape.APRON_HEIGHT + maxf(0.8, spec.gearClearance)
	showcase_aircraft.rotation.y = 0.0
	_tick_orbit(0.0, true)

func _start_campaign(n: int) -> void:
	_enter("campaign", catalogue.source.campaign[clampi(n - 1, 0, 59)], false)

func _start_free() -> void:
	_enter("free", {"name":"无限空战", "region":0, "detail":"各自为战"}, false)

func _restart_last() -> void:
	if last_operation.is_empty():
		return
	var next := last_operation
	if is_instance_valid(current_battle):
		profile.abort(current_battle.mode)
		_close_battle()
	_enter(next.mode, next.task, next.runway)

func _enter(mode: String, operation: Dictionary, runway: bool) -> void:
	if loading:
		return
	loading = true
	last_operation = {"mode":mode, "task":operation, "runway":runway}
	_show_loading(str(operation.name))
	await get_tree().process_frame
	var prepared: Dictionary = await _prepare_sortie(mode, operation, runway)
	if prepared.is_empty():
		loading = false
		_open("lobby")
		note = "战机或战区加载失败，请重试"
		_render_menu()
		return
	light_load_label.text = "正在装配战场"
	await get_tree().process_frame
	if is_instance_valid(showcase):
		remove_child(showcase)
		showcase.queue_free()
		showcase = null
	route = "battle"
	current_battle = Battle.new()
	add_child(current_battle)
	current_battle.finished.connect(_battle_finished, CONNECT_DEFERRED)
	current_battle.setup(catalogue, profile, mode, operation, runway, prepared)
	current_battle.paused = true
	load_meter.value = load_meter.max_value
	light_load_label.text = "准备完成"
	await get_tree().process_frame
	var fade := create_tween()
	fade.tween_property(view, "modulate:a", 0.0, 0.23)
	await fade.finished
	_clear_ui()
	var hud := Hud.new()
	hud.fight = current_battle
	hud.typeface = font
	hud.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	view.add_child(hud)
	active_hud = hud
	current_battle.paused = false
	loading = false

func _show_loading(title: String) -> void:
	_clear_ui()
	var size := get_viewport().get_visible_rect().size
	var image := TextureRect.new()
	image.texture = preload("res://assets/loading/alpine.webp")
	image.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	image.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	image.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	view.add_child(image)
	_panel(Rect2(Vector2.ZERO, size), Color("#08152675"))
	var midpoint := size * Vector2(0.5, 0.77)
	_panel(Rect2(midpoint - Vector2(290.0, 72.0), Vector2(580.0, 126.0)), Color("#081725e8"))
	_text(midpoint - Vector2(257.0, 57.0), title, 28, Color("#f2d397"))
	light_load_label = _text(midpoint - Vector2(257.0, 20.0), "正在准备战机与空域", 16)
	load_meter = ProgressBar.new()
	load_meter.position = midpoint - Vector2(257.0, -23.0)
	load_meter.size = Vector2(510.0, 11.0)
	load_meter.show_percentage = false
	view.add_child(load_meter)

func _prepare_sortie(mode: String, operation: Dictionary, runway: bool) -> Dictionary:
	var start := Battle.start_position(mode, operation, runway)
	var tiles := Landscape.opening_tiles(start, false)
	var seed_value := int(catalogue.source.theatres[int(operation.get("region", 0))].seed)
	var ids := [str(profile.state.selected)]
	if mode == "free":
		ids.append_array(Battle.FREE_ROSTER)
	elif mode == "campaign":
		var plan: Dictionary = operation.engagement
		ids.append_array(plan.roster)
		if plan.has("ace"):
			ids.append(plan.ace)
		if plan.get("drones", 0) > 0:
			ids.append("shade-drone")
	else:
		ids.append("j10")
	var requests := {}
	for id in ids:
		if catalogue.scenes.has(id) or requests.has(id):
			continue
		var path := "res://assets/fleet/%s.glb" % id
		if ResourceLoader.load_threaded_request(path, "PackedScene") != OK:
			return {}
		requests[id] = path
	var total := tiles.size() + requests.size() + 1
	load_meter.max_value = total
	var ready := {}
	var workers := {}
	var failure := false
	while not tiles.is_empty() or not requests.is_empty() or not workers.is_empty():
		for coord in workers.keys():
			var job: Thread = workers[coord]
			if not job.is_alive():
				var data: PackedFloat32Array = job.wait_to_finish()
				workers.erase(coord)
				if data.size() != Landscape.SIZE * Landscape.SIZE:
					failure = true
				ready[coord] = data
				load_meter.value += 1
		for id in requests.keys():
			var path: String = requests[id]
			var state := ResourceLoader.load_threaded_get_status(path)
			if state == ResourceLoader.THREAD_LOAD_IN_PROGRESS:
				continue
			if state == ResourceLoader.THREAD_LOAD_LOADED:
				catalogue.scenes[id] = ResourceLoader.load_threaded_get(path)
			else:
				failure = true
			requests.erase(id)
			load_meter.value += 1
		while workers.size() < 3 and not tiles.is_empty():
			var coord: Vector2i = tiles.pop_front()
			var job := Thread.new()
			if job.start(Landscape.bake_tile.bind(coord, seed_value)) == OK:
				workers[coord] = job
			else:
				failure = true
		light_load_label.text = "已准备 %d / %d 项" % [int(load_meter.value), total]
		await get_tree().process_frame
	return {} if failure else ready

func show_pause(show: bool) -> void:
	if not show:
		if is_instance_valid(pause_ui):
			pause_ui.queue_free()
		return
	_pause_panel("pause")

func _pause_panel(page: String) -> void:
	if is_instance_valid(pause_ui):
		view.remove_child(pause_ui)
		pause_ui.queue_free()
	pause_ui = Control.new()
	pause_ui.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	pause_ui.mouse_filter = Control.MOUSE_FILTER_STOP
	view.add_child(pause_ui)
	var flight_view := view
	view = pause_ui
	var centre := get_viewport().get_visible_rect().size * 0.5
	var top := centre - Vector2(176, 154)
	_panel(Rect2(top, Vector2(352, 308)), Color("#0b1729f5"))
	var title := "战斗暂停" if page == "pause" else ("飞行设置" if page == "settings" else "退出本局")
	_text(top + Vector2(28, 15), title, 26, Color("#ecd4a6"))
	match page:
		"pause":
			_button(Rect2(top + Vector2(28, 60), Vector2(296, 35)), "继续飞行", _resume)
			_button(Rect2(top + Vector2(28, 106), Vector2(143, 35)), "重新开始", _restart_last)
			_button(Rect2(top + Vector2(181, 106), Vector2(143, 35)), "飞行设置", _pause_panel.bind("settings"))
			_button(Rect2(top + Vector2(28, 152), Vector2(296, 35)), "收放起落架", func():
				_resume()
				current_battle.action.gear = true)
			_button(Rect2(top + Vector2(28, 218), Vector2(296, 35)), "退出本局", _pause_panel.bind("leave"))
		"settings":
			var fps := int(profile.state.settings.fps)
			_button(Rect2(top + Vector2(28, 62), Vector2(296, 36)), "帧率目标 · %d 帧/秒" % fps, _pause_option.bind("fps", 90 if fps == 60 else 60))
			_button(Rect2(top + Vector2(28, 108), Vector2(296, 36)), "反转垂直操控 · %s" % ("开启" if profile.state.settings.invert else "关闭"), _pause_option.bind("invert", not profile.state.settings.invert))
			_button(Rect2(top + Vector2(28, 154), Vector2(296, 36)), "声音 · %s" % ("关闭" if profile.state.settings.mute else "开启"), _pause_option.bind("mute", not profile.state.settings.mute))
			_button(Rect2(top + Vector2(28, 218), Vector2(296, 35)), "返回暂停", _pause_panel.bind("pause"))
		"leave":
			_text(top + Vector2(28, 76), "退出后返回大厅，本局不结算奖励。", 17, Color("#c4d4e1"))
			_button(Rect2(top + Vector2(28, 188), Vector2(143, 39)), "取消", _pause_panel.bind("pause"))
			_button(Rect2(top + Vector2(181, 188), Vector2(143, 39)), "确认退出", _abort_battle)
	view = flight_view

func _pause_option(key: String, value: Variant) -> void:
	profile.set_option(key, value)
	Engine.max_fps = int(profile.state.settings.fps)
	current_battle.audio.mute = profile.state.settings.mute
	_pause_panel("settings")

func _resume() -> void:
	if is_instance_valid(active_hud):
		active_hud.input_actions.pause.pressed.emit()

func _abort_battle() -> void:
	if not is_instance_valid(current_battle) or current_battle.ended:
		return
	profile.abort(current_battle.mode)
	_close_battle()
	_open("lobby")

func _close_battle() -> void:
	active_hud = null
	pause_ui = null
	remove_child(current_battle)
	current_battle.queue_free()
	current_battle = null

func _battle_finished(result: Dictionary) -> void:
	debrief = result
	if capture_dir.is_empty():
		profile.debrief(result)
	_close_battle()
	_open("report")

func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_PAUSED and is_instance_valid(active_hud) and is_instance_valid(current_battle) and not current_battle.paused:
		active_hud.input_actions.pause.pressed.emit()

func _input(event: InputEvent) -> void:
	if route not in ["lobby", "hangar"] or loading or not is_instance_valid(showcase_aircraft):
		return
	var area := Rect2(191.0, 74.0, 620.0, 395.0)
	if event is InputEventScreenTouch:
		if event.pressed and area.has_point(event.position):
			orbit_touches[event.index] = event.position
		else:
			orbit_touches.erase(event.index)
		orbit_span = 0.0
	elif event is InputEventScreenDrag and orbit_touches.has(event.index):
		orbit_touches[event.index] = event.position
		if orbit_touches.size() == 2:
			var fingers := orbit_touches.values()
			var gap: float = fingers[0].distance_to(fingers[1])
			if orbit_span > 6.0 and gap > 6.0:
				orbit_scale = clampf(orbit_scale * orbit_span / gap, 0.55, 1.7)
			orbit_span = gap
		else:
			_orbit_drag(event.relative)
		get_viewport().set_input_as_handled()
	elif event is InputEventMouseButton and event.device != InputEvent.DEVICE_ID_EMULATION:
		if event.button_index == MOUSE_BUTTON_LEFT:
			orbit_active = event.pressed and area.has_point(event.position)
		elif event.pressed and area.has_point(event.position) and event.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN]:
			orbit_scale = clampf(orbit_scale * (0.88 if event.button_index == MOUSE_BUTTON_WHEEL_UP else 1.13), 0.55, 1.7)
	elif event is InputEventMouseMotion and orbit_active and event.device != InputEvent.DEVICE_ID_EMULATION:
		_orbit_drag(event.relative)

func _orbit_drag(relative: Vector2) -> void:
	orbit_spin = wrapf(orbit_spin - relative.x * 0.005, -PI, PI)
	orbit_tilt = clampf(orbit_tilt + relative.y * 0.004, 0.025, 0.91)

func _tick_orbit(delta: float, snap := false) -> void:
	if not is_instance_valid(preview_camera) or not is_instance_valid(showcase_aircraft):
		return
	var spec := catalogue.aircraft(viewed_plane)
	var frame := clampf(maxf(spec.length, spec.span) / 20.0, 0.55, 1.85)
	var distance := 27.7 * frame * orbit_scale
	var target_point := showcase_aircraft.position + Vector3(0, 1.1, 0)
	var offset := Vector3(sin(orbit_spin) * cos(orbit_tilt), sin(orbit_tilt), cos(orbit_spin) * cos(orbit_tilt)) * distance
	var at := target_point + offset
	var alpha := 1.0 if snap else (1.0 - exp(-delta * 10.0))
	preview_camera.position = preview_camera.position.lerp(at, alpha)
	preview_camera.look_at(target_point, Vector3.UP)

func _process(delta: float) -> void:
	if route in ["lobby", "hangar"] and not loading:
		_tick_orbit(delta)
	if capture_dir.is_empty():
		if OS.has_feature("android") and is_instance_valid(current_battle):
			_adapt_resolution(delta)
		return
	capture_time += delta
	if fixture_stage == 0 and capture_time > 1.15:
		fixture_stage = 1
		await _snapshot("lobby")
		if capture_free:
			_start_free()
		else:
			_start_campaign(1)
	elif fixture_stage == 1 and is_instance_valid(current_battle) and current_battle.ready_for_play:
		var t: float = current_battle.time
		var wall := Time.get_ticks_usec()
		if last_frame_usec != 0 and t >= 0.25:
			frame_wall_samples.append((wall - last_frame_usec) / 1000.0)
		last_frame_usec = wall
		current_battle.action.gun = t > 0.8 and t < 4.2
		current_battle.action.missile = t > 1.1 and t < 3.6
		if t > 3.1 and t < 3.7:
			current_battle.action.boost = true
		if t > 4.0 and t < 5.1:
			current_battle.stick = Vector2(-0.50, 0.20)
		if t > 0.37 and not "combat-entry" in fixture_marks:
			fixture_marks.append("combat-entry")
			_snapshot("combat-entry")
		if t > 1.43 and not "battle" in fixture_marks:
			fixture_marks.append("battle")
			_snapshot("battle")
		if t > 4.60 and not "maneuver" in fixture_marks:
			fixture_marks.append("maneuver")
			_snapshot("maneuver")
		if t > (3.4 if capture_free else 7.5):
			fixture_stage = 2
			var f := FileAccess.open(capture_dir + "/desktop-run.json", FileAccess.WRITE)
			frame_wall_samples.sort()
			var mean := 0.0
			for sample in frame_wall_samples:
				mean += sample
			mean /= maxf(1.0, float(frame_wall_samples.size()))
			var tail_ms := 0.0
			var tail_count := maxi(1, ceili(frame_wall_samples.size() * 0.01))
			for i in range(maxi(0, frame_wall_samples.size() - tail_count), frame_wall_samples.size()):
				tail_ms += frame_wall_samples[i] / tail_count
			f.store_string(JSON.stringify({"movie_frame_ms_mean":mean,"movie_fps_one_percent_low":1000.0 / maxf(0.001, tail_ms),"ocean_fft":current_battle.world.ocean.material.get_shader_parameter("spectral_enabled"),"driver":RenderingServer.get_video_adapter_api_version(),"device":RenderingServer.get_video_adapter_name(),"physics_s":t,"mode":current_battle.mode,"aircraft_slots":current_battle.fleet.size(),"first_wave_alive":current_battle.alive_enemies(),"gun_and_missile_launches":current_battle.total_fired,"hits":current_battle.shots_hit,"regions":current_battle.world.current.size(),"fps_now":Engine.get_frames_per_second(),"static_memory":Performance.get_monitor(Performance.MEMORY_STATIC),"video_memory":Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED)}, "\t"))
			current_battle.paused = true
			current_battle.audio.stop_all()
			for i in range(3):
				await get_tree().process_frame
			get_tree().quit()

func _snapshot(name: String) -> void:
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(capture_dir + "/" + name + ".png")

func _adapt_resolution(dt: float) -> void:
	if current_battle.paused or dt > 0.25:
		return
	frame_average = lerpf(frame_average, dt, 1.0 - exp(-dt * 2.2))
	adaptive_clock += dt
	if adaptive_clock < 1.8:
		return
	adaptive_clock = 0.0
	var budget := 1.0 / float(profile.state.settings.fps)
	var viewport := get_viewport()
	var configured := float(profile.state.settings.quality)
	var scale := viewport.scaling_3d_scale
	slow_windows = slow_windows + 1 if frame_average > budget * 1.19 else 0
	fast_windows = fast_windows + 1 if frame_average < budget * 0.91 else 0
	if slow_windows >= 2:
		scale = maxf(0.71, scale - 0.05)
		slow_windows = 0
	elif fast_windows >= 4:
		scale = minf(configured, scale + 0.04)
		fast_windows = 0
	if not is_equal_approx(scale, viewport.scaling_3d_scale):
		viewport.scaling_3d_scale = scale
		current_battle.world.set_quality(scale)
