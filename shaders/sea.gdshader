shader_type spatial;
render_mode cull_disabled, diffuse_burley, specular_schlick_ggx;

uniform vec2 world_offset;
uniform vec4 deep : source_color = vec4(0.027, 0.095, 0.155, 1.0);
uniform vec4 shallow : source_color = vec4(0.055, 0.22, 0.24, 1.0);
uniform sampler2D shore_noise : repeat_enable, filter_linear_mipmap_anisotropic;
varying vec3 surface;
varying float crest;

void wave(vec2 axis, float length_m, float amplitude, float phase, vec2 ground, inout vec3 p, inout vec2 slope) {
	float k = 6.283185 / length_m;
	float angle = dot(axis, ground) * k + phase;
	p.xz += axis * cos(angle) * amplitude * 0.54;
	p.y += sin(angle) * amplitude;
	slope += axis * cos(angle) * amplitude * k;
}

void vertex() {
	vec3 p = VERTEX;
	vec2 ground = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xz + world_offset;
	vec2 slope = vec2(0.0);
	wave(vec2(0.863, -0.505), 113.0, 1.6, TIME * 0.71, ground, p, slope);
	wave(vec2(0.33, 0.944), 82.0, 0.78, -TIME * 0.98, ground, p, slope);
	wave(vec2(-0.71, 0.704), 39.0, 0.35, TIME * 1.36, ground, p, slope);
	VERTEX = p;
	NORMAL = normalize(vec3(-slope.x, 1.0, -slope.y));
	surface = vec3(ground.x, p.y, ground.y);
	crest = p.y;
}

void fragment() {
	vec2 uv = surface.xz;
	float small = texture(shore_noise, uv * 0.046 + vec2(TIME * 0.034, -TIME * 0.006)).r;
	float swell = texture(shore_noise, uv * 0.018 + vec2(-TIME * 0.012, TIME * 0.016)).r;
	float scatter = smoothstep(0.6, 1.0, small * 0.44 + swell * 0.7) * smoothstep(1.02, 2.5, crest);
	ALBEDO = mix(deep.rgb, shallow.rgb, swell * 0.54 + scatter * 0.22) + scatter * vec3(0.16, 0.24, 0.25);
	ROUGHNESS = mix(0.16, 0.36, small);
	METALLIC = 0.29;
	SPECULAR = 0.68;
}
