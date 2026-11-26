shader_type spatial;
render_mode unshaded, blend_mix, cull_front, depth_draw_never, depth_test_disabled, shadows_disabled;

uniform sampler3D combustion : repeat_disable, filter_linear;
uniform sampler2D scene_depth : hint_depth_texture, repeat_disable, filter_nearest;
uniform vec4 daylight : source_color;
instance uniform vec4 volume_state = vec4(0.0, 1.0, 1.0, 7.0);
varying vec3 local_eye;
varying vec3 local_point;

void vertex() {
	local_point = VERTEX;
	local_eye = (inverse(MODEL_MATRIX) * vec4(INV_VIEW_MATRIX[3].xyz, 1.0)).xyz;
}

vec3 lookup(vec3 point, float frame) {
	vec3 voxel = clamp(point + 0.5, vec3(0.0), vec3(1.0)) * 31.0 + 0.5;
	voxel.z = (voxel.z + frame * 32.0) / 6.0;
	return textureLod(combustion, voxel / 32.0, 0.0).rgb;
}

void fragment() {
	vec3 arrow = local_point - local_eye;
	float last = length(arrow);
	vec3 ray = arrow / max(last, 0.0001);
	vec3 inv = mix(vec3(-1.0), vec3(1.0), step(vec3(0.0), ray)) / max(abs(ray), vec3(0.0001));
	vec3 bounds_a = (-0.5 - local_eye) * inv;
	vec3 bounds_b = (0.5 - local_eye) * inv;
	vec3 enters = min(bounds_a, bounds_b);
	float first = max(0.0, max(enters.x, max(enters.y, enters.z)));
	float scene_z = texture(scene_depth, SCREEN_UV).r;
	vec4 scene_point = INV_PROJECTION_MATRIX * vec4(SCREEN_UV * 2.0 - 1.0, scene_z, 1.0);
	float opaque = last * (scene_point.z / scene_point.w) / min(-0.0001, VERTEX.z);
	last = min(last, opaque);
	if (last <= first) { discard; }

	float progress = volume_state.x;
	int samples = int(volume_state.w);
	float stride = (last - first) / float(samples);
	float jitter = fract(dot(floor(FRAGCOORD.xy), vec2(0.24513, 0.70711)));
	float time_frame = clamp(progress * 8.7, 0.0, 5.0);
	float begin_frame = floor(time_frame);
	float next_frame = min(5.0, begin_frame + 1.0);
	float life = (1.0 - smoothstep(0.56, 1.0, progress)) * smoothstep(0.0, 0.085, progress + 0.025);
	float transmit = 1.0;
	vec3 result = vec3(0.0);
	for (int i = 0; i < 9; ++i) {
		if (i >= samples) { break; }
		vec3 p = local_eye + ray * (first + (float(i) + jitter) * stride);
		vec3 matter = mix(lookup(p, begin_frame), lookup(p, next_frame), fract(time_frame));
		float flame = matter.g * (1.0 - smoothstep(0.14, 0.49, progress)) * volume_state.y;
		float density = (matter.r * 8.7 * volume_state.z + flame * 3.1) * life;
		float opacity = 1.0 - exp(-density * stride);
		vec3 soot = daylight.rgb * (0.023 + 0.12 * matter.b);
		vec3 heat = mix(vec3(1.0, 0.16, 0.02), vec3(1.0, 0.88, 0.54), smoothstep(0.19, 0.76, flame));
		result += (soot + heat * flame * 13.5) * (opacity * transmit);
		transmit *= 1.0 - opacity;
		if (transmit < 0.035) { break; }
	}
	float coverage = 1.0 - transmit;
	ALBEDO = result / max(coverage, 0.0001);
	ALPHA = coverage;
}
