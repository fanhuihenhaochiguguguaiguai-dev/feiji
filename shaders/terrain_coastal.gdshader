shader_type spatial;
render_mode cull_disabled, shadows_disabled, diffuse_burley, specular_disabled;
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
	if (covered_by_detail(ground_at, 144.0)) { discard; }
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
	vec2 rock_uv = (ground_at + point.y * vec2(0.79, -0.43) * smoothstep(0.06, 0.40, steepness)) * (0.155 / 6.0);
	vec2 scree_uv = ground_at * (0.14 / 6.0);
	vec2 rock_dx = dFdx(rock_uv);
	vec2 rock_dy = dFdy(rock_uv);
	vec2 scree_dx = dFdx(scree_uv);
	vec2 scree_dy = dFdy(scree_uv);
	vec3 surface_color;
	if (stone < 0.065) {
		surface_color = textureGrad(scree_scan, scree_uv, scree_dx, scree_dy).rgb * scree_tint.rgb;
	} else if (stone > 0.935) {
		surface_color = textureGrad(rock_scan, rock_uv, rock_dx, rock_dy).rgb * rock_tint.rgb;
	} else {
		vec3 rock = textureGrad(rock_scan, rock_uv, rock_dx, rock_dy).rgb * rock_tint.rgb;
		vec3 scree = textureGrad(scree_scan, scree_uv, scree_dx, scree_dy).rgb * scree_tint.rgb;
		surface_color = mix(scree, rock, smoothstep(0.065, 0.935, stone));
	}
	ALBEDO = surface_color * mix(vec3(1.0), tint, on_survey);
	ROUGHNESS = mix(0.92, 0.81, stone);
	SPECULAR = 0.0;
	// Baked visibility only affects the survey and is phased out at its edge.
	AO = mix(1.0, surface.a, on_survey * 0.72);
	AO_LIGHT_AFFECT = 0.56;
	FOG = aerial_transport(INV_VIEW_MATRIX[3].xyz, point);
}
