shader_type canvas_item;
render_mode blend_add;
// A soft pool of light on the ground of the stage, flattened to sit under what stands on it.

uniform float intensity = 0.0;
uniform vec3 tint = vec3(1.0, 0.95, 0.84);

void fragment() {
	float d = length((UV - vec2(0.5)) * 2.0);
	float glow = 1.0 - smoothstep(0.0, 1.0, d);
	COLOR = vec4(tint * glow * glow * intensity, 1.0);
}
