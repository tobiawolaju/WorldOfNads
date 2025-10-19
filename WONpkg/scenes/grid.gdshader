shader_type spatial;

// === User uniforms (only 3) ===
uniform vec3 base_color : source_color = vec3(1.0); // background color
uniform float grid_scale : hint_range(0.1, 50.0, 0.1) = 4.0; // how many grid cells per unit
uniform float line_width : hint_range(0.0005, 0.1, 0.0005) = 0.005; // thickness of lines (UV units)

// === Minimal outputs: matte, non-metallic ===
// (kept as constants for simplicity)
const float OUT_METALLIC = 0.0;
const float OUT_ROUGHNESS = 1.0;

varying vec2 v_uv;

void vertex() {
    // use object's UV coordinates (if mesh has UVs)
    v_uv = UV;
}

void fragment() {
    // scale UVs to control grid density
    vec2 uv = v_uv * grid_scale;

    // find distance to nearest grid line in X and Y
    vec2 grid_pos = abs(fract(uv) - 0.5);

    // the smaller of the two distances is how close we are to any orthogonal line
    float nearest = min(grid_pos.x, grid_pos.y);

    // anti-aliasing using fwidth (screen-space derivative)
    float aa = max(fwidth(uv.x), fwidth(uv.y));
    aa = max(aa, 1e-5);

    // smooth mask: 1.0 on line, 0.0 off line
    float half_width = line_width * 0.5;
    float mask = 1.0 - smoothstep(half_width - aa, half_width + aa, nearest);

    // black line color mixed over base color
    vec3 line_color = vec3(0.0);
    vec3 final_color = mix(base_color, line_color, mask);

    ALBEDO = final_color;
    METALLIC = OUT_METALLIC;
    ROUGHNESS = OUT_ROUGHNESS;
}
