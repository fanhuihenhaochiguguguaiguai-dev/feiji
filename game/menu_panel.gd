extends Control

var variant := 0
var font: Font
var title := ""
var icon := ""
var activate: Callable
var held := false
var over := false

func _ready() -> void:
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	mouse_entered.connect(func(): over = true; queue_redraw())
	mouse_exited.connect(func(): over = false; queue_redraw())
	resized.connect(queue_redraw)

func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			held = true
		elif held and Rect2(Vector2.ZERO, size).has_point(event.position):
			held = false
			activate.call()
		else:
			held = false
		queue_redraw()
		accept_event()

func _draw() -> void:
	var gold := variant == 1
	var larger := gold or variant == 2
	var cut := 31.0 if larger else 13.0
	var rect := size
	var points := PackedVector2Array([Vector2(cut,1),Vector2(rect.x - 2,1),Vector2(rect.x - cut,rect.y - 2),Vector2(1,rect.y - 2)])
	var surface := Color("#5c412bd9") if gold else Color("#0c2031da")
	if held or over:
		surface = surface.lightened(0.18)
	draw_colored_polygon(points, surface)
	points.append(points[0])
	var edge := Color("#f6d18b") if gold else Color("#6c9db880")
	if gold:
		draw_polyline(points, Color(0.85, 0.53, 0.21, 0.13), 9, true)
		draw_line(points[0], points[1], Color(0.93, 0.66, 0.36, 0.4), 5, true)
	draw_polyline(points, edge, 2.0 if gold else 1.0, true)
	draw_line(Vector2(cut + 7, rect.y - 6), Vector2(rect.x - cut + 1, rect.y - 6), Color(edge, 0.24), 1.2, true)
	var tint := Color("#fff2ce") if gold else Color("#e4eff5")
	var text_size := 33 if gold else (22 if larger else 20)
	var base := Vector2(70 if larger else 56, rect.y * 0.50 + text_size * 0.37)
	draw_string(font, base, title, HORIZONTAL_ALIGNMENT_LEFT, -1, text_size, tint)
	var c := Vector2(41 if larger else 31, rect.y * 0.50)
	match icon:
		"plane":
			var pts := [Vector2(0,-16),Vector2(3,-7),Vector2(3,-1),Vector2(15,7),Vector2(15,10),Vector2(4,7),Vector2(4,12),Vector2(7,15),Vector2(-7,15),Vector2(-4,12),Vector2(-4,7),Vector2(-15,10),Vector2(-15,7),Vector2(-3,-1),Vector2(-3,-7)]
			var shape := PackedVector2Array()
			for point in pts:
				shape.append(c+point)
			draw_colored_polygon(shape, tint)
		"infinite":
			for dir in [-1.0, 1.0]:
				var shape := PackedVector2Array()
				for j in 25:
					var a := TAU * float(j)/24.0
					shape.append(c + Vector2(dir * (8.0 - 8.0*cos(a)), 7.0*sin(a)))
				draw_polyline(shape, tint, 2.1, true)
		"home":
			draw_polyline(PackedVector2Array([c+Vector2(-13,0),c+Vector2(0,-12),c+Vector2(13,0)]),tint,2.9,true)
			draw_rect(Rect2(c+Vector2(-8,-2),Vector2(16,14)), tint, false, 2.3)
		"mods":
			draw_line(c+Vector2(-11,-10),c+Vector2(11,11),tint,3,true)
			draw_line(c+Vector2(12,-11),c+Vector2(-11,12),tint,3,true)
			draw_circle(c+Vector2(11,-10),4,tint,false,2,true)
		"map":
			draw_rect(Rect2(c-Vector2(12,10),Vector2(24,20)),tint,false,2)
			draw_polyline(PackedVector2Array([c+Vector2(-10,3),c+Vector2(-4,-4),c+Vector2(4,2),c+Vector2(10,-5)]),tint,2,true)
		"hangar":
			draw_polyline(PackedVector2Array([c+Vector2(-12,9),c+Vector2(-12,-3),c+Vector2(0,-10),c+Vector2(12,-3),c+Vector2(12,9),c+Vector2(-12,9)]),tint,2,true)
			draw_line(c+Vector2(-7,4),c+Vector2(7,4),tint,2,true)
		_:
			draw_circle(c, 4, tint, true, -1, true)
	if gold:
		for x in [0.0, 8.0]:
			var a := Vector2(size.x - 43 + x, c.y)
			draw_polyline(PackedVector2Array([a-Vector2(7,8),a,a-Vector2(7,-8)]), edge, 3, true)
