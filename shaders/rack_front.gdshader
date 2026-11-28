// Front face of a 42U rack behind a perforated door. Every LED is drawn here,
// procedurally, so a hall of racks costs no lights at all.
// UV spans one rack face: 0.62 m wide, 2.12 m tall.
shader_type spatial;

uniform float power = 1.0;        // 0 = rack is dark (power cut)
uniform float led_gain = 2.2;
uniform float seed = 0.0;         // differs per aisle so no two rows blink alike

uniform float bar = 0.0;          // teal light bar down the door edge (Hall B)
uniform float cage = 0.0;         // 1 = every LED is teal (Cage 7 equipment)
uniform float pulse_z = -100.0;   // world z of the travelling pulse
uniform float pulse_gain = 0.0;

varying float rid;
varying float wz;

float h1(float n) { return fract(sin(n * 127.1) * 43758.5453); }

void vertex() {
	// numbered by where the rack stands, so a row drawn in several pieces does not repeat
	rid = floor(MODEL_MATRIX[3].z / 0.62) + floor(MODEL_MATRIX[3].x * 2.0) * 17.0 + 1.0 + seed;
	wz = (MODEL_MATRIX * vec4(VERTEX, 1.0)).z;
}

void fragment() {
	float u = (UV.x - 0.5) * 0.62;
	float v = (1.0 - UV.y) * 2.12;
	float px = max(fwidth(v), fwidth(u));   // metres per pixel
	// no two racks are quite alike: some are dark, some have lost their door, some stand empty
	float rk = h1(rid * 3.17 + 0.5);
	float dead = step(0.955, rk);
	float open = step(rk, 0.05);
	float empty = step(0.9, h1(rid * 9.7 + 2.0));
	float tint = 0.75 + 0.5 * h1(rid * 5.1 + 7.0);
	vec3 alb = vec3(0.03);
	vec3 em = vec3(0.0);
	float rough = 0.7;

	if (abs(u) > 0.265 || v < 0.07 || v > 2.05) {
		// door frame
		alb = vec3(0.12, 0.125, 0.135) * tint;
		rough = 0.45;
	} else {
		float row = (v - 0.08) / 0.0445;
		float iu = floor(row);
		float fv = fract(row);
		float hr = h1(iu * 7.3 + rid * 13.1) * (1.0 - empty);
		float gap = smoothstep(0.0, 0.08, fv) * smoothstep(1.0, 0.92, fv);
		float kk = 0.0035 / (0.0035 + px);
		float y = (fv - 0.5) * 0.0445;
		if (iu >= 42.0) {
			// patch panel: a row of link lights
			alb = vec3(0.02);
			float cx = (u + 0.25) / 0.5 * 24.0;
			float col = floor(cx);
			float fu = fract(cx);
			float on = step(0.3, h1(col + iu * 31.0 + rid))
				* step(0.3, h1(col * 1.7 + iu + rid + floor(TIME * (4.0 + 8.0 * h1(col + rid)))));
			float dt = smoothstep(0.4, 0.15, abs(fu - 0.5)) * smoothstep(0.34, 0.12, abs(fv - 0.5));
			vec3 c = mix(vec3(0.1, 1.0, 0.3), vec3(1.0, 0.6, 0.1), step(0.85, h1(col * 3.3 + rid)));
			em = c * on * dt * 2.6 * mix(0.3, 1.0, kk);
		} else if (hr > 0.2) {
			// a server: green status, blue activity, sometimes a bank of port lights
			alb = vec3(0.06) * (0.5 + 0.5 * gap);
			float vent = smoothstep(0.3, 0.5, abs(fract(u * 90.0) - 0.5)) * step(abs(fv - 0.5), 0.3) * step(abs(u), 0.19);
			alb *= 1.0 - 0.6 * vent * smoothstep(0.004, 0.001, px);
			em += vec3(0.1, 1.0, 0.35) * smoothstep(0.0038 + px, 0.001, length(vec2(u + 0.24, y))) * 1.8 * kk * kk;
			float act = step(0.5, h1(iu + rid * 3.0 + floor(TIME * (3.0 + 9.0 * hr))));
			em += vec3(0.15, 0.45, 1.0) * smoothstep(0.0034 + px, 0.001, length(vec2(u + 0.226, y))) * act * 2.6 * kk * kk;
			if (u > 0.05 && u < 0.226 && hr > 0.72) {
				float dc = floor((u - 0.05) / 0.022);
				float du = fract((u - 0.05) / 0.022);
				float a2 = step(0.6, h1(dc * 5.0 + iu * 3.0 + rid + floor(TIME * 12.0 * h1(dc + iu))));
				em += vec3(0.1, 1.0, 0.3) * smoothstep(0.34, 0.1, abs(du - 0.5)) * smoothstep(0.14, 0.04, abs(fv - 0.22)) * a2 * 1.8 * kk;
			}
			// the odd amber fault light
			float fault = step(0.985, h1(iu * 3.7 + rid * 5.3));
			em += vec3(1.0, 0.55, 0.1) * smoothstep(0.0038 + px, 0.001, length(vec2(u + 0.21, y))) * fault * 2.4 * kk * kk;
		} else {
			// blanking panel
			alb = vec3(0.035) * (0.7 + 0.3 * gap);
		}
		// perforated door in front of everything
		vec2 hq = vec2(u, v) / 0.0045;
		hq.x += 0.5 * floor(hq.y);
		float hole = smoothstep(0.36, 0.26, length(fract(hq) - 0.5));
		float near = smoothstep(0.003, 0.0008, px);
		vec3 behind = alb * 1.5;
		alb = mix(alb * 0.6 + vec3(0.045), mix(vec3(0.11), alb * 0.8, hole), near) * tint;
		alb = mix(alb, behind, open);
		em *= mix(mix(0.75, 0.6 + 0.4 * hole, near), 1.0, open);
		// a strip of tape and a paper tag, on about one door in eight
		float tv = 1.1 + 0.6 * h1(rid * 2.3);
		float tag = step(0.875, h1(rid * 6.1 + 4.0)) * (1.0 - open) * step(abs(u + 0.1 + 0.2 * h1(rid)), 0.055) * step(abs(v - tv), 0.04);
		alb = mix(alb, vec3(0.5, 0.47, 0.3) * (0.7 + 0.5 * h1(rid * 8.0)), tag);
		em *= 1.0 - tag;
		rough = 0.6;
	}
	em *= 1.0 - dead * (1.0 - cage);
	em = mix(em, vec3(0.1, 0.9, 0.78) * dot(em, vec3(0.4)), cage);
	// teal light bar on the door edge, with a slow idle wave and the story pulse
	// by coverage, so that far away the bar dims instead of breaking into dashes
	float pu = max(fwidth(u), 0.0002);
	float inbar = clamp((0.013 - abs(u - 0.285)) / pu + 0.5, 0.0, 1.0) * min(1.0, 0.026 / pu) * step(0.1, v) * step(v, 2.02);
	float wave = 0.25 + 0.2 * sin(wz * 0.9 - TIME * 1.3);
	float d = wz - pulse_z;
	float pulse = pulse_gain * exp(-d * d * 1.6);
	em += vec3(0.1, 0.9, 0.78) * inbar * bar * (wave + pulse * 4.0);
	em += vec3(0.1, 0.9, 0.78) * pulse * 0.05 * bar;
	ALBEDO = alb;
	ROUGHNESS = rough;
	METALLIC = 0.0;
	SPECULAR = 0.4;
	EMISSION = em * power * led_gain;
}
