shader_type spatial;
render_mode unshaded, cull_disabled, shadows_disabled;
#include "air_transport.gdshaderinc"

uniform sampler2D detailed_regions : repeat_disable, filter_nearest;
uniform sampler2D geology_scan : source_color, repeat_enable, filter_linear_mipmap_anisotropic;
uniform float relief_color_strength = 0.15;
uniform float coastal_geology = 0.0;
uniform vec2 first_region;
uniform float region_span;
varying vec2 grid_position;

void vertex() {
	grid_position = VERTEX.xz / region_span - first_region;
}

void fragment() {
	ivec2 cell = ivec2(floor(grid_position));
	ivec2 size = textureSize(detailed_regions, 0);
	if (all(greaterThanEqual(cell, ivec2(0))) && all(lessThan(cell, size))) {
		if (texelFetch(detailed_regions, cell, 0).r > 0.5) {
			discard;
		}
	}
	vec3 absolute_terrain = vec3((grid_position + first_region) * region_span, 0.0).xzy;
	vec3 point = (INV_VIEW_MATRIX * vec4(VERTEX, 1.0)).xyz;
	// Preserve the surveyed baked color and shadow while transferring
	// the scan's shorter-scale variation into the resident surface.
	vec2 rock_uv = vec2(absolute_terrain.x + point.y * 1.24, absolute_terrain.z - point.y * 0.38) / vec2(243.0, 197.0);
	vec3 grain = texture(geology_scan, rock_uv).rgb;
	float baked_luminance = dot(COLOR.rgb, vec3(0.2126, 0.7152, 0.0722));
	float lit = smoothstep(0.075, 0.145, baked_luminance);
	float cover = smoothstep(12.0, 84.0, point.y) * (1.0 - smoothstep(630.0, 1500.0, point.y));
	vec3 exposed = mix(vec3(0.58, 0.63, 0.65), vec3(1.53, 1.20, 0.91), lit);
	vec3 local_tint = mix(exposed, exposed * vec3(0.78, 0.96, 0.76), cover);
	ALBEDO = COLOR.rgb * mix(vec3(1.0), local_tint, coastal_geology)
		* (vec3(1.0) + (grain * 2.0 - 0.42) * relief_color_strength);
	FOG = aerial_transport(INV_VIEW_MATRIX[3].xyz, point);
}
