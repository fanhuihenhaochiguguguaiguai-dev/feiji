shader_type spatial;
render_mode unshaded, cull_disabled, shadows_disabled;
#include "air_transport.gdshaderinc"
#include "terrain_coverage.gdshaderinc"

uniform sampler2D geology_scan : source_color, repeat_enable, filter_linear_mipmap_anisotropic;
uniform float relief_color_strength = 0.15;
varying vec2 ground_at;

void vertex() {
	ground_at = VERTEX.xz;
}

void fragment() {
	if (covered_by_detail(ground_at)) { discard; }
	vec3 point = (INV_VIEW_MATRIX * vec4(VERTEX, 1.0)).xyz;
	// Preserve the surveyed baked color and shadow while transferring
	// the scan's shorter-scale variation into the resident surface.
	vec2 rock_uv = (ground_at + point.y * vec2(1.24, -0.38)) / vec2(243.0, 197.0);
	vec3 grain = texture(geology_scan, rock_uv).rgb;
	ALBEDO = COLOR.rgb * (vec3(1.0) + (grain * 2.0 - 0.42) * relief_color_strength);
	FOG = aerial_transport(INV_VIEW_MATRIX[3].xyz, point);
}
