shader_type spatial;
render_mode cull_front;

uniform vec4 _color : source_color = vec4(0.3, 0.8, 1.0, 1.0);
uniform float sphere_size = 3.0;
global uniform vec3 player_pos;

varying vec3 world_vertex;

void vertex() {
	world_vertex = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	float min_dist = min(length(player_pos - world_vertex), sphere_size);
	float alpha = clamp(sphere_size - min_dist, 0.0, 1.0);

	// --- DITHER SHADER OPTIMIZATION ---
	// Dithering allows us to simulate transparency without using the expensive 
	// transparent render pass, which is a massive win for mobile WebGL.
	float dither = 0.0;
	{
		// 4x4 Bayer Matrix
		const float bayer[16] = {
			0.0625, 0.5625, 0.1875, 0.6875,
			0.8125, 0.3125, 0.9375, 0.4375,
			0.25, 0.75, 0.125, 0.625,
			1.0, 0.5, 0.875, 0.375
		};
		ivec2 screen_pos = ivec2(FRAGCOORD.xy) % 4;
		dither = bayer[screen_pos.x + screen_pos.y * 4];
	}

	if (alpha < dither) {
		discard;
	}

	ALBEDO = _color.rgb;
}