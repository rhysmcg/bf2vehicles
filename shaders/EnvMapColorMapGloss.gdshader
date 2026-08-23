shader_type spatial;

void vertex() {
	// Called for every vertex the material is visible on.
}
uniform sampler2D DiffuseTexture : source_color;
uniform sampler2D NormalTexture : hint_normal;
uniform sampler2D EnvMapTexture : source_color;

void fragment() {
	vec4 ColourTex = texture(DiffuseTexture, UV);
	vec4 NormalTex = texture(NormalTexture, UV);
	vec4 EnvMapTex = textureProj(EnvMapTexture,INV_PROJECTION_MATRIX*INV_VIEW_MATRIX*vec4(VIEW,0));

	ALBEDO = mix(ColourTex.rgb, EnvMapTex.rgb, ColourTex.a);
	NORMAL = NormalTex.rgb;
	SPECULAR = NormalTex.a;
}

void light() {
	// Called for every pixel for every light affecting the material.
}
