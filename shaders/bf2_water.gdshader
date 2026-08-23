shader_type spatial;

uniform vec3 WaterColor;
uniform float alpha_threshold : hint_range(0.0, 1.0);

void fragment() {
	ALBEDO = WaterColor.rgb;
	ALPHA = alpha_threshold;
}
