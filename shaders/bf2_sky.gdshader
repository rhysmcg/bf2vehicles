shader_type sky;


uniform vec4 viewProjMatrix;
uniform vec4 texOffset;
uniform vec4 texOffset2;

uniform vec4 flareParams;
uniform vec4 underwaterFog;
uniform vec2 fadeOutDist;
uniform vec2 cloudLerpFactors;
uniform float lightingBlend;
uniform vec3 lightingColor;
uniform sampler2D texture0;
uniform sampler2D texture1;
uniform sampler2D texture2;


void sky() {

    // Sample the sky texture using spherical coordinates
	vec4 ColourTex = texture(texture0, vec2(1.0,1.0));
   	COLOR = ColourTex.rgb;
}
