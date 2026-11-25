shader_type spatial;
render_mode unshaded, cull_back, depth_draw_never, shadows_disabled;

uniform sampler2D depth_tex : hint_depth_texture, repeat_disable, filter_nearest;
instance uniform float amplitude = 1.0;
varying float wave_depth;

void vertex() {
	wave_depth = -(MODELVIEW_MATRIX * vec4(VERTEX, 1.0)).z;
}

void fragment() {
	float d = texture(depth_tex, SCREEN_UV).r;
	vec4 p = INV_PROJECTION_MATRIX * vec4(SCREEN_UV * 2.0 - 1.0, d, 1.0);
	float depth_mask = smoothstep(0.0, 10.0, -p.z / p.w - wave_depth);
	float grazing = 1.0 - clamp(dot(normalize(NORMAL), normalize(VIEW)), 0.0, 1.0);
	float turbulence = 0.85 + 0.15 * sin(UV.y * 72.0 + TIME * 9.0 + sin(UV.x * 37.0) * 1.7);
	float edge = smoothstep(0.59, 0.90, grazing) * (1.0 - smoothstep(0.965, 1.0, grazing));
	ALBEDO = mix(vec3(0.48, 0.58, 0.66), vec3(0.91, 0.86, 0.71), turbulence * amplitude);
	ALPHA = edge * turbulence * depth_mask * amplitude * 0.34;
}
