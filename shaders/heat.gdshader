shader_type spatial;
render_mode unshaded, cull_back, depth_draw_never, shadows_disabled;

uniform sampler2D scene_depth : hint_depth_texture, repeat_disable, filter_nearest;

void fragment() {
	vec4 behind = INV_PROJECTION_MATRIX * vec4(SCREEN_UV * 2.0 - 1.0, texture(scene_depth, SCREEN_UV).r, 1.0);
	float clear_air = smoothstep(0.0, 5.0, -behind.z / behind.w + VERTEX.z);
	float wave = sin(UV.y * 83.0 - TIME * 33.0 + sin(UV.x * 18.0 + TIME * 3.8) * 0.95);
	float front = clamp(dot(normalize(NORMAL), VIEW), 0.0, 1.0);
	float shape = sin(UV.y * PI) * smoothstep(0.18, 0.56, front) * (1.0 - front * 0.52);
	ALBEDO = mix(vec3(0.32, 0.42, 0.62), vec3(0.94, 0.86, 0.76), wave * 0.5 + 0.5);
	ALPHA = clear_air * shape * (0.013 + pow(wave * 0.5 + 0.5, 5.0) * 0.10);
}
