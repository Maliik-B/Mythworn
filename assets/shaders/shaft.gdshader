shader_type canvas_item;
render_mode blend_add;
// One shaft of plain light, additive, falling from the top of its rect. No HDR glow in the
// compatibility renderer, so this is the bloom. `reach` is how far down it has fallen so far.

uniform float intensity = 0.0;
uniform vec3 tint = vec3(1.0, 0.95, 0.84);
uniform float top_width = 0.34;
uniform float bottom_width = 0.92;
uniform float reach = 1.0;
uniform float motes = 0.0;
uniform vec2 rect_size = vec2(560.0, 780.0);

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(41.3, 289.1))) * 43758.5453);
}

float noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), f.x),
		mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), f.x), f.y);
}

void fragment() {
	float half_width = mix(top_width, bottom_width, UV.y);
	float off_centre = abs(UV.x - 0.5) * 2.0 / max(half_width, 0.001);
	float beam = 1.0 - smoothstep(0.35, 1.0, off_centre);
	float fallen = 1.0 - smoothstep(reach - 0.12, reach, UV.y);
	float ends = smoothstep(0.0, 0.12, UV.y) * (1.0 - smoothstep(0.82, 1.0, UV.y));
	vec2 cell = UV * rect_size / 9.0;
	cell.y -= TIME * 1.5;
	float dust = pow(noise(cell), 16.0) * motes * 6.0;
	float light = beam * fallen * ends * (0.62 + dust);
	COLOR = vec4(tint * light * intensity, 1.0);
}
