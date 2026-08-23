shader_type spatial;

// Texture uniforms
uniform sampler2D texture_base : source_color;
uniform sampler2D texture_detail : source_color;
uniform sampler2D texture_dirt : source_color;
uniform sampler2D texture_crack : source_color;
uniform sampler2D texture_detail_normal : hint_normal;
uniform sampler2D texture_crack_normal : hint_normal;

// Feature flags
uniform bool has_alpha = false;
uniform bool has_dirt = false;
uniform bool has_crack = false;
uniform bool has_crack_normal = false;
uniform bool has_detail_normal = true;
uniform bool show_diffuse = true;
uniform bool show_lighting = true;

// Lighting parameters
uniform vec3 sun_ambient : source_color = vec3(0.3, 0.3, 0.3);
uniform vec3 sun_diffuse : source_color = vec3(0.7, 0.7, 0.7);
uniform vec3 sun_direction = vec3(0.5, -0.5, 0.5);
uniform float specular_power = 100.0;
uniform float specular_intensity = 1.0;

void fragment() {
	// Sample all textures
	vec4 base_map = texture(texture_base, UV);
	vec4 detail_map = texture(texture_detail, UV2);
	vec4 dirt_map = vec4(1.0);
	vec4 crack_map = vec4(0.0);
	vec4 detail_normal_map = vec4(0.5, 0.5, 1.0, 1.0);
	vec4 crack_normal_map = vec4(0.5, 0.5, 1.0, 1.0);
	
	// Conditional texture sampling based on feature flags
	// This mimics the complex conditional logic in the original shader
	if (has_dirt) {
		dirt_map = texture(texture_dirt, UV2);
		if (has_crack) {
			detail_normal_map = texture(texture_detail_normal, UV2);
			crack_map = texture(texture_crack, UV2);
			crack_normal_map = texture(texture_crack_normal, UV2);
		} else if (has_detail_normal) {
			detail_normal_map = texture(texture_detail_normal, UV2);
		}
	} else {
		if (has_crack) {
			detail_normal_map = texture(texture_detail_normal, UV2);
			crack_map = texture(texture_crack, UV2);
			crack_normal_map = texture(texture_crack_normal, UV2);
		} else if (has_detail_normal) {
			detail_normal_map = texture(texture_detail_normal, UV2);
		}
	}
	
	// Initialize output color
	vec3 frag_color = vec3(1.0);
	vec3 spec_mask = vec3(1.0);
	
	// Diffuse calculation
	if (show_diffuse) {
		frag_color = base_map.rgb * detail_map.rgb;
	} else {
		frag_color = vec3(0.75);
	}
	
	// Alpha handling
	float alpha_value = 1.0;
	if (has_alpha) {
		alpha_value = detail_map.a;
	}
	
	// Crack blending
	if (has_crack) {
		if (show_diffuse) {
			frag_color = mix(frag_color, crack_map.rgb, crack_map.a);
		}
	}
	
	// Dirt application
	if (has_dirt) {
		if (show_diffuse) {
			frag_color *= dirt_map.rgb;
		}
		// Reduce specularity where dirt is present
		float dirt_factor = dirt_map.r * dirt_map.g * dirt_map.b;
		spec_mask *= dirt_factor;
	}
	
	// Specular mask from texture alpha
	if (has_alpha) {
		if (has_detail_normal) {
			spec_mask *= detail_normal_map.a;
		}
	} else {
		spec_mask *= detail_map.a;
	}
	
	// Normal map calculation
	vec3 normal_tangent = vec3(0.0, 0.0, 1.0);
	if (has_detail_normal) {
		// Convert from [0,1] to [-1,1]
		normal_tangent = detail_normal_map.rgb * 2.0 - 1.0;
		
		// Blend with crack normal if present
		if (has_crack && has_crack_normal) {
			vec3 crack_normal = crack_normal_map.rgb * 2.0 - 1.0;
			normal_tangent = mix(normal_tangent, crack_normal, crack_map.a);
		}
		
		normal_tangent = normalize(normal_tangent);
	}
	
	// Custom lighting (when show_lighting is enabled)
	if (show_lighting) {
		// Normalize sun direction
		vec3 sun_dir = normalize(sun_direction);
		
		// Calculate N·L
		float ndotl = dot(normal_tangent, -sun_dir);
		
		// Apply ambient and diffuse lighting
		vec3 lighting = sun_ambient + sun_diffuse * max(ndotl, 0.0);
		frag_color *= lighting;
		
		// Specular calculation (Blinn-Phong)
		if (ndotl > 0.0) {
			vec3 view_dir = normalize(VIEW);
			vec3 half_vec = normalize(-sun_dir + view_dir);
			float ndoth = max(dot(normal_tangent, half_vec), 0.0);
			vec3 spec_color = pow(ndoth, specular_power) * spec_mask * specular_intensity;
			frag_color += sun_diffuse * spec_color;
		}
	}
	
	// Output
	ALBEDO = frag_color;
	ALPHA = alpha_value;
	
	// Apply normal map when detail normal is enabled
	if (has_detail_normal) {
		NORMAL_MAP = normal_tangent;
	}
	
	// Set up PBR properties
	// Note: Original shader uses custom lighting, so we disable Godot's lighting when show_lighting is true
	if (show_lighting) {
		// Use unshaded to prevent double-lighting
		EMISSION = frag_color;
		ALBEDO = vec3(0.0);
	}
	
	// Specular/Roughness for when using Godot's built-in lighting
	if (!show_lighting) {
		SPECULAR = 0.5;
		ROUGHNESS = 1.0 - (spec_mask.r * 0.5); // Convert spec mask to roughness
	}
}