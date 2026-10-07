shader_type spatial;
render_mode cull_disabled, depth_draw_opaque, shadows_disabled;

// Procedural mouth wobble - vertex displacement in the mouth UV region.
// Mirrors the three.js version in frontend/src/components/ThreeScene.tsx.
// The nad.fbx head mesh (Cube) has face UVs at U=[0.25,0.75], V=[0.375,0.875].
// Mouth occupies roughly the lower 35% of that V range.

uniform float wobble_amp = 0.008;       // max vertex offset (world units)
uniform float wobble_freq = 0.7;        // breathing frequency (Hz)
uniform float wobble_speech_amp = 0.0;  // speech layer (drive externally for lip-sync)
uniform float wobble_speech_freq = 8.0;

// Mouth UV bounds in the head atlas (matches three.js)
uniform vec2 mouth_uv_min = vec2(0.25, 0.375);
uniform vec2 mouth_uv_max = vec2(0.75, 0.545);

void vertex() {
    // UV-relative position inside the mouth rectangle
    vec2 mouth_rel = (UV - mouth_uv_min) / (mouth_uv_max - mouth_uv_min);

    // Smooth mask: 1.0 inside mouth, 0.0 outside with soft edges
    float in_mouth = smoothstep(0.0, 0.05, mouth_rel.y)
                     * smoothstep(1.0, 0.95, mouth_rel.y)
                     * smoothstep(0.0, 0.08, mouth_rel.x)
                     * smoothstep(1.0, 0.92, mouth_rel.x);

    // Breathing wave (slow) + optional speech wobble (fast)
    float breath = sin(TIME * wobble_freq * 6.28318) * 0.5 + 0.5;
    float speech = sin(TIME * wobble_speech_freq * 6.28318) * 0.5 + 0.5;
    float disp = (breath * wobble_amp + speech * wobble_speech_amp) * in_mouth;

    // Displace along normal
    VERTEX += NORMAL * disp;
}

void fragment() {
    // Standard unlit face rendering - albedo from vertex color or material
    ALBEDO = vec3(1.0);
    // If the mesh has vertex colors or a texture, they'll be used via the material
    // This shader only adds vertex displacement; the material handles color.
    // For a textured face, add: ALBEDO = texture(albedo_tex, UV).rgb;
}