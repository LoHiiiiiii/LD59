shader_type canvas_item;

uniform vec4 from_color : source_color = vec4(1.0);
uniform vec4 to_color : source_color = vec4(1.0);
uniform float threshold : hint_range(0.0, 1.0) = 0.05;
uniform bool radar_on = false;

void fragment() {
	vec4 col = texture(TEXTURE, UV);
	if (radar_on && length(col.rgb - from_color.rgb) < threshold) {
		col.rgb = to_color.rgb;
	}
	COLOR = col;
}
