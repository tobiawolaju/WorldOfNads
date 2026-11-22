shader_type spatial;
// Glass bubble look for the decorative dashboard chickens. Alpha-blended (not
// additive) so the shell still reads as glass over the bright lobby background.
render_mode blend_mix, depth_draw_never, cull_disabled, unshaded;

varying vec3 v_view_normal;
varying vec3 v_view_position;

void vertex() {
	vec4 model_view_position = MODELVIEW_MATRIX * vec4(VERTEX, 1.0);
	v_view_position = -model_view_position.xyz;
	// Godot 4 exposes the view-space normal matrix as MODELVIEW_NORMAL_MATRIX.
	v_view_normal = normalize(MODELVIEW_NORMAL_MATRIX * NORMAL);
}

void fragment() {
	vec3 view_dir = normalize(v_view_position);
	vec3 normal = normalize(v_view_normal);
	float facing = clamp(dot(view_dir, normal), 0.0, 1.0);
	float fresnel = 1.0 - facing;
	float rim = pow(fresnel, 2.2);

	// Iridescent shell tint, strongest at grazing angles.
	vec3 iridescence = vec3(
		sin(fresnel * 5.0 - TIME * 0.5),
		sin(fresnel * 5.0 - TIME * 0.5 + 2.094),
		sin(fresnel * 5.0 - TIME * 0.5 + 4.188)
	) * 0.5 + 0.5;

	vec3 glass_tint = vec3(0.52, 0.78, 1.0);
	ALBEDO = mix(glass_tint, iridescence, rim);
	ALPHA = clamp(0.14 + rim * 0.78, 0.0, 0.92);
}
