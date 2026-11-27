extends Control

const CANVAS := Vector2(1280.0, 720.0)
const ATLAS = preload("res://assets/ui/reference-atlas.webp")
const GOLD := Color("#f5d38c")
const INK := Color("#d4e9f3")

static var cached_face: Font
static var cached_distance_field: Font
var frame := Control.new()
var typeface: Font
var full_bleed: ShaderMaterial

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
	if art:
		var background := ColorRect.new()
		background.mouse_filter = Control.MOUSE_FILTER_IGNORE
		full_bleed = ShaderMaterial.new()
		full_bleed.shader = preload("res://shaders/full_bleed_loading.gdshader")
		full_bleed.set_shader_parameter("artwork", art)
		background.material = full_bleed
		add_child(background)
		background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	frame.size = CANVAS
	frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	frame.clip_contents = true
	add_child(frame)
	resized.connect(_fit)
	_fit()

func _fit() -> void:
	var safe := safe_bounds(self, size)
	var factor := maxf(0.001, minf(safe.size.x / CANVAS.x, safe.size.y / CANVAS.y))
	frame.scale = Vector2.ONE * factor
	frame.position = safe.position + (safe.size - CANVAS * factor) * 0.5
	if full_bleed:
		full_bleed.set_shader_parameter("drawable_ratio", size / (CANVAS * factor))
		full_bleed.set_shader_parameter("artwork_centre", safe.get_center() / size.max(Vector2.ONE))

static func safe_bounds(host: Control, fallback: Vector2) -> Rect2:
	if not OS.has_feature("android"):
		return Rect2(Vector2.ZERO, fallback)
	var window := host.get_window()
	var physical := Rect2i(window.position, window.size)
	var exposed := physical.intersection(DisplayServer.get_display_safe_area())
	if not exposed.has_area():
		return Rect2(Vector2.ZERO, fallback)
	var units := fallback / Vector2(physical.size)
	return Rect2(Vector2(exposed.position - physical.position) * units, Vector2(exposed.size) * units)

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
