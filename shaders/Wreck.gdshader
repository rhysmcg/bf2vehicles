shader_type spatial;

void vertex() {
	// Called for every vertex the material is visible on.
}
uniform sampler2D DiffuseTexture : source_color;
uniform sampler2D NormalTexture : source_color;


void fragment() {
	vec4 ColourTex = texture(DiffuseTexture, UV);
	vec4 NormalTex = texture(NormalTexture, UV);
	ALBEDO = ColourTex.rgb * NormalTex.rgb;
	SPECULAR = NormalTex.a;
}

void light() {
	// Called for every pixel for every light affecting the material.
}
