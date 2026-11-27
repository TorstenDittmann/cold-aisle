// A security monitor: grey-green, scan lines, noise, and full static on demand.
shader_type canvas_item;

uniform float static_amt = 0.0;

float h2(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }

void fragment() {
	vec3 c = texture(TEXTURE, UV).rgb;
	float l = dot(c, vec3(0.3, 0.6, 0.1));
	vec2 cellp = floor(UV * vec2(192.0, 144.0));
	float n = h2(cellp + floor(TIME * 15.0) * 17.0);
	l = l * 1.5 + (n - 0.5) * 0.08;
	l = mix(l, n * 0.7, static_amt);
	l *= 0.85 + 0.15 * step(0.5, fract(UV.y * 72.0));
	COLOR = vec4(vec3(0.8, 1.0, 0.86) * l, 1.0);
}
