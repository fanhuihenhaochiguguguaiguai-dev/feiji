extends Control

const CANVAS := Vector2(1280.0, 720.0)
const ATLAS = preload("res://assets/ui/reference-atlas.webp")
const GOLD := Color("#f5d38c")
const INK := Color("#d4e9f3")

static var cached_face: Font
static var cached_distance_field: Font
var frame := Control.new()
var typeface: Font

func mount(art: Texture2D, face: Font) -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	typeface = face
	if face is FontFile:
		if face != cached_face:
			cached_face = face
			var distance_field := face.duplicate() as FontFile
			distance_field.multichannel_signed_distance_field = true
			cached_distance_field = distance_field
		typeface = cached_distance_field
	var border := ColorRect.new()
	border.color = Color("#061429")
	border.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(border)
	border.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	frame.size = CANVAS
	frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	frame.clip_contents = true
	add_child(frame)
	picture(Rect2(Vector2.ZERO, CANVAS), art)
	resized.connect(_fit)
	_fit()

func _fit() -> void:
	var factor := minf(size.x / CANVAS.x, size.y / CANVAS.y)
	frame.scale = Vector2.ONE * factor
	frame.position = (size - CANVAS * factor) * 0.5

func picture(area: Rect2, art: Texture2D) -> TextureRect:
	var item := TextureRect.new()
	item.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	item.stretch_mode = TextureRect.STRETCH_SCALE
	item.texture = art
	item.position = area.position
	item.size = area.size
	item.mouse_filter = Control.MOUSE_FILTER_IGNORE
	frame.add_child(item)
	return item

static func tile(area: Rect2) -> AtlasTexture:
	var texture := AtlasTexture.new()
	texture.atlas = ATLAS
	texture.region = area
	texture.filter_clip = true
	return texture

func caption(area: Rect2, text: String, points: int, tint: Color) -> Label:
	var item := Label.new()
	item.text = text
	item.position = area.position
	item.size = area.size
	item.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	item.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	item.mouse_filter = Control.MOUSE_FILTER_IGNORE
	item.add_theme_font_override("font", typeface)
	item.add_theme_font_size_override("font_size", points)
	item.add_theme_color_override("font_color", tint)
	frame.add_child(item)
	return item
