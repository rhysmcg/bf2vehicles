shader_type spatial;

uniform sampler2D BaseTexture;


void fragment() {
	// Place fragment code here.
	vec4 BaseColour = texture(BaseTexture, UV);
}
