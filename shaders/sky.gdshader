shader_type sky;
render_mode use_half_res_pass;

uniform sampler2D panorama : source_color, filter_linear_mipmap, repeat_enable;
uniform sampler2D scattering : filter_linear, repeat_disable;
uniform sampler2D density : filter_linear_mipmap, repeat_enable;
uniform vec3 sun_direction;
uniform vec4 air_color : source_color;
uniform vec4 sun_color : source_color;
uniform vec2 terrain_origin;
uniform float panorama_offset;
uniform float panorama_range;
uniform float storm;
uniform int cloud_samples = 4;

vec2 panorama_uv(vec3 ray) {
	return vec2(atan(ray.x, -ray.z) / TAU + 0.5 + panorama_offset, acos(clamp(ray.y, -1.0, 1.0)) / PI);
}

float shape_at(vec3 point, float bottom, float thickness) {
	float altitude = clamp((point.y - bottom) / thickness, 0.0, 1.0);
	vec2 wind = vec2(8.0, 4.0) * TIME;
	vec2 sheet = (point.xz + terrain_origin + wind) / vec2(10100.0, 7450.0);
	vec3 fields = textureLod(density, sheet + vec2(0.18, -0.11) * altitude, 1.2).rgb;
	float outline = smoothstep(0.47 - storm * 0.09, 0.73, fields.r * 0.73 + fields.g * 0.27);
	return outline * smoothstep(0.0, 0.32, altitude) * (1.0 - smoothstep(0.48, 1.0, altitude));
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

void sky() {
	vec3 ray = normalize(EYEDIR);
	float angle = dot(ray, sun_direction);
	float phase = pow(max(0.0, angle), 5.0);
	if (AT_HALF_RES_PASS) {
		// Store opacity and premultiplied light in the color channels. The Mobile sky buffer may lack alpha.
		COLOR = vec3(AT_CUBEMAP_PASS ? vec2(0.0) : nearby_cloud(ray, POSITION, phase), 0.0);
	} else {
		vec2 uv = panorama_uv(ray);
		// Keep the original panorama's horizon, cloud shapes and photographed sun on the same rays.
		vec3 photo = texture(panorama, uv).rgb * panorama_range;
		vec3 scatter = texture(scattering, vec2(angle * 0.5 + 0.5, clamp(ray.y, 0.0, 1.0))).rgb;
		vec3 base = photo * mix(0.51, 0.44, storm);
		float clear_air = (1.0 - smoothstep(0.22, 0.60, dot(base, vec3(0.21, 0.72, 0.07)))) * (1.0 - storm);
		base *= mix(vec3(1.0), vec3(0.60, 0.87, 1.13), clear_air);
		base = mix(base, vec3(dot(base, vec3(0.21, 0.72, 0.07))) * vec3(0.87, 0.96, 1.12), storm * 0.57);
		base += scatter * air_color.rgb * (0.17 + phase * 0.11);
		float haze = exp(-max(0.0, ray.y) * 31.0);
		base = mix(base, air_color.rgb * 0.78, haze * 0.83);
		if (!AT_CUBEMAP_PASS) {
			vec2 cloud = clamp(HALF_RES_COLOR.rg, vec2(0.0), vec2(1.0));
			vec3 shade = air_color.rgb * mix(0.48, 0.36, storm);
			vec3 sunlit = mix(vec3(0.66, 0.74, 0.83), sun_color.rgb * 0.85, 0.26 + phase * 0.30);
			base = base * (1.0 - cloud.x) + cloud.x * shade + cloud.y * (sunlit - shade);
		}
		COLOR = base;
	}
}
