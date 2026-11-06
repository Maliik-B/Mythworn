shader_type canvas_item;
// A patch of plain light with its edge eaten back in steps, the way the page's edge is, and thin enough
// for the map to show through. One flat tone: no falloff, no bright edge, no bloom.

uniform float fade = 0.0;
uniform vec2 rect_size = vec2(130.0, 270.0);
uniform float cell = 4.0;
uniform vec4 tint : source_color = vec4(0.97, 0.97, 0.95, 0.68);

float wave(float x) {
	return fract(sin(x * 91.7) * 43758.5453);
}

void fragment() {
	vec2 c = floor(UV * rect_size / cell);
	vec2 q = (c + 0.5) * cell / rect_size * 2.0 - 1.0;
	// The width it keeps at this height: it wears away toward its head, each side bitten in steps.
	float keep = mix(0.36, 0.92, smoothstep(-1.0, 0.25, q.y));
	float row = floor(c.y / 3.0);
	float left = -keep + wave(row + 3.0) * 0.3 * keep;
	float right = keep - wave(row + 41.0) * 0.3 * keep;
	float inside = step(left, q.x) * step(q.x, right);
	COLOR = vec4(tint.rgb, tint.a * fade * inside);
}
