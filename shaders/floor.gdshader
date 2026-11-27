// Raised-access floor: 60 cm tiles, dark seams, perforated airflow tiles down the aisle.
// It is partly transparent: the mirrored hall beneath shows through as the reflection,
// strongest at grazing angles, absent on seams and perforated tiles.
shader_type spatial;
render_mode blend_mix, depth_draw_never, cull_back;

uniform float aisle_half_width = 0.66;
uniform float mirror = 0.6;
uniform float aisle_x = 1000.0;   // centre line of the perforated tiles; far away = none
varying vec3 wp;

float h2(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }

void vertex() {
	wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec2 tl = wp.xz / 0.6;
	vec2 f = fract(tl) - 0.5;
	vec2 ti = floor(tl);
	float px = max(fwidth(wp.x), fwidth(wp.z));
	float mx = max(abs(f.x), abs(f.y));
	float seam = smoothstep(0.487, 0.498, mx) * smoothstep(0.03, 0.005, px);
	vec3 alb = vec3(0.15, 0.155, 0.16) * (0.85 + 0.3 * h2(ti));
	float perf = step(abs((ti.x + 0.5) * 0.6 - aisle_x), aisle_half_width) * step(0.4, h2(ti + 3.0)) * step(mx, 0.43);
	vec2 hq = fract(wp.xz / 0.03) - 0.5;
	float holes = smoothstep(0.34, 0.26, length(hq));
	alb = mix(alb, alb * 0.75 * (1.0 - 0.8 * mix(0.4, holes, smoothstep(0.02, 0.006, px))), perf);
	alb *= 1.0 - 0.65 * seam;
	float fres = 0.22 + 0.78 * pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 4.0);
	float refl = mix(mirror, 0.22, perf) * (1.0 - seam) * fres;
	ALBEDO = alb;
	ROUGHNESS = mix(0.3, 0.6, max(perf, seam));
	METALLIC = 0.0;
	SPECULAR = 0.5;
	ALPHA = 1.0 - refl;
}
