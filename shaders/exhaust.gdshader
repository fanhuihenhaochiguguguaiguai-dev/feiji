shader_type spatial;
render_mode unshaded, cull_front, blend_add, depth_draw_never, depth_test_disabled, shadows_disabled;

uniform vec4 tint : source_color = vec4(0.28, 0.47, 1.0, 1.0);
uniform float intensity = 4.4;
uniform sampler2D scene_depth : hint_depth_texture, repeat_disable, filter_nearest;

varying vec3 local_eye;
varying vec3 local_point;

void vertex() {
	local_point = VERTEX;
	local_eye = (inverse(MODEL_MATRIX) * vec4(INV_VIEW_MATRIX[3].xyz, 1.0)).xyz;
}

void fragment() {
	vec3 from_eye = local_point - local_eye;
	float last = length(from_eye);
	vec3 ray = from_eye / max(0.0001, last);
	vec3 reciprocal = mix(vec3(-1.0), vec3(1.0), step(vec3(0.0), ray)) / max(abs(ray), vec3(0.0001));
	vec3 bounds_a = (-0.5 - local_eye) * reciprocal;
	vec3 bounds_b = (0.5 - local_eye) * reciprocal;
	vec3 enters = min(bounds_a, bounds_b);
	float first = max(0.0, max(enters.x, max(enters.y, enters.z)));
	float z = texture(scene_depth, SCREEN_UV).r;
	vec4 opaque = INV_PROJECTION_MATRIX * vec4(SCREEN_UV * 2.0 - 1.0, z, 1.0);
	last = min(last, last * (opaque.z / opaque.w) / min(-0.0001, VERTEX.z));
	if (last <= first) { discard; }

	// Integrate the hot core, turbulent sheath and standing shock cells along the sightline.
	int steps = -VERTEX.z < 110.0 ? 5 : 3;
	float stride = (last - first) / float(steps);
	float optical = 0.0;
	vec3 radiance = vec3(0.0);
	for (int i = 0; i < 5; i++) {
		if (i >= steps) { break; }
		vec3 p = local_eye + ray * (first + (float(i) + 0.5) * stride);
		float tail = clamp(p.y + 0.5, 0.0, 1.0);
		float phase = tail * 28.3 + sin(TIME * 19.0 + tail * 20.0) * 0.34;
		float shock = pow(0.5 + 0.5 * cos(phase), 6.0) * (1.0 - tail);
		vec2 swirl = vec2(sin(phase * 0.75 - TIME * 32.0), cos(phase * 0.91 - TIME * 28.0)) * tail * 0.049;
		float width = mix(0.44, 0.09, tail) * (1.0 + shock * 0.13);
		float radial = dot(p.xz + swirl, p.xz + swirl) / (width * width);
		float envelope = (1.0 - smoothstep(0.58, 1.0, tail)) * smoothstep(0.0, 0.035, tail);
		float density = (1.0 - smoothstep(0.08, 1.0, radial)) * envelope * exp(-1.27 * tail);
		float core = (1.0 - smoothstep(0.02, 0.40, radial)) * (0.19 + 0.75 * shock + 0.26 * (1.0 - tail));
		radiance += mix(tint.rgb, vec3(1.0, 0.93, 0.76), clamp(core, 0.0, 1.0)) * density * stride;
		optical += density * stride;
	}
	ALBEDO = radiance * (intensity / max(0.001, optical));
	ALPHA = 1.0 - exp(-optical * 4.8);
}
