shader_type canvas_item;
// A ring of wet ink spreading out from a point, drawn in the rect's own pixels. The radius wanders
// and the line swells and thins with the angle, so it reads as a pen's line and not a shockwave.
// A soft wash trails inside the front. Integer frequencies keep the seam at the angle's wrap closed.

uniform float radius = 0.0;
uniform float half_size = 512.0;
uniform float line_width = 9.0;
uniform float wash_depth = 110.0;
uniform float wash_strength = 0.16;
uniform float fade = 1.0;
uniform vec4 tint : source_color = vec4(0.96, 0.86, 0.62, 1.0);

void fragment() {
	vec2 p = (UV - 0.5) * 2.0 * half_size;
	float d = length(p);
	float a = atan(p.y, p.x);
	float wander = sin(a * 7.0 + 1.3) * 0.5 + sin(a * 13.0 + 4.1) * 0.3 + sin(a * 29.0) * 0.2;
	// A small ring keeps round: the same wander on a short line would read as a gear's teeth.
	float r = radius + wander * 6.0 * smoothstep(40.0, 320.0, radius);
	float w = line_width * (0.8 + 0.3 * sin(a * 5.0 + 2.0));
	float line = 1.0 - smoothstep(w * 0.5, w * 0.5 + 2.5, abs(d - r));
	float wash = smoothstep(r - wash_depth, r, d) * (1.0 - step(r, d)) * wash_strength;
	COLOR = vec4(tint.rgb, tint.a * fade * clamp(line + wash, 0.0, 1.0));
}
