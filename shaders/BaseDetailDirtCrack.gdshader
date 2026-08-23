shader_type spatial;

uniform sampler2D BaseTexture;
uniform sampler2D DetailTexture;
uniform sampler2D DirtTexture;
uniform sampler2D CrackTexture;

varying vec4 custom0;
varying vec4 custom1;
varying vec4 custom2;
varying vec4 custom3;

void vertex() {
	UV=UV;
	UV2=UV2;
	custom0=CUSTOM0;
	custom1=CUSTOM1;
}


void fragment() {
	// Place fragment code here.
	vec2 UV3 = vec2(custom0.w, custom0.x);
	vec2 UV4 = vec2(custom0.y, custom0.z);
	vec2 UV5 = vec2(custom1.w, custom1.x);
	vec4 BaseColour = texture(BaseTexture, UV);
	vec4 DetailColour = texture(DetailTexture, UV2);
	vec4 DirtColour = texture(DirtTexture, UV3);
	vec4 CrackColour = texture(CrackTexture, UV4);
	
	ALBEDO = BaseColour.rgb * DetailColour.rgb * CrackColour.rgb;
	SPECULAR = DetailColour.a;
	ROUGHNESS = DetailColour.a;
}
