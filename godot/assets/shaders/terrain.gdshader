shader_type spatial;

//
// =====================================
// TEXTURES
// =====================================
//

uniform sampler2D low_albedo : source_color;
uniform sampler2D grass_albedo : source_color;
uniform sampler2D rock_albedo : source_color;
uniform sampler2D snow_albedo : source_color;

//
// grass patch mask
// white = grass
// black = rocky patches
//

uniform sampler2D grass_patch_mask : source_color;


//
// =====================================
// HEIGHTS
// =====================================
//

uniform float grass_start = 4.0;
uniform float rock_start = 20.0;
uniform float snow_start = 42.0;

uniform float transition = 1.5;


//
// =====================================
// TRIPLANAR
// =====================================
//

uniform float texture_scale = 10.0;
uniform float blend_sharpness = 8.0;


//
// =====================================
// BREAKUP
// =====================================
//

uniform float breakup_scale = 18.0;
uniform float breakup_strength = 2.5;


//
// =====================================
// GRASS PATCHES
// =====================================
//

//
// how far into grass biome
// patches can exist
//

uniform float grass_patch_height_percent = 0.25;

//
// strength of rocky patches
//

uniform float grass_patch_strength = 1.0;

//
// mask scale
//

uniform float grass_patch_scale = 80.0;


//
// =====================================
// CLIFFS
// =====================================
//

uniform float cliff_start = 0.35;
uniform float cliff_hardness = 8.0;


//
// =====================================
// VARYINGS
// =====================================
//

varying vec3 world_pos;
varying vec3 world_normal;


//
// =====================================
// VERTEX
// =====================================
//

void vertex() {

	world_pos =
		(MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;

	world_normal = normalize(
		(MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz
	);
}


//
// =====================================
// TRIPLANAR
// =====================================
//

vec4 triplanar(
	sampler2D tex,
	vec3 pos,
	vec3 normal
) {

	vec3 blend = abs(normal);

	blend = pow(
		blend,
		vec3(blend_sharpness)
	);

	blend /= (
		blend.x +
		blend.y +
		blend.z
	);

	vec2 x_uv = pos.yz / texture_scale;
	vec2 y_uv = pos.xz / texture_scale;
	vec2 z_uv = pos.xy / texture_scale;

	vec4 x = texture(tex, x_uv);
	vec4 y = texture(tex, y_uv);
	vec4 z = texture(tex, z_uv);

	return
		x * blend.x +
		y * blend.y +
		z * blend.z;
}



//
// =====================================
// TERRAIN BREAKUP NOISE
// =====================================
//

float terrain_noise(vec3 pos) {

	vec2 uv = pos.xz / breakup_scale;

	return texture(
		grass_albedo,
		uv
	).r;
}



//
// =====================================
// FRAGMENT
// =====================================
//

void fragment() {

	//
	// =================================
	// WORLD DATA
	// =================================
	//

	float h = world_pos.y;

	vec3 n = normalize(world_normal);

	//
	// =================================
	// BIOME BREAKUP
	// =================================
	//

	float noise = terrain_noise(world_pos);

	h += (noise - 0.5) * breakup_strength;

	//
	// =================================
	// CLIFF MASK
	// =================================
	//

	float slope = 1.0 - n.y;

	float cliff_mask = smoothstep(
		cliff_start,
		1.0,
		pow(slope, cliff_hardness)
	);

	//
	// =================================
	// SAMPLE TEXTURES
	// =================================
	//

	vec4 low = triplanar(
		low_albedo,
		world_pos,
		n
	);

	vec4 grass = triplanar(
		grass_albedo,
		world_pos,
		n
	);

	vec4 rock = triplanar(
		rock_albedo,
		world_pos,
		n
	);

	vec4 snow = triplanar(
		snow_albedo,
		world_pos,
		n
	);

	//
	// =================================
	// BASE TERRAIN
	// =================================
	//

	vec3 terrain;

	//
	// SNOW
	//

	if (h >= snow_start) {

		float t = smoothstep(
			snow_start,
			snow_start + transition,
			h
		);

		terrain = mix(
			rock.rgb,
			snow.rgb,
			t
		);
	}

	//
	// ROCK
	//

	else if (h >= rock_start) {

		float t = smoothstep(
			rock_start,
			rock_start + transition,
			h
		);

		terrain = mix(
			grass.rgb,
			rock.rgb,
			t
		);
	}

	//
	// GRASS
	//

	else if (h >= grass_start) {

		float t = smoothstep(
			grass_start,
			grass_start + transition,
			h
		);

		terrain = mix(
			low.rgb,
			grass.rgb,
			t
		);

		//
		// =============================
		// GRASS ROCK PATCHES
		// =============================
		//

		float grass_zone_height =
			rock_start - grass_start;

		float patch_limit =
			grass_start +
			(grass_zone_height *
			grass_patch_height_percent);

		//
		// fade patches upward
		//

		float patch_height_fade =
			1.0 -
			smoothstep(
				grass_start,
				patch_limit,
				h
			);

		//
		// sample patch mask
		//

		vec2 patch_uv =
			world_pos.xz /
			grass_patch_scale;

		float patch_mask =
			texture(
				grass_patch_mask,
				patch_uv
			).r;

		//
		// invert mask
		// black = rock patches
		//

		patch_mask =
			1.0 - patch_mask;

		patch_mask *=
			patch_height_fade;

		patch_mask *=
			grass_patch_strength;

		//
		// blend rocky dirt patches
		//

		terrain = mix(
			terrain,
			rock.rgb,
			patch_mask
		);
	}

	//
	// LOW
	//

	else {

		terrain = low.rgb;
	}

	//
	// =================================
	// CLIFF OVERRIDE
	// =================================
	//

	terrain = mix(
		terrain,
		low.rgb,
		cliff_mask
	);

	//
	// =================================
	// FINAL
	// =================================
	//

	ALBEDO = terrain;

	ROUGHNESS = 0.96;

	SPECULAR = 0.03;
}