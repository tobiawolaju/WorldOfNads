shader_type canvas_item;

// Matches Dashboard.css `.lobby-bg img` mask:
// linear-gradient(to bottom, transparent 0%, black 20%, black 80%, transparent 100%)
// Cropped to lobbybg.jpeg's 1216x523 ratio by STRETCH_KEEP_ASPECT_COVERED, so
// fading by UV.y matches the frontend exactly.

void fragment() {
	vec2 uv = UV;
	float fade = 1.0;
	if (uv.y < 0.2) {
		fade = uv.y / 0.2;
	}
	if (uv.y > 0.8) {
		fade = (1.0 - uv.y) / 0.2;
	}
	COLOR = texture(TEXTURE, uv);
	COLOR.a *= fade;
}
