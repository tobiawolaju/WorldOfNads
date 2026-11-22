shader_type spatial;
// Iridescent soap-bubble shell matching the frontend ThreeScene chickens.
// Godot's add blend ignores ALPHA, so the falloff is premultiplied into ALBEDO:
// a saturated rainbow film plus a much brighter rim and a crisp glass highlight.
render_mode blend_add, depth_draw_never, cull_back, unshaded;

varying vec3 v_view_normal;
varying vec3 v_view_position;

void vertex() {
	vec4 model_view_position = MODELVIEW_MATRIX * vec4(VERTEX, 1.0);
	v_view_position = -model_view_position.xyz;
	// Godot 4 exposes the view-space normal matrix as MODELVIEW_NORMAL_MATRIX.
	v_view_normal = normalize(MODELVIEW_NORMAL_MATRIX * NORMAL);
}

void fragment() {
	vec3 normal = normalize(v_view_normal);
	vec3 view_dir = normalize(v_view_position);
	float fresnel = 1.0 - clamp(dot(view_dir, normal), 0.0, 1.0);

	// Same animated rainbow ramp as the frontend bubble shader.
	vec3 color;
	color.r = sin(fresnel * 5.0 - TIME * 0.5) * 0.5 + 0.5;
	color.g = sin(fresnel * 5.0 - TIME * 0.5 + 2.094) * 0.5 + 0.5;
	color.b = sin(fresnel * 5.0 - TIME * 0.5 + 4.188) * 0.5 + 0.5;

	// Fixed view-space key light for a curved glass reflection.
	vec3 light_dir = normalize(vec3(-0.45, 0.65, 0.7));
	vec3 half_dir = normalize(light_dir + view_dir);
	float highlight = pow(max(dot(normal, half_dir), 0.0), 55.0);

	// Saturated iridescent film, brighter toward the silhouette.
	float rim = pow(fresnel, 1.5);
	ALBEDO = color * (0.20 + rim * 1.35) + vec3(1.0) * highlight * 0.9;
	ALPHA = 1.0;
}
