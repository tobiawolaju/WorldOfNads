shader_type spatial;


render_mode depth_draw_opaque,
cull_disabled,
diffuse_burley,
specular_schlick_ggx;


//
// ======================================================
// ALBEDO COLOR
// ======================================================
//

uniform vec4 albedo : source_color =
	vec4(0.3, 0.8, 0.3, 1.0);


//
// ======================================================
// TEXTURES
// ======================================================
//

uniform sampler2D texture_albedo :
	source_color,
	filter_linear_mipmap,
	repeat_enable;

uniform sampler2D texture_metallic :
	hint_default_white,
	filter_linear_mipmap,
	repeat_enable;

uniform sampler2D texture_roughness :
	hint_roughness_r,
	filter_linear_mipmap,
	repeat_enable;

uniform sampler2D texture_normal :
	hint_roughness_normal,
	filter_linear_mipmap,
	repeat_enable;


//
// ======================================================
// MATERIAL
// ======================================================
//

uniform float roughness :
	hint_range(0.0, 1.0) = 1.0;

uniform float metallic :
	hint_range(0.0, 1.0) = 0.0;

uniform float specular :
	hint_range(0.0, 1.0) = 0.2;

uniform float normal_scale :
	hint_range(-16.0, 16.0) = 1.0;


//
// ======================================================
// UV
// ======================================================
//

uniform vec3 uv1_scale = vec3(1.0);
uniform vec3 uv1_offset = vec3(0.0);


//
// ======================================================
// HEIGHT FILTER
// ======================================================
//

uniform float grass_start_height = 2.0;
uniform float grass_end_height = 8.0;

uniform float fade_size = 1.0;

uniform float alpha_cutoff = 0.2;


//
// ======================================================
// MESH ROTATION
// ======================================================
//

uniform vec3 mesh_rotation_degrees =
	vec3(0.0);


//
// ======================================================
// WORLD POSITION
// ======================================================
//

varying vec3 world_pos;


//
// ======================================================
// ROTATION HELPERS
// ======================================================
//

mat3 rotation_x(float angle) {

	float s = sin(angle);
	float c = cos(angle);

	return mat3(
		vec3(1.0, 0.0, 0.0),
		vec3(0.0, c, -s),
		vec3(0.0, s, c)
	);
}

mat3 rotation_y(float angle) {

	float s = sin(angle);
	float c = cos(angle);

	return mat3(
		vec3(c, 0.0, s),
		vec3(0.0, 1.0, 0.0),
		vec3(-s, 0.0, c)
	);
}

mat3 rotation_z(float angle) {

	float s = sin(angle);
	float c = cos(angle);

	return mat3(
		vec3(c, -s, 0.0),
		vec3(s, c, 0.0),
		vec3(0.0, 0.0, 1.0)
	);
}


//
// ======================================================
// VERTEX
// ======================================================
//

void vertex() {

	//
	// UV
	//

	UV =
		UV * uv1_scale.xy +
		uv1_offset.xy;

	//
	// ROTATION
	//

	vec3 rot =
		radians(mesh_rotation_degrees);

	mat3 rx = rotation_x(rot.x);
	mat3 ry = rotation_y(rot.y);
	mat3 rz = rotation_z(rot.z);

	VERTEX =
		rz * ry * rx * VERTEX;

	NORMAL =
		normalize(
			rz * ry * rx * NORMAL
		);

	//
	// WORLD POSITION
	//

	world_pos =
		(MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}


//
// ======================================================
// FRAGMENT
// ======================================================
//

void fragment() {

	vec2 base_uv = UV;

	//
	// ==================================================
	// HEIGHT MASK
	// ==================================================
	//

	float start_fade = smoothstep(
		grass_start_height,
		grass_start_height + fade_size,
		world_pos.y
	);

	float end_fade = 1.0 - smoothstep(
		grass_end_height - fade_size,
		grass_end_height,
		world_pos.y
	);

	float height_mask =
		start_fade * end_fade;

	//
	// DISCARD INVISIBLE
	//

	if (height_mask < alpha_cutoff) {
		discard;
	}

	//
	// ==================================================
	// TEXTURES
	// ==================================================
	//

	vec4 albedo_tex =
		texture(texture_albedo, base_uv);

	//
	// ==================================================
	// FINAL MATERIAL
	// ==================================================
	//

	// PNG RGB ignored
	// only shader color used

	ALBEDO = albedo.rgb;

	METALLIC = metallic;

	ROUGHNESS = roughness;

	SPECULAR = specular;

	//
	// ==================================================
	// FINAL ALPHA
	// ==================================================
	//

	// PNG alpha controls grass shape

	ALPHA =
		albedo_tex.a *
		albedo.a *
		height_mask;

	if (ALPHA < alpha_cutoff) {
		discard;
	}
}
