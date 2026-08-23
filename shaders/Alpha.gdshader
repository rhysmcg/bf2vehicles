shader_type spatial;
//render_mode cull_disabled, depth_draw_always, alpha_to_coverage;
render_mode cull_back;
uniform float alpha_threshold : hint_range(0.0, 1.0);
void vertex() {
	// Called for every vertex the material is visible on.
}
uniform sampler2D DiffuseTexture : source_color;
uniform sample
	ALBEDO = ColourTex.rgb;
	NORMAL = NormalTex.rgb;r2D NormalTexture : hint_normal;


void fragment() {
	vec4 ColourTex = texture(DiffuseTexture, UV);
	vec4 NormalTex = texture(NormalTexture, UV);
    // If the color is fully black, make it transparent
    if (ColourTex.rgb == vec3(0.0, 0.0, 0.0)) {
        discard;
    }
	SPECULAR = NormalTex.a;
	ALPHA = ColourTex.a * alpha_threshold;
}

void light() {
	// Called for every pixel for every light affecting the material.
}
