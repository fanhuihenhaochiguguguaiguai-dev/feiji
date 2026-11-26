shader_type spatial;
render_mode unshaded, blend_mix, cull_front, depth_test_disabled, depth_draw_never, shadows_disabled, skip_vertex_transform;

uniform sampler2D wake_points : filter_nearest, repeat_disable;
uniform sampler3D density_field : filter_linear, repeat_enable;
uniform sampler2D scene_depth : hint_depth_texture, filter_nearest, repeat_disable;
uniform vec3 world_shift;
uniform float wake_clock;
uniform vec3 wake_span;
uniform vec4 daylight : source_color = vec4(1.0);
uniform vec3 sun_direction = vec3(0.7, 0.6, 0.3);

varying vec3 sample_position;
varying flat vec3 entry;
varying flat vec3 tangent;
varying flat vec4 dimensions;
varying flat vec4 state;

float wake_width(float age, int style, float sample_time, float settled) {
	if (style == 2) { return mix(0.24, 1.65, 1.0 - exp(-age * 2.1)); }
	if (style == 1) { return mix(0.95, 7.0, 1.0 - exp(-age * 1.45)); }
	// Carry over the 3b76018 expansion in metres and retain the volume's 3D density.
	float billow = 0.5 + 0.5 * sin(sample_time * (0.22 * 1.63 / 0.030) + age * 2.7);
	float spread = smoothstep(0.02, 1.65, age);
	return 0.55 + (3.10 + billow * 2.1) * spread + settled * (0.73 + billow * 0.46);
}

vec3 wake_origin(vec4 point, float age, int style) {
	float phase = dot(point.xz, vec2(0.025, 0.039)) + point.w * 5.4;
	float eddy = (style == 2 ? 2.0 : 4.0) * age;
	return point.xyz - world_shift + vec3(sin(phase), cos(phase * 0.71) * 0.44, cos(phase)) * eddy * 0.52
		+ age * (style == 2 ? vec3(0.8, -1.45, 1.7) : vec3(1.25, 2.8, -0.55));
}

void vertex() {
	int lane = int(texelFetch(wake_points, ivec2(66, INSTANCE_ID / 64), 0).x);
	int segment = INSTANCE_ID % 64;
	vec4 header = texelFetch(wake_points, ivec2(64, lane), 0);
	int count = int(header.y);
	int style = int(header.z);
	float span = wake_span[style];
	state = vec4(float(style), abs(header.w), span, 0.0);
	entry = vec3(0.0);
	tangent = vec3(1.0, 0.0, 0.0);
	dimensions = vec4(0.0);
	sample_position = vec3(0.0);
	if (segment >= count) {
		VERTEX = vec3(0.0, 0.0, 1.0);
	} else {
		int start = (int(header.x) + segment) % 64;
		vec4 p = texelFetch(wake_points, ivec2(start, lane), 0);
		int end_slot = segment + 1 == count ? 65 : (start + 1) % 64;
		vec4 q = texelFetch(wake_points, ivec2(end_slot, lane), 0);
		float age0 = max(0.0, wake_clock - p.w);
		float age1 = max(0.0, wake_clock - q.w);
		vec3 a = wake_origin(p, age0, style);
		vec3 b = wake_origin(q, age1, style);
		vec3 chord = b - a;
		float length_m = length(chord);
		if (age1 >= span || length_m < 0.035 || length_m > 140.0) {
			VERTEX = vec3(0.0, 0.0, 1.0);
		} else {
			entry = a;
			tangent = chord / length_m;
			float settled = header.w < 0.0 && style == 0
				? max(0.0, wake_clock - texelFetch(wake_points, ivec2(65, lane), 0).w) : 0.0;
			float width0 = wake_width(age0, style, p.w, settled);
			float width1 = wake_width(age1, style, q.w, settled);
			float padding = min(max(width0, width1) * 0.63, length_m * 0.41);
			dimensions = vec4(length_m, width0, width1, padding);
			state.w = age0;
			float box_width = max(width0, width1) * 1.13;
			vec3 normal = normalize(cross(tangent, abs(tangent.y) > 0.93 ? vec3(0.0, 0.0, 1.0) : vec3(0.0, 1.0, 0.0)));
			vec3 across = cross(tangent, normal);
			sample_position = a + tangent * (length_m * 0.5 + VERTEX.x * (length_m + padding * 2.0))
				+ (VERTEX.y * normal + VERTEX.z * across) * box_width * 2.0;
			VERTEX = (VIEW_MATRIX * vec4(sample_position, 1.0)).xyz;
		}
	}
}

void fragment() {
	vec3 ray_delta = sample_position - CAMERA_POSITION_WORLD;
	float exit_distance = length(ray_delta);
	vec3 ray = ray_delta / max(exit_distance, 0.001);
	vec3 offset = CAMERA_POSITION_WORLD - entry;
	float t0 = dot(offset, tangent);
	float direction = dot(ray, tangent);
	vec3 origin_radial = offset - t0 * tangent;
	vec3 radial_ray = ray - direction * tangent;
	float a = max(0.00001, dot(radial_ray, radial_ray));
	float b = dot(origin_radial, radial_ray);
	float max_width = max(dimensions.y, dimensions.z) * 1.13;
	float c = dot(origin_radial, origin_radial) - max_width * max_width;
	float root_squared = b * b - a * c;
	if (root_squared <= 0.0) { discard; }
	float root = sqrt(root_squared);
	float first = max(0.0, (-b - root) / a);
	float last = min(exit_distance, (-b + root) / a);
	float inv_dir = (direction < 0.0 ? -1.0 : 1.0) / max(abs(direction), 0.00001);
	float near_end = (-dimensions.w - t0) * inv_dir;
	float far_end = (dimensions.x + dimensions.w - t0) * inv_dir;
	first = max(first, min(near_end, far_end));
	last = min(last, max(near_end, far_end));
	vec4 opaque = INV_PROJECTION_MATRIX * vec4(SCREEN_UV * 2.0 - 1.0, texture(scene_depth, SCREEN_UV).r, 1.0);
	last = min(last, exit_distance * (opaque.z / opaque.w) / min(-0.001, VERTEX.z));
	if (last <= first) { discard; }

	float air = 0.0;
	float lighting = 0.0;
	int steps = max_width * 76.0 > first ? 4 : 2;
	float stride = (last - first) / float(steps);
	float age = state.w;
	float life = 1.0 - smoothstep(state.z * 0.19, state.z, age);
	float frequency = state.x > 1.5 ? 0.39 : 0.16;
	for (int i = 0; i < 4; i++) {
		if (i >= steps) { break; }
		float distance_m = first + (float(i) + 0.5) * stride;
		float axis = t0 + distance_m * direction;
		vec3 radial = origin_radial + radial_ray * distance_m;
		float axial = clamp(axis / dimensions.x, 0.0, 1.0);
		float width = mix(dimensions.y, dimensions.z, axial);
		vec3 pos = CAMERA_POSITION_WORLD + ray * distance_m + world_shift;
		float turbulent = texture(density_field, pos * frequency + vec3(0.0, -age * 0.19, 0.0)).r;
		float side = length(radial) / width;
		float edge = smoothstep(-dimensions.w - 0.001, dimensions.w + 0.001, axis)
			* (1.0 - smoothstep(dimensions.x - dimensions.w - 0.001, dimensions.x + dimensions.w + 0.001, axis));
		float shell = 1.0 - smoothstep(0.12, 0.77 + turbulent * 0.32, side);
		float density = edge * shell * (0.42 + 0.96 * turbulent);
		density *= life * state.y * stride / max(0.27, width);
		air += density;
		lighting += density * clamp(0.57 + dot(radial, sun_direction) / width * 0.64, 0.10, 1.0);
	}
	vec3 cool = state.x > 0.5 && state.x < 1.5 ? vec3(0.092, 0.095, 0.106) : vec3(0.48, 0.54, 0.62);
	vec3 warm = state.x > 0.5 && state.x < 1.5 ? vec3(0.33, 0.31, 0.29) : vec3(0.93, 0.92, 0.85);
	ALBEDO = mix(cool, warm * daylight.rgb, lighting / max(0.001, air));
	ALPHA = (1.0 - exp(-air * 1.63)) * smoothstep(4.0, 11.0, first);
}
