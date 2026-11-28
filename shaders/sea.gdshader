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
uniform sampler2D ocean_fields : repeat_enable, filter_linear_mipmap;
uniform vec4 slope_variance = vec4(0.0505, 0.0354, 0.0571, 0.0527);
uniform sampler2D water_response : repeat_disable, filter_linear;
uniform sampler2D coast_depth : repeat_disable, filter_linear;
uniform vec4 coast_area = vec4(0.0);
uniform sampler2DArray spectral_displacement : repeat_enable, filter_linear;
uniform sampler2DArray spectral_normals : repeat_enable, filter_linear;
uniform bool spectral_enabled = false;
uniform float spectral_weight = 0.0;
uniform float distant_reflection = 1.0;
varying vec3 water_point;

const float OUTER_GAIN = 0.68;
const float INNER_GAIN = 0.34;
const float CAPILLARY_GAIN = 0.50;

vec2 sea_state(vec2 point) {
	// The blue and alpha channels carry independent kilometre-scale wave groups.
	vec2 fields = textureLod(ocean_fields, point / 5100.0, 0.0).ba;
	return mix(vec2(0.68, 0.52), vec2(1.46, 1.53), smoothstep(vec2(0.15), vec2(0.85), fields));
}

vec3 wave_profile(vec2 point, vec2 axis, float wave_number, float height) {
	float phase = dot(axis, point) * wave_number - TIME * sqrt(9.81 * wave_number);
	return vec3(height * sin(phase), axis * (height * wave_number * cos(phase)));
}

vec3 analytical_swell(vec2 point, vec2 state) {
	return wave_profile(point, vec2(0.863, -0.505), 0.06756, state.x * 0.53)
		+ wave_profile(point, vec2(0.477, -0.879), 0.11855, state.x * 0.27)
		+ wave_profile(point, vec2(0.975, 0.222), 0.26091, state.y * 0.13);
}

// Height and slope share the crest; travelling packets break up the foam.
vec3 aircraft_wake(vec2 point) {
	vec2 delta = point - wake.xy;
	float travel = -dot(delta, wake.zw);
	float across = dot(delta, vec2(-wake.w, wake.z));
	if (travel <= 0.0 || travel >= 185.0 || abs(across) > 18.0) { return vec3(0.0); }
	float drift = 0.9 * sin(0.057 * travel - TIME * 0.63) * smoothstep(6.0, 88.0, travel);
	across -= drift;
	float spread = 1.6 + travel * 0.072;
	float edge = across / spread;
	float taper = smoothstep(0.0, 7.0, travel) * (1.0 - smoothstep(27.0, 185.0, travel));
	float mask = exp(-edge * edge * 3.2) * taper * wake_strength;
	float packet = sin(0.29 * travel - TIME * 3.2 + across * 0.47)
		+ 0.55 * sin(travel * 0.44 + across * 1.3);
	float phase = 1.26 * abs(across) - 0.22 * travel + 0.34 * packet;
	float crest = sin(phase);
	float amplitude = mask * (0.21 + 0.047 * packet);
	float transverse = sign(across) * 1.26 * cos(phase) * amplitude
		- crest * amplitude * 6.4 * edge / spread;
	float aeration = smoothstep(0.45, 0.93, crest) * smoothstep(-0.40, 1.25, packet) * mask;
	return vec3(crest * amplitude, transverse, aeration);
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

vec2 shore_sample(vec2 point) {
	vec2 coord = (point - coast_area.xy) * coast_area.z;
	vec2 margin = min(coord, vec2(1.0) - coord);
	float influence = smoothstep(0.0, 0.12, min(margin.x, margin.y));
	float elevation = textureLod(coast_depth, coord + vec2(coast_area.w * 0.5), 0.0).r * 63.75 - 32.0;
	return vec2(elevation, influence);
}

// Low-order shoaling: a shallower bottom slows and steepens the incoming crest.
// Return height, attenuation of offshore waves and foam from the same crest.
vec3 shore_wave(vec2 point, vec2 bed, vec2 state) {
	float depth = max(0.0, -bed.x);
	float shoaling = smoothstep(0.22, 1.6, depth) * (1.0 - smoothstep(3.0, 15.0, depth)) * bed.y;
	float bottom_phase = 1.26 * sqrt(depth + 0.3);
	float phase = dot(point, vec2(0.062, -0.049)) - bottom_phase - TIME * 1.26;
	float interruption = 0.17 * sin(dot(point, vec2(0.28, 0.19))) + 0.12 * sin(dot(point, vec2(0.09, -0.33)));
	float crest = 0.5 + 0.5 * cos(phase + interruption);
	float height = (pow(crest, 3.0) - 0.16) * shoaling * (0.55 + state.x * 0.24);
	float attenuate = 1.0 - 0.73 * bed.y * (1.0 - smoothstep(0.7, 8.5, depth));
	float breaks = 1.0 - smoothstep(1.1, 6.3, depth);
	float foam = smoothstep(0.78, 0.98, crest + interruption * 0.39)
		* shoaling * breaks * state.x * 0.84;
	return vec3(height, attenuate, foam);
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
	if (swell_geometry > 0.0) {
		vec2 state = sea_state(surface);
		if (spectral_enabled && spectral_weight > 0.0) {
			// The final Stockham pass leaves the texture transposed.
			displacement = textureLod(spectral_displacement, vec3(surface.yx / 160.0, 0), 0.0).xyz
				* (OUTER_GAIN * state.x * swell_geometry);
			if (ripple_geometry > 0.0) {
				displacement += textureLod(spectral_displacement, vec3(surface.yx / 39.0, 1), 0.0).xyz
					* (INNER_GAIN * state.y * ripple_geometry);
			}
		}
		if (spectral_weight < 1.0) {
			float swell = analytical_swell(surface, state).x * swell_geometry;
			displacement = mix(vec3(0.0, swell, 0.0), displacement, spectral_weight);
		}
		if (coast_area.w > 0.0) {
			vec2 bed = shore_sample(surface);
			vec3 break_water = shore_wave(surface, bed, state);
			displacement *= break_water.y;
			displacement.y += break_water.x * ripple_geometry;
		}
	}
	if (wake_strength > 0.0 && ripple_geometry > 0.0) {
		displacement.y += aircraft_wake(surface).x * ripple_geometry;
	}
	if (impact_age < 3.8 && ripple_geometry > 0.0) {
		displacement.y += water_impact(surface).x * ripple_geometry;
	}
	VERTEX += displacement;
	water_point = vec3(surface.x, displacement.y, surface.y);
}

void fragment() {
	float distance_m = length(VERTEX);
	vec2 uv = water_point.xz;
	vec2 dx = dFdx(uv);
	vec2 dz = dFdy(uv);
	float footprint = max(length(dx), length(dz));
	float outer_resolved = 1.0 - smoothstep(1.40, 11.5, footprint);
	float inner_resolved = 1.0 - smoothstep(0.34, 3.0, footprint);
	float fine_resolved = 1.0 - smoothstep(0.12, 0.94, footprint);
	float interaction = 1.0 - smoothstep(425.0, 1350.0, distance_m);
	vec2 state = sea_state(uv);
	vec2 bed = vec2(-32.0, 0.0);
	vec3 breaker = vec3(0.0, 1.0, 0.0);
	if (coast_area.w > 0.0 && distance_m < 6100.0) {
		bed = shore_sample(uv);
		bed.y *= 1.0 - smoothstep(4200.0, 6100.0, distance_m);
		breaker = shore_wave(uv, bed, state);
	}
	vec2 fine = vec2(0.0);
	if (fine_resolved > 0.0) {
		vec2 flow = vec2(0.019, -0.012) * TIME;
		fine = (textureGrad(ocean_fields, uv / 7.3 + flow, dx / 7.3, dz / 7.3).rg - vec2(0.5))
			* (CAPILLARY_GAIN * fine_resolved * state.y);
	}
	vec2 gradient = vec2(0.0);
	float foam = 0.0;
	vec2 scaled = state * vec2(OUTER_GAIN, INNER_GAIN) * breaker.y;
	vec2 visible_spectral = vec2(outer_resolved, inner_resolved) * spectral_weight;
	if (spectral_enabled && spectral_weight > 0.0) {
		if (outer_resolved > 0.0) {
			vec4 outer = textureLod(spectral_normals, vec3(uv.yx / 160.0, 0), 0.0);
			gradient += outer.xy * scaled.x * visible_spectral.x;
			foam = outer.w * outer_resolved * state.x * 0.68;
		}
		if (inner_resolved > 0.0) {
			vec4 inner = textureLod(spectral_normals, vec3(uv.yx / 39.0, 1), 0.0);
			gradient += inner.xy * scaled.y * visible_spectral.y;
			foam += inner.w * inner_resolved * state.y * 0.49;
		}
		foam = smoothstep(0.34, 0.92, foam) * spectral_weight * breaker.y;
	}
	if (spectral_weight < 1.0 && outer_resolved > 0.0) {
		gradient += analytical_swell(uv, state).yz * (outer_resolved * (1.0 - spectral_weight) * breaker.y);
	}
	gradient += fine * breaker.y;
	vec2 dh = vec2(dFdx(breaker.x), dFdy(breaker.x));
	float jacobian = dx.x * dz.y - dx.y * dz.x;
	if (abs(jacobian) > 0.00001 && bed.y > 0.0) {
		vec2 shore_slope = vec2(dh.x * dz.y - dh.y * dx.y, dx.x * dh.y - dz.x * dh.x) / jacobian;
		gradient += clamp(shore_slope, vec2(-0.62), vec2(0.62)) * interaction * inner_resolved;
		foam += breaker.z;
	}
	if (wake_strength > 0.0 && interaction > 0.0) {
		vec3 local_wave = aircraft_wake(uv);
		gradient += vec2(-wake.w, wake.z) * local_wave.y * interaction * inner_resolved;
		foam += local_wave.z * (0.44 + fine.y * 1.35) * interaction;
	}
	if (impact_age < 3.8 && interaction > 0.0) {
		vec4 ripple = water_impact(uv);
		gradient += ripple.yz * inner_resolved * interaction;
		foam += ripple.w * interaction;
	}
	vec3 normal_world = normalize(vec3(-gradient.x, 1.0, -gradient.y));
	NORMAL = (VIEW_MATRIX * vec4(normal_world, 0.0)).xyz;
	float angle = clamp(dot(NORMAL, VIEW), 0.0, 1.0);

	// Variance scales with amplitude squared. Only the portion that was not
	// resolved as a normal feeds the broader statistical reflection.
	vec2 hidden = vec2(1.0) - visible_spectral * visible_spectral;
	vec2 missing = slope_variance.xy * (scaled.x * scaled.x * hidden.x)
		+ slope_variance.zw * (scaled.y * scaled.y * hidden.y);
	float fine_amplitude = CAPILLARY_GAIN * 0.155 * state.y;
	missing += vec2(fine_amplitude * fine_amplitude * (1.0 - fine_resolved * fine_resolved));
	vec2 world_view = (INV_VIEW_MATRIX * vec4(VIEW, 0.0)).xz;
	vec2 view_weight = world_view * world_view + vec2(0.001);
	float sigma = sqrt(0.00036 + dot(missing, view_weight) / (view_weight.x + view_weight.y));
	vec2 response = (vec2(angle, clamp(sigma / 0.32, 0.0, 1.0)) * vec2(95.0, 47.0) + 0.5) / vec2(96.0, 48.0);
	float reflection = textureLod(water_response, response, 0.0).r;
	float body_variation = clamp(0.78 + 0.13 * state.x + 0.09 * state.y, 0.86, 1.16);
	vec3 water = (deep.rgb * body_variation + air_color.rgb * 0.032) * (1.0 - reflection);
	if (bed.y > 0.0) {
		float immersion = max(0.3, -bed.x) / max(0.40, angle);
		vec3 bottom = scatter_color.rgb * exp(-vec3(0.26, 0.091, 0.079) * immersion);
		water += bottom * ((0.75 - 0.42 * reflection) * bed.y);
	}
	foam = clamp(foam, 0.0, 0.92);
	ALBEDO = mix(water, vec3(0.48, 0.60, 0.63), foam);
	ROUGHNESS = mix(clamp(0.123 + 1.55 * sigma, 0.14, 0.63), 0.64, foam);
	METALLIC = 0.0;
	float broad_lobe = smoothstep(0.045, 0.21, sigma);
	EMISSION = air_color.rgb * reflection * (0.14 + 0.47 * broad_lobe) * distant_reflection * (1.0 - 0.75 * foam);
	SPECULAR = 0.353 * (1.0 - foam * 0.55) * (1.0 - broad_lobe * 0.18);
	FOG = aerial_transport(INV_VIEW_MATRIX[3].xyz, vec3(uv.x - world_offset.x, water_point.y, uv.y - world_offset.y));
}
