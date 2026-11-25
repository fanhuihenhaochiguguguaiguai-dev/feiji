shader_type sky;
render_mode use_half_res_pass;

uniform sampler2D panorama : source_color, filter_linear_mipmap;
uniform sampler2D dusk_sky : source_color, filter_linear_mipmap, repeat_enable;
uniform sampler2D density : repeat_enable, filter_linear_mipmap;
uniform vec3 sun_direction = vec3(-0.53, 0.15, -0.84);
uniform vec4 atmosphere : source_color = vec4(0.36, 0.48, 0.64, 1.0);
uniform vec4 sun_color : source_color = vec4(1.0, 0.65, 0.33, 1.0);
uniform vec2 terrain_origin;
uniform float storm = 0.0;
uniform float sunset = 1.0;
uniform int cloud_samples = 7;

vec2 uv_for(vec3 direction) {
	return vec2(atan(direction.x, -direction.z) / TAU + 0.5, acos(clamp(direction.y, -1.0, 1.0)) / PI);
}

float density_at(vec3 p, float floor_m, float thickness) {
	vec2 wind = vec2(18.0, 9.0) * TIME;
	vec2 uv = (p.xz + terrain_origin + wind) / 9400.0;
	float layer = clamp((p.y - floor_m) / thickness, 0.0, 1.0);
	float field = textureLod(density, uv + layer * vec2(0.20, -0.11), 1.0).r;
	float wisps = textureLod(density, uv * 3.23 + layer * vec2(-0.73, 0.31), 2.0).g;
	float fades = smoothstep(0.0, 0.3, layer) * (1.0 - smoothstep(0.59, 1.0, layer));
	return smoothstep(0.45 - 0.15 * storm, 0.77, field * 0.74 + wisps * 0.26) * fades;
}

vec4 volume_clouds(vec3 ray, vec3 eye, float angle) {
	float floor_m = mix(1150.0, 640.0, storm);
	float thickness = mix(780.0, 1180.0, storm);
	if (abs(ray.y) < 0.00001) { return vec4(0.0); }
	float a = (floor_m - eye.y) / ray.y;
	float b = (floor_m + thickness - eye.y) / ray.y;
	float near_t = max(0.0, min(a, b));
	float far_t = min(18500.0, max(a, b));
	if (near_t >= far_t) { return vec4(0.0); }
	float step_length = (far_t - near_t) / float(cloud_samples);
	float jitter = fract(sin(dot(uv_for(ray) * vec2(1024.0, 512.0), vec2(127.1, 311.7))) * 43758.5453) * 0.5 + 0.25;
	float transmission = 1.0;
	vec3 accumulation = vec3(0.0);
	for (int i = 0; i < 9; ++i) {
		if (i >= cloud_samples || transmission < 0.045) { break; }
		float travel = near_t + step_length * (float(i) + jitter);
		vec3 p = eye + ray * travel;
		float density0 = density_at(p, floor_m, thickness);
		if (density0 > 0.008) {
			float sun_cover = density_at(p + sun_direction * 360.0, floor_m, thickness);
			float lit = clamp(0.53 + (density0 - sun_cover) * 0.84, 0.18, 0.97);
			float alpha = 1.0 - exp(-density0 * step_length * (0.0021 + storm * 0.0011));
			vec3 scatter = mix(atmosphere.rgb * 0.44, vec3(0.62, 0.70, 0.79) * (0.8 - storm * 0.23), lit);
			scatter += sun_color.rgb * lit * (0.19 + 0.41 * pow(angle, 8.0)) * sunset;
			scatter = mix(scatter, atmosphere.rgb, smoothstep(3700.0, 18500.0, travel) * 0.64);
			accumulation += scatter * alpha * transmission;
			transmission *= 1.0 - alpha;
		}
	}
	return vec4(accumulation, 1.0 - transmission);
}

void sky() {
	vec3 ray = normalize(EYEDIR);
	float angle = clamp(dot(ray, normalize(sun_direction)), 0.0, 1.0);
	if (AT_HALF_RES_PASS) {
		vec4 clouds = AT_CUBEMAP_PASS ? vec4(0.0) : volume_clouds(ray, POSITION, angle);
		COLOR = clouds.rgb;
		ALPHA = clouds.a;
	} else {
		vec3 base = texture(panorama, uv_for(ray)).rgb;
		if (!AT_CUBEMAP_PASS && sunset > 0.5) {
			vec2 uv = uv_for(ray);
			uv.x += 0.44 - uv_for(sun_direction).x;
			base = mix(base * 0.22, texture(dusk_sky, uv).rgb * 0.92, 0.88);
		}
		float gradient = pow(1.0 - abs(ray.y), 7.0);
		base = mix(base * vec3(0.82, 0.94, 1.13), atmosphere.rgb, gradient * 0.21);
		base += sun_color.rgb * (pow(angle, 54.0) * 0.18 + pow(angle, 11500.0) * 6.5);
		if (!AT_CUBEMAP_PASS) { base = base * (1.0 - HALF_RES_COLOR.a) + HALF_RES_COLOR.rgb; }
		COLOR = base;
	}
}
