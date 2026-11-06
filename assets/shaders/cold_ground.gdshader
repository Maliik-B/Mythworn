shader_type canvas_item;
// The other map's backdrop, turning up outward from one point on a stepped front. Nothing lights the
// front and nothing fades across it: this is one place giving way to another, not something burning
// through, so each block is either the old ground or the new. Dimmed and darkened at the edges, in the
// realm's own dark, so the map's nodes stay on top of a pale sky.

uniform vec2 center = vec2(960.0, 540.0);
uniform float reach = 0.0;
uniform vec2 view = vec2(1920.0, 1080.0);
uniform float block = 15.0;
uniform float ragged = 44.0;
uniform float dim = 0.74;
uniform vec3 edge_tint = vec3(0.06, 0.08, 0.12);

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

void fragment() {
	vec2 cell = floor(UV * view / block);
	float offset = (hash(cell) - 0.5) * ragged;
	float shown = step(length((cell + 0.5) * block - center) + offset, reach);
	vec3 picture = texture(TEXTURE, UV).rgb * dim;
	float vignette = smoothstep(0.35, 1.05, length((UV - 0.5) * vec2(1.25, 1.0)) * 1.4);
	COLOR = vec4(mix(picture, edge_tint, vignette * 0.55), shown);
}
