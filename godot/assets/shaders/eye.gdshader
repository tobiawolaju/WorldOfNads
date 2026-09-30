shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_opaque, shadows_disabled;

// White sphere with a single black dot that always faces the camera.
//
// Everything is measured in view space, where the camera sits at the origin, so the
// result does not depend on where the mesh's node origin is or how it was authored.

// Colour of the eyeball. Pure white by default, tint this for a coloured iris.
uniform vec3 eye_color : source_color = vec3(1.0);

// Colour of the dot itself. Kept separate from eye_color so you can have a black pupil
// on a coloured eye, which is the usual case.
uniform vec3 pupil_color : source_color = vec3(0.0);

// Angular radius of the dot, in radians. ~0.35 is a natural-looking pupil.
uniform float pupil_size : hint_range(0.02, 1.2) = 0.35;
// Edge softness in radians, so the circle is not aliased.
uniform float pupil_softness : hint_range(0.001, 0.3) = 0.04;
// Optional darkening at the silhouette, like a socket or eyelid shadow.
uniform float rim_darken : hint_range(0.0, 1.0) = 0.25;

// Nudges the dot off the exact centre of view, in radians. X moves it sideways and
// Y moves it up or down. Use these to reposition the dot without touching the code;
// raising Y past ~1.2 slides it toward the top of the sphere.
// These are separate floats rather than one vec2 because hint_range only applies to
// scalars, and this way each gets a slider in the inspector.
uniform float dot_shift_x : hint_range(-2.0, 2.0) = 0.0;
uniform float dot_shift_y : hint_range(-2.0, 2.0) = 0.0;

// Rolls the dot around the view axis, in radians. No effect on a perfectly round dot,
// but useful for aiming an elongated dot.
uniform float dot_roll : hint_range(-3.14159, 3.14159) = 0.0;

// Set to 1 if the mesh's normals point inward, which would put the dot on the far side.
uniform float flip_dot : hint_range(0.0, 1.0) = 0.0;

// Debug: paints the whole sphere flat magenta. If you cannot see this, the material is
// not assigned and nothing else in this shader matters yet.
uniform float debug_flat : hint_range(0.0, 1.0) = 0.0;

void fragment() {
	// NORMAL and VIEW are both in view space, and the camera sits at the view-space
	// origin, so the direction from this fragment back to the viewer is simply -VIEW.
	vec3 to_camera = normalize(-VIEW);
	vec3 surface_normal = normalize(NORMAL) * mix(1.0, -1.0, flip_dot);

	// Build a stable screen-aligned basis in view space so dot_shift moves the dot in
	// the same direction regardless of where the camera happens to be pointing.
	vec3 right = normalize(cross(vec3(0.0, 1.0, 0.0), to_camera) + vec3(0.0001, 0.0, 0.0));
	vec3 up = normalize(cross(to_camera, right));

	// Rotate the up axis by dot_roll so an elongated dot can be aimed.
	float roll_c = cos(dot_roll);
	float roll_s = sin(dot_roll);
	vec3 rolled_up = up * roll_c + right * roll_s;
	vec3 rolled_right = right * roll_c - up * roll_s;

	// Aim direction for the pupil, offset from dead centre by the manual shift.
	vec3 aim = normalize(to_camera + rolled_right * dot_shift_x + rolled_up * dot_shift_y);

	// Angle between this point on the sphere and the aim direction. Sizing the dot by an
	// angle rather than a distance keeps it the same apparent size from every direction,
	// which is what stops it ballooning when viewed from directly above.
	float facing = acos(clamp(dot(surface_normal, aim), -1.0, 1.0));

	// Smoothstep across the pupil radius for an anti-aliased edge.
	float softness = max(pupil_softness, 0.001);
	float inside = 1.0 - smoothstep(pupil_size - softness, pupil_size + softness, facing);

	// Rim shading driven by the true silhouette angle, independent of the dot shift.
	float rim = smoothstep(0.9, 1.5708, acos(clamp(dot(surface_normal, to_camera), -1.0, 1.0)));
	vec3 color = mix(eye_color, eye_color * (1.0 - rim_darken), rim);
	color = mix(color, pupil_color, inside);

	// Debug: flat magenta over everything else. Assigned last so it always wins. If the
	// sphere does not turn magenta, the material is not on the mesh and nothing else in
	// this shader matters yet.
	if (debug_flat > 0.5) {
		color = vec3(1.0, 0.0, 1.0);
	}

	ALBEDO = color;
	ALPHA = 1.0;
}
