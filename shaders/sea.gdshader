shader_type spatial;
render_mode cull_disabled, shadows_disabled, diffuse_burley, specular_schlick_ggx;

uniform vec2 world_offset;
uniform vec4 wake;
uniform float wake_strength = 0.0;
uniform vec4 deep : source_color = vec4(0.027, 0.090, 0.139, 1.0);
uniform vec4 scatter_color : source_color = vec4(0.098, 0.264, 0.277, 1.0);
uniform sampler2D shore_noise : repeat_enable, filter_linear_mipmap_anisotropic;
uniform sampler2D coast_depth : repeat_disable, filter_linear;
uniform vec4 coast_area = vec4(0.0);
uniform sampler2DArray spectral_displacement : repeat_enable, filter_linear;
uniform sampler2DArray spectral_normals : repeat_enable, filter_linear;
uniform bool spectral_enabled = false;
varying vec3 water_point;
varying vec2 long_slope;

void swell(vec2 axis, float length_m, float amplitude, float phase, vec2 point, inout vec3 displacement, inout vec2 slope) {
	float k = TAU / length_m;
	float angle = dot(axis, point) * k + phase;
	displacement.xz += axis * cos(angle) * amplitude * 0.5;
	displacement.y += sin(angle) * amplitude;
	slope += axis * cos(angle) * amplitude * k;
}

void vertex() {
	vec2 local = VERTEX.xz;
	float radial = max(abs(local.x), abs(local.y));
	// Let the outer rings disappear into the air perspective before reaching the horizon.
	float ring = clamp(radial / 256.0, 0.0, 1.0);
	float factor = 1.0 + 46.0 * pow(ring, 4.8) + 144.0 * pow(ring, 15.0);
	VERTEX.xz *= factor;
	vec2 surface = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xz + world_offset;
	vec3 displacement = vec3(0.0);
	vec2 slope = vec2(0.0);
	float detail = 1.0 - smoothstep(125.0, 720.0, radial);
	swell(vec2(0.863, -0.505), 154.0, 0.94, TIME * 0.61, surface, displacement, slope);
	swell(vec2(0.33, 0.944), 61.0, 0.42, -TIME * 1.04, surface, displacement, slope);
	if (spectral_enabled) {
		displacement += texture(spectral_displacement, vec3(surface / 160.0, 0)).xyz * 0.84 * detail;
		displacement += texture(spectral_displacement, vec3(surface / 39.0, 1)).xyz * 0.46 * detail;
	}
	VERTEX += displacement * detail;
	water_point = vec3(surface.x, displacement.y, surface.y);
	long_slope = slope;
}

void fragment() {
	float distance_m = length(VERTEX);
	vec2 uv = water_point.xz;
	float near_detail = 1.0 - smoothstep(390.0, 1700.0, distance_m);
	vec2 flow = vec2(0.014, -0.009) * TIME;
	vec2 fine = vec2(0.0);
	if (near_detail > 0.0) {
		fine = (texture(shore_noise, uv * 0.087 + flow).rg - texture(shore_noise, uv * 0.047 - flow * 0.7).gr) * 0.135;
	}
	vec2 gradient = long_slope * 0.73 + fine * near_detail;
	float foam = 0.0;
	if (spectral_enabled && near_detail > 0.0) {
		vec4 outer = texture(spectral_normals, vec3(uv / 160.0, 0));
		vec4 inner = texture(spectral_normals, vec3(uv / 39.0, 1));
		gradient += (outer.xy * 0.8 + inner.xy * 0.65) * near_detail;
		foam = smoothstep(0.12, 1.2, outer.w * 0.60 + inner.w * 0.45) * near_detail;
	} else {
		foam = smoothstep(0.76, 1.25, water_point.y) * near_detail * 0.22;
	}
	if (wake_strength > 0.0 && near_detail > 0.0) {
		vec2 delta = uv - wake.xy;
		float along = -dot(delta, wake.zw);
		float crosswind = abs(delta.x * wake.w - delta.y * wake.z);
		float wake_line = exp(-max(along, 0.0)*0.022) * (1.0 - smoothstep(0.9 + along * 0.016, 3.0 + along * 0.055, crosswind));
		foam += wake_strength * wake_line * smoothstep(0.0, 3.0, along) * near_detail * 0.63;
	}
	vec3 normal_world = normalize(vec3(-gradient.x, 1.0, -gradient.y));
	NORMAL = (VIEW_MATRIX * vec4(normal_world, 0.0)).xyz;
	float angle = clamp(dot(NORMAL, VIEW), 0.0, 1.0);
	vec3 water = deep.rgb;
	if (coast_area.w > 0.5 && distance_m < 2200.0) {
		vec2 shore_uv = (uv - coast_area.xy) * coast_area.z + vec2(0.5 / 64.0);
		float edge = min(min(shore_uv.x, shore_uv.y), min(1.0 - shore_uv.x, 1.0 - shore_uv.y));
		if (edge > 0.0) {
			float sea_floor = texture(coast_depth, shore_uv).r * 63.75 - 32.0;
			float shore_weight = smoothstep(0.0, 0.11, edge);
			float shallows = smoothstep(-20.0, -1.0, sea_floor) * (1.0 - smoothstep(1.0, 8.0, sea_floor)) * shore_weight;
			float immersion = max(0.3, -sea_floor) / max(0.72, angle);
			water += scatter_color.rgb * exp(-vec3(0.32, 0.137, 0.063) * immersion) * (0.62 * shore_weight);
			float breaker = 0.5 + 0.5 * sin(sea_floor * 0.72 + TIME * 1.55 + fine.x * 12.0);
			foam += shallows * smoothstep(0.66, 0.94, breaker) * 0.62;
		}
	}
	float fresnel = pow(1.0 - angle, 5.0);
	ALBEDO = mix(water, vec3(0.49, 0.61, 0.62), clamp(foam, 0.0, 0.82));
	ROUGHNESS = mix(0.30 + fresnel * 0.14, 0.54, foam);
	METALLIC = 0.0;
	SPECULAR = (0.23 + 0.24 * fresnel) * (1.0 - foam * 0.58);
}
