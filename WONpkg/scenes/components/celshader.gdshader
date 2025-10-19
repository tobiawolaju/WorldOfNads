shader_type spatial;
render_mode unshaded;

uniform sampler2D colour : source_color;
uniform vec3 light_direction;
uniform float shadow_threshold : hint_range(0.0, 1.0) = 0.2;
uniform float shadow_darkness : hint_range(0.0, 1.0) = 0.25;

void vertex() {

}

vec3 euler_rotation(vec3 input, vec3 rotation) {
	vec3 matrix[3];

		vec3 result = input - light_direction;

		float aa = cos(rotation.x);
		float ab = cos(rotation.y);
		float ac = cos(rotation.z);
		float ba = sin(rotation.x);
		float bb = sin(rotation.y);
		float bc = sin(rotation.z);
		float ca = aa * ac;
		float cb = aa * bc;
		float da = ba * ac;
		float db = ba * bc;

		matrix[0].x = ab * ac;
		matrix[1].x = bb * da - cb;
		matrix[2].x = bb * ca + db;
		matrix[0].y = ab * bc;
		matrix[1].y = bb * db + ca;
		matrix[2].y = bb * cb - da;
		matrix[0].z = -bb;
		matrix[1].z = ab * ba;
		matrix[2].z = ab * aa;

		vec3 tmp = result;

		result.x = matrix[0][0] * tmp.x + matrix[1][0] * tmp.y + matrix[2][0] * tmp.z;
		result.y = matrix[0][1] * tmp.x + matrix[1][1] * tmp.y + matrix[2][1] * tmp.z;
		result.z = matrix[0][2] * tmp.x + matrix[1][2] * tmp.y + matrix[2][2] * tmp.z;

		return result;
}

vec3 get_sun_direction(vec3 pos) {
	vec3 blue = vec3(0.00000, 0.00000, 1.00000);
	vec3 diff = pos - blue;
	vec3 loc = pos - diff;
	vec3 dir = light_direction;

	vec3 result = euler_rotation(loc, dir);

	return normalize(result);
}

void fragment() {
	vec4 tex_col = texture(colour, UV);

	vec3 result = tex_col.rgb;

	vec3 world_normals = normalize((INV_VIEW_MATRIX * vec4(NORMAL.xyz, 0.0)).xyz);
	vec3 sun_direction = get_sun_direction(NODE_POSITION_WORLD);
	float shading = dot(world_normals, sun_direction);
	float cel;

	if (shading < shadow_threshold) {
		cel = 1.0;
	} else {
		cel = 0.0;
	}

	cel = (cel * -1.0) + 1.0;
	cel = clamp(cel + shadow_darkness, 0.0, 1.0);

	result *= cel;

	ALBEDO = result;
}