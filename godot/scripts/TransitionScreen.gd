extends CanvasLayer

var ColorRectNode: ColorRect
var tween: Tween
var is_transitioning := false

var fog_shader_code := """
shader_type canvas_item;

uniform float progress : hint_range(0.0, 1.0) = 0.0;
uniform vec4 fog_color : source_color = vec4(0.85, 0.9, 0.95, 1.0); // light grayish-blue fog

float hash(vec2 p) {
    return fract(sin(dot(p, vec2(12.9898, 78.233))) * 43758.5453);
}

float noise(vec2 x) {
    vec2 p = floor(x);
    vec2 f = fract(x);
    f = f * f * (3.0 - 2.0 * f);
    return mix(mix(hash(p + vec2(0.0, 0.0)), hash(p + vec2(1.0, 0.0)), f.x),
               mix(hash(p + vec2(0.0, 1.0)), hash(p + vec2(1.0, 1.0)), f.x), f.y);
}

float fbm(vec2 x) {
    float v = 0.0;
    float a = 0.5;
    vec2 shift = vec2(100.0);
    mat2 rot = mat2(vec2(cos(0.5), sin(0.5)), vec2(-sin(0.5), cos(0.50)));
    for (int i = 0; i < 4; ++i) {
        v += a * noise(x);
        x = rot * x * 2.0 + shift;
        a *= 0.5;
    }
    return v;
}

void fragment() {
    float n = fbm(UV * 5.0 + vec2(TIME * 0.1, TIME * -0.05));
    // transition mapping
    float alpha = smoothstep(n - 0.2, n + 0.2, progress * 1.5 - 0.2);
    COLOR = vec4(fog_color.rgb, fog_color.a * alpha);
}
"""

func _ready() -> void:
    layer = 100 # Ensure it shows on top of everything
    
    ColorRectNode = ColorRect.new()
    ColorRectNode.set_anchors_preset(Control.PRESET_FULL_RECT)
    ColorRectNode.mouse_filter = Control.MOUSE_FILTER_IGNORE
    
    var mat = ShaderMaterial.new()
    var shader = Shader.new()
    shader.code = fog_shader_code
    mat.shader = shader
    mat.set_shader_parameter("progress", 0.0)
    ColorRectNode.material = mat
    
    add_child(ColorRectNode)

func change_scene(target_scene: String) -> void:
    if is_transitioning:
        return
    is_transitioning = true
    ColorRectNode.mouse_filter = Control.MOUSE_FILTER_STOP
    
    if tween:
        tween.kill()
    tween = create_tween()
    
    # Fog rolls in
    tween.tween_method(_update_progress, 0.0, 1.0, 0.8).set_ease(Tween.EASE_IN_OUT).set_trans(Tween.TRANS_SINE)
    
    # Scene transition
    tween.tween_callback(func():
        get_tree().change_scene_to_file(target_scene)
    )
    
    # Small pause
    tween.tween_interval(0.1)
    
    # Fog dissipates
    tween.tween_method(_update_progress, 1.0, 0.0, 0.8).set_ease(Tween.EASE_IN_OUT).set_trans(Tween.TRANS_SINE)
    
    tween.tween_callback(func():
        is_transitioning = false
        ColorRectNode.mouse_filter = Control.MOUSE_FILTER_IGNORE
    )

func _update_progress(val: float) -> void:
    if ColorRectNode.material:
        ColorRectNode.material.set_shader_parameter("progress", val)
