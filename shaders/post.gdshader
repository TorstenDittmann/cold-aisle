// The lens: colour fringing at the edges, vignette, cool tint, film grain.
shader_type canvas_item;

uniform sampler2D screen_tex : hint_screen_texture, filter_linear;
uniform float fringe = 0.0018;
uniform float vignette = 0.34;
uniform float grain = 0.04;
uniform float contrast = 1.06;
uniform vec3 tint : source_color = vec3(0.97, 1.0, 1.03);
uniform float pixel_rows = 240.0;   // grain and dither are locked to the big pixels
uniform float colour_steps = 40.0;   // levels per channel, with ordered dither
uniform float lid = 0.0;   // 0 = eye open, 1 = eye closed

float h2(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }

void fragment() {
	vec2 uv = SCREEN_UV;
	vec2 d = uv - 0.5;
	vec2 k = d * dot(d, d) * fringe * 4.0;
	vec3 c = vec3(texture(screen_tex, uv - k).r, texture(screen_tex, uv).g, texture(screen_tex, uv + k).b);
	c = (c - 0.5) * contrast + 0.5;
	c *= tint;
	float aspect = SCREEN_PIXEL_SIZE.y / SCREEN_PIXEL_SIZE.x;
	c *= 1.0 - vignette * smoothstep(0.3, 1.1, length(d * vec2(aspect, 1.0)) * 1.15);
	float l = dot(c, vec3(0.2126, 0.7152, 0.0722));
	vec2 cell = floor(uv * vec2(pixel_rows * aspect, pixel_rows));
	float n = h2(cell + floor(TIME * 12.0) * 31.7);
	c += (n - 0.5) * grain * (1.0 - abs(l - 0.5));
	// ordered dither down to a small palette, on the same pixel grid
	float bayer = fract(dot(mod(cell, 4.0), vec2(0.25, 0.5)) + mod(cell.x, 2.0) * mod(cell.y, 2.0) * 0.125);
	c = floor(c * colour_steps + bayer) / colour_steps;
	// eyelid: the frame closes to a line
	float open = 1.0 - lid;
	float h = open * open * (3.0 - 2.0 * open) * 0.5;
	float bow = 0.12 * lid * (1.0 - pow(abs(d.x) * 2.0, 2.0));
	float e = abs(d.y) - (h + bow * h * 2.0);
	c *= mix(1.0, smoothstep(0.012, -0.012, e), step(0.001, lid));
	COLOR = vec4(clamp(c, 0.0, 1.0), 1.0);
}
