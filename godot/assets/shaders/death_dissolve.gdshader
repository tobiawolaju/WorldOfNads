// Pixel Dreamer — Dissolve with Glowing Edge (Godot 4 · spatial · Forward+/Mobile/Compatibility)
// MIT License · https://pixeldreamerstudio.itch.io/
// Animate `dissolve` from 0 (solid) to 1 (gone). The burning edge glows with `edge_color`.
//
// LOCAL MODIFICATION (World of Nads): the character body is drawn by
// `skin_shaded.gdshader`, which uses a soft wrap-diffuse. This material replaces
// that one at the instant of death, so without the same wrap the body would
// flash noticeably brighter for the frame before the burn eats into it. The
// lighting term below is copied from `skin_shaded.gdshader` for that reason.
// Delete it and use `albedo.rgb * tex.rgb` for the unmodified stock effect.
shader_type spatial;
render_mode cull_disabled;

uniform vec4 albedo : source_color = vec4(0.8, 0.8, 0.85, 1.0);
uniform sampler2D albedo_texture : source_color, filter_linear_mipmap, hint_default_white;
uniform float roughness : hint_range(0.0, 1.0) = 0.5;
uniform float metallic : hint_range(0.0, 1.0) = 0.0;
uniform float dissolve : hint_range(0.0, 1.0) = 0.4;
uniform float edge_width : hint_range(0.0, 0.3) = 0.06;
uniform vec4 edge_color : source_color = vec4(1.0, 0.45, 0.1, 1.0);
uniform float edge_energy : hint_range(0.0, 16.0) = 6.0;
uniform float noise_scale = 2.5;
uniform bool use_world_space = false; // true = pattern stays put when the object moves

varying vec3 npos;

float hash(vec3 p) {
	p = fract(p * 0.3183099 + 0.1);
	p *= 17.0;
	return fract(p.x * p.y * p.z * (p.x + p.y + p.z));
}
float vnoise(vec3 x) {
	vec3 i = floor(x);
	vec3 f = fract(x);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(mix(hash(i), hash(i + vec3(1,0,0)), f.x), mix(hash(i + vec3(0,1,0)), hash(i + vec3(1,1,0)), f.x), f.y),
	           mix(mix(hash(i + vec3(0,0,1)), hash(i + vec3(1,0,1)), f.x), mix(hash(i + vec3(0,1,1)), hash(i + vec3(1,1,1)), f.x), f.y), f.z);
}
float fbm(vec3 p) {
	float v = 0.0;
	float a = 0.5;
	for (int i = 0; i < 4; i++) {
		v += a * vnoise(p);
		p *= 2.03;
		a *= 0.5;
	}
	return v;
}

void vertex() {
	npos = use_world_space ? (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz : VERTEX;
}

void fragment() {
	float n = clamp((fbm(npos * noise_scale) - 0.22) / 0.56, 0.0, 1.0);
	// stretch so dissolve 0 = solid and 1 = fully gone
	float d = dissolve * (1.0 + edge_width) - edge_width;
	if (n < d) {
		discard;
	}
	vec4 tex = texture(albedo_texture, UV);

	// Local modification: match the body's wrap-diffuse so the swap is invisible.
	vec3 light = normalize(BACKLIGHT);
	float ndotl = max(0.0, dot(NORMAL, light));
	float wrap = pow(ndotl * 0.7 + 0.3, 1.3);

	ALBEDO = albedo.rgb * tex.rgb * wrap;
	ROUGHNESS = roughness;
	METALLIC = metallic;
	float edge = 1.0 - smoothstep(d, d + edge_width, n);
	EMISSION = edge_color.rgb * edge * edge_energy * step(0.001, dissolve);
}
