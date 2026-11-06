shader_type canvas_item;
// Ground gone white: a low broken drift along the field, a little heavier at its foot and going to a
// dusting down the wind, so it reads as snow blown here and not as something poured. One flat colour with
// no feather, because soft white over a dark field reads as grey and this has to stay white.

uniform float grow = 0.0;  // how far down the wind it has reached, 0 to 1
uniform vec2 rect_size = vec2(520.0, 60.0);
uniform vec2 cell = vec2(3.0, 3.0);
uniform vec4 tint : source_color = vec4(0.97, 0.97, 0.95, 1.0);

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

void fragment() {
	vec2 c = floor(UV * rect_size / cell);
	vec2 uv = (c + 0.5) * cell / rect_size;
	float along = uv.x;
	float across = abs(uv.y - 0.5) * 2.0;
	float body = mix(0.46, 0.06, smoothstep(0.1, 1.0, along)) * smoothstep(0.0, 0.1, along);
	body *= 0.72 + 0.2 * sin(along * 19.0 + 1.0) + 0.14 * sin(along * 53.0);
	// Solid only near the foot: down the wind more and more of it is bare ground.
	float solid = step(across, body) * step(hash(c), mix(1.1, 0.26, smoothstep(0.1, 0.8, along)));
	float dusting = step(mix(0.91, 0.975, along), hash(c + 7.0)) * step(across, 0.95);
	COLOR = vec4(tint.rgb, max(solid, dusting) * step(along, grow));
}
