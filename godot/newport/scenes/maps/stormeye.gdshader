shader_type spatial;

render_mode unshaded, cull_disabled, depth_draw_always, blend_add;

// =====================
// COLORS
// =====================

uniform vec3 bottom_color = vec3(0.1, 0.6, 1.0);
uniform vec3 top_color    = vec3(0.6, 0.9, 1.0);
uniform vec3 streak_color = vec3(1.0, 1.0, 1.0);

// =====================
// CONTROLS
// =====================

uniform float height_fade = 1.0;
uniform float streak_intensity = 2.0;
uniform float streak_speed = 3.0;
uniform float streak_scale = 40.0;

uniform float fresnel_strength = 2.0;
uniform float fresnel_power = 3.0;

// =====================
// MAIN
// =====================

void fragment() {

    vec2 uv = UV;

    // vertical mask (stable + clean)
    float h = UV.y;

    // =====================
    // BASE GRADIENT
    // =====================

    vec3 base = mix(bottom_color, top_color, h);

    // =====================
    // VERTICAL ENERGY LINES
    // =====================

    float x = UV.x * streak_scale;
    float streaks = sin(x + TIME * streak_speed);

    streaks = abs(streaks);
    streaks = smoothstep(0.4, 1.0, streaks);
    streaks = 1.0 - streaks;

    // stronger near bottom
    streaks *= pow(1.0 - h, 2.0);

    // =====================
    // FRESNEL EDGE GLOW
    // =====================

    float fresnel = pow(1.0 - abs(dot(NORMAL, VIEW)), fresnel_power);
    fresnel *= fresnel_strength;

    // =====================
    // FINAL
    // =====================

    vec3 color = base;

    color += streak_color * streaks * streak_intensity;
    color += vec3(0.3, 0.7, 1.0) * fresnel;

    // EMISSION is the main driver (this is key)
    EMISSION = color * 3.0;

    // keep it visible without relying on alpha
    ALBEDO = base;

    // subtle additive feel without disappearing
    ALPHA = 1.0;
}