shader_type spatial;

uniform sampler2D face_tex : source_color;
uniform float thickness = 0.01;

void vertex() {
    float h = texture(face_tex, UV).a;
    VERTEX += NORMAL * h * thickness;
}

void fragment() {
    vec4 tex = texture(face_tex, UV);

    if (tex.a < 0.01)
        discard;

    ALBEDO = tex.rgb;
    ALPHA = tex.a;
}