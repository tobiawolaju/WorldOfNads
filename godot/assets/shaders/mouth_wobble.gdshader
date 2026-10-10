shader_type spatial;
render_mode  blend_mix, cull_disabled;

uniform vec4 mouth_color : source_color = vec4(0.15, 0.02, 0.02, 1.0);

uniform vec4 lip_outline_color : source_color = vec4(0.05, 0.005, 0.005, 1.0);
uniform float lip_outline_thickness : hint_range(0.0, 0.5) = 0.08;

// Bunny teeth
uniform vec4 tooth_color : source_color = vec4(1.0, 0.95, 0.85, 1.0);
uniform float tooth_width : hint_range(0.01, 0.5) = 0.16;
uniform float tooth_height : hint_range(0.01, 0.8) = 0.35;
uniform float tooth_spacing : hint_range(0.0, 1.0) = 0.22;
uniform float tooth_drop : hint_range(-1.0, 1.0) = 0.05;
uniform float tooth_roundness : hint_range(0.01, 1.0) = 0.2;

uniform float width : hint_range(0.01, 1.0) = 0.75;
uniform float height : hint_range(0.01, 1.0) = 0.25;

uniform int layers : hint_range(2, 32, 1) = 16;

uniform float depth : hint_range(0.0, 1.0) = 0.25;
uniform float taper : hint_range(0.1, 1.0) = 0.65;
uniform float darkness : hint_range(0.0, 1.0) = 1.0;

uniform float end_x : hint_range(-1.0, 1.0) = 0.0;
uniform float end_y : hint_range(-1.0, 1.0) = 0.0;

uniform float parallax_factor : hint_range(0.0, 3.0) = 1.0;


float rounded_box(vec2 p, vec2 half_size, float radius) {
    vec2 q = abs(p) - half_size + radius;
    return length(max(q, vec2(0.0))) + min(max(q.x, q.y), 0.0) - radius;
}


void fragment() {

    vec2 base_uv = UV;

    vec2 base_p = base_uv * 2.0 - 1.0;

    base_p.x /= width;
    base_p.y /= height;

    float base_shape =
        base_p.x * base_p.x +
        base_p.y * base_p.y;

    // Mouth opening
    float opening =
        step(base_shape, 1.0);

    // Lip outline
    float inner_radius =
        1.0 - lip_outline_thickness;

    float inner_shape =
        (base_p.x / inner_radius) *
        (base_p.x / inner_radius) +
        (base_p.y / inner_radius) *
        (base_p.y / inner_radius);

    float inner_opening =
        step(inner_shape, 1.0);

    float lip_outline =
        opening - inner_opening;


    // -------------------------
    // CAVITY
    // -------------------------

    vec3 view =
        normalize(VIEW);

    vec3 tangent =
        normalize(TANGENT);

    vec3 bitangent =
        normalize(
            cross(NORMAL, tangent)
        );

    vec2 view_offset =
        vec2(
            dot(view, tangent),
            dot(view, bitangent)
        );

    float deepest = 0.0;
    float deepest_t = 0.0;

    for (int i = 0; i < layers; i++) {

        float t =
            float(i) /
            float(layers - 1);

        float z =
            t * depth;

        vec2 uv =
            base_uv;

        // Inverted parallax
        uv -=
            view_offset *
            z *
            parallax_factor;

        // Endpoint movement
        vec2 end_offset =
            vec2(end_x, end_y) * t;

        uv -= end_offset;

        float scale =
            mix(
                1.0,
                taper,
                t
            );

        vec2 p =
            uv * 2.0 - 1.0;

        p.x /=
            width * scale;

        p.y /=
            height * scale;

        float shape =
            p.x * p.x +
            p.y * p.y;

        float layer_mask =
            step(shape, 1.0);

        if (layer_mask > 0.0) {
            deepest = 1.0;
            deepest_t = t;
        }
    }

    float dark_amount =
        deepest_t * darkness;

    vec3 cavity_color =
        mix(
            mouth_color.rgb,
            vec3(0.0),
            dark_amount
        );


    // -------------------------
    // LIP
    // -------------------------

    vec3 final_color =
        mix(
            cavity_color,
            lip_outline_color.rgb,
            lip_outline
        );


   // -------------------------
// TWO BUNNY TEETH
// -------------------------

float tooth_mask = 0.0;

// Left tooth
vec2 left_tooth =
    base_p -
    vec2(-tooth_spacing, tooth_drop);

float left_shape =
    rounded_box(
        left_tooth,
        vec2(tooth_width, tooth_height),
        tooth_roundness
    );

float left_mask =
    step(left_shape, 0.0);

// Right tooth
vec2 right_tooth =
    base_p -
    vec2(tooth_spacing, tooth_drop);

float right_shape =
    rounded_box(
        right_tooth,
        vec2(tooth_width, tooth_height),
        tooth_roundness
    );

float right_mask =
    step(right_shape, 0.0);

tooth_mask =
    max(left_mask, right_mask);

// Keep teeth inside mouth
tooth_mask *= opening;


// Teeth go behind the mouth
final_color =
    mix(
        cavity_color,
        tooth_color.rgb,
        tooth_mask
    );

// Lip outline is ALWAYS on top
final_color =
    mix(
        final_color,
        lip_outline_color.rgb,
        lip_outline
    );

ALBEDO = final_color;

ALPHA =
    max(
        opening,
        tooth_mask
    );
}