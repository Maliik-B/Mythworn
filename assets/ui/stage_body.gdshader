// A body on the combat stage. `drain` takes the colour out of it and leaves its values, so it is the
// same man with the colour gone. Purple never reaches the stage: a stand-in sheet that carries some
// comes out as slate.
//
// `page` is the manuscript look's treatment, done here rather than baked so the look stays one switch:
// the sheet's values mapped onto one ramp between `value_lo` and `value_hi`, a one-pixel ink outline,
// and a rim from a window at the upper left. Lapis is the one colour it keeps; drained, it goes to slate.
shader_type canvas_item;

uniform float drain : hint_range(0.0, 1.0) = 0.0;
uniform bool page = false;
uniform float value_lo = 0.05;
uniform float value_hi = 0.6;

const vec3 INK = vec3(0.118, 0.106, 0.094);
const vec3 LAPIS = vec3(0.122, 0.235, 0.533);
const vec3 LAPIS_RIM = vec3(0.18, 0.333, 0.722);
const vec3 LAPIS_OUT = vec3(0.353, 0.384, 0.463);

vec3 ramp(int i) {
	if (i <= 0) return vec3(0.118, 0.106, 0.094);
	if (i == 1) return vec3(0.165, 0.149, 0.133);
	if (i == 2) return vec3(0.239, 0.227, 0.208);
	if (i == 3) return vec3(0.353, 0.341, 0.314);
	if (i == 4) return vec3(0.435, 0.447, 0.455);
	if (i == 5) return vec3(0.549, 0.525, 0.463);
	return vec3(0.812, 0.784, 0.722);
}

float value_of(vec3 c) {
	return dot(c, vec3(0.299, 0.587, 0.114));
}

void fragment() {
	vec4 c = COLOR;
	if (page) {
		vec2 px = TEXTURE_PIXEL_SIZE;
		float up = texture(TEXTURE, UV + vec2(0.0, -px.y)).a;
		float up_left = texture(TEXTURE, UV + vec2(-px.x, -px.y)).a;
		if (c.a < 0.5) {
			float near = max(max(up, texture(TEXTURE, UV + vec2(0.0, px.y)).a),
				max(texture(TEXTURE, UV + vec2(-px.x, 0.0)).a, texture(TEXTURE, UV + vec2(px.x, 0.0)).a));
			c = near > 0.5 ? vec4(INK, 1.0) : vec4(0.0);
		} else {
			bool lit = up < 0.5 || up_left < 0.5;
			if (c.b > c.r * 1.3 && c.b > c.g * 1.25 && c.b > 0.25) {
				c.rgb = mix(lit ? LAPIS_RIM : LAPIS, LAPIS_OUT, drain);
			} else {
				float x = clamp((value_of(c.rgb) - value_lo) / max(0.01, value_hi - value_lo), 0.0, 1.0);
				int i = int(floor(pow(x, 0.9) * 6.0 + 0.5));
				c.rgb = ramp(lit ? i + 1 : i);
			}
			c.a = 1.0;
		}
		COLOR = c;
	} else {
		float value = value_of(c.rgb);
		float purple = clamp((min(c.r, c.b) - c.g) * 6.0, 0.0, 1.0);
		COLOR.rgb = mix(c.rgb, vec3(value) * vec3(0.98, 1.0, 1.04), max(drain, purple));
	}
}
