shader_type canvas_item;

void fragment() {
	float bevel = mix(0.18, 0.04, UV.y);
	float horizontal = smoothstep(0.0, 0.16, UV.x - bevel) * smoothstep(0.0, 0.16, 1.0 - UV.x - (0.24 - bevel));
	float vertical = smoothstep(0.02, 0.34, UV.y) * smoothstep(0.02, 0.26, 1.0 - UV.y);
	COLOR.a *= horizontal * vertical;
}
