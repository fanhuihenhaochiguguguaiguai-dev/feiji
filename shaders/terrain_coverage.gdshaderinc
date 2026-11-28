uniform sampler2D detailed_regions : repeat_disable, filter_nearest;
uniform vec2 first_region;
uniform float region_span;

bool covered_by_detail(vec2 ground_at) {
	ivec2 cell = ivec2(floor(ground_at / region_span - first_region));
	ivec2 size = textureSize(detailed_regions, 0);
	return all(greaterThanEqual(cell, ivec2(0))) && all(lessThan(cell, size))
		&& texelFetch(detailed_regions, cell, 0).r > 0.5;
}
