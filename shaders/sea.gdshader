shader_type spatial;
render_mode cull_disabled, shadows_disabled, diffuse_burley, specular_schlick_ggx;

uniform vec2 world_offset;
uniform vec4 wake;
uniform float wake_strength = 0.0;
uniform vec4 deep : source_color = vec4(0.027, 0.090, 0.139, 1.0);
uniform vec4 scatter_color : source_color = vec4(0.067, 0.204, 0.224, 1.0);
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
	// Keep metre spacing around the flight path and extend the outer rings to the horizon.
	float factor = 1.0 + 46.0 * pow(clamp(radial / 256.0, 0.0, 1.0), 4.8);
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
	float grazing = 1.0 - clamp(dot(normalize(NORMAL), VIEW), 0.0, 1.0);
	vec2 uv = water_point.xz;
	float near_detail = 1.0 - smoothstep(390.0, 1700.0, distance_m);
	vec2 flow = vec2(0.014, -0.009) * TIME;
	vec2 fine = (texture(shore_noise, uv * 0.085 + flow).rg - texture(shore_noise, uv * 0.051 - flow * 0.65).gr) * 0.22;
	vec2 gradient = long_slope * 0.73 + fine * near_detail;
	float foam = 0.0;
	if (spectral_enabled) {
		vec4 outer = texture(spectral_normals, vec3(uv / 160.0, 0));
		vec4 inner = texture(spectral_normals, vec3(uv / 39.0, 1));
		gradient += (outer.xy * 0.8 + inner.xy * 0.65) * near_detail;
		foam = smoothstep(0.12, 1.2, outer.w * 0.60 + inner.w * 0.45) * near_detail;
	} else {
		foam = smoothstep(0.76, 1.25, water_point.y) * near_detail * 0.22;
	}
	vec2 delta = uv - wake.xy;
	float along = -dot(delta, wake.zw);
	float crosswind = abs(delta.x * wake.w - delta.y * wake.z);
	float wake_line = exp(-max(along, 0.0)*0.022) * (1.0 - smoothstep(0.9 + along * 0.016, 3.0 + along * 0.055, crosswind));
	foam += wake_strength * wake_line * smoothstep(0.0, 3.0, along) * near_detail * 0.63;
	float shallows = 0.0;
	if (coast_area.w > 0.5 && distance_m < 2200.0) {
		vec2 shore_uv = (uv - coast_area.xy) * coast_area.z + vec2(0.5 / 64.0);
		float edge = min(min(shore_uv.x, shore_uv.y), min(1.0 - shore_uv.x, 1.0 - shore_uv.y));
		if (edge > 0.0) {
			float sea_floor = texture(coast_depth, shore_uv).r * 63.75 - 32.0;
			shallows = smoothstep(-23.0, -1.0, sea_floor) * (1.0 - smoothstep(1.0, 8.0, sea_floor)) * smoothstep(0.0, 0.11, edge);
			float breaker = 0.5 + 0.5 * sin(sea_floor * 0.72 + TIME * 1.55 + fine.x * 12.0);
			foam += shallows * smoothstep(0.66, 0.94, breaker) * 0.62;
		}
	}
	float zenith_blend = pow(grazing, 3.5);
	vec3 normal_world = normalize(vec3(-gradient.x, 1.0, -gradient.y));
	NORMAL = normalize((VIEW_MATRIX * vec4(normal_world, 0.0)).xyz);
	ALBEDO = mix(mix(deep.rgb, scatter_color.rgb, smoothstep(-0.15, 1.45, water_point.y) * 0.36 + shallows * 0.37), vec3(0.44, 0.62, 0.64), clamp(foam, 0.0, 0.80));
	ROUGHNESS = mix(0.28 + zenith_blend * 0.065, 0.55, foam);
	METALLIC = 0.025;
	SPECULAR = 0.29 + 0.19 * zenith_blend;
}
