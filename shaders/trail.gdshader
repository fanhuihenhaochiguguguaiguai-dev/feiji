shader_type spatial;
render_mode unshaded, blend_mix, cull_disabled, depth_draw_never, shadows_disabled;

uniform sampler2D grain : repeat_enable, filter_linear_mipmap;
uniform sampler2D depth_tex : hint_depth_texture, repeat_disable, filter_nearest;

void fragment() {
	float streak = texture(grain, vec2(UV.x * 0.91 - TIME * 0.055, UV.y * 0.44 + 0.17)).r;
	float detail = texture(grain, vec2(UV.x * 1.71 + 0.38, UV.y * 0.96 - TIME * 0.075)).g;
	float edge = abs(UV.y * 2.0 - 1.0) + (streak - 0.48) * 0.41;
	float density = (1.0 - smoothstep(0.06, 0.99, edge)) * smoothstep(0.08, 0.72, streak * 0.68 + detail * 0.32);
	float depth = texture(depth_tex, SCREEN_UV).x;
	vec4 behind = INV_PROJECTION_MATRIX * vec4(SCREEN_UV * 2.0 - 1.0, depth, 1.0);
	float fade = smoothstep(0.0, 6.0, (-behind.z / behind.w) + VERTEX.z);
	ALBEDO = COLOR.rgb * mix(0.49, 1.08, smoothstep(0.15, 0.85, streak + (UV.y - 0.5) * 0.27));
	ALPHA = COLOR.a * density * fade * smoothstep(7.0, 24.0, -VERTEX.z);
}
