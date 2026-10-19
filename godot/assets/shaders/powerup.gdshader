// powerup.gdshader
// ---------------------------------------------------------------------------
// Power-up AURA, ported to 3D from the original 2D canvas_item aura.
//
// It is drawn on a billboarded quad that wraps the player (player.gd builds it),
// so - like the 2D original - UV spans the whole card and a soft radial falloff
// grows an animated glow *around* the character, rather than an outline. The
// character itself is drawn over the middle of the card (depth test), so only
// the surrounding glow shows.
//
// PERFORMANCE: this card can cover a big part of the screen, and the project
// runs the GL Compatibility renderer, so two things matter here:
//   1. The noise uses a sin-free hash. The original `random()` spent two sin()
//      calls per lattice corner, i.e. ~24 transcendentals per pixel, and that
//      dominated the effect's whole cost. The hash below is pure ALU and gives
//      the same kind of gradient input, so the noise looks the same but is far
//      cheaper.
//   2. Fragments whose glow is already effectively zero are discarded before
//      any noise is computed, which keeps the work off the card's corners and
//      outer edge (and off the blend hardware for those pixels).
//
// Applied from godot/scripts/player.gd via apply_powerup_visual().
// ---------------------------------------------------------------------------
shader_type spatial;
render_mode unshaded, blend_add, cull_disabled, depth_draw_never;

// Overall strength (kept from the original). Fade this 0..1 for an in/out.
uniform float AuraProgres : hint_range(0.0, 1.0, 0.01) = 1.0;
// Global colour multiplier over everything below.
uniform vec4 tint : source_color = vec4(1.0, 1.0, 1.0, 1.0);
// The two colours the aura swirls between. Tint them for different power-ups.
uniform vec4 color_a : source_color = vec4(0.2, 0.75, 1.0, 1.0);
uniform vec4 color_b : source_color = vec4(1.0, 0.25, 0.85, 1.0);
// How many colour bands wrap around the aura, and how fast they rotate.
uniform float swirl : hint_range(0.0, 8.0, 0.01) = 3.0;
uniform float swirl_speed : hint_range(-8.0, 8.0, 0.01) = 1.5;
// Optional extra ramp. Left empty it defaults to black, so the two-colour swirl
// above is the whole look until you assign a texture.
uniform sampler2D color_gradiant : source_color, hint_default_black, repeat_enable, filter_linear_mipmap;
// Noise scale / drift, same names as the original 2D shader.
uniform float Tilling : hint_range(0.0, 60.0, 0.01) = 10.0;
uniform vec2 MovementDirSpeed = vec2(-0.6, 1.0);
uniform vec2 MovementDirSpeed2 = vec2(0.6, 1.0);
uniform vec2 Noise_Seed = vec2(1.0);
// Radial falloff: low = big soft blob, high = tighter core.
uniform float falloff : hint_range(0.4, 6.0, 0.01) = 1.6;
// Gentle size pulse so the aura feels alive.
uniform float breathe : hint_range(0.0, 0.3, 0.001) = 0.05;
// Fragments this far inside the falloff edge (1.0 = fully faded) are skipped
// outright. The default is invisible and already buys back ~30% of the card.
uniform float cutout : hint_range(0.0, 0.35, 0.005) = 0.02;

// Sin-free 2D hash (Dave Hoskins, "Hash without Sine"), same (-1,1) gradient
// contract as the original sin()-based random() for a fraction of the cost.
vec2 random(vec2 uv) {
	vec2 p = uv + Noise_Seed;
	vec3 p3 = fract(p.xyx * vec3(0.1031, 0.1030, 0.0973));
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.xx + p3.yz) * p3.zy) * 2.0 - 1.0;
}

float noise(vec2 uv) {
	vec2 uv_index = floor(uv);
	vec2 uv_fract = fract(uv);
	vec2 blur = smoothstep(0.0, 1.0, uv_fract);
	float bottom_left = dot(random(uv_index + vec2(0.0, 0.0)), uv_fract - vec2(0.0, 0.0));
	float bottom_right = dot(random(uv_index + vec2(1.0, 0.0)), uv_fract - vec2(1.0, 0.0));
	float top_left = dot(random(uv_index + vec2(0.0, 1.0)), uv_fract - vec2(0.0, 1.0));
	float top_right = dot(random(uv_index + vec2(1.0, 1.0)), uv_fract - vec2(1.0, 1.0));
	float bottom_mix = mix(bottom_left, bottom_right, blur.x);
	float top_mix = mix(top_left, top_right, blur.x);
	return (mix(bottom_mix, top_mix, blur.y) + 1.0) * 0.5;
}

// Breathing: pulse the quad's own size around its centre.
void vertex() {
	VERTEX.xy *= 1.0 + breathe * sin(TIME * 4.0);
}

void fragment() {
	vec2 uv = UV;
	vec2 centred = uv - vec2(0.5);
	float d = length(centred) * 2.0;
	float radial = 1.0 - d;

	// Dead zone: nothing visible is drawn out here, so bail before spending any
	// noise work (and before the blend, which is pure bandwidth).
	if (radial <= cutout) {
		discard;
	}

	// Soft round falloff: bright at the centre, gone before the quad's corners.
	float mask = pow(radial, falloff);

	// Swirling colour bands (the 2D version swirled a gradient texture).
	float angle = atan(centred.y, centred.x);
	float ramp_t = 0.5 + 0.5 * sin(angle * swirl + TIME * swirl_speed);
	vec3 procedural = mix(color_a.rgb, color_b.rgb, ramp_t);
	vec3 ramp_tex = texture(color_gradiant, vec2(uv.x, 0.5)).rgb;
	vec3 gradient = (procedural + ramp_tex) * tint.rgb;

	// Wispy, drifting energy from the original noise setup.
	vec2 TimeUV = MovementDirSpeed * TIME;
	vec2 TimeUV2 = MovementDirSpeed2 * TIME;
	float band = noise(uv * Tilling - TimeUV);
	float speckle = noise(uv * Tilling + TimeUV);
	float speckle2 = noise(uv * Tilling + TimeUV2);

	float energy = 0.4 + 0.6 * band * speckle;
	float wisp = clamp(0.45 + 0.55 * speckle * speckle2, 0.0, 1.0);

	ALBEDO = gradient * energy * mask;
	ALPHA = wisp * AuraProgres;
}
