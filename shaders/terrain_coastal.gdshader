shader_type spatial;
render_mode cull_disabled, shadows_disabled, diffuse_burley, specular_schlick_ggx;
#include "air_transport.gdshaderinc"
#include "terrain_coverage.gdshaderinc"

uniform sampler2D surveyed_surface : repeat_disable, filter_linear_mipmap;
uniform sampler2D geology_colors : source_color, repeat_disable, filter_linear_mipmap;
uniform sampler2D rock_scan : source_color, repeat_enable, filter_linear_mipmap_anisotropic;
uniform sampler2D scree_scan : source_color, repeat_enable, filter_linear_mipmap_anisotropic;
uniform vec4 rock_tint : source_color;
uniform vec4 scree_tint : source_color;
uniform vec2 survey_origin;
uniform float survey_span;
varying vec2 ground_at;

void vertex() {
	ground_at = VERTEX.xz;
}

vec2 lattice_uv(vec2 at, float width) {
	return (at * (width - 1.0) + 0.5) / width;
}

void fragment() {
	if (covered_by_detail(ground_at)) { discard; }
	vec3 point = (INV_VIEW_MATRIX * vec4(VERTEX, 1.0)).xyz;
	vec3 geometric = normalize(mat3(INV_VIEW_MATRIX) * NORMAL);
	vec2 survey = (ground_at - survey_origin) / survey_span;
	float edge = min(min(survey.x, survey.y), min(1.0 - survey.x, 1.0 - survey.y));
	float on_survey = smoothstep(0.025, 0.102, edge) * smoothstep(5.0, 56.0, point.y);
	// The runway corridor uses authored terrain instead of the survey.
	on_survey *= smoothstep(3700.0, 4900.0, distance(ground_at, vec2(-340.0, 350.0)));
	vec4 surface = texture(surveyed_surface, lattice_uv(survey, 513.0));
	vec2 oct = surface.rg * 2.0 - 1.0;
	vec3 surveyed_normal = normalize(vec3(oct.x, max(0.05, 1.0 - abs(oct.x) - abs(oct.y)), oct.y));
	vec3 normal = normalize(mix(geometric, surveyed_normal, on_survey));
	NORMAL = normalize(mat3(VIEW_MATRIX) * normal);

	float steepness = max(0.0, 1.0 - normal.y);
	float stone = mix(smoothstep(0.075, 0.35, steepness), surface.b, on_survey);
	vec3 tint = texture(geology_colors, lattice_uv(survey, 1025.0)).rgb;
	// Match the two close-range scan families in projection and material
	// scale. Offset rock sampling along the incline to limit vertical stretch.
	vec2 slope_uv = ground_at + point.y * vec2(0.79, -0.43) * smoothstep(0.06, 0.40, steepness);
	vec3 rock = texture(rock_scan, slope_uv * (0.155 / 6.0)).rgb * rock_tint.rgb;
	vec3 scree = texture(scree_scan, ground_at * (0.14 / 6.0)).rgb * scree_tint.rgb;
	ALBEDO = mix(scree, rock, stone) * mix(vec3(1.0), tint, on_survey);
	ROUGHNESS = mix(0.92, 0.81, stone);
	SPECULAR = 0.20;
	// Baked visibility only affects the survey and is phased out at its edge.
	AO = mix(1.0, surface.a, on_survey);
	AO_LIGHT_AFFECT = 0.78;
	FOG = aerial_transport(INV_VIEW_MATRIX[3].xyz, point);
}
