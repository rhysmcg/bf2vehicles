shader_type spatial;

uniform sampler2D BaseTexture;
uniform sampler2D DetailTexture;
uniform sampler2D NDetailTexture;


void fragment() {
	// Place fragment code here.
	vec4 BaseColour = texture(BaseTexture, UV);
	vec4 DetailColour = texture(DetailTexture, UV2);
	vec4 NDetailColour = texture(NDetailTexture, UV2);
	ALBEDO = BaseColour.rgb * DetailColour.rgb;
	SPECULAR = DetailColour.a;
	ROUGHNESS = DetailColour.a;
	NORMAL_MAP = NDetailColour.rgb;
}
