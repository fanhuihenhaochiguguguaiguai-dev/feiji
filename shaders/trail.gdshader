shader_type spatial;
render_mode unshaded, blend_mix, cull_disabled, depth_draw_never, shadows_disabled;

uniform sampler2D grain : repeat_enable, filter_linear_mipmap;
uniform sampler2D depth_tex : hint_depth_texture, repeat_disable, filter_nearest;

void fragment() {
	float streak = texture(grain, vec2(UV.x * 0.91 - TIME * 0.055, UV.y * 0.44 + 0.17)).r;
	float edge = abs(UV.y * 2.0 - 1.0) + (streak - 0.5) * 0.26;
	float density = (1.0 - smoothstep(0.06, 0.95, edge)) * mix(0.47, 1.0, streak);
	float depth = texture(depth_tex, SCREEN_UV).x;
	vec4 behind = INV_PROJECTION_MATRIX * vec4(SCREEN_UV * 2.0 - 1.0, depth, 1.0);
	float fade = smoothstep(0.0, 6.0, (-behind.z / behind.w) + VERTEX.z);
	ALBEDO = COLOR.rgb * mix(0.70, 1.10, streak);
	ALPHA = COLOR.a * density * fade * smoothstep(7.0, 24.0, -VERTEX.z);
}
