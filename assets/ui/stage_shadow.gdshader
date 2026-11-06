// A body's cast shadow: its own frame in one flat colour.
shader_type canvas_item;

uniform vec4 flat_color = vec4(0.0, 0.0, 0.0, 0.5);

void fragment() {
	COLOR = vec4(flat_color.rgb, step(0.5, COLOR.a) * flat_color.a);
}
