shader_type spatial;
// Unshaded camera-facing puff. Rendered in the OPAQUE pass with a Bayer dither
// instead of alpha blending, so smoke costs no transparent pass - the same trick
// as proximityfade.gdshader, which matters a lot on mobile WebGL.
render_mode unshaded, cull_disabled, depth_draw_opaque, billboard;

uniform vec4 smoke_color : source_color = vec4(0.72, 0.74, 0.76, 1.0);
uniform float density : hint_range(0.0, 1.0) = 0.85;
uniform float dissolve = 0.0;
uniform float uv_rot = 0.0;
uniform float fade : hint_range(0.0, 1.0) = 1.0;

varying vec2 puff_uv;

float hash21(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453123);
}

float value_noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	float a = hash21(i);
	float b = hash21(i + vec2(1.0, 0.0));
	float c = hash21(i + vec2(0.0, 1.0));
	float d = hash21(i + vec2(1.0, 1.0));
	return mix(mix(a, b, u.x), mix(c, d, u.x), u.y);
}

float fbm(vec2 p) {
	float v = 0.0;
	float amp = 0.5;
	for (int i = 0; i < 3; i++) {
		v += amp * value_noise(p);
		p *= 2.03;
		amp *= 0.5;
	}
	return v;
}

void vertex() {
	// Per-puff UV spin so overlapping puffs do not share the same noise pattern.
	float s = sin(uv_rot);
	float c = cos(uv_rot);
	vec2 centered = UV - vec2(0.5);
	puff_uv = vec2(centered.x * c - centered.y * s, centered.x * s + centered.y * c) + vec2(0.5);
}

void fragment() {
	vec2 centered = puff_uv * 2.0 - 1.0;
	float r = length(centered);
	float mask = 1.0 - smoothstep(0.35, 1.0, r);
	float n = fbm(puff_uv * 4.0 + dissolve);
	float alpha = mask * density * fade * (0.55 + 0.5 * n);

	// --- 4x4 BAYER DITHER ---
	// Simulates soft transparency without the expensive transparent render pass.
	const float bayer[16] = {
		0.0, 8.0, 2.0, 10.0,
		12.0, 4.0, 14.0, 6.0,
		3.0, 11.0, 1.0, 9.0,
		15.0, 7.0, 13.0, 5.0
	};
	ivec2 screen_pos = ivec2(FRAGCOORD.xy) % 4;
	float dither = (bayer[screen_pos.x + screen_pos.y * 4] + 0.5) / 16.0;

	if (alpha < dither) {
		discard;
	}

	ALBEDO = smoke_color.rgb * (0.85 + 0.35 * n);
}
