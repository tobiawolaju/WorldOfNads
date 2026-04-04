shader_type spatial;
render_mode unshaded;

uniform vec4 color_inner : source_color = vec4(1.0, 0.0, 0.0, 1.0);
uniform vec4 color_mid   : source_color = vec4(0.0, 1.0, 0.0, 1.0);
uniform vec4 color_outer : source_color = vec4(0.0, 0.0, 1.0, 1.0);

uniform float radius_inner = 0.3;
uniform float radius_outer = 0.6;

void fragment() {
    vec2 d = UV - vec2(0.5);
    float dist = length(d);

    vec3 col;

    if (dist < radius_inner) {
        float t = dist / radius_inner;
        col = mix(color_inner.rgb, color_mid.rgb, t);
    } else {
        float t = (dist - radius_inner) / (radius_outer - radius_inner);
        col = mix(color_mid.rgb, color_outer.rgb, t);
    }

    ALBEDO = col;
}