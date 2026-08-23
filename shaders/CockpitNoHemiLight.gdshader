shader_type spatial;
render_mode unshaded;

void vertex() {
	// Called for every vertex the material is visible on.
}
uniform sampler2D DiffuseTexture : source_color;
uniform sampler2D NormalTexture : hint_normal;


void fragment() {
	vec4 ColourTex = texture(DiffuseTexture, UV);
	vec4 NormalTex = texture(NormalTexture, UV);
	ALBEDO = ColourTex.rgb;
	NORMAL = NormalTex.rgb;
	//SPECULAR = ColourTex.a;
}

void light() {
	// Called for every pixel for every light affecting the material.
}
