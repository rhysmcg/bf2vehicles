shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_lambert, specular_schlick_ggx;

// === Per-Chunk Textures (all use UV 0-1 per chunk) ===
uniform sampler2D ColorMap : source_color, filter_linear_mipmap, repeat_disable;
uniform sampler2D LightMap : source_color, filter_linear_mipmap, repeat_disable;
uniform sampler2D SplatMap1 : source_color, filter_linear_mipmap, repeat_disable; // R,G,B,A -> Detail 1-4
uniform sampler2D SplatMap2 : source_color, filter_linear_mipmap, repeat_disable; // R,G -> Detail 5-6
uniform sampler2D LowDetailComponent : source_color, filter_linear_mipmap, repeat_disable; // Controls low detail blending

// === Shared Detail Textures (tiled within the chunk UV space) ===
uniform sampler2D DetailMap1 : source_color, filter_linear_mipmap, repeat_enable;
uniform sampler2D DetailMap2 : source_color, filter_linear_mipmap, repeat_enable;
uniform sampler2D DetailMap3 : source_color, filter_linear_mipmap, repeat_enable;
uniform sampler2D DetailMap4 : source_color, filter_linear_mipmap, repeat_enable;
uniform sampler2D DetailMap5 : source_color, filter_linear_mipmap, repeat_enable;
uniform sampler2D DetailMap6 : source_color, filter_linear_mipmap, repeat_enable;

// === Shared Low Detail Texture (contains 3 textures in RGB channels) ===
// R channel: LowDetailType 2 (horizontal/flat rocky surfaces)
// G channel: LowDetailType 2 (vertical/steep rocky surfaces)
// B channel: LowDetailType 1 (bumpy surfaces like grass/sand/gravel)
// LowDetailType 0 (smooth surfaces like tarmac/beach sand) = no low detail
uniform sampler2D LowDetailMap : source_color, filter_linear_mipmap, repeat_enable;

// === Tiling Parameters (relative to UV 0-1 of chunk) ===
uniform float DetailTiling : hint_range(1.0, 64.0) = 16.0;        // How many times detail textures repeat per chunk
uniform float FarTopTilingHi : hint_range(1.0, 32.0) = 6.0;       // Low detail type 1 tiling (grass/sand)
uniform float FarSideTiling : hint_range(1.0, 64.0) = 16.0;       // Low detail type 2 side tiling (rocky slopes)

// === Blend Parameters ===
uniform float BlendStart : hint_range(0.0, 200.0) = 50.0;  // Distance where blending starts
uniform float BlendEnd : hint_range(0.0, 500.0) = 150.0;   // Distance where low detail takes over
uniform vec3 BlendMod : source_color = vec3(0.2, 0.5, 0.2); // Normal blend modifiers for triplanar

// === Lighting Parameters ===
uniform vec4 SunColor : source_color = vec4(1.0, 0.95, 0.8, 1.0);
uniform float SunIntensity : hint_range(0.0, 4.0) = 2.0;
uniform vec4 GIColor : source_color = vec4(0.4, 0.5, 0.6, 1.0);

void fragment() {
	// === Use UV for everything (0-1 per chunk) ===
	vec2 base_uv = UV;
	vec2 detail_uv = UV * DetailTiling;

	// === Sample Per-Chunk Textures ===
	vec3 color_map = texture(ColorMap, base_uv).rgb;
	vec4 light_map = texture(LightMap, base_uv);
	vec4 splat_weights1 = texture(SplatMap1, base_uv);
	vec4 splat_weights2 = texture(SplatMap2, base_uv);
	vec4 low_component = texture(LowDetailComponent, base_uv);

	// === Calculate Normal-Based Blending ===
	vec3 world_normal = normalize((INV_VIEW_MATRIX * vec4(NORMAL, 0.0)).xyz);
	vec3 blend_weights = max(abs(world_normal) - BlendMod, vec3(0.0));
	float blend_sum = blend_weights.x + blend_weights.y + blend_weights.z;
	blend_weights /= max(blend_sum, 0.001);

	// === Distance-Based Blend Factor ===
	float camera_distance = length(VERTEX);
	float distance_blend = clamp((camera_distance - BlendStart) / (BlendEnd - BlendStart), 0.0, 1.0);

	// === Sample Detail Maps (tiled within chunk) ===
	vec3 detail1 = texture(DetailMap1, detail_uv).rgb;
	vec3 detail2 = texture(DetailMap2, detail_uv).rgb;
	vec3 detail3 = texture(DetailMap3, detail_uv).rgb;
	vec3 detail4 = texture(DetailMap4, detail_uv).rgb;
	vec3 detail5 = texture(DetailMap5, detail_uv).rgb;
	vec3 detail6 = texture(DetailMap6, detail_uv).rgb;

	// === Blend Detail Maps Based on Splat Weights ===
	vec3 detail_combined =
		detail1 * splat_weights1.r +
		detail2 * splat_weights1.g +
		detail3 * splat_weights1.b +
		detail4 * splat_weights1.a +
		detail5 * splat_weights2.r +
		detail6 * splat_weights2.g;

	// === Sample Low Detail Map ===
	// The low detail map contains 3 different textures in RGB channels
	// Sample with different tiling based on surface type
	vec2 low_detail_uv_top = UV * FarTopTilingHi;    // For grass/sand (type 1)
	vec2 low_detail_uv_side = UV * FarSideTiling;    // For rocky surfaces (type 2)

	vec3 low_detail_y = texture(LowDetailMap, low_detail_uv_top).rgb;
	vec3 low_detail_x = texture(LowDetailMap, low_detail_uv_side).rgb;
	vec3 low_detail_z = texture(LowDetailMap, low_detail_uv_side).rgb;

	// === Apply Low Detail Based on Surface Type ===
	// low_component.r controls blend amount
	// low_component.b controls "mounten" (rocky) factor

	// Calculate which low detail channel to use based on normal
	// Flat surfaces (Y-plane): use B channel (type 1 - grass/sand)
	// Steep surfaces (X/Z-plane): use G channel (type 2 - vertical rock)
	float low_detail_flat = low_detail_y.b;  // Type 1: grass/sand/gravel
	float low_detail_steep = (low_detail_x.g * blend_weights.x +
	                           low_detail_y.r * blend_weights.y +  // Type 2 horizontal
	                           low_detail_z.g * blend_weights.z);  // Type 2 vertical

	// Blend between flat and steep based on surface angle
	float mounten = mix(low_detail_flat, low_detail_steep, blend_weights.x + blend_weights.z);

	// Apply low detail component control
	// low_component.r = blend factor
	// low_component.b = mountain factor (makes slopes more rocky)
	float low_detail_value = mix(0.5, mounten, low_component.r);

	// Apply mountain enhancement factor (from BF2 shader)
	low_detail_value *= (4.0 * mix(0.5, mounten, low_component.b));

	// === Combine Detail and Low Detail Based on Distance ===
	// Close up: use detail textures
	// Far away: blend to low detail
	vec3 both_detail = detail_combined * low_detail_value;
	vec3 combined_detail = mix(both_detail * 2.0, vec3(low_detail_value), distance_blend);

	// === Apply Color Map ===
	vec3 base_color = color_map * combined_detail;

	// === Lighting Calculation ===
	// BF2 Lightmap channel breakdown (confirmed from Photoshop inspection):
	// .r (red) = Water mask (white = water, black = ground)
	// .g (green) = Direct light/shadows (white = lit, black = shadow)
	// .b (blue) = Ambient/sky light (white = lit, black = shadow, blurry/soft)
	// .a (alpha) = Sun occlusion factor (0 = shadowed, 1 = full sun)

	// Direct sun lighting (uses alpha channel for occlusion)
	vec3 sun_light = light_map.g * SunColor.rgb * SunIntensity;

	// Ambient/indirect lighting (uses blue channel - the blurry ambient light)
	vec3 ambient_light = light_map.b * GIColor.rgb;

	// Combine lighting
	vec3 accumulated_light = sun_light + ambient_light;

	// Optional: Use green channel as additional direct light multiplier
	// (This might be redundant with alpha, so test with/without)
	accumulated_light *= light_map.b;

	// === Final Output ===
	// BF2 multiplies by 2 at the end
	vec3 final_color = base_color * accumulated_light * 2.0;

	ALBEDO = final_color;

	// Terrain is non-metallic and rough
	METALLIC = 0.0;
	ROUGHNESS = 0.9;
}