shader_type canvas_item;
// A plain patch of light where the picture stops: one flat tone, opaque, in a soft-cornered shape. It mixes rather than adds, so it cannot bloom, and it ends with a short falloff, so there is
// no halo, no bright edge and nothing that reads as a torn hole.

uniform float fade = 0.0;
uniform vec4 tint : source_color = vec4(0.93, 0.93, 0.91, 1.0);

void fragment() {
	vec2 q = abs(UV - 0.5) * 2.0;
	float d = pow(pow(q.x, 6.0) + pow(q.y, 6.0), 1.0 / 6.0);
	float shape = 1.0 - smoothstep(0.86, 1.0, d);
	COLOR = vec4(tint.rgb, tint.a * fade * shape);
}
