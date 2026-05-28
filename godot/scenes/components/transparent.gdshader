shader_type spatial;
render_mode blend_mix, cull_back;

//
// =====================================
// TEXTURE
// =====================================
//

uniform sampler2D grass_texture : source_color;

//
// =====================================
// HEIGHT RANGE
// =====================================
//

uniform float grass_start_height = 2.0;
uniform float grass_end_height = 8.0;
uniform float fade_size = 1.0;

//
// =====================================
// VISIBILITY
// =====================================
//

uniform float alpha_cutoff = 0.2;

varying vec3 world_pos;

//
// =====================================
// VERTEX
// =====================================
//

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

//
// =====================================
// FRAGMENT
// =====================================
//

void fragment() {

	// 🌍 height mask
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

	float height_mask = start_fade * end_fade;

	// ❌ discard invisible grass
	if (height_mask < alpha_cutoff) {
		discard;
	}

	// 🌿 texture
	vec4 tex = texture(grass_texture, UV);

	ALBEDO = tex.rgb;
	ALPHA = tex.a * height_mask;
}