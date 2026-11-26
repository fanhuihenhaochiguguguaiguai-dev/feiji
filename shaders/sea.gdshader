shader_type spatial;
render_mode cull_disabled, shadows_disabled, diffuse_burley, specular_schlick_ggx;

uniform vec2 world_offset;
uniform vec4 wake;
uniform float wake_strength = 0.0;
uniform vec4 deep : source_color = vec4(0.027, 0.090, 0.139, 1.0);
uniform vec4 scatter_color : source_color = vec4(0.098, 0.264, 0.277, 1.0);
uniform vec4 air_color : source_color = vec4(0.53, 0.64, 0.75, 1.0);
uniform sampler2D shore_noise : repeat_enable, filter_linear_mipmap_anisotropic;
uniform sampler2D coast_depth : repeat_disable, filter_linear;
uniform vec4 coast_area = vec4(0.0);
uniform sampler2DArray spectral_displacement : repeat_enable, filter_linear;
uniform sampler2DArray spectral_normals : repeat_enable, filter_linear;
uniform bool spectral_enabled = false;
uniform float spectral_weight = 0.0;
varying vec3 water_point;

const vec2 SWELL_AXIS = vec2(0.863, -0.505);
const float SWELL_K = TAU / 93.0;
const float OUTER_GAIN = 0.62;
const float INNER_GAIN = 0.40;

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
		vec2 delta = uv - wake.xy;
		float along = max(0.0, -dot(delta, wake.zw));
		float crosswind = abs(delta.x * wake.w - delta.y * wake.z);
		float wake_line = exp(-along * 0.022) * (1.0 - smoothstep(0.9 + along * 0.016, 3.0 + along * 0.055, crosswind));
		foam += wake_strength * wake_line * smoothstep(0.0, 3.0, along) * near_detail * 0.63;
	}
	vec3 normal_world = normalize(vec3(-gradient.x, 1.0, -gradient.y));
	NORMAL = (VIEW_MATRIX * vec4(normal_world, 0.0)).xyz;
	float angle = clamp(dot(NORMAL, VIEW), 0.0, 1.0);
	float sea_state = 0.5;
	if (outer_resolved < 0.86) {
		float broad = textureLod(shore_noise, uv / 11800.0 + flow * 0.012, 2.0).r;
		sea_state = mix(broad, 0.5, smoothstep(0.55, 0.86, outer_resolved));
	}
	vec3 water = deep.rgb * mix(0.88, 1.14, sea_state) + air_color.rgb * 0.045;
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
	ALBEDO = mix(water, vec3(0.49, 0.61, 0.62), clamp(foam, 0.0, 0.82));
	float unresolved = 0.066 * (1.0 - outer_resolved) + 0.049 * (1.0 - inner_resolved);
	ROUGHNESS = mix(sqrt(0.068 + unresolved), 0.59, clamp(foam, 0.0, 1.0));
	METALLIC = 0.0;
	float broad_lobe = 1.0 - outer_resolved;
	float grazing = 1.0 - clamp(dot(VIEW, VIEW_MATRIX[1].xyz), 0.0, 1.0);
	// After the sampled normal is subpixel, approximate its sky convolution with the shared horizon radiance.
	EMISSION = air_color.rgb * (broad_lobe * (0.043 + 0.19 * grazing * grazing * grazing));
	SPECULAR = 0.255 * (1.0 - foam * 0.55) * (1.0 - broad_lobe * 0.38);
	FOG = vec4(air_color.rgb * 0.78, smoothstep(1800.0, 16600.0, distance_m));
}
