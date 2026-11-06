shader_type canvas_item;
// Ink arriving, or ink leaving, across a canvas item. The sweep runs in the item's own pixels, so
// it works on a Label (whose UVs point into the font atlas) as well as on a sprite. Two items given
// the same origin and span sweep together, which is what lets one name write over another.

uniform float progress = 0.0;
uniform float origin_x = 0.0;
uniform float span_x = 1000.0;
// Above zero, a wrapped block of text inks down its lines instead of straight across.
uniform float span_y = 0.0;
uniform float softness = 0.09;
uniform float grain = 26.0;
// False: nothing at 0, everything at 1. True: everything at 0, nothing at 1.
uniform bool leaving = false;
uniform vec3 edge_color = vec3(1.0, 0.93, 0.72);
uniform float edge_amount = 0.85;

varying vec2 local_pos;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), f.x),
		mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), f.x), f.y);
}

void vertex() {
	local_pos = VERTEX;
}

void fragment() {
	float across = clamp((local_pos.x - origin_x) / max(span_x, 1.0), 0.0, 1.0);
	float field = across;
	if (span_y > 0.0) {
		field = mix(across, clamp(local_pos.y / span_y, 0.0, 1.0), 0.8);
	}
	float n = noise(local_pos / grain) * 0.65 + noise(local_pos / (grain * 0.31)) * 0.35;
	field = field * 0.86 + n * 0.14;
	float front = progress * (1.0 + softness);
	float written = 1.0 - smoothstep(front - softness, front, field);
	float band = written * (1.0 - written) * 4.0;
	if (leaving) {
		written = 1.0 - written;
	}
	COLOR.rgb = mix(COLOR.rgb, edge_color, band * edge_amount);
	COLOR.a *= written;
}
