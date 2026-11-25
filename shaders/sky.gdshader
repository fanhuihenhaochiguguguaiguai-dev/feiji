shader_type sky;

uniform sampler2D panorama : source_color, filter_linear_mipmap;
uniform sampler2D dusk_sky : source_color, filter_linear_mipmap, repeat_enable;
uniform sampler2D density : repeat_enable, filter_linear_mipmap;
uniform vec3 sun_direction = vec3(-0.53, 0.15, -0.84);
uniform vec4 atmosphere : source_color = vec4(0.42, 0.52, 0.66, 1.0);
uniform vec4 sun_color : source_color = vec4(1.0, 0.65, 0.33, 1.0);
uniform float storm = 0.0;
uniform float sunset = 1.0;

vec2 uv_for(vec3 d) {
	return vec2(atan(d.x, -d.z) / 6.283185 + 0.5, acos(clamp(d.y,-1.0,1.0)) / 3.141593);
}

void sky() {
	vec3 ray = normalize(EYEDIR);
	vec3 col = texture(panorama, uv_for(ray)).rgb;
	if (!AT_CUBEMAP_PASS && sunset > 0.5) {
		vec2 uv = uv_for(ray);
		uv.x += 0.44 - uv_for(sun_direction).x;
		col = mix(col * 0.22, texture(dusk_sky, uv).rgb * 0.95, 0.88);
	}
	float angle = clamp(dot(ray, normalize(sun_direction)), 0.0, 1.0);
	float horizon = pow(1.0 - abs(ray.y), 8.0);
	col = mix(col * vec3(0.80, 0.92, 1.14), atmosphere.rgb, horizon * 0.22);
		float orange_dusk = (1.0 - smoothstep(0.0, 0.04, abs(ray.y - sun_direction.y) - 0.15)) * pow(angle, 12.0) * sunset;
	col += sun_color.rgb * (pow(angle, 56.0) * 0.22 + pow(angle, 11500.0) * 7.5 + orange_dusk * 0.23);
	if (ray.y > 0.017 && !AT_CUBEMAP_PASS) {
		vec2 plane = ray.xz / max(ray.y + 0.13, 0.1);
		vec2 uv = plane * 0.12 + vec2(TIME * 0.003, -TIME * 0.001);
		float field = texture(density, uv).r * 0.78 + texture(density, uv * 2.35 + 0.34).r * 0.22;
		float cloud = smoothstep(0.51 - storm * 0.22, 0.76, field) * smoothstep(0.02, 0.12, ray.y);
		float core = smoothstep(0.56, 0.94, field);
		vec3 dark = atmosphere.rgb * (0.45 + 0.25 * (1.0 - storm));
		vec3 warm = mix(vec3(0.59, 0.65, 0.76), sun_color.rgb, pow(angle, 5.0) * 0.8);
		col = mix(col, mix(warm, dark, core) + pow(angle, 30.0) * sun_color.rgb * 0.21, cloud * 0.73);
	}
	COLOR = col;
}
