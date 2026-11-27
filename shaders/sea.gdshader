shader_type spatial;
render_mode cull_disabled, shadows_disabled, diffuse_burley, specular_schlick_ggx;
#include "air_transport.gdshaderinc"

uniform vec2 world_offset;
uniform vec4 wake;
uniform float wake_strength = 0.0;
uniform vec3 impact_centre;
uniform float impact_age = 3.8;
uniform vec4 deep : source_color = vec4(0.027, 0.090, 0.139, 1.0);
uniform vec4 scatter_color : source_color = vec4(0.098, 0.264, 0.277, 1.0);
uniform sampler2D shore_noise : repeat_enable, filter_linear_mipmap_anisotropic;
uniform sampler2D water_response : repeat_disable, filter_linear;
uniform sampler2D coast_depth : repeat_disable, filter_linear;
uniform vec4 coast_area = vec4(0.0);
uniform sampler2DArray spectral_displacement : repeat_enable, filter_linear;
uniform sampler2DArray spectral_normals : repeat_enable, filter_linear;
uniform bool spectral_enabled = false;
uniform float spectral_weight = 0.0;
uniform float distant_reflection = 1.0;
varying vec3 water_point;

const vec2 SWELL_AXIS = vec2(0.863, -0.505);
const float SWELL_K = TAU / 93.0;
const float OUTER_GAIN = 0.62;
const float INNER_GAIN = 0.40;

// Height, transverse slope and aeration are derived from the same pressure field.
vec3 aircraft_wake(vec2 point) {
	vec2 delta = point - wake.xy;
	float travel = -dot(delta, wake.zw);
	float across = dot(delta, vec2(-wake.w, wake.z));
	if (travel <= 0.0 || travel >= 185.0 || abs(across) > 17.0) { return vec3(0.0); }
	float spread = 1.3 + travel * 0.075;
	float edge = abs(across) / spread;
	float taper = smoothstep(0.0, 6.0, travel) * (1.0 - smoothstep(35.0, 185.0, travel));
	float mask = exp(-edge * edge * 3.9) * taper * wake_strength;
	float crest = 1.35 * abs(across) - 0.21 * travel;
	float amplitude = mask * 0.31;
	return vec3(sin(crest) * amplitude, sign(across) * 1.35 * cos(crest) * amplitude,
		smoothstep(0.22, 0.93, sin(crest)) * mask);
}

vec4 water_impact(vec2 point) {
	vec2 delta = point - impact_centre.xy;
	float radius_m = length(delta);
	float envelope = radius_m - impact_age * 16.0;
	float strength = impact_centre.z * (1.0 - smoothstep(0.05, 3.8, impact_age)) * exp(-envelope * envelope * 0.057);
	float phase = envelope * 1.05;
	return vec4(strength * sin(phase), delta / max(radius_m, 0.8) * strength * cos(phase),
		strength * smoothstep(0.71, 1.0, sin(phase)));
}

float coast_crest(float terrain_height, vec2 uv) {
	float crest = terrain_height * 0.66 + TIME * 1.6 + sin(dot(uv, vec2(0.071, -0.063))) * 0.48;
	return 0.5 + 0.5 * sin(crest);
}

void vertex() {
	vec2 local = VERTEX.xz;
	float radial = max(abs(local.x), abs(local.y));
	// Let the outer rings disappear into the air perspective before reaching the horizon.
	float ring = clamp(radial / 256.0, 0.0, 1.0);
	float factor = 1.0 + 46.0 * pow(ring, 4.8) + 144.0 * pow(ring, 15.0);
	VERTEX.xz *= factor;
	vec2 surface = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xz + world_offset;
	float radius_m = length(VERTEX.xz);
	float swell_geometry = 1.0 - smoothstep(120.0, 680.0, radius_m);
	float ripple_geometry = 1.0 - smoothstep(42.0, 155.0, radius_m);
	vec3 displacement = vec3(0.0);
	if (spectral_enabled && spectral_weight > 0.0 && swell_geometry > 0.0) {
		// The retained FFT packs the result of its last pass in transposed order.
		displacement = textureLod(spectral_displacement, vec3(surface.yx / 160.0, 0), 0.0).xyz * (OUTER_GAIN * swell_geometry);
		if (ripple_geometry > 0.0) {
			displacement += textureLod(spectral_displacement, vec3(surface.yx / 39.0, 1), 0.0).xyz * (INNER_GAIN * ripple_geometry);
		}
	}
	if (spectral_weight < 1.0 && swell_geometry > 0.0) {
		float swell = sin(dot(SWELL_AXIS, surface) * SWELL_K + TIME * 0.79) * (0.65 * swell_geometry);
		displacement = mix(vec3(0.0, swell, 0.0), displacement, spectral_weight);
	}
	if (wake_strength > 0.0 && ripple_geometry > 0.0) {
		displacement.y += aircraft_wake(surface).x * ripple_geometry;
	}
	if (impact_age < 3.8 && ripple_geometry > 0.0) {
		displacement.y += water_impact(surface).x * ripple_geometry;
	}
	if (coast_area.w > 0.5 && ripple_geometry > 0.0) {
		vec2 coord = (surface - coast_area.xy) * coast_area.z + vec2(0.5 / 64.0);
		float edge = min(min(coord.x, coord.y), min(1.0 - coord.x, 1.0 - coord.y));
		if (edge > 0.0) {
			float elevation = textureLod(coast_depth, coord, 0.0).r * 63.75 - 32.0;
			float shoal = smoothstep(-11.0, -3.0, elevation) * (1.0 - smoothstep(-1.0, 1.0, elevation));
			float crest = coast_crest(elevation, surface);
			displacement.y += (crest * crest * crest - 0.12) * 0.69 * shoal * ripple_geometry * smoothstep(0.0, 0.11, edge);
		}
	}
	VERTEX += displacement;
	water_point = vec3(surface.x, displacement.y, surface.y);
}

void fragment() {
	float distance_m = length(VERTEX);
	vec2 uv = water_point.xz;
	// Migrate the subpixel slope energy to the reflection lobe using the pixel's world footprint.
	float footprint = max(length(dFdx(uv)), length(dFdy(uv)));
	float outer_resolved = 1.0 - smoothstep(1.2, 11.0, footprint);
	float inner_resolved = 1.0 - smoothstep(0.34, 2.5, footprint);
	float near_detail = 1.0 - smoothstep(550.0, 1850.0, distance_m);
	vec2 flow = vec2(0.014, -0.009) * TIME;
	vec2 fine = vec2(0.0);
	if (inner_resolved > 0.0 && near_detail > 0.0) {
		fine = (texture(shore_noise, uv * 0.17 + flow).rg - vec2(0.5)) * (0.094 * inner_resolved * near_detail);
	}
	vec2 gradient = fine;
	float foam = 0.0;
	if (spectral_enabled && spectral_weight > 0.0) {
		if (outer_resolved > 0.0) {
			vec4 outer = textureLod(spectral_normals, vec3(uv.yx / 160.0, 0), 0.0);
			gradient += outer.xy * (OUTER_GAIN * outer_resolved * spectral_weight);
			foam = outer.w * outer_resolved * 0.68;
		}
		if (inner_resolved > 0.0) {
			vec4 inner = textureLod(spectral_normals, vec3(uv.yx / 39.0, 1), 0.0);
			gradient += inner.xy * (INNER_GAIN * inner_resolved * spectral_weight);
			foam += inner.w * inner_resolved * 0.47;
		}
		foam = smoothstep(0.26, 0.84, foam) * spectral_weight;
	}
	if (spectral_weight < 1.0 && outer_resolved > 0.0) {
		gradient += SWELL_AXIS * cos(dot(SWELL_AXIS, uv) * SWELL_K + TIME * 0.79) *
			(0.65 * SWELL_K * outer_resolved * (1.0 - spectral_weight));
	}
	if (wake_strength > 0.0 && near_detail > 0.0) {
		vec3 local_wave = aircraft_wake(uv);
		gradient += vec2(-wake.w, wake.z) * local_wave.y * near_detail * inner_resolved;
		foam += (local_wave.z * 0.92 + abs(local_wave.x) * 0.41) * near_detail;
	}
	if (impact_age < 3.8 && near_detail > 0.0) {
		vec4 ripple = water_impact(uv);
		gradient += ripple.yz * inner_resolved * near_detail;
		foam += ripple.w * near_detail;
	}
	vec3 normal_world = normalize(vec3(-gradient.x, 1.0, -gradient.y));
	NORMAL = (VIEW_MATRIX * vec4(normal_world, 0.0)).xyz;
	float angle = clamp(dot(NORMAL, VIEW), 0.0, 1.0);
	float unresolved = 0.042 * (1.0 - outer_resolved) + 0.035 * (1.0 - inner_resolved);
	float sigma = sqrt(0.0025 + unresolved);
	vec2 response = (vec2(angle, clamp(sigma / 0.32, 0.0, 1.0)) * vec2(95.0, 47.0) + 0.5) / vec2(96.0, 48.0);
	float reflection = textureLod(water_response, response, 0.0).r;
	vec3 water = (deep.rgb + air_color.rgb * 0.045) * (1.0 - reflection);
	if (coast_area.w > 0.5 && distance_m < 6100.0) {
		vec2 shore_uv = (uv - coast_area.xy) * coast_area.z + vec2(0.5 / 64.0);
		float edge = min(min(shore_uv.x, shore_uv.y), min(1.0 - shore_uv.x, 1.0 - shore_uv.y));
		if (edge > 0.0) {
			float sea_floor = texture(coast_depth, shore_uv).r * 63.75 - 32.0;
			float shore_weight = smoothstep(0.0, 0.12, edge) * (1.0 - smoothstep(4200.0, 6100.0, distance_m));
			float shallows = smoothstep(-20.0, -1.0, sea_floor) * (1.0 - smoothstep(1.0, 8.0, sea_floor)) * shore_weight;
			float immersion = max(0.3, -sea_floor) / max(0.72, angle);
			vec3 bottom = scatter_color.rgb * exp(-vec3(0.26, 0.091, 0.079) * immersion);
			water += bottom * ((0.75 - 0.42 * reflection) * shore_weight);
			float breaker = coast_crest(sea_floor, uv) + fine.x * 0.43;
			foam += shallows * smoothstep(0.66, 0.94, breaker) * 0.62;
		}
	}
	ALBEDO = mix(water, vec3(0.49, 0.61, 0.62), clamp(foam, 0.0, 0.82));
	ROUGHNESS = mix(sqrt(0.068 + unresolved), 0.59, clamp(foam, 0.0, 1.0));
	METALLIC = 0.0;
	float broad_lobe = 1.0 - outer_resolved;
	// Resolved highlights still come from the sky probe and sun. The table recovers the broad unresolved lobe.
	EMISSION = air_color.rgb * reflection * broad_lobe * distant_reflection * (1.0 - 0.75 * clamp(foam, 0.0, 1.0));
	SPECULAR = 0.353 * (1.0 - foam * 0.55) * (1.0 - broad_lobe * 0.42);
	FOG = aerial_transport(INV_VIEW_MATRIX[3].xyz, vec3(uv.x - world_offset.x, water_point.y, uv.y - world_offset.y));
}
