shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never, shadows_disabled;

void fragment() {
	vec2 ellipse = (UV - 0.5) * vec2(2.0, 2.0);
	float radius = dot(ellipse, ellipse);
	ALBEDO = vec3(0.008, 0.016, 0.023);
	ALPHA = 0.54 * exp(-4.5 * radius) * (1.0 - smoothstep(0.46, 1.0, radius));
}
