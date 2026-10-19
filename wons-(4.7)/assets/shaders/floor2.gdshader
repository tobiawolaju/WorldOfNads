shader_type spatial;
render_mode unshaded;

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
    
    // --- DITHER SHADER OPTIMIZATION ---
    float dither = 0.0;
    {
        const float bayer[16] = {
            0.0625, 0.5625, 0.1875, 0.6875,
            0.8125, 0.3125, 0.9375, 0.4375,
            0.25, 0.75, 0.125, 0.625,
            1.0, 0.5, 0.875, 0.375
        };
        ivec2 screen_pos = ivec2(FRAGCOORD.xy) % 4;
        dither = bayer[screen_pos.x + screen_pos.y * 4];
    }

    if (col.r > dither) {
        discard;
    }
}