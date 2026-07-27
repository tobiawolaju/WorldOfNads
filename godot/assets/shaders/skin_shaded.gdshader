shader_type spatial;
render_mode cull_back;

uniform vec4 albedo : source_color = vec4(1.0, 0.18, 0.54, 1.0);
uniform float roughness_val : hint_range(0.0, 1.0) = 0.5;
uniform float metalness_val : hint_range(0.0, 1.0) = 0.0;

void fragment() {
	vec3 light = normalize(BACKLIGHT);
	float NdotL = max(0.0, dot(NORMAL, light));
	float diff = NdotL * 0.8 + 0.2;
	ALBEDO = albedo.rgb * diff;
	ROUGHNESS = roughness_val;
	METALLIC = metalness_val;
}
