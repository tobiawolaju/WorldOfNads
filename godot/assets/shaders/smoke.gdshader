shader_type spatial;
// Soft, camera-facing smoke puff for CPUParticles3D. Particles need real alpha,
// so this blends (rather than the opaque-pass dither trick) and uses a radial
// falloff plus fbm noise so each particle reads as a round wisp instead of a
// flat quad. COLOR carries the particle's own colour/alpha: COLOR.a fades each
// puff in/out over its lifetime, COLOR.r randomises its spin + noise offset.
render_mode blend_mix, cull_disabled, unshaded, billboard, depth_draw_never;

uniform vec4 smoke_color : source_color = vec4(0.45, 0.8, 0.4, 1.0);
uniform float softness : hint_range(0.0, 1.0) = 0.5;
uniform float density : hint_range(0.0, 1.0) = 0.75;
uniform float cloud_alpha : hint_range(0.0, 1.0) = 1.0;

varying vec2 puff_uv;
varying vec4 puff_color;

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
	puff_uv = UV;
	puff_color = COLOR;
}

void fragment() {
	// Spin the puff's UV by a per-particle angle (COLOR.r), so overlapping
	// particles do not stack the same noise pattern.
	float angle = puff_color.r * 6.28318530718;
	float s = sin(angle);
	float c = cos(angle);
	vec2 centered = puff_uv - vec2(0.5);
	vec2 spun = vec2(centered.x * c - centered.y * s, centered.x * s + centered.y * c);

	float r = length(spun * 2.0);
	float mask = 1.0 - smoothstep(softness, 1.0, r);
	float n = fbm((spun + vec2(0.5)) * 4.0 + puff_color.r * 9.0);
	float alpha = mask * density * cloud_alpha * puff_color.a * (0.5 + 0.6 * n);

	ALBEDO = smoke_color.rgb * (0.8 + 0.4 * n);
	ALPHA = clamp(alpha, 0.0, 1.0);
}
