shader_type spatial;
render_mode unshaded, blend_mix, cull_disabled, depth_draw_never, shadows_disabled, skip_vertex_transform;

uniform sampler2D smoke_volume : source_color, repeat_disable, filter_linear_mipmap;
uniform sampler2D depth_tex : hint_depth_texture, repeat_disable, filter_nearest;

void vertex() {
	vec3 forward = MODEL_MATRIX[0].xyz;
	vec3 point = MODEL_MATRIX[3].xyz + forward * UV.x;
	vec3 eye = INV_VIEW_MATRIX[3].xyz - point;
	vec3 transverse = cross(forward, eye);
	if (dot(transverse, transverse) < 0.001) {
		transverse = MODEL_MATRIX[1].xyz;
	}
	float phase = INSTANCE_CUSTOM.r + UV.x * 0.22;
	float settled = INSTANCE_CUSTOM.b;
	float age = max(0.0, INSTANCE_CUSTOM.g - UV.x * 0.03);
	float billow = 0.5 + 0.5 * sin(phase * 1.63 + age * 2.7);
	float spread = smoothstep(0.02, 1.65, age);
	point += vec3(sin(phase), 0.2 + billow, cos(phase * 0.68)) * spread * (0.62 + settled * 0.88);
	float width = 0.51 + (3.10 + billow * 2.1) * spread + settled * (0.73 + billow * 0.46);
	point += normalize(transverse) * ((UV.y * 2.0 - 1.0) * width);
	VERTEX = (VIEW_MATRIX * vec4(point, 1.0)).xyz;
	float fade = pow(clamp(1.0 - settled / 3.1, 0.0, 1.0), 1.35);
	fade *= smoothstep(0.0, 1.0, INSTANCE_CUSTOM.a + UV.x * 0.125);
	COLOR = vec4(0.64, 0.67, 0.72, fade * (0.84 - spread * 0.42 + billow * 0.13));
	UV.x = phase;
}

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
