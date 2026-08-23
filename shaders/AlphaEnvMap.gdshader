shader_type spatial;
//render_mode cull_disabled, depth_prepass_alpha;
render_mode blend_mix,depth_draw_opaque,cull_back,diffuse_burley,specular_disabled,unshaded,shadows_disabled,world_vertex_coords,ambient_light_disabled,depth_prepass_alpha;
void vertex() {
	// Called for every vertex the material is visible on.
}
uniform sampler2D DiffuseTexture : source_color;
uniform sampler2D NormalTexture : hint_normal;
uniform sampler2D EnvMapTexture : source_color;

void fragment() {


	vec4 ColourTex = texture(DiffuseTexture, UV);
	vec4 NormalTex = texture(NormalTexture, UV);
	vec4 EnvMapTex = textureProj(EnvMapTexture,INV_PROJECTION_MATRIX*INV_VIEW_MATRIX*vec4(VIEW,0));
	//vec3 EnvMapTex = texture(EnvMapTexture, vec2(reflectionDir.z, reflectionDir.x)).rgb;

	ALBEDO = mix(ColourTex.rgb, EnvMapTex.rgb, ColourTex.a);
	NORMAL = NormalTex.rgb;
	SPECULAR = NormalTex.a;
	ALPHA = ColourTex.a;
}

void light() {
	// Called for every pixel for every light affecting the material.
}
