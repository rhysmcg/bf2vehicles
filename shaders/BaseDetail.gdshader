shader_type spatial;

uniform sampler2D BaseTexture;
uniform sampler2D DetailTexture;


void fragment() {
	// Place fragment code here.
	vec4 BaseColour = texture(BaseTexture, UV);
	vec4 DetailColour = texture(DetailTexture, UV2);

	ALBEDO = BaseColour.rgb * DetailColour.rgb;
	SPECULAR = DetailColour.a;
	ROUGHNESS = DetailColour.a;
}
