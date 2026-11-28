extends Node3D

const Data = preload("res://game/catalogue.gd")
const Profile = preload("res://game/profile.gd")
const Battle = preload("res://game/battle.gd")
const Landscape = preload("res://game/world.gd")
const Hud = preload("res://game/hud.gd")
const PausePanel = preload("res://game/pause_panel.gd")
const LoadingScreen = preload("res://game/loading_screen.gd")
const CarrierLobby = preload("res://game/reference_lobby.gd")
const CarrierStage = preload("res://game/carrier_stage.gd")

var catalogue: Data
var profile: Profile
var font: Font
var layer := CanvasLayer.new()
var view: Control
var showcase: Node3D
var showcase_aircraft: Node3D
var showcase_stage: CarrierStage
var lobby_screen: CarrierLobby
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
var menu_safe := Rect2()
var preview_camera: Camera3D
var active_hud: Control
var last_operation := {}
var loading_screen: LoadingScreen
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
	if not catalogue:
		catalogue = Data.new()
	if not profile:
		profile = Profile.new(catalogue)
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
	button_styles["normal"] = CarrierLobby.border_style()
	button_styles["hover"] = CarrierLobby.border_style()
	button_styles["hover"].modulate_color = Color(1.25,1.37,1.45)
	button_styles["pressed"] = CarrierLobby.border_style(true)
	button_styles["disabled"] = CarrierLobby.border_style()
	button_styles["disabled"].modulate_color = Color(0.69,0.76,0.85)
	add_child(layer)
	get_viewport().size_changed.connect(func():
		if not loading and route != "battle":
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
		_sync_showcase_stage()
	if page != "hangar":
		viewed_plane = str(profile.state.selected)
		_set_showcase_aircraft(viewed_plane)
	_render_menu()

func _clear_ui() -> void:
	lobby_screen = null
	if is_instance_valid(view):
		layer.remove_child(view)
		view.queue_free()
	view = Control.new()
	view.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	view.mouse_filter = Control.MOUSE_FILTER_IGNORE
	view.theme = ui_theme
	layer.add_child(view)

func _panel(area: Rect2, color: Color = Color.WHITE) -> Panel:
	var p := Panel.new()
	p.position = area.position
	p.size = area.size
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if not panel_styles.has(color):
		panel_styles[color] = CarrierLobby.border_style()
		if color != Color.WHITE:
			panel_styles[color].modulate_color = color.lerp(Color.WHITE, 0.74)
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
	_show_carrier_lobby()
	if route == "lobby":
		return
	menu_safe = CarrierLobby.safe_bounds(view, get_viewport().get_visible_rect().size)
	var size := menu_safe.end
	var left := menu_safe.position.x + lobby_screen.frame.scale.x * 260.0 + 9.0
	var p := Vector2(left, menu_safe.position.y + 92.0)
	var box_w := 426.0
	var sidebar := Vector2(size.x - box_w - 20, p.y)
	match route:
		"campaign":
			_panel(Rect2(p, Vector2(size.x - p.x - 21, size.y - p.y - 25)))
			_text(p + Vector2(21, 11), "战区简报", 27)
			var column := minf(250.0, (size.x-p.x-347.0)/2.0)
			for i in 6:
				_button(Rect2(p + Vector2(21 + (i % 3) * column * 0.67, 64 + (i / 3) * 40), Vector2(column*0.62, 34)), catalogue.source.chapters[i], _select_chapter.bind(i))
			var ops: Array = catalogue.source.campaign
			for j in 10:
				var row: Dictionary = ops[list_chapter * 10 + j]
				var xy: Vector2 = p + Vector2(22 + (j % 2) * column, 156 + (j / 2) * 49)
				var unlocked: bool = row.campaign <= profile.state.campaign
				_button(Rect2(xy, Vector2(column-9, 39)), "%02d   %s%s" % [row.campaign, row.name, "" if unlocked else "  ·  未解锁"], _focus_campaign.bind(int(row.campaign)))
			var mission: Dictionary = ops[selected_mission - 1]
			var brief := p + Vector2(2.0*column+52.0, 157)
			var brief_width := size.x - brief.x - 44.0
			_panel(Rect2(brief - Vector2(16, 12), Vector2(brief_width + 25.0, 247.0)), Color("#142638cd"))
			_text(brief + Vector2(0, 15), str(mission.name), 24, Color("#ecd09a"))
			_text(brief + Vector2(0, 57), mission.detail, 17, Color("#cbd8e4"), brief_width)
			_button(Rect2(brief + Vector2(0, 185), Vector2(minf(220.0, brief_width), 40)), "开始任务" if mission.campaign <= profile.state.campaign else "未解锁", _start_campaign.bind(selected_mission), mission.campaign <= profile.state.campaign)

		"training":
			_training_menu(Vector2(size.x-478,p.y-8))
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

func _chrome_icon(parent: Control, area: Rect2, source: Rect2) -> void:
	var picture := TextureRect.new()
	picture.mouse_filter = Control.MOUSE_FILTER_IGNORE
	picture.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	picture.texture = CarrierLobby.chrome_slice(source)
	picture.position = area.position
	picture.size = area.size
	parent.add_child(picture)

func _training_menu(at: Vector2) -> void:
	var height := minf(456.0, menu_safe.end.y - at.y - 34.0)
	var box := _panel(Rect2(at, Vector2(455, height)))
	box.add_theme_stylebox_override("panel", CarrierLobby.border_style(true))
	_chrome_icon(view, Rect2(at + Vector2(12, 9), Vector2(431, 44)), Rect2(0, 505, 280, 38))
	var row_height := (height - 112.0) / Data.TRAINING.size()
	for i in Data.TRAINING.size():
		var lesson: Array = Data.TRAINING[i]
		var mission := {"id":"training_"+lesson[2], "name":lesson[0], "detail":lesson[1], "lesson":lesson[2], "region":0}
		var row := at + Vector2(16.0, 60.0 + i * row_height)
		var card := _button(Rect2(row, Vector2(423, row_height-5.0)), "", _enter.bind("training", mission, takeoff and i == 0))
		card.tooltip_text = lesson[0]
		_chrome_icon(card, Rect2(9,5,92,row_height-15.0), Rect2(87*i,460,85,40))
		_text(row + Vector2(107, 2), lesson[0], 19, Color("#ffe1a1"))
		_text(row + Vector2(107, 27), lesson[1], 15, Color("#e0f2ff"))
	var toggle := _button(Rect2(at + Vector2(16,height-53.0),Vector2(423,40)), "起飞方式  ·  %s     »" % ("跑道" if takeoff else "空中"), _toggle_takeoff)
	toggle.add_theme_stylebox_override("normal", CarrierLobby.border_style(true))

func _aircraft_details(sidebar: Vector2, width: float, viewport_size: Vector2) -> void:
	var spec := catalogue.aircraft(viewed_plane)
	var owned: bool = viewed_plane in profile.state.unlocked
	if not panel_mods or not owned:
		var left := menu_safe.position.x + 183.0
		var shelf := Vector2(left,viewport_size.y-232.0)
		var span := viewport_size.x-left-20.0
		_panel(Rect2(shelf,Vector2(span,102)))
		_chrome_icon(view, Rect2(shelf+Vector2(17,15),Vector2(64,64)), Rect2(505,419,44,44))
		_text(shelf+Vector2(91,12),str(spec.name),26)
		_text(shelf+Vector2(91,52),"%s · %s" % [spec.origin,spec.role],15,Color("#c1e9fa"))
		var stats := shelf + Vector2(maxf(312.0,span*0.35),15)
		_stat_line(stats,"极速",float(spec.maxSpeed)*3.6,1750.0,"%d 公里/时" % (spec.maxSpeed*3.6))
		_stat_line(stats+Vector2(0,24),"耐久",float(spec.durability),4450.0,str(spec.durability))
		_stat_line(stats+Vector2(0,48),"翼展",float(spec.span),24.0,"%.1f 米" % spec.span)
		var selection := "已选择" if viewed_plane == profile.state.selected else ("选择战机" if owned else ("未解锁 · %d 信用点" % Data.AIRCRAFT_PRICE))
		_button(Rect2(shelf+Vector2(span-201.0,12),Vector2(185,34)),selection,_select_plane,viewed_plane != profile.state.selected)
		if owned and viewed_plane == profile.state.selected:
			var mods := _button(Rect2(shelf+Vector2(span-201.0,53),Vector2(185,35)),"改装升级  »",_toggle_mods)
			mods.add_theme_stylebox_override("normal",CarrierLobby.border_style(true))
	else:
		_panel(Rect2(sidebar, Vector2(width, 365)))
		_text(sidebar + Vector2(21, 14), str(spec.name), 28)
		_text(sidebar + Vector2(21, 53), "%s · %s" % [spec.origin, spec.role], 16, Color("#a4c4d9"))
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
	scroll.position = Vector2(menu_safe.position.x+184,viewport_size.y-124.0)
	scroll.size = Vector2(viewport_size.x-scroll.position.x-21.0,97.0)
	scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	var bar := HBoxContainer.new()
	bar.add_theme_constant_override("separation", 9)
	var roster: Array = [catalogue.aircraft("j20")]
	for item: Dictionary in catalogue.source.fleet:
		if item.id != "j20":
			roster.append(item)
	for plane: Dictionary in roster:
		if plane.support:
			continue
		var button := Button.new()
		var card_state := "已选择" if plane.id == viewed_plane else ("可使用" if plane.id in profile.state.unlocked else "未解锁")
		button.tooltip_text = "%s  ·  %s" % [plane.name,card_state]
		var artwork := ["j20","a10","alphajet","bf109"].find(plane.id)
		if artwork >= 0:
			_chrome_icon(button,Rect2(24,8,145,40),Rect2(122*artwork,419,120,35))
		else:
			_chrome_icon(button,Rect2(74,6,45,44),Rect2(505,419,44,44))
		var title := Label.new()
		title.mouse_filter=Control.MOUSE_FILTER_IGNORE
		title.text=button.tooltip_text
		title.position=Vector2(7,52)
		title.size=Vector2(179,24)
		title.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER
		title.text_overrun_behavior=TextServer.OVERRUN_TRIM_ELLIPSIS
		title.add_theme_font_size_override("font_size",13)
		button.add_child(title)
		button.custom_minimum_size = Vector2(193,81)
		button.add_theme_stylebox_override("normal",CarrierLobby.border_style(plane.id == viewed_plane))
		button.add_theme_stylebox_override("hover",button_styles.hover)
		button.add_theme_stylebox_override("pressed",button_styles.pressed)
		button.pressed.connect(_browse_plane.bind(str(plane.id)))
		bar.add_child(button)
	scroll.add_child(bar)
	view.add_child(scroll)
	scroll.set_deferred("scroll_horizontal", card_scroll)
	scroll.get_h_scroll_bar().value_changed.connect(func(value): card_scroll = int(value))

func _stat_line(at: Vector2, label: String, value: float, range_max: float, display: String) -> void:
	_text(at,label,14,Color("#dff2fd"))
	for active in [false,true]:
		var bar := ColorRect.new()
		bar.color=Color("#75d8fd") if active else Color("#163548")
		bar.position=at+Vector2(55,8)
		bar.size=Vector2(128.0*(clampf(value/range_max,0,1) if active else 1.0),5)
		bar.mouse_filter=Control.MOUSE_FILTER_IGNORE
		view.add_child(bar)
	_text(at+Vector2(196,0),display,14,Color("#eefbff"))

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

func _show_carrier_lobby() -> void:
	var plane := catalogue.aircraft(str(profile.state.selected))
	var details := {"name":plane.name, "role":plane.role, "notice":note,
		"level":Data.level(int(profile.state.xp)), "credits":int(profile.state.credits)}
	var handlers := {
		"lobby":["大厅", _open.bind("lobby")], "hangar":["战机机库", _open.bind("hangar")],
		"campaign":["战役", _open.bind("campaign")], "training":["训练模式", _open.bind("training")],
		"pilot":["个人档案", _open.bind("pilot")], "settings":["设置", _open.bind("settings")],
		"start":["开始战斗", _start_campaign.bind(int(profile.state.campaign))], "free":["无限空战", _start_free],
	}
	lobby_screen = CarrierLobby.new()
	view.add_child(lobby_screen)
	lobby_screen.configure(font, details, handlers, route)

func _build_showcase() -> void:
	showcase = Node3D.new()
	showcase.name = "SharedCarrierShowcase"
	add_child(showcase)
	preview_camera = Camera3D.new()
	preview_camera.far = 18000.0
	preview_camera.near = 0.32
	showcase.add_child(preview_camera)
	showcase_stage = CarrierStage.new()
	showcase_stage.name = "CarrierStage"
	showcase.add_child(showcase_stage)
	showcase_stage.setup(preview_camera, catalogue.source.theatres[0])
	showcase_aircraft = Node3D.new()
	showcase.add_child(showcase_aircraft)
	_set_showcase_aircraft(str(profile.state.selected))
	_sync_showcase_stage()

func _sync_showcase_stage() -> void:
	preview_camera.fov = 34.0 if route in ["lobby", "hangar"] else 38.0
	preview_camera.h_offset = -0.4 if route in ["lobby", "hangar"] else 4.2
	preview_camera.v_offset = -0.32 if route != "hangar" else -1.12
	preview_camera.make_current()
	_tick_orbit(0.0, true)

func _set_showcase_aircraft(id: String) -> void:
	if id == preview_id and showcase_aircraft.get_child_count() > 0:
		return
	preview_id = id
	for child in showcase_aircraft.get_children():
		showcase_aircraft.remove_child(child)
		child.queue_free()
	var spec := catalogue.aircraft(id)
	var plane := catalogue.mesh(id)
	showcase_aircraft.add_child(plane)
	catalogue.set_gear(catalogue.gear_tracks(plane), 1.0, id == "j20")
	for surface: MeshInstance3D in plane.find_children("*", "MeshInstance3D", true, false):
		surface.layers = 2
	if id == "j20":
		var fill := OmniLight3D.new()
		fill.position = Vector3(8.0, 6.8, -3.8)
		fill.omni_range = 25.0
		fill.light_energy = 3.1
		fill.light_color = Color("#c8d5ec")
		fill.light_cull_mask = 2
		plane.add_child(fill)
	showcase_aircraft.position.y = CarrierStage.DECK_Y + maxf(0.8, spec.gearClearance)
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
		loading_screen = null
		_open("lobby")
		note = "战机或战区加载失败，请重试"
		_render_menu()
		return
	loading_screen.set_status("正在装配战场")
	await get_tree().process_frame
	if is_instance_valid(showcase):
		showcase.get_parent().remove_child(showcase)
		showcase.queue_free()
		showcase = null
	route = "battle"
	current_battle = Battle.new()
	add_child(current_battle)
	current_battle.finished.connect(_battle_finished, CONNECT_DEFERRED)
	current_battle.setup(catalogue, profile, mode, operation, runway, prepared)
	current_battle.paused = true
	if DisplayServer.get_name() != "headless":
		var camera := current_battle.camera
		current_battle.effects.prime(camera.position - camera.global_basis.z * 13.0)
		await RenderingServer.frame_post_draw
		current_battle.effects.end_prime()
	loading_screen.meter.value = loading_screen.meter.max_value
	loading_screen.set_status("准备完成")
	await get_tree().process_frame
	var fade := create_tween()
	fade.tween_property(view, "modulate:a", 0.0, 0.23)
	await fade.finished
	loading_screen = null
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
	loading_screen = LoadingScreen.new()
	view.add_child(loading_screen)
	loading_screen.configure(preload("res://assets/loading/alpine.webp"), font, title)

func _prepare_sortie(mode: String, operation: Dictionary, runway: bool) -> Dictionary:
	var start := Battle.start_position(mode, operation, runway)
	var tiles := Landscape.opening_tiles(start)
	var seed_value := int(catalogue.source.theatres[int(operation.get("region", 0))].seed)
	Landscape.prepare_relief(seed_value)
	var fine_tiles := Landscape.fine_tile_index(seed_value)
	var relief_color := Landscape.load_relief_color(seed_value)
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
	var aircraft_paths := {}
	for id in ids:
		if not catalogue.scenes.has(id):
			aircraft_paths[id] = Data.mesh_path(id)
	var total := tiles.size() + aircraft_paths.size() + 1 + int(seed_value == 413)
	var meter := loading_screen.meter
	meter.max_value = total
	var ready := {}
	# Serialize the GPU-facing imports. The same material or texture can be
	# shared by several scenes and the renderer needs frames to service it.
	for id in aircraft_paths:
		loading_screen.set_status("正在加载%s" % catalogue.aircraft(id).name)
		var scene := await Data.load_scene(get_tree(), aircraft_paths[id])
		if not scene:
			return {}
		catalogue.scenes[id] = scene
		meter.value += 1
	if seed_value == 413:
		loading_screen.set_status("正在加载海岸场景")
		var cliff := await Data.load_scene(get_tree(), Landscape.COASTAL_CLIFF)
		if not cliff:
			return {}
		ready[Landscape.COASTAL_CLIFF] = cliff
		meter.value += 1
	# These are CPU-side tile decodes. Yield after each to keep the loading
	# screen repainting without a second queue to join or abandon on retry.
	for coord in tiles:
		var data := Landscape.read_region(coord, seed_value, fine_tiles, relief_color)
		if data.is_empty():
			return {}
		ready[coord] = data
		meter.value += 1
		loading_screen.set_status("已准备 %d / %d 项" % [int(meter.value), total])
		await get_tree().process_frame
	if relief_color:
		ready["relief_color"] = relief_color
	return ready

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
	panel.header = "战斗暂停" if page == "pause" else "飞行设置"
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
			panel.action(Rect2(41, 292, 482, 46), "退出本局", "leave", _abort_battle)
		"settings":
			var i := 0
			for item in _setting_items(false):
				panel.action(Rect2(41, 106 + i * 59, 482, 45), item[0], "", _set_setting.bind(item[1], item[2]))
				i += 1
			panel.action(Rect2(41, 289, 482, 45), "返回暂停", "", _pause_panel.bind("pause"))

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
	if route not in ["lobby", "hangar", "training"] or loading or not is_instance_valid(showcase_aircraft):
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
	if is_instance_valid(lobby_screen) and lobby_screen.blocks_orbit(at):
		return false
	for control in view.get_children():
		if (control is Panel or control is BaseButton or control is ScrollContainer) and control.visible and control.get_global_rect().has_point(at):
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
	var distance := orbit_distance * orbit_display.z
	spin += 3.48 if route != "training" else 3.17
	tilt += 0.011 if route == "lobby" else 0.071
	if route == "training":
		distance *= 1.12
	var offset := Vector3(sin(spin) * cos(tilt), sin(tilt), cos(spin) * cos(tilt)) * distance
	var at := target_point + offset
	at.y = maxf(at.y, CarrierStage.DECK_Y + 0.85)
	if not snap and preview_camera.position.is_equal_approx(at):
		return
	preview_camera.position = at
	preview_camera.look_at(target_point, Vector3.UP)
	showcase_stage.follow_view(at)

func _process(delta: float) -> void:
	if route in ["lobby", "hangar", "training"] and not loading:
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
	current_battle.world.set_background_budget(slow_windows >= 2, thermal_limited)
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
