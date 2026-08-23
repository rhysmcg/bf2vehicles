shader_type spatial;

void vertex() {
	// Called for every vertex the material is visible on.
}
uniform sampler2D Colour : source_color;
uniform sampler2D Normal_os : hint_normal;
uniform sampler2D Normal_b : hint_normal;

void fragment() {
	vec4 ColourTex = texture(Colour, UV);
	vec4 NormalTex = texture(Normal_os, UV);
	vec4 Normal_bTex = texture(Normal_b, UV);
	ALBEDO = ColourTex.rgb;
	NORMAL = normalize(TANGENT * NormalTex.x + BINORMAL * NormalTex.y + NORMAL * NormalTex.z) * Normal_bTex.rgb;
}

void light() {
	// Called for every pixel for every light affecting the material.
}
