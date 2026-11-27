extends "res://game/reference_frame.gd"

var meter := ProgressBar.new()
var status: Label
var fill: NinePatchRect
var status_art: TextureRect
var fill_width := 0.0
var caps := Vector2i.ZERO

func configure(art: Texture2D, face: Font, mission: String) -> void:
	mount(art, face)
	mouse_filter = Control.MOUSE_FILTER_STOP
	var startup := mission.is_empty()
	if startup:
		status = caption(Rect2(444, 629, 392, 32), "", 20, INK)
		status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	else:
		if mission == "破晓巡弋":
			picture(Rect2(358, 466, 217, 51), tile(Rect2(0, 83, 217, 51)))
		else:
			caption(Rect2(361, 463, 602, 55), mission, 41, GOLD)
		status = caption(Rect2(362, 521, 596, 34), "正在准备战机与空域", 22, INK)
		status_art = picture(Rect2(359, 523, 156, 27), tile(Rect2(218, 83, 156, 27)))
		status_art.hide()
	fill = NinePatchRect.new()
	fill.texture = tile(Rect2(0, 0, 350, 26) if startup else Rect2(0, 28, 704, 49))
	fill.position = Vector2(443, 667) if startup else Vector2(300, 562)
	fill.size = Vector2(0, 13 if startup else 35)
	caps = Vector2i(12, 24) if startup else Vector2i(15, 28)
	fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	fill_width = 394.0 if startup else 676.0
	frame.add_child(fill)
	meter.hide()
	meter.step = 0.0
	add_child(meter)
	meter.value_changed.connect(_paint_progress)
	_paint_progress(0.0)

func set_status(value: String) -> void:
	status.text = value
	if status_art:
		status_art.visible = value == "正在装配战场"
		status.visible = not status_art.visible

func _paint_progress(_value: float) -> void:
	fill.visible = meter.ratio > 0.0
	var span := fill_width * meter.ratio
	var cap_scale := minf(1.0, span / float(caps.x + caps.y))
	fill.patch_margin_left = floori(caps.x * cap_scale)
	fill.patch_margin_right = floori(caps.y * cap_scale)
	fill.size.x = span
