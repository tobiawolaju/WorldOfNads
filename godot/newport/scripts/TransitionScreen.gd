extends CanvasLayer

var ColorRectNode: ColorRect
var tween: Tween
var is_transitioning := false

var fog_shader_code := """
shader_type canvas_item;

uniform float progress : hint_range(0.0, 1.0) = 0.0;
uniform vec4 fog_color : source_color = vec4(0.9, 0.95, 1.0, 1.0); // very light blue/white cloud
uniform vec4 outline_color : source_color = vec4(1.0, 1.0, 1.0, 1.0); // pure white fluffy edge

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
    float n = fbm(UV * 6.0 + vec2(TIME * 0.1, TIME * -0.05));
    
    // distance from center, mapping from 0 at center to 1 at edges.
    vec2 p = UV * 2.0 - 1.0; 
    float dist = max(abs(p.x), abs(p.y)); // Square-ish mask pulls from edges
    
    // add puffiness
    float mask = dist + n * 0.6;
    
    // progress ranges 0.0 to 1.0
    float threshold = mix(1.6, -0.2, progress);
    
    // Toon-style hard edge with a slight anti-alias
    float cloud = smoothstep(threshold - 0.02, threshold + 0.02, mask);
    
    // Add an outline
    float outline_thickness = 0.12;
    float cloud_inner = smoothstep(threshold + outline_thickness - 0.02, threshold + outline_thickness + 0.02, mask);
    
    float outline = cloud - cloud_inner;
    
    vec4 final_color = mix(fog_color, outline_color, outline);
    final_color.a *= cloud;
    
    COLOR = final_color;
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
	
	# Fog rolls in from edges (1.5 seconds)
	tween.tween_method(_update_progress, 0.0, 1.0, 1.5).set_ease(Tween.EASE_IN_OUT).set_trans(Tween.TRANS_SINE)
	
	# Scene transition
	tween.tween_callback(func():
		get_tree().change_scene_to_file(target_scene)
	)
	
	# Wait half a second so the new scene has time to fully load or wake up
	tween.tween_interval(0.5)
	
	# Fog dissipates back to edges (1.5 seconds)
	tween.tween_method(_update_progress, 1.0, 0.0, 1.5).set_ease(Tween.EASE_IN_OUT).set_trans(Tween.TRANS_SINE)
	
	tween.tween_callback(func():
		is_transitioning = false
		ColorRectNode.mouse_filter = Control.MOUSE_FILTER_IGNORE
	)

func _update_progress(val: float) -> void:
	if ColorRectNode.material:
		ColorRectNode.material.set_shader_parameter("progress", val)
