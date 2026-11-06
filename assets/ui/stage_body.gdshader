// A body on the combat stage. `drain` takes the colour out of it and leaves its values, so it is the
// same man with the colour gone. Purple never reaches the stage: a stand-in sheet that carries some
// comes out as slate. A `baked` sheet (tools/bake_sheet.py) is one value ramp already, and all it has
// to lose is its lapis, which goes to slate at the same value.
shader_type canvas_item;

uniform float drain : hint_range(0.0, 1.0) = 0.0;
uniform bool baked = false;
// Toward white, for the blink of a landed hit. Modulate cannot do this on a near-black sprite.
uniform float flash : hint_range(0.0, 1.0) = 0.0;

const vec3 LAPIS_OUT = vec3(0.353, 0.384, 0.463);
const float LAPIS_VALUE = 0.235;

void fragment() {
	vec3 c = COLOR.rgb;
	float value = dot(c, vec3(0.299, 0.587, 0.114));
	if (baked) {
		bool lapis = c.b > c.r * 1.3 && c.b > c.g * 1.25 && c.b > 0.25;
		if (lapis) {
			COLOR.rgb = mix(c, LAPIS_OUT * value / LAPIS_VALUE, drain);
		}
	} else {
		float purple = clamp((min(c.r, c.b) - c.g) * 6.0, 0.0, 1.0);
		COLOR.rgb = mix(c, vec3(value) * vec3(0.98, 1.0, 1.04), max(drain, purple));
	}
	COLOR.rgb = mix(COLOR.rgb, vec3(1.0), flash);
}
