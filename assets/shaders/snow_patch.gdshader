shader_type canvas_item;
// Ground gone white, in blocks, one flat colour with no feather: soft white over a dark field reads as
// grey, and this has to stay white. `grow` runs it out from the middle, with flakes landing ahead of it.

uniform float grow = 0.0;
uniform vec2 rect_size = vec2(800.0, 240.0);
uniform float cell = 4.0;
uniform vec4 tint : source_color = vec4(0.97, 0.97, 0.95, 1.0);

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

void fragment() {
	vec2 px = floor(UV * rect_size / cell) * cell;
	vec2 q = (px / rect_size - 0.5) * 2.0;
	float a = atan(q.y, q.x);
	float ragged = 0.8 + 0.1 * sin(a * 5.0 + 0.7) + 0.06 * sin(a * 11.0 + 2.3) + 0.04 * sin(a * 23.0);
	float d = length(q) / ragged;
	float solid = step(d, grow);
	float landed = step(0.9, hash(px)) * step(d, grow * 1.22);
	COLOR = vec4(tint.rgb, max(solid, landed));
}
