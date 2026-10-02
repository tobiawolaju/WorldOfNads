shader_type canvas_item;

// Match-card artwork, ported from frontend/src/pages/Dashboard.css `.match-card`.
//
// The CSS card is a 330x220 box that stacks:
//   * background: url(match.image) cover / center / no-repeat
//   * scale: 0.9
//   * transform: perspective(600px) rotateY(0) skewX(-5deg)
//   * a mask-image radial-gradient dissolve (ellipse 84% 84% at 50% 50%,
//     #000 0 74%, rgba(0,0,0,.5) 90%, transparent 100%)
//   * a ::before halftone dot grid (5px pitch, 1.6px ink, white 0.85, opacity
//     .6 resting / .9 hovered) carrying its own radial rim mask
//   * a ::after neon overlay (radial at top-left, rgba(0,0,0,.397) -> transparent
//     70%, mix-blend-mode: overlay, opacity .8 resting / 1 hovered)
//   * filter: grayscale(100%) brightness(0.7) on completed matches
//
// Every value is evaluated in CSS pixels inside that 330x220 box, and the panel
// zoom scales the node, so the dissolve and the halftone stay crisp at any
// window size (the old match_card_bg.png baked this at 116x77 and went soft).
// The upright text/prize plate stay ordinary Controls on top of this.

uniform sampler2D source_tex : filter_linear;
uniform vec2 css_size = vec2(330.0, 220.0);
uniform float dot_opacity : hint_range(0.0, 1.0) = 0.6;
uniform float neon_opacity : hint_range(0.0, 1.0) = 0.8;
uniform float grayscale_amount : hint_range(0.0, 1.0) = 0.0;
uniform float brightness_amount : hint_range(0.0, 2.0) = 1.0;

// tan(-5deg). CSS skewX(-5deg) maps pre -> post as x' = x + SKEW_TAN * y.
const float SKEW_TAN = -0.08748866;
const float EDGE_RAMP = 0.84;
const float DOT_PITCH = 5.0;
const float DOT_INK = 1.6;

float dissolve(float d) {
	if (d <= 0.74) {
		return 1.0;
	}
	if (d <= 0.90) {
		return mix(0.5, 1.0, (0.90 - d) / 0.16);
	}
	if (d <= 1.00) {
		return mix(0.0, 0.5, (1.00 - d) / 0.10);
	}
	return 0.0;
}

void fragment() {
	float card_alpha = COLOR.a;
	vec2 center = css_size * 0.5;

	// Undo `scale: 0.9` then `transform: skewX(-5deg)` (uniform scale and a
	// horizontal shear commute, so either order lands on the same point).
	vec2 q = UV * css_size;
	vec2 rel = q - center;
	rel /= 0.9;
	rel.x -= SKEW_TAN * rel.y;
	vec2 p = rel + center;

	// mask-image radial dissolve. `ellipse 84% 84%` makes the radii 84% of the
	// full box (not the half-size), so normalize against css_size.
	vec2 edge = (p - center) / (css_size * EDGE_RAMP);
	float d = length(edge);
	float alpha = dissolve(d);

	// `overflow: hidden` clips the card to its 330x220 box *before* the transform.
	// The dissolve ellipse above is wider than the box (84% of 330 = 277px vs the
	// 165px half-width), so on its own it never reaches zero at the slot edges and
	// the card would fill the whole axis-aligned slot with smeared edge pixels.
	// Clipping in source space is what turns the silhouette into the scaled, sheared
	// parallelogram the CSS draws. Derivatives give a pixel-wide anti-aliased edge.
	vec2 p_ddx = dFdx(p);
	vec2 p_ddy = dFdy(p);
	float aa = 0.5 * (length(p_ddx) + length(p_ddy));
	float box_x = smoothstep(-aa, aa, p.x) * (1.0 - smoothstep(css_size.x - aa, css_size.x + aa, p.x));
	float box_y = smoothstep(-aa, aa, p.y) * (1.0 - smoothstep(css_size.y - aa, css_size.y + aa, p.y));
	alpha *= box_x * box_y;

	// background: url(...) cover / center.
	vec2 src = vec2(textureSize(source_tex, 0));
	vec2 uv = p / css_size;
	float box_aspect = css_size.x / css_size.y;
	float src_aspect = src.x / max(src.y, 1.0);
	if (src_aspect > box_aspect) {
		uv.x = (uv.x - 0.5) * (box_aspect / src_aspect) + 0.5;
	} else {
		uv.y = (uv.y - 0.5) * (src_aspect / box_aspect) + 0.5;
	}
	vec3 base = texture(source_tex, clamp(uv, vec2(0.0), vec2(1.0))).rgb;

	// ::before halftone dots, confined to the rim by its own radial mask and by
	// the card dissolve.
	float ring_out = clamp((d - 0.52) / 0.36, 0.0, 1.0);
	float ring_in = clamp((1.0 - d) / 0.12, 0.0, 1.0);
	float dot_band = 0.85 * min(ring_out, ring_in) * dot_opacity * alpha;
	vec2 cell = mod(p, DOT_PITCH) - DOT_PITCH * 0.5;
	float halftone = 1.0 - smoothstep(DOT_INK, DOT_INK + 0.6, length(cell));
	base = mix(base, vec3(1.0), halftone * dot_band);

	// ::after neon overlay under mix-blend-mode: overlay.
	float reach = length(css_size) * 0.7;
	float sa = 0.397 * (1.0 - clamp(length(p) / reach, 0.0, 1.0)) * neon_opacity;
	vec3 overlay = mix(vec3(0.0), 2.0 * base - 1.0, step(vec3(0.5), base));
	base = base * (1.0 - sa) + overlay * sa;

	// `.match-card[data-status="completed"]` filter.
	float lum = dot(base, vec3(0.2126, 0.7152, 0.0722));
	base = mix(base, vec3(lum), grayscale_amount);
	base *= mix(1.0, brightness_amount, grayscale_amount);

	COLOR = vec4(base, alpha * card_alpha);
}
