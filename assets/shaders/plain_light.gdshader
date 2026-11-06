shader_type canvas_item;
// A slit of plain light: one flat tone, opaque, opening from the middle. It mixes rather than adds, so it
// cannot bloom, its straight sides end in a pixel or two, so there is no halo and no bright edge, and it
// goes out upward rather than ending in a top, so it reads as light and not as a thing standing there.

uniform float fade = 0.0;
uniform float open = 0.0;
uniform vec2 rect_size = vec2(26.0, 340.0);
uniform vec4 tint : source_color = vec4(0.95, 0.95, 0.93, 1.0);

void fragment() {
	float half_w = 0.5 * rect_size.x * open;
	float from_middle = abs(UV.x - 0.5) * rect_size.x;
	float shape = 1.0 - smoothstep(half_w - 1.0, half_w + 1.0, from_middle);
	float upward = smoothstep(0.0, 0.4, UV.y);
	COLOR = vec4(tint.rgb, tint.a * fade * shape * upward);
}
