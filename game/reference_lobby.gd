extends "res://game/reference_frame.gd"

const PLATE = preload("res://assets/ui/carrier-lobby.webp")
const TARGETS := {
	"lobby": Rect2(27, 128, 229, 65),
	"hangar": Rect2(27, 206, 229, 63),
	"campaign": Rect2(27, 283, 229, 64),
	"pilot": Rect2(745, 13, 198, 42),
	"settings": Rect2(1164, 10, 108, 46),
	"start": Rect2(846, 483, 431, 91),
	"training": Rect2(737, 590, 242, 53),
	"free": Rect2(982, 590, 256, 53),
}
const FOREGROUND := [Rect2(0, 0, 1280, 75), Rect2(0, 111, 259, 239),
	Rect2(15, 542, 423, 109), Rect2(835, 482, 445, 93), Rect2(734, 589, 508, 57), Rect2(0, 655, 1280, 65)]

var actions := {}

func configure(face: Font, model: Texture2D, details: Dictionary, handlers: Dictionary) -> void:
	mount(PLATE, face)
	picture(Rect2(Vector2.ZERO, CANVAS), model)
	# Keep the photographed frame in front when the aircraft is orbited or enlarged.
	for area: Rect2 in FOREGROUND:
		var layer := AtlasTexture.new()
		layer.atlas = PLATE
		var pixels := PLATE.get_size() / CANVAS
		var start := (area.position * pixels).round()
		layer.region = Rect2(start, (area.end * pixels).round() - start)
		layer.filter_clip = true
		picture(area, layer)
	var gold := Color("#ffe29b")
	_value(Rect2(910, 18, 20, 28), Rect2(376, 83, 20, 28), str(details.level), "1", 18, INK)
	_value(Rect2(1073, 16, 57, 31), Rect2(397, 83, 57, 31), str(details.credits), "2600", 20, gold,
		Rect2(1073, 16, 63, 31))
	_value(Rect2(157, 557, 198, 41), Rect2(0, 135, 198, 41), details.name, "歼二十战斗机", 27, Color.WHITE,
		Rect2(160, 557, 250, 41))
	_value(Rect2(161, 605, 108, 28), Rect2(198, 135, 108, 28), details.role, "隐身战斗机", 19, INK,
		Rect2(162, 601, 238, 33))
	if not str(details.notice).is_empty():
		var notice := caption(Rect2(312, 81, 660, 36), details.notice, 19, INK)
		notice.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		notice.add_theme_color_override("font_outline_color", Color("#101923"))
		notice.add_theme_constant_override("outline_size", 6)
	var hover := ShaderMaterial.new()
	hover.shader = preload("res://shaders/lobby_button.gdshader")
	var invisible := StyleBoxEmpty.new()
	for id: String in TARGETS:
		var area: Rect2 = TARGETS[id]
		var button := Button.new()
		button.name = id
		button.position = area.position
		button.size = area.size
		button.tooltip_text = handlers[id][0]
		button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		button.pressed.connect(handlers[id][1])
		for state in ["normal", "hover", "pressed", "focus", "disabled"]:
			button.add_theme_stylebox_override(state, invisible)
		var light := ColorRect.new()
		light.color = Color("#cdf5ff00")
		light.mouse_filter = Control.MOUSE_FILTER_IGNORE
		light.material = hover
		button.add_child(light)
		light.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		button.mouse_entered.connect(func(): light.color.a = 0.12)
		button.mouse_exited.connect(func(): light.color.a = 0.0)
		button.button_down.connect(func(): light.color.a = 0.26)
		button.button_up.connect(func(): light.color.a = 0.0)
		button.focus_entered.connect(func(): light.color.a = 0.14)
		button.focus_exited.connect(func(): light.color.a = 0.0)
		frame.add_child(button)
		actions[id] = button

func blocks_orbit(at: Vector2) -> bool:
	for button: Button in actions.values():
		if button.get_global_rect().has_point(at):
			return true
	var local := frame.get_global_transform().affine_inverse() * at
	return not Rect2(0, 73, 1280, 582).has_point(local)

func _value(area: Rect2, source: Rect2, actual: String, master: String, points: int, tint: Color,
		text_area := Rect2()) -> void:
	if actual == master:
		picture(area, tile(source))
	else:
		var bounds := area if text_area == Rect2() else text_area
		var length := typeface.get_string_size(actual, HORIZONTAL_ALIGNMENT_LEFT, -1.0, points).x
		var fitted := maxi(1, floori(points * minf(1.0, bounds.size.x / maxf(1.0, length))))
		caption(bounds, actual, fitted, tint)
