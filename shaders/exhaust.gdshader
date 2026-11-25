shader_type spatial;
render_mode unshaded, cull_disabled, blend_add, depth_draw_never, shadows_disabled;

uniform vec4 tint : source_color = vec4(0.41, 0.58, 1.0, 1.0);
uniform float intensity = 1.6;
uniform float bias = 0.0;
varying vec3 flame_axis;

void vertex() {
	flame_axis = VERTEX;
}

void fragment() {
	float tail = clamp(1.0 - UV.y, 0.0, 1.0);
	float taper = smoothstep(0.02, 0.26, tail) * (0.49 + tail * 0.75);
	float wobble = sin(UV.x * 38.0 + TIME * 86.0 + UV.y * 18.0) * 0.14;
	float turbulence = 0.72 + 0.23 * sin(flame_axis.y * 16.0 - TIME * 52.0 + wobble) + wobble;
	float hot = pow(max(0.0, sin(flame_axis.y * 25.0 - TIME * 9.0)), 7.0);
	float edge = pow(1.0 - abs(dot(normalize(NORMAL), VIEW)), 1.35);
	vec3 radiance = mix(tint.rgb, vec3(1.0, 0.74, 0.42), bias * tail + hot * 0.18);
	ALBEDO = radiance * intensity;
	ALPHA = clamp(taper * turbulence * (0.20 + edge * 0.57), 0.0, 0.76);
}
