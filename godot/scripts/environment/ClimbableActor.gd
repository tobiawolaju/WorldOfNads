extends Area3D
class_name ClimbableActor
## Lightweight climb trigger for moving/character bodies (other players, bots).
## Add as a child of a PhysicsBody3D/CharacterBody3D so the local player can
## climb on it ("horde" stacking). Uses a simple outward normal (good enough for
## capsules/characters). Disable via `monitoring=false` for far/dormant actors.

@export var trigger_radius: float = 0.85
@export var trigger_height: float = 2.1
@export var vault_on_exit: bool = true
## Don't attach when the player is clearly standing on top of the actor.
@export var top_block_margin: float = 0.55

var _shape: CollisionShape3D
var _host: Node3D

func _ready() -> void:
	_host = get_parent() as Node3D
	collision_layer = 0
	collision_mask = 0xFFFFFFFF
	monitorable = false
	_shape = CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = trigger_radius
	cap.height = trigger_height
	_shape.shape = cap
	_shape.position = Vector3(0, trigger_height * 0.5, 0)
	add_child(_shape)
	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)
	set_physics_process(monitoring)


func set_climb_enabled(enabled: bool) -> void:
	# Nothing to do when the state already matches: the lobby calls this every
	# physics frame for every bot.
	if monitoring == enabled:
		return

	# Read the overlaps while monitoring is still on. get_overlapping_bodies()
	# is invalid on an area with monitoring disabled and would spam errors.
	var overlapping: Array[Node3D] = []
	if not enabled and monitoring:
		overlapping = get_overlapping_bodies()

	monitoring = enabled
	set_physics_process(enabled)

	if not enabled and _host != null:
		# Detach any climber if this actor becomes non-climbable.
		for body in overlapping:
			if body != null and is_instance_valid(body) and body.has_method("end_climb"):
				body.call("end_climb", _host, false, false)


func _is_climber(body: Node3D) -> bool:
	return body != null and body.has_method("begin_climb") and body.get("is_local") == true


func _on_body_entered(body: Node3D) -> void:
	if not monitoring or not _is_climber(body):
		return
	_try_attach(body)


func _on_body_exited(body: Node3D) -> void:
	if body != null and body.has_method("end_climb") and _host != null:
		body.call("end_climb", _host, false, vault_on_exit)


func _physics_process(_delta: float) -> void:
	if not monitoring or _host == null:
		return
	# Re-check overlaps (handles cases where body_entered edge didn't retrigger).
	for body in get_overlapping_bodies():
		if _is_climber(body):
			_try_attach(body)


func _try_attach(player: Node3D) -> void:
	if player == null or _host == null or not is_instance_valid(_host):
		return
	# If player is mostly above the actor, treat as standing on top, not climbing.
	var dy := player.global_position.y - _host.global_position.y
	if dy > trigger_height - top_block_margin:
		return
	var normal := _face_normal_for(player)
	if normal.length_squared() < 0.0001:
		return
	player.call("begin_climb", _host, normal)


func _face_normal_for(player: Node3D) -> Vector3:
	# Outward horizontal normal: points from actor toward the player (player hugs the face).
	var v := player.global_position - _host.global_position
	v.y = 0.0
	if v.length_squared() < 0.0001:
		return Vector3.ZERO
	var outward := v.normalized()
	# Optional sanity: if somehow nearly vertical relation, reject.
	return outward
