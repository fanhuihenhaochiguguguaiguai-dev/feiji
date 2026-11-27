extends "res://game/reference_frame.gd"

const CHROME = preload("res://assets/ui/studio-chrome.webp")
const TARGETS := {
	"lobby": Rect2(27, 128, 229, 65), "hangar": Rect2(27, 206, 229, 63),
	"campaign": Rect2(27, 283, 229, 64), "pilot": Rect2(745, 13, 198, 42),
	"settings": Rect2(1164, 10, 108, 46), "start": Rect2(846, 483, 431, 91),
	"training": Rect2(737, 590, 242, 53), "free": Rect2(982, 590, 256, 53),
}
const PLAQUES := {
	"lobby": [Rect2(0,130,233,70), Vector2(26,126)], "hangar": [Rect2(235,130,233,68), Vector2(26,204)],
	"campaign": [Rect2(470,130,233,68), Vector2(26,282)], "pilot": [Rect2(0,79,200,47), Vector2(744,11)],
	"settings": [Rect2(378,79,109,50), Vector2(1164,8)], "start": [Rect2(0,202,448,97), Vector2(832,479)],
	"training": [Rect2(450,202,248,58), Vector2(734,588)], "free": [Rect2(718,202,261,58), Vector2(979,588)],
}

var actions := {}

func configure(face: Font, details: Dictionary, handlers: Dictionary, page: String) -> void:
	mount(null, face)
	var extra := frame.size - CANVAS
	var right := Vector2(extra.x, 0)
	var corner := extra
	var base := Vector2(0, extra.y)
	var brass := Color("#ffe0a1")
	art(Rect2(0,0,741,76), Rect2(0,0,741,76))
	art(Rect2(Vector2(969,10)+right,Vector2(173,46)), Rect2(202,79,173,46))
	value(Rect2(Vector2(1073,16)+right,Vector2(64,31)),Rect2(397,83,57,31),str(details.credits),"2600",20,brass)
	var trim := ColorRect.new()
	trim.color = Color("#b78e52")
	trim.position = Vector2(0, frame.size.y-24)
	trim.size = Vector2(frame.size.x, 2)
	trim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	frame.add_child(trim)
	art(Rect2(Vector2(frame.size.x/2.0-122,frame.size.y-57),Vector2(244,57)),Rect2(433,302,244,57))
	if page == "lobby":
		art(Rect2(Vector2(13,539)+base,Vector2(428,113)),Rect2(0,302,428,113))
		value(Rect2(Vector2(157,557)+base,Vector2(245,41)),Rect2(0,135,198,41),details.name,"歼二十战斗机",27,Color.WHITE)
		value(Rect2(Vector2(161,605)+base,Vector2(215,28)),Rect2(198,135,108,28),details.role,"隐身战斗机",19,INK)
		if not str(details.notice).is_empty():
			var notice := caption(Rect2(frame.size.x/2.0-330,81,660,36), details.notice,19,INK)
			notice.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			notice.add_theme_color_override("font_outline_color", Color("#101923"))
			notice.add_theme_constant_override("outline_size",6)
	var hover := ShaderMaterial.new()
	hover.shader = preload("res://shaders/lobby_button.gdshader")
	var blank := StyleBoxEmpty.new()
	for id: String in TARGETS:
		if id in ["start","free","training"] and page != "lobby":
			continue
		var shift := corner if id in ["start","free","training"] else (right if id in ["pilot","settings"] else Vector2.ZERO)
		var control_area: Rect2 = TARGETS[id]
		var plaque: Array = PLAQUES[id]
		var tile_area: Rect2 = plaque[0]
		var plate := art(Rect2(Vector2(plaque[1])+shift,tile_area.size),tile_area)
		if id in ["lobby","hangar","campaign"]:
			if id == page and id != "lobby":
				plate.modulate = Color(1.16,1.22,1.24)
			elif id == "lobby" and page != "lobby":
				plate.modulate = Color(0.72,0.82,0.87)
		var hit := Button.new()
		hit.name = id
		hit.position = control_area.position+shift
		hit.size = control_area.size
		hit.tooltip_text = handlers[id][0]
		hit.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		hit.pressed.connect(handlers[id][1])
		for state in ["normal","hover","pressed","focus","disabled"]:
			hit.add_theme_stylebox_override(state,blank)
		var light := ColorRect.new()
		light.color = Color("#ccf4ff00")
		light.mouse_filter = Control.MOUSE_FILTER_IGNORE
		light.material = hover
		hit.add_child(light)
		light.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		hit.mouse_entered.connect(func(): light.color.a=0.13)
		hit.mouse_exited.connect(func(): light.color.a=0.0)
		hit.button_down.connect(func(): light.color.a=0.27)
		hit.button_up.connect(func(): light.color.a=0.0)
		hit.focus_entered.connect(func(): light.color.a=0.15)
		hit.focus_exited.connect(func(): light.color.a=0.0)
		frame.add_child(hit)
		actions[id]=hit
	value(Rect2(Vector2(910,18)+right,Vector2(24,28)),Rect2(376,83,20,28),str(details.level),"1",18,INK)

func _fit() -> void:
	var safe := safe_bounds(self,size)
	var factor := maxf(0.001,minf(safe.size.x/CANVAS.x,safe.size.y/CANVAS.y))
	frame.position=safe.position
	frame.scale=Vector2.ONE*factor
	frame.size=safe.size/factor

func blocks_orbit(at: Vector2) -> bool:
	for hit: Button in actions.values():
		if hit.get_global_rect().has_point(at):
			return true
	var local := frame.get_global_transform().affine_inverse()*at
	return local.y < 76.0 or local.y > frame.size.y-27.0

func art(area: Rect2, source: Rect2) -> TextureRect:
	return picture(area, chrome_slice(source))

static func chrome_slice(source: Rect2) -> AtlasTexture:
	var part := AtlasTexture.new()
	part.atlas=CHROME
	part.region=source
	part.filter_clip=true
	return part

static func border_style(brass := false) -> StyleBoxTexture:
	var result := StyleBoxTexture.new()
	result.texture=CHROME
	result.region_rect=Rect2(809 if brass else 712,300,88,88)
	for edge in [SIDE_LEFT,SIDE_RIGHT,SIDE_TOP,SIDE_BOTTOM]:
		result.set_texture_margin(edge,15.0)
		result.set_content_margin(edge,8.0)
	return result

func value(area: Rect2, source: Rect2, actual: String, master: String, points: int, tint: Color) -> void:
	if actual == master:
		picture(Rect2(area.position, source.size), tile(source))
	else:
		var length := typeface.get_string_size(actual,HORIZONTAL_ALIGNMENT_LEFT,-1.0,points).x
		var fitted := maxi(1,floori(points*minf(1.0,area.size.x/maxf(1.0,length))))
		caption(area,actual,fitted,tint)
