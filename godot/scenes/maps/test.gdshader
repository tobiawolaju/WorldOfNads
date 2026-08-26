shader_type spatial;
render_mode cull_disabled;

uniform sampler2D card_texture : source_color, filter_linear_mipmap;
uniform vec4 base_color : source_color = vec4(0.35, 0.35, 0.35, 1.0);
uniform vec4 tip_color : source_color = vec4(1.0, 1.0, 1.0, 1.0);
uniform float alpha_threshold : hint_range(0.0, 1.0) = 0.5;
uniform bool invert_gradient = false;

void fragment() {
	vec4 tex = texture(card_texture, UV);
	if (tex.a < alpha_threshold) {
		discard;
	}
	float t = invert_gradient ? UV.y : 1.0 - UV.y;
	ALBEDO = tex.rgb * mix(base_color.rgb, tip_color.rgb, t);
}
