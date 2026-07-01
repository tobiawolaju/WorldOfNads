shader_type spatial;
render_mode unshaded, blend_mix;

uniform vec4 color_inner : source_color = vec4(1.0, 0.0, 0.0, 1.0);
uniform vec4 color_mid   : source_color = vec4(0.0, 1.0, 0.0, 0.7);
uniform vec4 color_outer : source_color = vec4(0.0, 0.0, 1.0, 0.0);

uniform float radius_inner = 0.3;
uniform float radius_outer = 0.6;

void fragment() {
    vec2 d = UV - vec2(0.5);
    float dist = length(d);

    vec4 col;

    if (dist < radius_inner) {
        float t = dist / radius_inner;
        col = mix(color_inner, color_mid, t);
    } else {
        float t = (dist - radius_inner) / (radius_outer - radius_inner);
        col = mix(color_mid, color_outer, t);
    }

    ALBEDO = col.rgb;
    ALPHA = col.a;
}