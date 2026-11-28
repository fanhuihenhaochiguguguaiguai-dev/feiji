uniform sampler2D detailed_regions : repeat_disable, filter_nearest;
uniform vec2 first_region;
uniform float region_span;

bool covered_by_detail(vec2 ground_at, float overlap_metres) {
	vec2 grid = ground_at / region_span - first_region;
	ivec2 cell = ivec2(floor(grid));
	ivec2 size = textureSize(detailed_regions, 0);
	if (any(lessThan(cell, ivec2(0))) || any(greaterThanEqual(cell, size))) {
		return false;
	}
	int mask = int(round(texelFetch(detailed_regions, cell, 0).r * 255.0));
	if (mask < 128) { return false; }
	vec2 offset = fract(grid) * region_span;
	return !(((mask & 1) != 0 && offset.x < overlap_metres)
		|| ((mask & 2) != 0 && (region_span - offset.x) < overlap_metres)
		|| ((mask & 4) != 0 && offset.y < overlap_metres)
		|| ((mask & 8) != 0 && (region_span - offset.y) < overlap_metres));
}
