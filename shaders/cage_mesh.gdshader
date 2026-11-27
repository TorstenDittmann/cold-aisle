// Welded wire mesh for Cage 7. Close up it is real wires; far away it becomes a
// half-density screen-door pattern so it never shimmers at low resolution.
shader_type spatial;
render_mode cull_disabled;

uniform float cell = 0.05;
varying vec3 wp;

void vertex() {
	wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec2 p = vec2(wp.x + wp.z, wp.y) / cell;
	float px = fwidth(p.x) + fwidth(p.y);
	vec2 f = abs(fract(p) - 0.5);
	float wire = step(0.36, max(f.x, f.y));
	vec2 sc = floor(FRAGCOORD.xy);
	float far = mod(sc.x + sc.y, 2.0);
	float keep = mix(wire, far, smoothstep(0.5, 1.2, px));
	if (keep < 0.5) {
		discard;
	}
	ALBEDO = vec3(0.16, 0.165, 0.17);
	ROUGHNESS = 0.5;
	METALLIC = 0.6;
}
