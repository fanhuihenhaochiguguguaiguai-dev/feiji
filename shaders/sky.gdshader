shader_type sky;
render_mode use_half_res_pass;

uniform sampler2D panorama : source_color, filter_linear_mipmap, repeat_enable;
uniform sampler2D scattering : filter_linear, repeat_disable;
uniform sampler3D density : filter_linear, repeat_enable;
uniform vec3 sun_direction;
uniform vec4 air_color : source_color;
uniform vec4 sun_color : source_color;
uniform vec2 terrain_origin;
global uniform vec2 cloud_drift;
uniform float panorama_offset;
uniform float panorama_range;
uniform float storm;
uniform int cloud_samples = 4;

vec2 panorama_uv(vec3 ray) {
	return vec2(atan(ray.x, -ray.z) / TAU + 0.5 + panorama_offset, acos(clamp(ray.y, -1.0, 1.0)) / PI);
}

float shape_at(vec3 point, float bottom, float thickness) {
	float altitude = clamp((point.y - bottom) / thickness, 0.0, 1.0);
	vec2 sheet = (point.xz + terrain_origin + cloud_drift) / vec2(10100.0, 7450.0);
	float fill = textureLod(density, vec3(sheet, (altitude * 31.0 + 0.5) / 32.0), 0.0).r;
	return min(1.0, fill * (1.0 + storm * 0.34));
}

vec2 nearby_cloud(vec3 ray, vec3 camera_at, float phase) {
	float bottom = mix(1080.0, 680.0, storm);
	float thickness = mix(820.0, 1260.0, storm);
	float dy = sign(ray.y + 0.000001) * max(0.0001, abs(ray.y));
	vec2 span = (vec2(bottom, bottom + thickness) - camera_at.y) / dy;
	float enter = max(0.0, min(span.x, span.y));
	float leave = min(max(span.x, span.y), 6600.0);
	if (enter >= leave) { return vec2(0.0); }
	float step_m = (leave - enter) / float(cloud_samples);
	float transmit = 1.0;
	float centre = 0.0;
	for (int i = 0; i < 4; ++i) {
		if (i >= cloud_samples || transmit < 0.08) { break; }
		float t = enter + step_m * (float(i) + 0.5);
		vec3 p = camera_at + ray * t;
		float fill = shape_at(p, bottom, thickness);
		float opacity = 1.0 - exp(-fill * step_m * 0.0019 * (1.0 - smoothstep(4400.0, 6600.0, t)));
		centre += t * opacity * transmit;
		transmit *= 1.0 - opacity;
	}
	float coverage = 1.0 - transmit;
	if (coverage < 0.004) { return vec2(0.0); }
	vec3 centre_point = camera_at + ray * (centre / coverage);
	// One short sunward lookup shades only the nearby cloud visible to the player.
	float blocker = shape_at(centre_point + sun_direction * thickness * 0.44, bottom, thickness);
	float light = exp(-blocker * (2.1 + storm * 0.8)) * (0.66 + phase * 0.34);
	return vec2(coverage, coverage * light);
}

vec3 solar_disc(vec3 ray, float alignment) {
	if (alignment < 0.987) { return vec3(0.0); }
	// Mean solar angular diameter is 0.533 degrees. Chord distance is stable at the limb.
	const float angular_radius = 0.0046513;
	float chord = length(ray - sun_direction);
	float pixel = max(0.00012, fwidth(chord) * 0.74);
	float mask = 1.0 - smoothstep(angular_radius - pixel, angular_radius + pixel, chord);
	float mu = sqrt(max(0.0, 1.0 - (chord * chord) / (angular_radius * angular_radius)));
	float limb = 0.42 + 0.58 * mu;
	float transmission = exp(-0.095 / max(0.05, sun_direction.y));
	float disc = mask * limb * (15.5 * mix(1.0, 0.18, storm));
	// Normalized forward lobe, separate from the existing broad sky scattering.
	const float anisotropy = 0.972;
	const float peak_width = (1.0 - anisotropy) * (1.0 - anisotropy);
	float forward = pow(peak_width / (peak_width + anisotropy * chord * chord), 1.5);
	float halo = forward * (1.0 - smoothstep(0.10, 0.16, chord)) * mix(0.52, 0.18, storm);
	return sun_color.rgb * transmission * (disc + halo);
}

void sky() {
	vec3 ray = normalize(EYEDIR);
	float angle = dot(ray, sun_direction);
	float phase = pow(max(0.0, angle), 5.0);
	if (AT_HALF_RES_PASS) {
		// Store opacity and premultiplied light in the color channels. The Mobile sky buffer may lack alpha.
		COLOR = vec3(AT_CUBEMAP_PASS ? vec2(0.0) : nearby_cloud(ray, POSITION, phase), 0.0);
	} else {
		vec2 uv = panorama_uv(ray);
		// The panorama contributes photographed clouds and horizon. Direct solar light uses the shared bearing.
		vec3 photo = texture(panorama, uv).rgb * panorama_range;
		vec3 scatter = texture(scattering, vec2(angle * 0.5 + 0.5, clamp(ray.y, 0.0, 1.0))).rgb;
		vec3 base = photo * mix(0.51, 0.44, storm);
		float clear_air = (1.0 - smoothstep(0.22, 0.60, dot(base, vec3(0.21, 0.72, 0.07)))) * (1.0 - storm);
		base *= mix(vec3(1.0), vec3(0.60, 0.87, 1.13), clear_air);
		base = mix(base, vec3(dot(base, vec3(0.21, 0.72, 0.07))) * vec3(0.87, 0.96, 1.12), storm * 0.57);
		base += scatter * air_color.rgb * (0.17 + phase * 0.11);
		float haze = exp(-max(0.0, ray.y) * 31.0);
		float altitude_haze = 0.83;
		if (!AT_CUBEMAP_PASS) {
			altitude_haze = mix(0.83, 0.50 + storm * 0.19, smoothstep(1100.0, 4200.0, POSITION.y));
		}
		base = mix(base, air_color.rgb * 0.78, haze * altitude_haze);
		if (!AT_CUBEMAP_PASS) {
			// The existing directional light supplies direct illumination and reflection highlights.
			base += solar_disc(ray, angle);
			vec2 cloud = clamp(HALF_RES_COLOR.rg, vec2(0.0), vec2(1.0));
			vec3 shade = air_color.rgb * mix(0.48, 0.36, storm);
			vec3 sunlit = mix(vec3(0.66, 0.74, 0.83), sun_color.rgb * 0.85, 0.26 + phase * 0.30);
			base = base * (1.0 - cloud.x) + cloud.x * shade + cloud.y * (sunlit - shade);
		}
		COLOR = base;
	}
}
