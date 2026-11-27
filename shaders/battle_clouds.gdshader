shader_type spatial;
render_mode unshaded, fog_disabled, cull_disabled, depth_draw_never, shadows_disabled;

uniform sampler2D scene_depth : hint_depth_texture, repeat_disable, filter_nearest;
uniform sampler3D cloud_field : filter_linear, repeat_enable;
uniform sampler2D clearance_map : filter_linear, repeat_enable;
uniform vec2 field_origin;
uniform vec2 field_period;
uniform vec2 altitude_range;
uniform vec3 sun_direction;
uniform vec4 sun_color : source_color;
uniform vec4 air_color : source_color;
uniform int light_channel = 1;
uniform float step_scale = 1.0;
uniform float density_gain = 1.0;

void vertex() {
	POSITION = vec4(VERTEX.xy, 1.0, 1.0);
}

void fragment() {
	vec2 ndc = SCREEN_UV * 2.0 - 1.0;
	vec3 ray_view = normalize((INV_PROJECTION_MATRIX * vec4(ndc, 0.0, 1.0)).xyz);
	vec3 ray = mat3(INV_VIEW_MATRIX) * ray_view;
	vec3 eye = INV_VIEW_MATRIX[3].xyz;
	float height = altitude_range.y - altitude_range.x;
	float dy = mix(-1.0, 1.0, step(0.0, ray.y)) * max(abs(ray.y), 0.0001);
	vec2 hit = (altitude_range - eye.y) / dy;
	float first = max(0.0, min(hit.x, hit.y));
	float last = min(max(hit.x, hit.y), 14500.0);
	if (last - first < 1.0) { discard; }

	// Clamp the integration at the surface so a cloud can hide a distant
	// ridge or ocean from above while leaving the aircraft in front intact.
	float depth = texture(scene_depth, SCREEN_UV).r;
	if (depth > 0.0) {
		vec4 opaque = INV_PROJECTION_MATRIX * vec4(ndc, depth, 1.0);
		last = min(last, length(opaque.xyz / opaque.w));
	}
	if (last - first < 1.0) { discard; }

	float jitter = mix(0.43, 0.57, fract(52.9829189 * fract(dot(FRAGCOORD.xy, vec2(0.06711056, 0.00583715)))));
	float transmit = 1.0;
	float front = last;
	vec3 glow = vec3(0.0);
	vec3 origin = vec3((eye.xz + field_origin) / field_period, (eye.y - altitude_range.x) / height);
	vec3 direction = vec3(ray.xz / field_period, ray.y / height);
	float phase = pow(max(0.0, dot(ray, sun_direction)), 5.0);
	vec3 indirect = mix(vec3(0.19, 0.245, 0.315), air_color.rgb, 0.21);
	vec3 lit = sun_color.rgb * (0.66 + phase * 0.30);
	float t = first;
	for (int i = 0; i < 48; ++i) {
		if (t >= last || transmit < 0.035) { break; }
		vec3 ray_start = origin + direction * t;
		float stride = mix(114.0, 320.0, smoothstep(2000.0, 11800.0, t)) * step_scale;
		vec3 bounds = textureLod(clearance_map, ray_start.xy, 0.0).rgb;
		float clearance = bounds.r * 4000.0;
		if (clearance > stride) {
			t += clearance;
			continue;
		}
		// At most 300 m, within the expanded horizontal bounds of the atlas.
		float height_pad = 300.0 * abs(direction.z);
		if (stride < 300.0 && (ray_start.z < bounds.g - height_pad || ray_start.z > bounds.b + height_pad)) {
			t += 300.0;
			continue;
		}
		stride = min(stride, last - t);
		float sample_at = t + stride * jitter;
		vec3 point = ray_start + direction * (stride * jitter);
		point.z = (clamp(point.z, 0.0, 1.0) * 47.0 + 0.5) / 48.0;
		vec4 field = textureLod(cloud_field, point, 0.0);
		t += stride;
		if (field.r < 0.005) { continue; }
		float fade = 1.0 - smoothstep(9000.0, 14500.0, sample_at);
		float optical = field.r * density_gain * stride * fade * 0.0035;
		float opacity = 1.0 - exp(-optical);
		if (opacity > 0.003) {
			front = min(front, sample_at);
		}
		vec3 cloud = indirect * mix(0.68, 1.1, point.z) + lit * field[light_channel] * (0.70 + phase * 0.22);
		cloud = mix(cloud, air_color.rgb * 0.87, 1.0 - exp(-sample_at * 0.000028));
		glow += cloud * opacity * transmit;
		transmit *= 1.0 - opacity;
	}
	float coverage = 1.0 - transmit;
	if (coverage < 0.002) { discard; }
	// Also depth-test the visible cloud front against hardware depth. Some
	// Mobile buffers expose a cleared sampled depth at scaled resolutions.
	vec4 clip = PROJECTION_MATRIX * vec4(ray_view * max(front, 0.58), 1.0);
	DEPTH = clip.z / clip.w;
	ALBEDO = glow / coverage;
	ALPHA = coverage;
}
