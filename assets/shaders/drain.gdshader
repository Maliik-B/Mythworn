shader_type canvas_item;
// Colour going out of a thing. Corruption here is subtraction, so this only ever takes away:
// no veins, no growth, nothing added but a little ash in what is left.

uniform float amount = 0.0;
uniform vec3 ash = vec3(0.74, 0.73, 0.70);
uniform float dim = 0.0;

void fragment() {
	float luma = dot(COLOR.rgb, vec3(0.299, 0.587, 0.114));
	vec3 drained = vec3(luma) * ash;
	COLOR.rgb = mix(COLOR.rgb, drained, amount) * (1.0 - dim * amount);
}
