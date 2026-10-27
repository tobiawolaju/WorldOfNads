# Headless selftest for the SERVER-SPAWNED weapon pickups (w1..w5).
#
# The server owns a weapon's spawn spot and who carries it, exactly like a
# power-up. This proves the client half: the id -> kind table, the id the pickup
# reports, hiding a remotely held weapon, seating the server's spot, and showing
# the weapon in a REMOTE player's hand.
#
#   Godot_v4.8-beta1_win64_console.exe --headless --path godot --script res://tools/_test_server_weapon_sync.gd
# Prints FAIL lines for every broken expectation and exits non-zero if any fail.
#
# The pickup's script is reached through the instantiated scene, never through the
# `LocalPickup2` class name: a `--script` run parses this file before the project's
# autoloads are registered, and LocalPickup2.gd references the GameManager
# autoload, so naming the class here would fail to compile the whole file.
extends SceneTree

const HAND_SLOT := "Skeleton3D/BoneAttachment3D"
## Node names under the hand slot, keyed the same way skin.tscn names them.
const KIND_NAMES := {
	"sword": 1,
	"ak47": 2,
	"glock": 3,
	"Knife": 4,
	"rpg": 5,
}

var failures := 0

func _initialize() -> void:
	var pickup := (load("res://scenes/pickup2.tscn") as PackedScene).instantiate() as Node3D
	root.add_child(pickup)
	await process_frame

	# --- 1. The id roster matches the server's WEAPON_IDS. ---
	var expected := {
		"w1": 1,
		"w2": 2,
		"w3": 3,
		"w4": 4,
		"w5": 5,
	}
	var script: GDScript = pickup.get_script()
	var consts: Dictionary = script.get_script_constant_map()
	var kinds: Dictionary = consts.get("SERVER_WEAPON_KINDS", {})
	_check("LocalPickup2 maps every server weapon id", kinds.size() == expected.size())
	for item_id in expected.keys():
		_check("%s spawns weapon kind %d" % [item_id, expected[item_id]],
			int(kinds.get(item_id, 0)) == expected[item_id])
		_check("kind_for_server_id agrees on %s" % item_id,
			int(script.call("kind_for_server_id", item_id)) == expected[item_id])
	_check("an unknown id maps to NONE",
		int(script.call("kind_for_server_id", "w9")) == 0)

	var pm_script := load("res://scripts/player/PlayerManager.gd") as GDScript
	var tracked: Array = []
	if pm_script != null:
		tracked = pm_script.get_script_constant_map().get("WEAPON_ITEM_IDS", [])
	_check("PlayerManager tracks the same weapon ids",
		tracked.size() == expected.size())

	# --- 2. A pickup named after a server id reports that id. ---
	_check("a hand-placed weapon is a local prop",
		String(pickup.call("server_item_id")) == "")
	pickup.name = "w3"
	pickup.set("weapon_kind", 3)
	_check("a weapon renamed to w3 reports the server id",
		String(pickup.call("server_item_id")) == "w3")

	# --- 3. A remote hold hides the ground model and blocks a second grab. ---
	pickup.call("set_remote_held", true)
	_check("a remotely held weapon is hidden", not pickup.visible)
	_check("a remotely held weapon cannot be grabbed",
		not bool(pickup.call("can_pick_up")))
	_check("is_being_held covers a remote hold",
		bool(pickup.call("is_being_held")))
	pickup.call("set_remote_held", false)
	_check("a released weapon is grabbable again",
		bool(pickup.call("can_pick_up")))

	# --- 4. The server's spot is seated. ---
	await physics_frame
	var target := Vector3(4.0, 1.0, -6.0)
	pickup.call("apply_server_spawn", target)
	await physics_frame
	await physics_frame
	var seated: Vector3 = pickup.global_position
	_check("the server spot is applied on the horizontal plane (%.2f, %.2f)" % [seated.x, seated.z],
		absf(seated.x - target.x) < 0.01 and absf(seated.z - target.z) < 0.01)
	_check("the weapon is visible at its server spot", pickup.visible)

	# --- 5. Another player's hand shows the weapon the server says they hold. ---
	var player := (load("res://scenes/skin.tscn") as PackedScene).instantiate() as Node3D
	root.add_child(player)
	await process_frame
	player.call("show_remote_weapon", int(expected["w5"]))
	_check("show_remote_weapon shows exactly the rpg", _visible_hand_weapon(player) == "rpg")
	player.call("show_remote_weapon", 0)
	_check("show_remote_weapon(NONE) clears the hand", _visible_hand_weapon(player) == "")

	# --- 6. A spent server weapon is re-rolled by the SERVER, not locally. ---
	pickup.call("pick_up", player)
	_check("the pickup hides when grabbed", not pickup.visible)
	pickup.call("deplete_and_respawn", seated)
	_check("a spent server weapon stays hidden until the server re-seats it",
		not pickup.visible)
	pickup.call("apply_server_spawn", Vector3(-7.0, 1.0, 2.0))
	await physics_frame
	await physics_frame
	_check("the re-roll arrives through apply_server_spawn", pickup.visible)

	pickup.queue_free()
	player.queue_free()
	await process_frame
	if failures == 0:
		print("SELFTEST PASS")
		quit(0)
	else:
		print("SELFTEST FAIL: %d failure(s)" % failures)
		quit(1)


# Name of the single visible weapon model in the hand slot, or "" when none/many.
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
		print("PASS  ", what)
		return
	failures += 1
	print("FAIL: " + what)
