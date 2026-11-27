shader_type sky;

uniform sampler2D panorama : source_color, filter_linear_mipmap, repeat_enable;
uniform vec3 sun_direction;
uniform float panorama_offset;

void sky() {
	vec3 ray = normalize(EYEDIR);
	vec2 uv = vec2(atan(ray.x, -ray.z) / TAU + 0.5 + panorama_offset, acos(clamp(ray.y, -1.0, 1.0)) / PI);
	vec3 capture = texture(panorama, uv).rgb;
	float toward = max(0.0, dot(ray, sun_direction));
	float scattering = pow(toward, 15.0) * exp(-abs(ray.y - sun_direction.y) * 7.0);
	vec3 dusk = vec3(0.64, 0.79, 1.02);
	vec3 warm = vec3(1.38, 0.84, 0.50);
	vec3 graded = capture * mix(dusk, warm, scattering * 0.78);
	if (AT_CUBEMAP_PASS) {
		// Reserve the concentrated sun reflection for the directional light.
		float peak = max(graded.r, max(graded.g, graded.b));
		COLOR = graded * (0.46 / (1.0 + 0.23 * peak));
	} else {
		COLOR = graded * 0.255;
	}
	COLOR += scattering * vec3(0.28, 0.115, 0.036);
}
