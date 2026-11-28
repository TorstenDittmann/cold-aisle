// Raised-access floor: 60 cm tiles, dark seams, perforated airflow tiles down the aisle.
// It is partly transparent: the mirrored hall beneath shows through as the reflection,
// strongest at grazing angles, absent on seams and perforated tiles.
shader_type spatial;
render_mode blend_mix, depth_draw_never, cull_back;

uniform float aisle_half_width = 0.66;
uniform float mirror = 0.6;
uniform float aisle_x = 1000.0;   // centre line of the perforated tiles; far away = none
uniform vec4 line_z = vec4(10000.0);   // painted lines running east-west, by depth
uniform float line_b = 10000.0;         // and one in blue
varying vec3 wp;

// A painted line, by how much of the pixel it covers: far away it fades instead of flickering.
float paint(float z0) {
	float pz = max(fwidth(wp.z), 0.0005);
	return clamp((0.05 - abs(wp.z - z0)) / pz + 0.5, 0.0, 1.0) * min(1.0, 0.1 / pz);
}

float h2(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }

float vn(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(h2(i), h2(i + vec2(1.0, 0.0)), f.x), mix(h2(i + vec2(0.0, 1.0)), h2(i + vec2(1.0, 1.0)), f.x), f.y);
}

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
	// wear: a tile replaced last year, a tile nobody has cleaned, and stains that dull the shine
	alb *= 1.0 + 0.5 * step(0.965, h2(ti + 11.0)) - 0.4 * step(0.92, h2(ti + 23.0));
	float stain = smoothstep(0.6, 0.78, vn(wp.xz * 0.42) * 0.7 + vn(wp.xz * 1.7 + 9.0) * 0.3);
	float scuff = smoothstep(0.8, 0.95, vn(vec2(wp.x * 9.0, wp.z * 0.5 + 40.0))) * step(0.5, h2(ti + 5.0));
	alb *= 1.0 - 0.45 * stain - 0.3 * scuff;
	vec2 hq = fract(wp.xz / 0.03) - 0.5;
	float holes = smoothstep(0.34, 0.26, length(hq));
	alb = mix(alb, alb * 0.75 * (1.0 - 0.8 * mix(0.4, holes, smoothstep(0.02, 0.006, px))), perf);
	alb *= 1.0 - 0.65 * seam;
	float fres = 0.22 + 0.78 * pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 4.0);
	float refl = mix(mirror, 0.22, perf) * (1.0 - seam) * fres * (1.0 - 0.7 * stain) * (1.0 - 0.5 * scuff);
	float ly = max(max(paint(line_z.x), paint(line_z.y)), max(paint(line_z.z), paint(line_z.w)));
	float lb = paint(line_b);
	alb = mix(alb, vec3(0.5, 0.4, 0.06), ly);
	alb = mix(alb, vec3(0.1, 0.24, 0.4), lb);
	refl *= 1.0 - max(ly, lb);
	ALBEDO = alb;
	ROUGHNESS = mix(0.3, 0.6, max(perf, seam));
	METALLIC = 0.0;
	SPECULAR = 0.5;
	ALPHA = 1.0 - refl;
}
