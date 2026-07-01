shader_type spatial;
render_mode blend_mix, cull_disabled, specular_disabled;

uniform vec4 color_ground : source_color = vec4(0.18, 0.12, 0.06, 1.0);
uniform vec4 color_base : source_color = vec4(0.20, 0.52, 0.14, 1.0);
uniform vec4 color_tip : source_color = vec4(0.40, 0.72, 0.22, 1.0);
uniform float height_scale : hint_range(0.1, 3.0) = 1.0;
uniform float wind_strength : hint_range(0.0, 1.5) = 0.4;
uniform float wind_freq : hint_range(0.1, 4.0) = 1.0;
uniform float noise_scale : hint_range(0.5, 8.0) = 3.0;
uniform float detail : hint_range(0.0, 1.0) = 0.6;

uniform float lod_near : hint_range(5.0, 50.0) = 15.0;
uniform float lod_far : hint_range(20.0, 150.0) = 60.0;
uniform float fade_distance : hint_range(0.0, 50.0) = 10.0;
uniform float billboard_fade : hint_range(0.0, 1.0) = 0.5;
uniform vec3 light_direction = vec3(0.0, 1.0, 0.0);

varying float v_h;
varying float v_lod;
varying float v_dist;

float hash(vec2 p) {
    return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453123);
}

float smooth_noise(vec2 p) {
    vec2 i = floor(p);
    vec2 f = fract(p);
    f = f * f * (3.0 - 2.0 * f);
    float a = hash(i);
    float b = hash(i + vec2(1.0, 0.0));
    float c = hash(i + vec2(0.0, 1.0));
    float d = hash(i + vec2(1.0, 1.0));
    return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
}

void vertex() {
    vec3 world_origin = (MODEL_MATRIX * vec4(0.0, 0.0, 0.0, 1.0)).xyz;
    vec3 cam_pos = (INV_VIEW_MATRIX * vec4(0.0, 0.0, 0.0, 1.0)).xyz;
    float dist = distance(world_origin, cam_pos);
    float lod = 1.0 - smoothstep(lod_near, lod_far, dist);
    v_lod = lod;

    vec3 pos = VERTEX;

    float bb = 1.0 - smoothstep(0.0, max(billboard_fade, 0.001), lod);
    bb = clamp(bb, 0.0, 1.0);
    if (bb > 0.001) {
        vec3 to_cam = normalize(cam_pos - world_origin);
        float target_yaw = atan(to_cam.x, to_cam.z);
        float current_yaw = atan(VERTEX.x, VERTEX.z);
        float yaw_diff = target_yaw - current_yaw;
        float ca = cos(yaw_diff * bb);
        float sa = sin(yaw_diff * bb);
        pos.x = VERTEX.x * ca - VERTEX.z * sa;
        pos.z = VERTEX.x * sa + VERTEX.z * ca;
        NORMAL = vec3(NORMAL.x * ca - NORMAL.z * sa, NORMAL.y, NORMAL.x * sa + NORMAL.z * ca);
    }

    float noise = smooth_noise(VERTEX.xz * noise_scale);
    float detail_noise = smooth_noise(VERTEX.xz * noise_scale * 4.0) * 0.3;
    float detail_lod = mix(detail_noise, 0.0, 1.0 - lod);
    float h = (noise * 0.7 + detail_lod) * height_scale;
    h *= detail + (1.0 - detail) * 0.3;
    h *= lod;
    pos.y += h;

    float wind = sin(TIME * wind_freq + VERTEX.x * 1.5 + VERTEX.z * 1.2) * wind_strength * h;
    pos.x += wind * lod;
    pos.z += cos(TIME * wind_freq * 0.7 + VERTEX.z * 2.0 + VERTEX.x * 1.8) * wind_strength * h * 0.4 * lod;

    VERTEX = pos;
    v_h = clamp(h / max(height_scale, 0.01), 0.0, 1.0);
    v_dist = dist;
}

void fragment() {
    vec3 col = mix(color_ground.rgb, color_base.rgb, smoothstep(0.0, 0.2, v_h));
    col = mix(col, color_tip.rgb, smoothstep(0.3, 1.0, v_h));

    float shadow = 0.85 + 0.15 * (1.0 - abs(NORMAL.y));
    col *= shadow;

    ALBEDO = col;
    ROUGHNESS = mix(0.95, 0.8, v_lod);

    float dist_fade = 1.0 - smoothstep(lod_near, lod_far + fade_distance, v_dist);
    ALPHA = clamp(dist_fade, 0.0, 1.0);
}
