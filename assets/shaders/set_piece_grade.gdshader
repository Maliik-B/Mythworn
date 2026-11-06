shader_type canvas_item;
// The stage's grade: everything already drawn beneath this rect, with its colour taken down.

uniform sampler2D screen_tex : hint_screen_texture, filter_linear, repeat_disable;
uniform float saturation = 1.0;
uniform vec3 tint = vec3(1.0);
uniform float lift = 0.0;

void fragment() {
	vec3 c = texture(screen_tex, SCREEN_UV).rgb;
	float luma = dot(c, vec3(0.299, 0.587, 0.114));
	c = mix(vec3(luma), c, saturation) * tint + vec3(lift);
	COLOR = vec4(c, 1.0);
}
