shader_type spatial;
render_mode unshaded, cull_disabled, shadows_disabled;

uniform sampler2D detailed_regions : repeat_disable, filter_nearest;
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
	ALBEDO = COLOR.rgb;
}
