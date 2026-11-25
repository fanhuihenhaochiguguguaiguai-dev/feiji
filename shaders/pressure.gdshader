shader_type spatial;
render_mode unshaded, cull_back, depth_draw_never, shadows_disabled;

uniform sampler2D screen_tex : hint_screen_texture, repeat_disable, filter_linear;
uniform sampler2D depth_tex : hint_depth_texture, repeat_disable, filter_nearest;
instance uniform float amplitude = 1.0;
varying float wave_depth;

void vertex() {
	wave_depth = -(MODELVIEW_MATRIX * vec4(VERTEX, 1.0)).z;
}

void fragment() {
	float d = texture(depth_tex, SCREEN_UV).r;
	vec4 p = INV_PROJECTION_MATRIX * vec4(SCREEN_UV * 2.0 - 1.0, d, 1.0);
	float depth_mask = smoothstep(0.0, 12.0, -p.z / p.w - wave_depth);
	float edge = pow(1.0 - clamp(dot(normalize(NORMAL), normalize(VIEW)), 0.0, 1.0), 2.3);
	vec2 shear = NORMAL.xy * edge * (0.004 + 0.0008 * sin(UV.y * 93.0 + TIME * 10.0)) * amplitude * depth_mask;
	ALBEDO = texture(screen_tex, clamp(SCREEN_UV + shear, vec2(0.001), vec2(0.999))).rgb;
	ALPHA = edge * depth_mask * amplitude * 0.77;
}
