shader_type spatial;
render_mode unshaded, blend_mix, cull_disabled, depth_draw_never, shadows_disabled;

uniform sampler2D smoke_volume : source_color, repeat_disable, filter_linear_mipmap;
uniform sampler2D depth_tex : hint_depth_texture, repeat_disable, filter_nearest;

vec4 smoke_section(float path, float across) {
	float frame = mod(floor(path) * 7.0, 16.0);
	vec2 cell = vec2(mod(frame, 4.0), floor(frame * 0.25));
	vec2 texel = vec2(mix(0.23, 0.82, across), mix(0.18, 0.82, fract(path)));
	return texture(smoke_volume, (cell + texel) * 0.25);
}

void fragment() {
	float path = UV.x * 0.56 - TIME * 0.065;
	float overlap = 0.5 - 0.5 * cos(TAU * fract(path));
	vec4 smoke = mix(smoke_section(path + 0.5, 1.0 - UV.y), smoke_section(path, UV.y), overlap);
	float edge = 1.0 - smoothstep(0.62, 1.0, abs(UV.y * 2.0 - 1.0));
	float depth = texture(depth_tex, SCREEN_UV).x;
	vec4 behind = INV_PROJECTION_MATRIX * vec4(SCREEN_UV * 2.0 - 1.0, depth, 1.0);
	float fade = smoothstep(0.0, 6.0, (-behind.z / behind.w) + VERTEX.z);
	ALBEDO = COLOR.rgb * (0.68 + dot(smoke.rgb, vec3(0.25, 0.31, 0.16)));
	ALPHA = COLOR.a * smoke.a * edge * fade * smoothstep(7.0, 24.0, -VERTEX.z);
}
