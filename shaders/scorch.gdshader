shader_type spatial;
render_mode blend_mix, cull_back, depth_draw_never, shadows_disabled;

instance uniform vec4 wound_port;
instance uniform vec4 wound_starboard;
instance uniform vec4 wound_hull;
instance uniform vec4 bearing_port;
instance uniform vec4 bearing_starboard;
instance uniform vec4 bearing_hull;
varying vec3 skin_point;
varying vec3 skin_normal;

void vertex() {
	skin_point = VERTEX;
	skin_normal = NORMAL;
	VERTEX += NORMAL * (0.009 / max(1.0, max(bearing_hull.w, max(bearing_port.w, bearing_starboard.w))));
}

vec2 wound(vec4 contact, vec4 projection) {
	if (contact.w <= 0.0) { return vec2(0.0); }
	vec3 delta = (skin_point - contact.xyz) * projection.w;
	float depth = dot(delta, projection.xyz);
	vec3 on_plane = delta - depth * projection.xyz;
	float facing = smoothstep(0.10, 0.67, dot(normalize(skin_normal), projection.xyz));
	float imprint = length(on_plane) / mix(0.44, 1.31, sqrt(contact.w));
	float abrasion = sin(dot(on_plane, vec3(41.0, 63.0, 27.0))) * cos(dot(on_plane, vec3(19.0, 91.0, 47.0)));
	float ash = (1.0 - smoothstep(0.17, 1.04, imprint + abrasion * 0.10)) * facing;
	float pit = (1.0 - smoothstep(0.07, 0.29, imprint + abrasion * 0.06)) * facing;
	return vec2(ash, pit) * (1.0 - smoothstep(1.1, 3.5, abs(depth)));
}

void fragment() {
	vec2 marks = max(wound(wound_hull, bearing_hull), max(wound(wound_port, bearing_port), wound(wound_starboard, bearing_starboard)));
	if (marks.x < 0.01) { discard; }
	ALBEDO = mix(vec3(0.088, 0.066, 0.049), vec3(0.015, 0.017, 0.017), marks.y);
	ROUGHNESS = 0.86;
	METALLIC = 0.12;
	ALPHA = marks.x * 0.91;
}
