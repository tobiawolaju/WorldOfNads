# Headless selftest for LocalPickup2 (weapon pickups) and the hand-mesh switching
# it drives in skin.tscn.
#   Godot_v4.8-beta1_win64_console.exe --headless --path godot --script res://tools/_test_weapon_pickup.gd
# Prints FAIL lines for every broken expectation and exits non-zero if any fail.
extends SceneTree

const HAND_SLOT := "Skeleton3D/BoneAttachment3D"
const KIND_NAMES := {
	"sword": 1,
	"ak47": 2,
	"glock": 3,
	"Knife": 4,
	"rpg": 5,
}

var failures := 0

func _initialize() -> void:
	# --- 1. The scene runs the weapon script and shows exactly one model. ---
	var pickup := (load("res://scenes/pickup2.tscn") as PackedScene).instantiate() as Node3D
	_check("pickup2 uses LocalPickup2", pickup != null and pickup.get_script() != null
		and String(pickup.get_script().resource_path).ends_with("LocalPickup2.gd"))
	root.add_child(pickup)
	await process_frame

	_check("default kind is SWORD", int(pickup.get("weapon_kind")) == 1)
	_check("default uses is 8", int(pickup.get("uses")) == 8)
	_check("only sword visible by default", _visible_model_name(pickup) == "sword")

	for kind_name in KIND_NAMES.keys():
		var kind: int = KIND_NAMES[kind_name]
		pickup.set("weapon_kind", kind)
		_check("kind %d shows only %s" % [kind, kind_name], _visible_model_name(pickup) == kind_name)
		_check("kind %d uses the 4-letter FIRE caption" % kind,
			str(pickup.call("weapon_label")) == "FIRE")
		_check("kind %d uses the #ff6cff action colour" % kind,
			(pickup.call("weapon_color") as Color).is_equal_approx(Color(1.0, 0.42352942, 1.0)))

	# The pickup may bob, but it must never spin.
	await process_frame
	await process_frame
	var pivot := pickup.get_node_or_null("WeaponPivot") as Node3D
	_check("weapon models do not spin", pivot != null and is_zero_approx(pivot.rotation.y))

	# --- 2. Picking up hides the ground model and reports a local hold. ---
	var holder := Node3D.new()
	root.add_child(holder)
	pickup.set("weapon_kind", 2)  # AK47
	_check("pickable before grab", bool(pickup.call("can_pick_up")))
	_check("pick_up succeeds", bool(pickup.call("pick_up", holder)))
	_check("pickup hidden while held", not (pickup as Node3D).visible)
	_check("is_being_held true", bool(pickup.call("is_being_held")))
	_check("cannot grab twice", not bool(pickup.call("pick_up", holder)))

	# --- 3. Spending the last charge recycles the pickup far away. ---
	# The respawn probe needs a real physics space, which is only reachable from
	# inside a physics frame.
	await physics_frame
	var from := (pickup as Node3D).global_position
	pickup.call("deplete_and_respawn", from + Vector3(1.0, 0.0, 0.0))
	_check("pickup visible again after deplete", (pickup as Node3D).visible)
	_check("pickup no longer held", not bool(pickup.call("is_being_held")))
	# The probe itself runs on the next physics frame: Jolt refuses a space query
	# while the physics step owns the space, so the new spot lands a frame later.
	await physics_frame
	await physics_frame
	var moved := (pickup as Node3D).global_position.distance_to(from + Vector3(1.0, 0.0, 0.0))
	_check("pickup respawns far away (moved %.1f)" % moved, moved >= 20.0)

	# --- 4. skin.tscn exposes exactly one hand weapon at a time. ---
	var player := (load("res://scenes/skin.tscn") as PackedScene).instantiate() as Node3D
	for kind_name in KIND_NAMES.keys():
		var kind: int = KIND_NAMES[kind_name]
		player.call("_set_weapon_visual", kind)
		_check("skin shows only %s for kind %d" % [kind_name, kind], _visible_hand_weapon(player) == kind_name)
	player.call("_set_weapon_visual", 0)
	_check("skin hides every weapon for NONE", _visible_hand_weapon(player) == "")

	# --- 5. The HUD ring treats charges as its fraction, one step per use. ---
	var hud: Object = (load("res://scripts/ui/buttons.gd") as GDScript).new()
	hud.call("show_power_up", "AK47", Color.WHITE, 0.0, 8, 8)
	_check("hud ring full at 8/8", bool(hud.get("_ring_active"))
		and is_equal_approx(float(hud.get("_ring_remaining")), 8.0)
		and is_equal_approx(float(hud.get("_ring_duration")), 8.0))
	hud.call("show_power_up", "AK47", Color.WHITE, 0.0, 1, 8)
	_check("hud ring shows 1/8", is_equal_approx(float(hud.get("_ring_remaining")), 1.0)
		and not bool(hud.get("_ring_held_ready")))
	hud.call("show_power_up", "", Color.WHITE, 0.0, -1, 0)
	_check("hud ring clears when the weapon is spent", not bool(hud.get("_ring_active")))
	hud.free()

	# --- 6. End-to-end: grab -> hand mesh -> 8 uses -> respawn. ---
	root.add_child(player)
	await process_frame
	player.set("last_pickup_request_ms", -100000)
	pickup.set("weapon_kind", 2)
	pickup.set("freeze", true)
	(pickup as Node3D).global_position = player.global_position + Vector3(1.2, 0.0, 0.0)
	_check("player grabs the nearby weapon", bool(player.call("_try_pickup_weapon")))
	_check("player holds AK47", int(player.get("held_weapon_kind")) == 2)
	_check("grab starts at 8 uses", int(player.get("held_weapon_uses")) == 8
		and int(player.get("held_weapon_max_uses")) == 8)
	_check("ak47 shown in hand after grab", _visible_hand_weapon(player) == "ak47")
	_check("ground pickup hidden after grab", not (pickup as Node3D).visible)

	for _i in 7:
		player.call("_use_held_weapon")
	_check("after 7 uses one charge remains", int(player.get("held_weapon_uses")) == 1)
	_check("weapon still in hand with one charge", _visible_hand_weapon(player) == "ak47")

	await physics_frame
	player.call("_use_held_weapon")
	_check("last use clears the held weapon", int(player.get("held_weapon_kind")) == 0
		and int(player.get("held_weapon_uses")) == 0)
	_check("hand is empty after the last use", _visible_hand_weapon(player) == "")
	_check("pickup visible again after the last use", (pickup as Node3D).visible
		and not bool(pickup.call("is_being_held")))
	# Same one-physics-frame deferral as section 3.
	await physics_frame
	await physics_frame
	var respawned := (pickup as Node3D).global_position.distance_to(player.global_position)
	_check("pickup respawned away from the player (%.1f m)" % respawned, respawned >= 20.0)

	player.queue_free()
	holder.queue_free()
	pickup.queue_free()
	await process_frame
	if failures == 0:
		print("SELFTEST PASS")
		quit(0)
	else:
		print("SELFTEST FAIL: %d failure(s)" % failures)
		quit(1)


# Name of the single visible weapon model on the pickup, or "" when none/many.
# The models are re-parented under WeaponPivot by _ready, but must also be found
# before that (editor preview / instantiated but not yet in the tree).
func _visible_model_name(pickup: Node) -> String:
	var found := ""
	for kind_name in KIND_NAMES.keys():
		var node := pickup.get_node_or_null("WeaponPivot/" + String(kind_name)) as Node3D
		if node == null:
			node = pickup.get_node_or_null(String(kind_name)) as Node3D
		if node != null and node.visible:
			if found != "":
				return ""
			found = String(kind_name)
	return found


func _visible_hand_weapon(player: Node) -> String:
	var slot := player.get_node_or_null(HAND_SLOT) as Node3D
	if slot == null:
		_check("missing hand slot " + HAND_SLOT, false)
		return ""
	var found := ""
	for kind_name in KIND_NAMES.keys():
		var node := slot.get_node_or_null(String(kind_name)) as Node3D
		if node != null and node.visible:
			if found != "":
				return ""
			found = String(kind_name)
	return found


func _check(what: String, ok: bool) -> void:
	if ok:
		return
	failures += 1
	print("FAIL: " + what)
