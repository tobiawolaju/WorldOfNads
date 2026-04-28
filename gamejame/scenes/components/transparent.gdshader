shader_type spatial;
render_mode unshaded;

uniform vec4 color_inner : source_color = vec4(1.0, 0.2, 0.2, 1.0);
uniform vec4 color_mid   : source_color = vec4(0.2, 1.0, 0.2, 1.0);
uniform vec4 color_outer : source_color = vec4(0.2, 0.2, 1.0, 1.0);

uniform float radius_inner = 0.3;
uniform float radius_outer = 0.6;

// fake transparency strength
uniform float opacity = 0.6;

// pixelation amount (set to 0 to disable)
uniform float pixel_size = 64.0;

void fragment() {
    // 🔹 Pixel snap (optional)
    vec2 uv = UV;
    if (pixel_size > 0.0) {
        uv = floor(UV * pixel_size) / pixel_size;
    }

    // 🔹 Radial distance
    vec2 d = uv - vec2(0.5);
    float dist = length(d);

    // 🔹 3-color gradient
    vec3 col;
    if (dist < radius_inner) {
        float t = dist / radius_inner;
        col = mix(color_inner.rgb, color_mid.rgb, t);
    } else {
        float t = (dist - radius_inner) / (radius_outer - radius_inner);
        col = mix(color_mid.rgb, color_outer.rgb, t);
    }

    // 🔹 Radial fade (stronger at edges)
    float fade = 1.0 - clamp(dist / radius_outer, 0.0, 1.0);
    float final_opacity = opacity * fade;

    // 🔹 Dithering (screen-door transparency)
    vec2 grid = mod(floor(FRAGCOORD.xy), 4.0);
    float threshold = (grid.x + grid.y * 4.0) / 16.0;

    if (threshold > final_opacity) {
        discard;
    }

    ALBEDO = col;
}