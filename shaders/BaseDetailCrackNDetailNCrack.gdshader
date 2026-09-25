shader_type spatial;

uniform sampler2D BaseTexture;
uniform sampler2D DetailTexture;
uniform sampler2D CrackTexture;
uniform sampler2D NDetailTexture;
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
	// Place fragment code here.
	vec2 UV3 = vec2(custom0.x, custom0.y);
	vec2 UV4 = vec2(custom0.z, custom0.w);
	vec2 UV5 = vec2(custom1.x, custom1.y);
	vec4 BaseColour = texture(BaseTexture, UV);
	vec4 DetailColour = texture(DetailTexture, UV2);
	vec4 CrackColour = texture(CrackTexture, UV3);
	
	vec4 NDetailColour = texture(NDetailTexture, UV2);
	vec4 NCrackColour = texture(NCrackTexture, UV2);
	vec3 final_color = mix(BaseColour.rgb * DetailColour.rgb, CrackColour.rgb, CrackColour.a);
	vec3 final_normal = mix(NDetailColour.rgb, NCrackColour.rgb, CrackColour.a);
	
	ALBEDO = final_color.rgb;
	SPECULAR = DetailColour.a;
	ROUGHNESS = DetailColour.a;
	NORMAL_MAP = final_normal;
}
