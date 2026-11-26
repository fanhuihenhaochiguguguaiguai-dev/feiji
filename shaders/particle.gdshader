shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, cull_disabled, shadows_disabled;
uniform sampler2D flipbook : source_color, repeat_disable, filter_linear_mipmap;
uniform sampler2D opposite_light : source_color, repeat_disable, filter_linear_mipmap;
uniform bool relight_smoke = false;
uniform vec3 sun_direction = vec3(0.0, 1.0, 0.0);
uniform vec4 sun_color : source_color = vec4(1.0);
uniform sampler2D depth_tex : hint_depth_texture, repeat_disable, filter_nearest;
instance uniform float life = 0.0;
instance uniform vec4 tint : source_color = vec4(1.0);
instance uniform float emission_gain = 0.0;
instance uniform float roll = 0.0;
instance uniform float soft_depth = 1.0;
instance uniform bool contact_flash = false;
varying vec3 camera_position;
varying vec3 local_sun;

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
	if (relight_smoke) {
		vec3 light = mat3(VIEW_MATRIX) * sun_direction;
		local_sun = vec3(mat2(vec2(c, -s), vec2(s, c)) * light.xy, light.z);
	}
}

void fragment() {
	float f = min(15.0, floor(clamp(life, 0.0, 1.0) * 16.0));
	vec2 uv = (UV + vec2(mod(f, 4.0), floor(f / 4.0))) * 0.25;
	vec2 radial = (UV - vec2(0.5)) * 2.0;
	vec4 texel;
	float mask;
	if (contact_flash) {
		float r2 = dot(radial, radial);
		float kernel = exp(-r2 * 10.0);
		float spikes = exp(-abs(radial.x * radial.y) * 98.0) * exp(-r2 * 5.8);
		texel = vec4(mix(vec3(1.0, 0.47, 0.15), vec3(1.0, 0.96, 0.84), kernel), 1.0);
		mask = (1.0 - smoothstep(0.58, 1.0, r2)) * max(kernel, spikes * 0.48);
	} else {
		texel = texture(flipbook, uv);
		mask = texel.a * (1.0 - smoothstep(0.23, 0.52, length(UV - vec2(0.5))));
	}
	float depth = texture(depth_tex, SCREEN_UV).x;
	vec4 behind = INV_PROJECTION_MATRIX * vec4(SCREEN_UV * 2.0 - 1.0, depth, 1.0);
	float soft = smoothstep(0.0, soft_depth, (-behind.z / behind.w) + camera_position.z);
	vec3 shade = texel.rgb;
	if (relight_smoke) {
		float lit = dot(texel.rgb, max(local_sun, vec3(0.0)))
			+ dot(texture(opposite_light, uv).rgb, max(-local_sun, vec3(0.0)));
		shade = vec3(0.27, 0.31, 0.38) + sun_color.rgb * lit * 0.94;
	}
	ALBEDO = shade * tint.rgb;
	EMISSION = ALBEDO * emission_gain;
	ALPHA = mask * soft * tint.a;
}
