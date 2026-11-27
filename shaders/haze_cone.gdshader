// A soft slab of lit air under each strip light. Additive, no depth write.
shader_type spatial;
render_mode unshaded, blend_add, cull_disabled, depth_draw_never, shadows_disabled;

uniform vec3 colour : source_color = vec3(0.82, 0.92, 1.0);
uniform float strength = 0.05;

void fragment() {
	float down = 1.0 - UV.y;                       // 1 at the fitting, 0 at the floor
	float side = 1.0 - abs(UV.x - 0.5) * 2.0;
	float a = pow(down, 1.6) * smoothstep(0.0, 0.6, side);
	ALBEDO = colour * a * strength;
}
