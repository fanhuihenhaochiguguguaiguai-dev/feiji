shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx;

uniform sampler2D scan_color : source_color, repeat_enable, filter_linear_mipmap_anisotropic;
uniform sampler2D scan_normal : repeat_enable, filter_linear_mipmap_anisotropic;
uniform sampler2D scan_orm : repeat_enable, filter_linear_mipmap_anisotropic;
varying vec2 deck_metres;

void vertex() {
	deck_metres = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xz;
}

void fragment() {
	vec2 p = deck_metres;
	vec2 uv = p / vec2(8.2, 11.3);
	vec3 scan = texture(scan_color, uv).rgb;
	vec3 detail = texture(scan_normal, uv).xyz * 2.0 - 1.0;
	vec3 packed = texture(scan_orm, uv).rgb;
	float pooled = smoothstep(0.31, 0.66, texture(scan_orm, p * 0.044).g + 0.09 * sin(p.x * 1.31 + p.y * 0.67));
	vec2 grid = abs(fract(p / vec2(3.3, 5.7) + 0.5) - 0.5) * vec2(3.3, 5.7);
	float joints = 1.0 - smoothstep(0.007, 0.015 + fwidth(p.x) * 0.72, min(grid.x, grid.y));
	ALBEDO = mix(scan * vec3(0.90, 1.04, 1.17), vec3(0.075, 0.100, 0.133), 0.46) * (1.0 - joints * 0.19);
	ROUGHNESS = mix(0.43 + packed.g * 0.10, 0.205, pooled);
	METALLIC = mix(0.18, 0.34, pooled);
	SPECULAR = 0.39;
	AO = mix(1.0, packed.r, 0.28);
	vec3 ripple = vec3(detail.x, 0.0, detail.y) * mix(0.22, 0.071, pooled);
	NORMAL = normalize(NORMAL + mat3(VIEW_MATRIX) * ripple);
	CLEARCOAT = pooled * 0.51;
	CLEARCOAT_ROUGHNESS = 0.19;
}
