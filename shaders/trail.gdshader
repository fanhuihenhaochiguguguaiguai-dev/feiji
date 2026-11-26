shader_type spatial;
render_mode unshaded, blend_mix, cull_back, depth_draw_never, shadows_disabled, skip_vertex_transform;

uniform sampler2D smoke_volume : source_color, repeat_disable, filter_linear_mipmap;
uniform sampler2D depth_tex : hint_depth_texture, repeat_disable, filter_nearest;

varying vec3 stream_axis;
varying vec2 section_uv;

void vertex() {
	vec3 forward = MODEL_MATRIX[0].xyz;
	float along = VERTEX.y + 0.5;
	vec3 point = MODEL_MATRIX[3].xyz + forward * along;
	vec3 radial = (MODEL_MATRIX[1].xyz * VERTEX.z + MODEL_MATRIX[2].xyz * VERTEX.x) * 2.0;
	float phase = INSTANCE_CUSTOM.r + along * 0.22;
	float settled = INSTANCE_CUSTOM.b;
	float age = max(0.0, INSTANCE_CUSTOM.g - along * 0.03);
	float billow = 0.5 + 0.5 * sin(phase * 1.63 + age * 2.7);
	float spread = smoothstep(0.02, 1.65, age);
	point += vec3(sin(phase), 0.2 + billow, cos(phase * 0.68)) * spread * (0.62 + settled * 0.88);
	float width = 0.55 + (3.10 + billow * 2.1) * spread + settled * (0.73 + billow * 0.46);
	point += radial * width;
	VERTEX = (VIEW_MATRIX * vec4(point, 1.0)).xyz;
	NORMAL = mat3(VIEW_MATRIX) * radial;
	stream_axis = normalize(mat3(VIEW_MATRIX) * forward);
	section_uv = vec2(phase, UV.x);
	float fade = pow(clamp(1.0 - settled / 3.1, 0.0, 1.0), 1.35);
	fade *= smoothstep(0.0, 1.0, INSTANCE_CUSTOM.a + along * 0.125);
	COLOR = vec4(0.64, 0.67, 0.72, fade * (0.84 - spread * 0.42 + billow * 0.13));
}

vec4 smoke_section(float path, float across) {
	float frame = mod(floor(path) * 7.0, 16.0);
	vec2 cell = vec2(mod(frame, 4.0), floor(frame * 0.25));
	vec2 texel = vec2(mix(0.23, 0.82, across), mix(0.18, 0.82, fract(path)));
	return texture(smoke_volume, (cell + texel) * 0.25);
}

void fragment() {
	float path = section_uv.x * 0.56 - TIME * 0.065;
	float overlap = 0.5 - 0.5 * cos(TAU * fract(path));
	float swirl = 0.5 - 0.5 * cos(TAU * (section_uv.y + path * 0.12));
	vec4 smoke = mix(smoke_section(path + 0.5, 1.0 - swirl), smoke_section(path, swirl), overlap);
	// Chord through the cylindrical proxy, with a bounded path when looking along the stream.
	float parallel = dot(VIEW, stream_axis);
	float chord = clamp(dot(normalize(NORMAL), VIEW) / max(0.27, 1.0 - parallel * parallel), 0.0, 1.0);
	float depth = texture(depth_tex, SCREEN_UV).x;
	vec4 behind = INV_PROJECTION_MATRIX * vec4(SCREEN_UV * 2.0 - 1.0, depth, 1.0);
	float fade = smoothstep(0.0, 6.0, (-behind.z / behind.w) + VERTEX.z);
	ALBEDO = COLOR.rgb * (0.68 + dot(smoke.rgb, vec3(0.25, 0.31, 0.16)));
	ALPHA = (1.0 - exp(-COLOR.a * smoke.a * chord * 1.85)) * fade * smoothstep(7.0, 24.0, -VERTEX.z);
}
