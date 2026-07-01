shader_type canvas_item;

// filter_linear is better for zooming than mipmaps, which cause blur.
uniform sampler2D SCREEN_TEXTURE : hint_screen_texture, filter_linear;

// Positive = Fisheye, Negative = Anti-Fisheye
uniform float effect_amount = -0.05;

void fragment() {
	// Get base UV
	vec2 uv = SCREEN_UV;
	
	// Calculate Aspect Ratio
	float ratio = SCREEN_PIXEL_SIZE.x / SCREEN_PIXEL_SIZE.y;
	
	// Center the coordinates (-0.5 to 0.5)
	vec2 p = uv - 0.5;
	
	// Adjust Y by ratio to make the distortion circular, not oval
	p.y /= ratio;
	
	// Distance from center
	float r = length(p);
	float power = effect_amount;

	if (power != 0.0) {
		float bind;
		
		// Calculate the "Bind" (the boundary of the effect)
		if (power > 0.0) {
			// For Fisheye: distance to the furthest corner
			bind = length(vec2(0.5, 0.5 / ratio));
		} else {
			// For Anti-Fisheye: distance to the closest edge
			bind = (ratio < 1.0) ? 0.5 : 0.5 / ratio;
		}

		// Apply the distortion math
		if (power > 0.0) {
			// Fisheye logic
			// The tan() function is what creates the "zoom" look.
			p = normalize(p) * tan(r * power) * bind / tan(bind * power);
		} else {
			// Anti-fisheye logic
			p = normalize(p) * atan(r * -power * 10.0) * bind / atan(-power * bind * 10.0);
		}
	}

	// Restore the aspect ratio
	p.y *= ratio;
	
	// Move coordinates back to 0.0 - 1.0 range
	vec2 final_uv = p + 0.5;

	// Optimization: Only sample if inside the screen to avoid edge wrapping/streaking
	if (final_uv.x < 0.0 || final_uv.x > 1.0 || final_uv.y < 0.0 || final_uv.y > 1.0) {
		COLOR = vec4(0.0, 0.0, 0.0, 1.0); // Black bars for out-of-bounds
	} else {
		COLOR = texture(SCREEN_TEXTURE, final_uv);
	}
}