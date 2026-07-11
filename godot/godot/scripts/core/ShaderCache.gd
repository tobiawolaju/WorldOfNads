extends Node

## ShaderCache Autoload
## Pre-caches shaders at startup to prevent runtime stuttering on web/mobile.

func _ready() -> void:
	# Removed auto-start to allow Home.gd to control it
	pass

func pre_cache_shaders() -> void:
	print("Pre-caching shaders...")
	
	# Create a temporary container that stays hidden
	var container = Node3D.new()
	container.visible = false
	add_child(container)
	
	# Create a Camera3D to "see" the meshes
	var cam = Camera3D.new()
	cam.current = true
	container.add_child(cam)
	cam.transform.origin = Vector3(0, 0, 5)
	
	# List of important scenes/materials to cache
	var mesh_paths = [
		"res://scenes/skin1.tscn",
		"res://scenes/skin2.tscn",
		"res://scenes/skin3.tscn",
		"res://scenes/skin4.tscn",
		"res://scenes/skin5.tscn",
		"res://scenes/skin6.tscn",
		"res://scenes/skin7.tscn",
		"res://scenes/skin8.tscn",
		"res://scenes/props/enviroment/bus.tscn",
		"res://scenes/waypoint.tscn"
	]
	
	for path in mesh_paths:
		if ResourceLoader.exists(path):
			var scene = load(path).instantiate()
			container.add_child(scene)
			
			if scene is Node3D:
				# Position 3D objects in front of the camera
				scene.transform.origin = Vector3(0, 0, 0)
	
	# Wait two frames for the GPU to compile the shaders
	await get_tree().process_frame
	await get_tree().process_frame
	
	# Clean up
	container.queue_free()
	print("Shader caching complete.")
