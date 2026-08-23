shader_type spatial;
render_mode cull_disabled, depth_draw_always, alpha_to_coverage;

uniform sampler2D BaseTexture;
uniform float alpha_threshold : hint_range(0.0, 1.0);

void fragment() {
	// Place fragment code here.
	vec4 BaseColour = texture(BaseTexture, UV);
    if (BaseColour.a < alpha_threshold) {
        discard;
    }
	ALBEDO = BaseColour.rgb;
	ALPHA = BaseColour.a;
}
