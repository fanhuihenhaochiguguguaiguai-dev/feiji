extends Node3D

const Data = preload("res://game/catalogue.gd")
const Profile = preload("res://game/profile.gd")
const Battle = preload("res://game/battle.gd")
const Landscape = preload("res://game/world.gd")
const Hud = preload("res://game/hud.gd")
const CutButton = preload("res://game/menu_panel.gd")
const PausePanel = preload("res://game/pause_panel.gd")

var catalogue := Data.new()
var profile := Profile.new(catalogue)
var font: Font
var layer := CanvasLayer.new()
var view: Control
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
var orbit_emulated_through := -1
var orbit_display := Vector3(-2.279, 0.105, 1.0)
var orbit_distance := 27.7
var preview_id := ""
var ui_theme := Theme.new()
var button_styles := {}
var panel_styles := {}
var preview_camera: Camera3D
var active_hud: Control
var last_operation := {}
var light_load_label: Label
var load_meter: ProgressBar
var loading := false
var pause_ui: Control
var adaptive_clock := 0.0
var frame_average := 0.0
var slow_windows := 0
var fast_windows := 0
var device_power: Object
var thermal_limited := false
var cool_windows := 0

func _ready() -> void:
	font = load("res://assets/locale/PilotSC.otf")
	if font == null:
		font = ThemeDB.fallback_font
	if OS.has_feature("android") and Engine.has_singleton("AndroidRuntime"):
		var version = JavaClassWrapper.wrap("android.os.Build$VERSION")
		if version and int(version.SDK_INT) >= 29:
			device_power = Engine.get_singleton("AndroidRuntime").getApplicationContext().getSystemService("power")
	_apply_settings()
	ui_theme.default_font = font
	ui_theme.default_font_size = 17
	for state in ["normal", "hover", "pressed", "disabled"]:
		var fill := Color("#142c43e8") if state == "normal" else (Color("#101a27d0") if state == "disabled" else Color("#244e69ee"))
		button_styles[state] = _box_style(fill, Color("#57839ca8"), 2)
	add_child(layer)
	get_viewport().size_changed.connect(func():
		if route != "battle":
			_render_menu())
	viewed_plane = str(profile.state.selected)
	selected_mission = int(profile.state.campaign)
	list_chapter = (selected_mission - 1) / 10
	_open("lobby")

func _open(page: String) -> void:
	_cancel_orbit()
	route = page
	note = ""
	if not is_instance_valid(showcase) and route != "battle":
		get_viewport().scaling_3d_scale = float(profile.state.settings.quality)
		_build_showcase()
	elif is_instance_valid(showcase):
		preview_camera.make_current()
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
	view.theme = ui_theme
	layer.add_child(view)

static func _box_style(fill: Color, edge: Color, radius: int) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = fill
	style.border_color = edge
	style.set_border_width_all(1)
	style.set_corner_radius_all(radius)
	return style

func _panel(area: Rect2, color: Color = Color("#0d2033d9")) -> Panel:
	var p := Panel.new()
	p.position = area.position
	p.size = area.size
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if not panel_styles.has(color):
		panel_styles[color] = _box_style(color, Color("#63869e71"), 3)
	p.add_theme_stylebox_override("panel", panel_styles[color])
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
	for role in button_styles:
		b.add_theme_stylebox_override(role, button_styles[role])
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
			var i := 0
			for item in _setting_items(true):
				_button(Rect2(sidebar + Vector2(20, 68 + i * 58), Vector2(375, 44)), item[0], _set_setting.bind(item[1], item[2]))
				i += 1
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
		var selection := "已选择" if viewed_plane == profile.state.selected else ("选择战机" if owned else ("未解锁 · %d 信用点" % Data.AIRCRAFT_PRICE))
		_button(Rect2(sidebar + Vector2(21, 227), Vector2(190, 40)), selection, _select_plane, viewed_plane != profile.state.selected)
		if owned and viewed_plane == profile.state.selected:
			_button(Rect2(sidebar + Vector2(226, 227), Vector2(165, 40)), "进入改装", _toggle_mods)
	else:
		_button(Rect2(sidebar + Vector2(295, 49), Vector2(114, 32)), "查看机体", _toggle_mods)
		var index := 0
		for part in Data.UPGRADE_LABELS:
			var rank := profile.level_of(part)
			var gain: float = Data.UPGRADE_GAINS[part]
			var level_text := "%d → %d" % [rank, mini(Data.UPGRADE_LIMIT, rank + 1)]
			var delta_text := "+%d 米" % int(gain) if part == "radar" else "+%s%%" % snappedf(gain * 100.0, 0.1)
			var caption := "%s %s\n%s · %d 信用点" % [Data.UPGRADE_LABELS[part], level_text, delta_text, Data.upgrade_price(rank)]
			_button(Rect2(sidebar + Vector2(17 + (index % 2) * 199, 87 + (index / 2) * 47), Vector2(191, 43)), caption, _upgrade.bind(part), rank < Data.UPGRADE_LIMIT)
			index += 1
		index = 0
		var mounted := profile.selected_weapon()
		for id in Data.MISSILES:
			var item: Dictionary = Data.MISSILES[id]
			var status := "已挂载" if mounted == id else ("挂载" if profile.state.inventory.has(id) else "%d 信用点" % int(item.price))
			_button(Rect2(sidebar + Vector2(18, 232 + index * 36), Vector2(388, 32)), "%s · %s · %.2f 公里" % [item.label, status, item.range / 1000.0], _equip.bind(id), catalogue.missile_compatible(spec, id) and mounted != id)
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

func _setting_items(lobby: bool) -> Array:
	var current: Dictionary = profile.state.settings
	var result := [["帧率目标 · %d 帧/秒" % current.fps, "fps", 90 if current.fps == 60 else 60]]
	if lobby:
		var scale: float = current.quality
		result.append(["三维渲染精度 · %d%%" % roundi(scale * 100.0), "quality", 1.0 if scale < 0.95 and scale > 0.75 else (0.7 if scale > 0.95 else 0.85)])
	result.append_array([
		["反转垂直操控 · %s" % ("开启" if current.invert else "关闭"), "invert", not current.invert],
		["声音 · %s" % ("关闭" if current.mute else "开启"), "mute", not current.mute]])
	return result

func _apply_settings() -> void:
	Engine.max_fps = mini(int(profile.state.settings.fps), 60) if thermal_limited else int(profile.state.settings.fps)
	get_viewport().scaling_3d_scale = float(profile.state.settings.quality)
	if is_instance_valid(current_battle):
		current_battle.audio.mute = profile.state.settings.mute

func _set_setting(key: String, value: Variant) -> void:
	if not profile.set_option(key, value):
		note = "设置保存失败"
	_apply_settings()
	if is_instance_valid(pause_ui):
		_pause_panel("settings")
	else:
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
	Landscape.add_environment(showcase, catalogue.source.theatres[0], true)
	var ridges := (load("res://assets/environment/airfield-ridges.glb") as PackedScene).instantiate() as Node3D
	ridges.position = at
	var baked := StandardMaterial3D.new()
	baked.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	baked.vertex_color_use_as_albedo = true
	for surface in ridges.find_children("*", "MeshInstance3D", true, false):
		surface.material_override = baked
		surface.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	showcase.add_child(ridges)
	showcase_aircraft = Node3D.new()
	showcase_aircraft.position = at + Vector3(0.0, 1.5, 0.0)
	showcase.add_child(showcase_aircraft)
	var airfield := MeshInstance3D.new()
	var tarmac := PlaneMesh.new()
	tarmac.size = Vector2(260.0, 120)
	airfield.mesh = tarmac
	airfield.position = at + Vector3(0.0, 0.08, 0.0)
	var wet := ORMMaterial3D.new()
	wet.albedo_texture = preload("res://assets/studio/tarmac.webp")
	wet.albedo_color = Color("#929ba4")
	wet.orm_texture = preload("res://assets/studio/tarmac-orm.png")
	wet.normal_enabled = true
	wet.normal_scale = 0.19
	wet.normal_texture = preload("res://assets/studio/tarmac-normal.png")
	wet.uv1_scale = Vector3(3.8, 1.8, 1.0)
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
	var lens := SphereMesh.new()
	lens.radius = 0.18
	lens.height = 0.36
	lens.radial_segments = 8
	lens.rings = 4
	lens.material = lamps
	for i in 14:
		var inst := MeshInstance3D.new()
		inst.mesh = lens
		inst.position = at + Vector3(4 + i * 4.1, 0.27, -27.0)
		showcase.add_child(inst)
	_set_showcase_aircraft(str(profile.state.selected))

func _set_showcase_aircraft(id: String) -> void:
	if id == preview_id and showcase_aircraft.get_child_count() > 0:
		return
	preview_id = id
	for child in showcase_aircraft.get_children():
		showcase_aircraft.remove_child(child)
		child.queue_free()
	var spec := catalogue.aircraft(id)
	var plane: Node3D = catalogue.mesh(id)
	showcase_aircraft.add_child(plane)
	catalogue.set_gear(catalogue.gear_tracks(plane), 1.0)
	showcase_aircraft.position.y = Landscape.APRON_HEIGHT + maxf(0.8, spec.gearClearance)
	orbit_distance = 27.7 * clampf(maxf(spec.length, spec.span) / 20.0, 0.55, 1.85)
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
	_cancel_orbit()
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
	if DisplayServer.get_name() != "headless":
		var camera := current_battle.camera
		current_battle.effects.prime(camera.position - camera.global_basis.z * 13.0)
		await RenderingServer.frame_post_draw
		current_battle.effects.end_prime(camera)
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
	var tiles := Landscape.opening_tiles(start)
	var seed_value := int(catalogue.source.theatres[int(operation.get("region", 0))].seed)
	Landscape.prepare_relief(seed_value)
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
		var path := Data.mesh_path(id)
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
	var panel := PausePanel.new()
	pause_ui = panel
	panel.typeface = font
	panel.header = "战斗暂停" if page == "pause" else ("飞行设置" if page == "settings" else "退出本局")
	panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	view.add_child(panel)
	match page:
		"pause":
			panel.action(Rect2(41, 106, 482, 49), "继续飞行", "continue", _resume, true)
			panel.action(Rect2(41, 169, 231, 45), "重新开始", "restart", _restart_last)
			panel.action(Rect2(292, 169, 231, 45), "飞行设置", "settings", _pause_panel.bind("settings"))
			panel.action(Rect2(41, 230, 482, 46), "收放起落架", "gear", func():
				_resume()
				current_battle.action.gear = true)
			panel.action(Rect2(41, 292, 482, 46), "退出本局", "leave", _pause_panel.bind("leave"))
		"settings":
			var i := 0
			for item in _setting_items(false):
				panel.action(Rect2(41, 106 + i * 59, 482, 45), item[0], "", _set_setting.bind(item[1], item[2]))
				i += 1
			panel.action(Rect2(41, 289, 482, 45), "返回暂停", "", _pause_panel.bind("pause"))
		"leave":
			panel.notice = "退出后返回大厅，本局不结算奖励。"
			panel.action(Rect2(41, 228, 231, 46), "取消", "", _pause_panel.bind("pause"))
			panel.action(Rect2(292, 228, 231, 46), "确认退出", "leave", _abort_battle)

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
	profile.debrief(result)
	_close_battle()
	_open("report")

func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_PAUSED:
		_cancel_orbit()
	if what == NOTIFICATION_APPLICATION_PAUSED and is_instance_valid(active_hud) and is_instance_valid(current_battle) and not current_battle.paused:
		active_hud.input_actions.pause.pressed.emit()

func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.physical_keycode == KEY_ESCAPE and event.pressed and not event.echo and is_instance_valid(pause_ui):
		_resume()
		get_viewport().set_input_as_handled()
		return
	if route not in ["lobby", "hangar"] or loading or not is_instance_valid(showcase_aircraft):
		return
	if event is InputEventScreenTouch:
		if event.pressed and not event.canceled:
			if orbit_touches.is_empty() and not _orbit_clear(event.position):
				return
			orbit_touches[event.index] = event.position
		elif not orbit_touches.erase(event.index):
			return
		orbit_span = _pinch_span()
		orbit_emulated_through = Engine.get_process_frames() + 1
		get_viewport().set_input_as_handled()
	elif event is InputEventScreenDrag and orbit_touches.has(event.index):
		var previous: Vector2 = orbit_touches[event.index]
		orbit_touches[event.index] = event.position
		if orbit_touches.size() > 1:
			var gap := _pinch_span()
			if orbit_span > 6.0 and gap > 6.0:
				orbit_scale = clampf(orbit_scale * orbit_span / gap, 0.55, 1.7)
			orbit_span = gap
		else:
			_orbit_drag(event.position - previous)
		get_viewport().set_input_as_handled()
	elif event is InputEventMouse:
		if event.device == InputEvent.DEVICE_ID_EMULATION:
			if not orbit_touches.is_empty() or Engine.get_process_frames() <= orbit_emulated_through:
				get_viewport().set_input_as_handled()
			return
		if event is InputEventMouseButton:
			if event.button_index == MOUSE_BUTTON_LEFT:
				var was_active := orbit_active
				orbit_active = event.pressed and _orbit_clear(event.position)
				if was_active or orbit_active:
					get_viewport().set_input_as_handled()
			elif event.pressed and event.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN] and _orbit_clear(event.position):
				orbit_scale = clampf(orbit_scale * (0.88 if event.button_index == MOUSE_BUTTON_WHEEL_UP else 1.13), 0.55, 1.7)
				get_viewport().set_input_as_handled()
		elif event is InputEventMouseMotion and orbit_active:
			_orbit_drag(event.relative)
			get_viewport().set_input_as_handled()

func _orbit_clear(at: Vector2) -> bool:
	for control in view.get_children():
		if (control is Panel or control is BaseButton or control is ScrollContainer or control is CutButton) and control.visible and control.get_global_rect().has_point(at):
			return false
	return true

func _cancel_orbit() -> void:
	orbit_active = false
	orbit_touches.clear()
	orbit_span = 0.0

func _pinch_span() -> float:
	if orbit_touches.size() < 2:
		return 0.0
	var fingers := orbit_touches.values()
	return fingers[0].distance_to(fingers[1])

func _orbit_drag(relative: Vector2) -> void:
	orbit_spin = wrapf(orbit_spin - relative.x * 0.005, -PI, PI)
	orbit_tilt = clampf(orbit_tilt + relative.y * 0.004, -0.08, 0.91)

func _tick_orbit(delta: float, snap := false) -> void:
	if not is_instance_valid(preview_camera) or not is_instance_valid(showcase_aircraft):
		return
	var alpha := 1.0 if snap else (1.0 - exp(-delta * 10.0))
	orbit_display.x = lerp_angle(orbit_display.x, orbit_spin, alpha)
	orbit_display.y = lerpf(orbit_display.y, orbit_tilt, alpha)
	orbit_display.z = lerpf(orbit_display.z, orbit_scale, alpha)
	var target_point := showcase_aircraft.position + Vector3(0, 1.1, 0)
	var tilt := orbit_display.y
	var spin := orbit_display.x
	var offset := Vector3(sin(spin) * cos(tilt), sin(tilt), cos(spin) * cos(tilt)) * orbit_distance * orbit_display.z
	var at := target_point + offset
	at.y = maxf(at.y, Landscape.APRON_HEIGHT + 0.85)
	preview_camera.position = at
	preview_camera.look_at(target_point, Vector3.UP)

func _process(delta: float) -> void:
	if route in ["lobby", "hangar"] and not loading:
		_tick_orbit(delta)
	if OS.has_feature("android") and is_instance_valid(current_battle):
		_adapt_resolution(delta)

func _adapt_resolution(dt: float) -> void:
	if current_battle.paused:
		return
	dt = minf(dt, 0.25)
	frame_average = lerpf(frame_average, dt, 1.0 - exp(-dt * 2.2))
	adaptive_clock += dt
	if adaptive_clock < 1.8:
		return
	adaptive_clock = 0.0
	if device_power:
		var status := int(device_power.getCurrentThermalStatus())
		cool_windows = cool_windows + 1 if status <= 1 else 0
		if status >= 3:
			thermal_limited = true
		elif cool_windows >= 8:
			thermal_limited = false
		var selected := int(profile.state.settings.fps)
		var target := mini(60, selected) if thermal_limited else selected
		if Engine.max_fps != target:
			Engine.max_fps = target
	var budget := 1.0 / float(Engine.max_fps)
	var viewport := get_viewport()
	var configured := float(profile.state.settings.quality)
	if thermal_limited:
		configured = minf(0.79, configured)
	var scale := viewport.scaling_3d_scale
	slow_windows = slow_windows + 1 if frame_average > budget * 1.19 else 0
	fast_windows = fast_windows + 1 if frame_average < budget * 0.91 else 0
	if slow_windows >= 2:
		scale = maxf(0.71, scale - 0.05)
		slow_windows = 0
	elif fast_windows >= 4:
		scale = minf(configured, scale + 0.04)
		fast_windows = 0
	scale = minf(scale, configured)
	if not is_equal_approx(scale, viewport.scaling_3d_scale):
		viewport.scaling_3d_scale = scale
		current_battle.world.set_quality(scale)
