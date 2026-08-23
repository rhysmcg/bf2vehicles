shader_type spatial;

uniform sampler2D ColorMap : source_color;
uniform sampler2D SplatMap1 : source_color; // Channels R, G, B, A used for DetailMap 1-4
uniform sampler2D SplatMap2 : source_color; // Channels R, G used for DetailMap 5-6

uniform sampler2D DetailMap1 : source_color;
uniform sampler2D DetailMap2 : source_color;
uniform sampler2D DetailMap3 : source_color;
uniform sampler2D DetailMap4 : source_color;
uniform sampler2D DetailMap5 : source_color;
uniform sampler2D DetailMap6 : source_color;

uniform vec3 AmbientColor : source_color = vec3(0.70, 0.67, 0.58); // Mapped from Lightmanager.ambientcolor

// --- New Uniform for Detail Tiling ---
uniform float DetailScale : hint_range(0.1, 100.0) = 10.0;


uniform float DetailFadeStart : hint_range(10.0, 100.0) = 40.0;
uniform float DetailFadeEnd : hint_range(10.0, 150.0) = 80.0;

void fragment() {
	// UV for base ColorMap (non-tiled)
	vec2 BaseUV = UV;
	
	// Tiled UV for high-frequency detail maps
	vec2 DetailUV = UV * DetailScale;
	
	float dist = -VERTEX.z; 
	
	float fade_factor = smoothstep(DetailFadeStart, DetailFadeEnd, dist);
	
	// --- Texture Lookups ---
	vec4 ColourTexTexture = texture(ColorMap, BaseUV);
	
	// Detail Map Lookups (Using Tiled UV)
	// The detail maps are generally grayscale or contain high-frequency color info.
	vec4 DetailMapTexture1 = texture(DetailMap1, DetailUV);
	vec4 DetailMapTexture2 = texture(DetailMap2, DetailUV);
	vec4 DetailMapTexture3 = texture(DetailMap3, DetailUV);
	vec4 DetailMapTexture4 = texture(DetailMap4, DetailUV);
	vec4 DetailMapTexture5 = texture(DetailMap5, DetailUV);
	vec4 DetailMapTexture6 = texture(DetailMap6, DetailUV);
	
	// SplatMap Lookups (Using Base UV)
	vec4 SplatWeights1 = texture(SplatMap1, BaseUV);
	vec4 SplatWeights2 = texture(SplatMap2, BaseUV);

	// --- Detail Blending ---
	
	// 1. Calculate the weighted sum of all detail maps.
	// We assume a blending scheme:
	// Splat1.r -> Detail1, Splat1.g -> Detail2, Splat1.b -> Detail3, Splat1.a -> Detail4
	// Splat2.r -> Detail5, Splat2.g -> Detail6
	vec3 BlendedDetail = 
		DetailMapTexture1.rgb * SplatWeights1.r +
		DetailMapTexture2.rgb * SplatWeights1.g +
		DetailMapTexture3.rgb * SplatWeights1.b +
		DetailMapTexture4.rgb * SplatWeights1.r +
		DetailMapTexture5.rgb * SplatWeights2.g +
		DetailMapTexture6.rgb * SplatWeights2.b;
		
	vec3 DetailColor = BlendedDetail.rgb * ColourTexTexture.rgb;
		
	// 2. Final ALBEDO is the base color (ColorMap) modulated (multiplied) by the blended detail texture.
	// This makes the detail maps act like a high-frequency filter/overlay.
vec3 FinalAlbedo = mix(
		DetailColor, 
		ColourTexTexture.rgb, 
		fade_factor
	);

    // 3. Apply color boost for old-game fidelity (Section 1 in previous response)
    ALBEDO = FinalAlbedo;
	
	//EMISSION = ALBEDO * 0.5;
	//EMISSION = ALBEDO * AmbientColor * 0.1;
	//ALBEDO = ALBEDO * 2.0;

}

void light() {
	// Called for every pixel for every light affecting the material.
	
}