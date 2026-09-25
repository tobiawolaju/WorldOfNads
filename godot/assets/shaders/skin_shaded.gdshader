shader_type spatial;
render_mode cull_back;

uniform vec4 albedo : source_color = vec4(1.0, 0.18, 0.54, 1.0);
uniform float roughness_val : hint_range(0.0, 1.0) = 0.9;
uniform float metalness_val : hint_range(0.0, 1.0) = 0.0;

void fragment() {
	vec3 light = normalize(BACKLIGHT);
	// Soft matte diffuse with a slight wrap so the highlight bleeds gently,
	// reads as puffy 3D cartoon instead of a sharp plastic glint.
	float NdotL = max(0.0, dot(NORMAL, light));
	float diff = pow(NdotL * 0.7 + 0.3, 1.3);
	ALBEDO = albedo.rgb * diff;
	ROUGHNESS = roughness_val;
	METALLIC = metalness_val;
}
