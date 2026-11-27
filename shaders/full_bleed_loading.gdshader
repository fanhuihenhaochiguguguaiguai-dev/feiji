shader_type canvas_item;
render_mode unshaded;

uniform sampler2D artwork : source_color, filter_linear_mipmap, repeat_disable;
uniform vec2 drawable_ratio = vec2(1.0);
uniform vec2 artwork_centre = vec2(0.5);

void fragment() {
	vec2 reference_uv = (UV - artwork_centre) * drawable_ratio + 0.5;
	vec2 edge = clamp(reference_uv, vec2(0.0), vec2(1.0));
	vec2 beyond = reference_uv - edge;
	// Extend only the sky and cloud edge strips, while keeping the title,
	// aircraft and metal panel at their original scale and proportions.
	vec2 contained = abs(beyond) * 0.74 / (vec2(1.0) + 3.4 * abs(beyond));
	vec2 sample_uv = edge - sign(beyond) * contained;
	sample_uv.y += (sin(sample_uv.y * 8.8 + sign(beyond.x) * 0.8) * 0.027) * abs(beyond.x);
	COLOR = texture(artwork, clamp(sample_uv, vec2(0.0), vec2(1.0)));
}
