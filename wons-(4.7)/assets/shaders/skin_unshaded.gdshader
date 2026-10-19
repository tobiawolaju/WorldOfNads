shader_type spatial;
render_mode unshaded, depth_draw_opaque;

uniform vec4 albedo : source_color = vec4(1.0, 0.18, 0.54, 1.0);

void fragment() {
	ALBEDO = albedo.rgb;
}
