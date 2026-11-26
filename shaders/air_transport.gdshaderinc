uniform sampler2D air_column : repeat_disable, filter_linear;
uniform vec4 air_color : source_color;
uniform vec4 solar_color : source_color;
uniform vec3 solar_direction;
uniform float aerosol_extinction = 0.000024;

vec4 aerial_transport(vec3 eye, vec3 point) {
	vec3 displacement = point - eye;
	float distance_m = max(0.01, length(displacement));
	vec2 altitude = clamp(vec2(eye.y, point.y) / 8000.0, vec2(0.0), vec2(1.0));
	vec2 density = textureLod(air_column, (altitude * 127.0 + 0.5) / 128.0, 0.0).rg;
	vec2 extinction = density * vec2(0.000012, aerosol_extinction);
	float optical_depth = (extinction.x + extinction.y) * distance_m;
	float sunward = pow(max(0.0, dot(displacement / distance_m, solar_direction)), 5.0);
	vec3 atmosphere = mix(air_color.rgb, solar_color.rgb, 0.27 * sunward);
	return vec4(atmosphere * 0.78, 1.0 - exp(-optical_depth));
}
