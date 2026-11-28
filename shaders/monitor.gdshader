// One screen of the camera wall: a dim, grainy view down a corridor that is not quite
// any real one, with a time stamp, a recording light and a slow rolling bar.
shader_type spatial;
render_mode unshaded;

uniform float seed = 0.0;

float h(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }

void fragment() {
	vec2 uv = UV;
	vec2 vp = vec2(0.5 + 0.18 * sin(seed * 2.3), 0.4 + 0.08 * cos(seed * 1.7));
	vec2 c = uv - vp;
	// floor, walls and ceiling meeting at a vanishing point
	float wall = step(abs(c.y) * (1.2 + 0.5 * h(vec2(seed, 1.0))), abs(c.x));
	float depth = clamp(max(abs(c.x), abs(c.y)) * 2.2, 0.0, 1.0);
	float lum = mix(0.05, mix(0.3, 0.17, wall), depth);
	lum *= c.y > 0.0 || wall > 0.5 ? 1.0 : 0.55;
	// rack fronts or doors as darker panels along the walls
	float panels = step(0.5, fract(log(max(abs(c.x), 0.01)) * (3.0 + 2.0 * h(vec2(seed, 2.0)))));
	lum *= 1.0 - 0.35 * panels * wall;
	// a row of ceiling lights running away
	float lamp = smoothstep(0.035, 0.0, abs(c.x) - abs(c.y) * 0.12) * step(c.y, -0.03) * step(0.45, fract(log(max(-c.y, 0.01)) * 2.6));
	lum += 0.5 * lamp;
	// grain, a rolling bar, soft scan rows
	lum += (h(floor(uv * vec2(96.0, 60.0)) + floor(TIME * 8.0)) - 0.5) * 0.06;
	lum += 0.07 * smoothstep(0.1, 0.0, abs(fract(uv.y - TIME * 0.06 + seed * 0.37) - 0.5));
	lum *= 0.9 + 0.1 * sin(uv.y * 150.0);
	vec3 col = lum * vec3(0.72, 1.0, 0.86);
	// time stamp and camera name: blocks of text too small to read
	float tx = step(0.05, uv.x) * step(uv.x, 0.42) * step(0.88, uv.y) * step(uv.y, 0.93);
	col = mix(col, vec3(0.75, 0.85, 0.8), tx * step(0.35, h(vec2(floor(uv.x * 60.0), seed))));
	float rec = smoothstep(0.022, 0.012, length((uv - vec2(0.92, 0.09)) * vec2(1.6, 1.0))) * step(0.5, fract(TIME * 0.8 + seed));
	col = mix(col, vec3(1.0, 0.12, 0.08), rec);
	// the bezel shadow at the edges
	col *= smoothstep(0.0, 0.04, uv.x) * smoothstep(1.0, 0.96, uv.x) * smoothstep(0.0, 0.05, uv.y) * smoothstep(1.0, 0.95, uv.y);
	ALBEDO = col * 1.5;
}
