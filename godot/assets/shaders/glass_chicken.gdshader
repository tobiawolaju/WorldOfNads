shader_type spatial;
render_mode blend_add, depth_draw_never, cull_disabled, unshaded;

varying vec3 v_normal;
varying vec3 v_view_position;

void vertex() {
	vec4 model_view_position = MODELVIEW_MATRIX * vec4(VERTEX, 1.0);
	v_view_position = -model_view_position.xyz;
	v_normal = normalize(NORMAL_MATRIX * NORMAL);
}

void fragment() {
	vec3 view_dir = normalize(v_view_position);
	float fresnel = 1.0 - dot(view_dir, v_normal);
	fresnel = pow(fresnel, 2.5);

	vec3 color;
	color.r = sin(fresnel * 5.0 - TIME * 0.5) * 0.5 + 0.5;
	color.g = sin(fresnel * 5.0 - TIME * 0.5 + 2.094) * 0.5 + 0.5;
	color.b = sin(fresnel * 5.0 - TIME * 0.5 + 4.188) * 0.5 + 0.5;

	ALBEDO = color;
	ALPHA = fresnel * 0.8;
}
