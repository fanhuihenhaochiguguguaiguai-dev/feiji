shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, cull_disabled, shadows_disabled;
uniform sampler2D flipbook : source_color, filter_linear_mipmap;
uniform sampler2D depth_tex : hint_depth_texture, repeat_disable, filter_nearest;
instance uniform float life = 0.0;
instance uniform vec4 tint : source_color = vec4(1.0);
instance uniform float emission_gain = 0.0;
instance uniform float hidden = 0.0;
instance uniform bool atlas = false;
instance uniform float roll = 0.0;
instance uniform float soft_depth = 1.0;
varying vec3 camera_position;

void vertex() {
	float scale_x = length(MODEL_MATRIX[0].xyz);
	float scale_y = length(MODEL_MATRIX[1].xyz);
	mat4 aligned = mat4(INV_VIEW_MATRIX[0], INV_VIEW_MATRIX[1], INV_VIEW_MATRIX[2], MODEL_MATRIX[3]);
	VERTEX.xy *= vec2(scale_x, scale_y);
	float c = cos(roll);
	float s = sin(roll);
	VERTEX.xy = mat2(vec2(c, s), vec2(-s, c)) * VERTEX.xy;
	MODELVIEW_MATRIX = VIEW_MATRIX * aligned;
	camera_position = (MODELVIEW_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec2 uv = UV;
	if (atlas) {
		float f = floor(clamp(life * 15.0, 0.0, 15.0));
		uv = (uv + vec2(mod(f, 4.0), floor(f / 4.0))) * 0.25;
	}
	vec4 texel = texture(flipbook, uv);
	float mask = texel.a * smoothstep(0.52, 0.23, length(UV - vec2(0.5)));
	float depth = texture(depth_tex, SCREEN_UV).x;
	vec4 behind = INV_PROJECTION_MATRIX * vec4(SCREEN_UV * 2.0 - 1.0, depth, 1.0);
	float soft = smoothstep(0.0, soft_depth, (-behind.z / behind.w) + camera_position.z);
	ALBEDO = mix(texel.rgb, vec3(0.65, 0.65, 0.67), hidden) * tint.rgb;
	EMISSION = ALBEDO * emission_gain;
	ALPHA = mask * soft * tint.a;
}
