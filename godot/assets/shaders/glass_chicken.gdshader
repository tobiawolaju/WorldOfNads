shader_type spatial;
// Iridescent glass bubble for the dashboard preview chickens, matching the
// frontend ThreeScene look. The preview SubViewport is transparent, so
// alpha-blended materials get darkened by the offscreen composite (they read as
// black glass). Additive keeps the whole shell luminous instead.
//
// Godot's add blend ignores ALPHA, so the fresnel falloff is premultiplied into
// ALBEDO, with a strong base term so the body never falls to black.
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

	// Fixed view-space key light for a crisp curved glass reflection.
	vec3 light_dir = normalize(vec3(-0.45, 0.65, 0.7));
	vec3 half_dir = normalize(light_dir + view_dir);
	float highlight = pow(max(dot(normal, half_dir), 0.0), 80.0);

	// Pale iridescent film across the body, brighter toward the silhouette.
	vec3 body = mix(color, vec3(1.0), 0.18);
	float rim = pow(fresnel, 1.8);
	ALBEDO = body * (0.55 + rim * 1.15) + vec3(1.0) * highlight * 0.9;
	ALPHA = 1.0;
}
