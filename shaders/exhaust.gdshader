shader_type spatial;
render_mode unshaded, cull_disabled, blend_add, depth_draw_never, shadows_disabled;

uniform vec4 tint : source_color = vec4(0.41, 0.58, 1.0, 1.0);
uniform float intensity = 1.6;
uniform float bias = 0.0;
uniform sampler2D flame_flipbook : source_color, repeat_disable, filter_linear_mipmap;

void fragment() {
	float tail = clamp(1.0 - UV.y, 0.0, 1.0);
	float taper = smoothstep(0.02, 0.26, tail) * (0.49 + tail * 0.75);
	float frame = floor(mod(TIME * 28.0, 30.0));
	frame = min(frame, 30.0 - frame);
	vec2 cell = vec2(mod(frame, 4.0), floor(frame * 0.25));
	vec2 plume_uv = vec2(0.49 + cos(UV.x * TAU) * 0.14, 0.59 + tail * 0.25);
	vec4 volume = texture(flame_flipbook, (plume_uv + cell) * 0.25);
	float turbulence = 0.48 + volume.a * 0.64;
	float hot = volume.g * volume.a;
	float edge = pow(1.0 - abs(dot(normalize(NORMAL), VIEW)), 1.35);
	vec3 radiance = mix(tint.rgb, vec3(1.0, 0.74, 0.42), bias * tail + hot * 0.18);
	ALBEDO = radiance * intensity;
	ALPHA = clamp(taper * turbulence * (0.20 + edge * 0.57), 0.0, 0.76);
}
