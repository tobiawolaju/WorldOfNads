shader_type canvas_item;

// Crops any texture to a circle so a square profile picture reads as an avatar.
// The badge fallback does not use this: it draws the existing circular disc
// asset, which is already the right shape.
//
// `ring_alpha` draws a soft outline instead of a hard cut, which keeps the
// avatar legible against both the bright sky and the dark storm.

uniform float ring_width : hint_range(0.0, 0.2) = 0.06;
uniform vec4 ring_color : source_color = vec4(1.0, 1.0, 1.0, 0.30);

void fragment() {
	vec2 centered = UV - vec2(0.5);
	float distance_from_center = length(centered);

	if (distance_from_center > 0.5) {
		discard;
	}

	vec4 tex = texture(TEXTURE, UV);

	if (ring_width > 0.0 && distance_from_center > 0.5 - ring_width) {
		// Keep the source alpha so a partially transparent edge still blends.
		COLOR = vec4(ring_color.rgb, ring_color.a * tex.a);
	} else {
		COLOR = tex;
	}
}
