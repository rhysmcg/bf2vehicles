shader_type spatial;
render_mode cull_disabled, depth_draw_always, alpha_to_coverage;

void vertex() {
	// Called for every vertex the material is visible on.
}
uniform sampler2D Colour : source_color;
uniform sampler2D Normal_os : hint_normal;
uniform sampler2D Normal_b : hint_normal;
uniform float alpha_threshold : hint_range(0.0, 1.0);


void fragment() {
	vec4 ColourTex = texture(Colour, UV);
	vec4 NormalTex = texture(Normal_os, UV);
	vec4 Normal_bTex = texture(Normal_b, UV);
    // If the alpha value of the fragment is below the threshold, discard it
    if (ColourTex.a < alpha_threshold) {
        discard;
    }

	ALBEDO = ColourTex.rgb;
	ALPHA = ColourTex.a;
	//NORMAL = Normal_bTex.rgb;
	//SPECULAR = Normal_bTex.a;

}
