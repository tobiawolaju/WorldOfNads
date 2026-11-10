// powerup.gdshader (low-cost aura)
// Cheap radial glow for low-end/mobile web: no noise, no gradient texture samples,
// minimal ALU. Billboarded quad surrounds the player during power-up use.
shader_type spatial;
render_mode unshaded, blend_add, cull_disabled, depth_draw_never;

uniform float AuraProgres : hint_range(0.0, 1.0, 0.01) = 1.0;
uniform vec4 tint : source_color = vec4(1.0, 1.0, 1.0, 1.0);
uniform vec4 color_a : source_color = vec4(0.2, 0.75, 1.0, 1.0);
uniform vec4 color_b : source_color = vec4(1.0, 0.25, 0.85, 1.0);
uniform float swirl : hint_range(0.0, 8.0, 0.01) = 2.0;
uniform float swirl_speed : hint_range(-8.0, 8.0, 0.01) = 1.2;
uniform float falloff : hint_range(0.4, 6.0, 0.01) = 1.7;
uniform float breathe : hint_range(0.0, 0.3, 0.001) = 0.03;

void vertex() {
	// Gentle pulse (cheap).
	VERTEX.xy *= 1.0 + breathe * sin(TIME * 3.0);
}

void fragment() {
	vec2 centred = UV - vec2(0.5);
	float d = length(centred) * 2.0;
	float radial = 1.0 - d;
	if (radial <= 0.03) {
		discard;
	}
	float mask = pow(max(radial, 0.0), falloff);
	float angle = atan(centred.y, centred.x);
	float t = 0.5 + 0.5 * sin(angle * swirl + TIME * swirl_speed);
	vec3 col = mix(color_a.rgb, color_b.rgb, t) * tint.rgb;
	float pulse = 0.85 + 0.15 * sin(TIME * 2.5);
	ALBEDO = col * mask * pulse;
	ALPHA = mask * AuraProgres;
}
