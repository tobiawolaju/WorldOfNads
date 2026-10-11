shader_type canvas_item;

// Flat ("unshaded") thumbnail filter for the store's shaded/flat toggle, ported
// from frontend/src/pages/Dashboard.css:
//
//   .skin-preview__variant.is-flat .skin-preview__variant-img {
//     filter: saturate(0.15) contrast(0.95) brightness(1.05);
//   }
//
// The two editions of a skin share one artwork (see skinCombos.json), so the
// toggle differentiates the flat edition by desaturating its square the way the
// frontend does. Kept as a shader rather than a pre-baked grey texture so it
// stays crisp while the panel zoom scales the thumbnail up.

uniform float saturation : hint_range(0.0, 2.0) = 0.15;
uniform float contrast : hint_range(0.0, 2.0) = 0.95;
uniform float brightness : hint_range(0.0, 2.0) = 1.05;

void fragment() {
	vec4 tex = texture(TEXTURE, UV);
	// saturate(): blend the sampled colour with its luma (0 = greyscale).
	float lum = dot(tex.rgb, vec3(0.2126, 0.7152, 0.0722));
	vec3 rgb = mix(vec3(lum), tex.rgb, saturation);
	// contrast() pivots around mid-grey, then brightness() is a linear gain.
	rgb = (rgb - vec3(0.5)) * contrast + vec3(0.5);
	rgb *= brightness;
	COLOR *= vec4(rgb, tex.a);
}
