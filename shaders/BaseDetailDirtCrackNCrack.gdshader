shader_type spatial;

uniform sampler2D BaseTexture;
uniform sampler2D DetailTexture;
uniform sampler2D DirtTexture;
uniform sampler2D CrackTexture;
uniform sampler2D NCrackTexture;


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
	vec2 UV3 = vec2(custom0.x, custom0.y);
	vec2 UV4 = vec2(custom0.z, custom0.w);
	vec2 UV5 = vec2(custom1.x, custom1.y);
	vec4 BaseColour = texture(BaseTexture, UV);
	vec4 DetailColour = texture(DetailTexture, UV2);
	vec4 DirtColour = texture(DirtTexture, UV3);
	vec4 NCrackColour = texture(NCrackTexture, UV4);
	vec3 final_color = BaseColour.rgb * DetailColour.rgb * DirtColour.rgb;

	
	ALBEDO = final_color.rgb;
	SPECULAR = DetailColour.a;
	ROUGHNESS = DetailColour.a;
	NORMAL_MAP = NCrackColour.rgb;
}
