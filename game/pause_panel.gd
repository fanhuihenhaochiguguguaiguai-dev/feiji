extends Control

const FRAME := Vector2(564, 370)
const INK := Color("#e7f6ff")
const EDGE := Color("#58c9de")

class ActionButton extends Button:
	var primary := false
	var glyph := ""
	var typeface: Font

	func _ready() -> void:
		flat = true
		mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		for state in ["normal", "hover", "pressed", "disabled", "focus"]:
			add_theme_stylebox_override(state, StyleBoxEmpty.new())
		for state in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color", "font_disabled_color"]:
			add_theme_color_override(state, Color.TRANSPARENT)
		mouse_entered.connect(queue_redraw)
		mouse_exited.connect(queue_redraw)
		button_down.connect(queue_redraw)
		button_up.connect(queue_redraw)
		focus_entered.connect(queue_redraw)
		focus_exited.connect(queue_redraw)

	func _draw() -> void:
		var bright := is_hovered() or has_focus() or button_pressed
		var edge := Color("#7deeff") if primary or bright else Color("#569bad")
		var fill := Color("#09546bee") if primary else Color("#0d2939f1")
		var shape := corners(Rect2(Vector2.ONE, size - Vector2.ONE * 2.0), 11.0)
		draw_colored_polygon(shape, fill.lightened(0.09) if bright else fill)
		shape.append(shape[0])
		if primary:
			draw_polyline(shape, Color(edge, 0.16), 8.0, true)
		draw_polyline(shape, Color(edge, 0.75), 1.35, true)
		draw_line(Vector2(17, size.y - 4), Vector2(size.x - 17, size.y - 4), Color(edge, 0.22), 1.0, true)
		var font_size := 27 if primary else 23
		var width := typeface.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
		var y := size.y * 0.5
		var start := (size.x - width - (36.0 if not glyph.is_empty() else 0.0)) * 0.5
		if not glyph.is_empty():
			draw_icon(Vector2(start + 11, y), Color("#9aeeff") if primary else Color("#bddfeb"))
			start += 36.0
		draw_string(typeface, Vector2(start, y + font_size * 0.35), text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, Color("#f1f9fd"))

	func draw_icon(p: Vector2, tint: Color) -> void:
		match glyph:
			"continue":
				for offset in [-5.0, 5.0]:
					var a := p + Vector2(offset, 0.0)
					draw_polyline(PackedVector2Array([a + Vector2(-4, -8), a + Vector2(4, 0), a + Vector2(-4, 8)]), tint, 2.8, true)
			"restart":
				draw_arc(p, 10.0, -2.66, 2.66, 23, tint, 2.0, true)
				draw_polyline(PackedVector2Array([p + Vector2(-9,-10), p + Vector2(-10,-4), p + Vector2(-4,-5)]), tint, 2.0, true)
			"settings":
				draw_circle(p, 7.0, tint, false, 2.0, true)
				for tooth in 8:
					var axis := Vector2.RIGHT.rotated(float(tooth) * TAU / 8.0)
					draw_line(p + axis * 7.0, p + axis * 11.0, tint, 2.8, true)
			"gear":
				draw_polyline(PackedVector2Array([p + Vector2(-12,-8), p + Vector2(0,-5), p + Vector2(12,-8)]), tint, 2.0, true)
				draw_line(p + Vector2(0,-6), p + Vector2(0,5), tint, 2.0, true)
				for side in [-1.0, 1.0]:
					draw_circle(p + Vector2(side * 7, 5), 4.1, tint, false, 2.0, true)
			"leave":
				draw_polyline(PackedVector2Array([p + Vector2(2,-10), p + Vector2(-9,-10), p + Vector2(-9,10), p + Vector2(2,10)]), tint, 2.0, true)
				draw_line(p + Vector2(-3,0), p + Vector2(11,0), tint, 2.0, true)
				draw_polyline(PackedVector2Array([p + Vector2(5,-5), p + Vector2(11,0), p + Vector2(5,5)]), tint, 2.0, true)

	static func corners(rect: Rect2, cut: float) -> PackedVector2Array:
		var a := rect.position
		var b := rect.end
		return PackedVector2Array([Vector2(a.x + cut, a.y), Vector2(b.x - cut, a.y), Vector2(b.x, a.y + cut), Vector2(b.x, b.y - cut), Vector2(b.x - cut, b.y), Vector2(a.x + cut, b.y), Vector2(a.x, b.y - cut), Vector2(a.x, a.y + cut)])

var header := "战斗暂停"
var notice := ""
var typeface: Font
var body := Control.new()

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	body.size = FRAME
	body.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(body)
	resized.connect(_reflow)
	_reflow()

func _reflow() -> void:
	var fit := minf(1.0, minf((size.x - 40.0) / FRAME.x, (size.y - 38.0) / FRAME.y))
	body.scale = Vector2.ONE * maxf(0.15, fit)
	body.position = (size - FRAME * body.scale) * 0.5
	queue_redraw()

func action(area: Rect2, label: String, glyph: String, pressed: Callable, primary := false) -> void:
	var button := ActionButton.new()
	button.name = label
	button.text = label
	button.typeface = typeface
	button.glyph = glyph
	button.primary = primary
	button.position = area.position
	button.size = area.size
	button.pressed.connect(pressed)
	body.add_child(button)

func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), Color("#030c193a"))
	draw_set_transform(body.position, 0.0, body.scale)
	var shape := ActionButton.corners(Rect2(Vector2.ZERO, FRAME), 23.0)
	draw_colored_polygon(shape, Color("#061c29ed"))
	shape.append(shape[0])
	draw_polyline(shape, Color(EDGE, 0.12), 12.0, true)
	draw_polyline(shape, Color(EDGE, 0.52), 1.8, true)
	var inner := ActionButton.corners(Rect2(Vector2(6, 6), FRAME - Vector2(12, 12)), 20.0)
	inner.append(inner[0])
	draw_polyline(inner, Color(EDGE, 0.2), 1.1, true)
	for x in [0, 1]:
		for y in [0, 1]:
			var corner := Vector2(6.0 if x == 0 else FRAME.x - 6.0, 6.0 if y == 0 else FRAME.y - 6.0)
			var direction := Vector2(1 if x == 0 else -1, 1 if y == 0 else -1)
			draw_polyline(PackedVector2Array([corner + Vector2(0, 28)*direction, corner + Vector2(0, 19)*direction, corner + Vector2(19, 0)*direction, corner + Vector2(38, 0)*direction]), EDGE.lightened(0.24), 2.4, true)
	var mid := FRAME.x * 0.5
	var aircraft := PackedVector2Array([Vector2(0,-16),Vector2(3,-5),Vector2(9,1),Vector2(36,4),Vector2(36,6),Vector2(9,6),Vector2(3,10),Vector2(-3,10),Vector2(-9,6),Vector2(-36,6),Vector2(-36,4),Vector2(-9,1),Vector2(-3,-5)])
	for i in aircraft.size():
		aircraft[i] += Vector2(mid, 25)
	draw_colored_polygon(aircraft, INK)
	for side in [-1.0, 1.0]:
		draw_line(Vector2(mid + side * 119, 68), Vector2(mid + side * 194, 68), Color(EDGE, 0.49), 1.5, true)
		for line in 7:
			var a := Vector2(mid + side * (186 + line * 4), 24.0)
			draw_line(a, a + Vector2(side * 26, 19), Color(EDGE, 0.11), 1.0, true)
	draw_string(typeface, Vector2(0, 82), header, HORIZONTAL_ALIGNMENT_CENTER, int(FRAME.x), 42, INK)
	if not notice.is_empty():
		draw_string(typeface, Vector2(0, 171), notice, HORIZONTAL_ALIGNMENT_CENTER, int(FRAME.x), 21, INK)
