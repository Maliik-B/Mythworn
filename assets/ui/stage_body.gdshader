// A body on the combat stage. `drain` takes the colour out of it and leaves its values, so it is the
// same man with the colour gone. Purple never reaches the stage: a stand-in sheet that carries some
// comes out as slate.
shader_type canvas_item;

uniform float drain : hint_range(0.0, 1.0) = 0.0;

void fragment() {
	vec3 c = COLOR.rgb;
	float value = dot(c, vec3(0.299, 0.587, 0.114));
	float purple = clamp((min(c.r, c.b) - c.g) * 6.0, 0.0, 1.0);
	float amount = max(drain, purple);
	COLOR.rgb = mix(c, vec3(value) * vec3(0.98, 1.0, 1.04), amount);
}
