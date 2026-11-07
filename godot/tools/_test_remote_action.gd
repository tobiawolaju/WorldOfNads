# Headless selftest for forwarded WEAPON ACTIONS.
#
# Another player used to be a carried gun on their back and nothing else: the
# server only forwarded movement animation, so a shot was invisible. The shooter
# now stamps (act, act_seq) into update_state, the server forwards it, and every
# other client replays the clip + muzzle flash exactly once per new seq.
#
#   Godot_v4.8-beta1_win64_console.exe --headless --path godot --script res://tools/_test_remote_action.gd
# Prints FAIL lines for every broken expectation and exits non-zero if any fail.
extends SceneTree

const SKIN_SCENE := "res://scenes/skin.tscn"
const HAND_SLOT := "Skeleton3D/BoneAttachment3D"
const BACK_SLOT := "Skeleton3D/BackBoneAttachment3D"
const MUZZLE_PATH := "Skeleton3D/Marker3D"
const WEAPONS: Array[String] = ["sword", "ak47", "glock", "Knife", "rpg"]

# LocalPickup2.WeaponKind values, spelled out so the test file does not need the
# class name at --script parse time.
const SWORD := 1
const AK47 := 2

var failures: int = 0
var _started: bool = false


func _process(_delta: float) -> bool:
	if _started:
		return false
	_started = true
	_run()  # async, not awaited: the action timers need frames to tick
	return false


func _run() -> void:
	# --- 1. The shooter stamps a fresh action into update_state. ---
	var local: Node = (load(SKIN_SCENE) as PackedScene).instantiate()
	root.add_child(local)
	await process_frame
	var fake_root := FakeRoot.new()
	fake_root.ws = FakeWS.new()
	root.add_child(fake_root)
	local.set("root", fake_root)

	_check("a fresh player has no action yet", int(local.get("_weapon_action_kind")) == 0)
	_check("...and its counter is zero", int(local.get("_weapon_action_seq")) == 0)

	local.call("_start_weapon_action", "shoot")
	_check("a shot stamps action kind 1", int(local.get("_weapon_action_kind")) == 1)
	_check("a shot bumps the action counter", int(local.get("_weapon_action_seq")) == 1)

	local.call("_start_weapon_action", "hook")
	_check("a hook stamps action kind 2", int(local.get("_weapon_action_kind")) == 2)
	_check("the counter keeps moving", int(local.get("_weapon_action_seq")) == 2)

	local.call("_send_state_to_server", true)
	var packet: Variant = MsgPack.unpack(fake_root.ws.last_message)
	_check("update_state was sent", packet is Dictionary)
	if packet is Dictionary:
		_check("the packet carries the action kind", int(packet.get("act", -1)) == 2)
		_check("the packet carries the action seq", int(packet.get("act_seq", -1)) == 2)

	# --- 2. Only a new, real action replays. ---
	var pm_script := load("res://scripts/player/PlayerManager.gd") as GDScript
	_check("a new action replays once",
			bool(pm_script.call("accepts_remote_action", 0, 1, 1)))
	_check("a repeated snapshot does not replay",
			not bool(pm_script.call("accepts_remote_action", 1, 1, 1)))
	_check("an older seq never replays",
			not bool(pm_script.call("accepts_remote_action", 5, 4, 1)))
	_check("kind 0 is not an action",
			not bool(pm_script.call("accepts_remote_action", 0, 1, 0)))

	# --- 3. A remote draws, flashes and holsters. ---
	var remote := _make_remote_avatar()
	root.add_child(remote)
	await process_frame
	remote.call("show_remote_weapon", AK47)
	_check("the ak47 is carried on the back", _visible_weapon_in(remote, BACK_SLOT) == "ak47")
	_check("the hand is empty between actions", _visible_weapon_in(remote, HAND_SLOT) == "")

	remote.call("play_action", 1)
	await process_frame
	_check("a forwarded shot draws the ak47 into the hand",
			_visible_weapon_in(remote, HAND_SLOT) == "ak47")
	_check("a forwarded shot empties the back", _visible_weapon_in(remote, BACK_SLOT) == "")

	var marker := remote.get_node_or_null(MUZZLE_PATH) as Node3D
	var flashes := 0
	if marker != null:
		for child in marker.get_children():
			if child.has_method("flash"):
				flashes += 1
	_check("a forwarded shot reuses one muzzle flash", flashes == 1, str(flashes))
	var flash: Node = remote.get("_muzzle_flash")
	_check("the flash hangs off the remote's muzzle",
			flash != null and flash.get_parent() == marker)
	_check("the flash is sized for the ak47",
			flash != null and is_equal_approx((flash as Node3D).scale.x, 1.3),
			"%.2f" % ((flash as Node3D).scale.x if flash != null else 0.0))

	# A second shot while the clip is still running restarts it and keeps the gun.
	remote.call("play_action", 1)
	await process_frame
	_check("a second shot keeps the weapon drawn",
			_visible_weapon_in(remote, HAND_SLOT) == "ak47")
	await create_timer(0.7).timeout
	_check("the weapon returns to the back when the clip ends",
			_visible_weapon_in(remote, BACK_SLOT) == "ak47")
	_check("the hand is empty again", _visible_weapon_in(remote, HAND_SLOT) == "")

	# A hook is the same layer with the other clip.
	remote.call("show_remote_weapon", SWORD)
	var flash_id_before := flash.get_instance_id() if flash != null else 0
	remote.call("play_action", 2)
	await process_frame
	_check("a forwarded hook draws the sword", _visible_weapon_in(remote, HAND_SLOT) == "sword")
	var flash_after: Node = remote.get("_muzzle_flash")
	_check("a hook reuses the existing flash instead of adding one",
			flash_after != null and flash_after.get_instance_id() == flash_id_before
			and _flash_count(remote) == 1, str(_flash_count(remote)))
	await create_timer(1.6).timeout
	_check("the sword is back on the spine after the swing",
			_visible_weapon_in(remote, BACK_SLOT) == "sword")
	_check("the hand is empty after the swing", _visible_weapon_in(remote, HAND_SLOT) == "")

	# Far away the avatar is parked: an action must not wake it up.
	remote.call("set_animation_lod_enabled", false)
	remote.call("play_action", 1)
	await process_frame
	_check("a parked remote does not draw its weapon",
			_visible_weapon_in(remote, HAND_SLOT) == "")

	# Pooling: a recycled node must not keep the previous occupant's weapon.
	remote.call("set_animation_lod_enabled", true)
	remote.call("reset_remote_state")
	_check("a recycled remote carries nothing", _visible_weapon_in(remote, BACK_SLOT) == "")
	_check("a recycled remote hides its hand", _visible_weapon_in(remote, HAND_SLOT) == "")

	_finish()


## The same conversion PlayerManager runs for every other player: the skin
## scene's visuals under a RemotePlayer node, with the body dropped.
func _make_remote_avatar() -> Node3D:
	var source := (load(SKIN_SCENE) as PackedScene).instantiate()
	var remote := (load("res://scripts/player/RemotePlayer.gd") as GDScript).new() as Node3D
	remote.name = "RemoteAvatar"
	for child in source.get_children():
		source.remove_child(child)
		child.owner = null
		remote.add_child(child)
	source.free()
	return remote


func _flash_count(remote: Node) -> int:
	var marker := remote.get_node_or_null(MUZZLE_PATH) as Node3D
	if marker == null:
		return 0
	var count := 0
	for child in marker.get_children():
		if child.has_method("flash"):
			count += 1
	return count


func _visible_weapon_in(rig: Node, slot_path: String) -> String:
	var slot := rig.get_node_or_null(slot_path) as Node3D
	if slot == null or not slot.visible:
		return ""
	var found := ""
	for slot_name in WEAPONS:
		var node := slot.get_node_or_null(slot_name) as Node3D
		if node != null and node.visible:
			if found != "":
				return ""
			found = slot_name
	return found


func _finish() -> void:
	print("remote action selftest: %d failure(s)" % failures)
	quit(1 if failures > 0 else 0)


func _check(what: String, ok: bool, detail: String = "") -> void:
	if ok:
		print("PASS  ", what)
		return
	failures += 1
	print("FAIL  ", what, "" if detail == "" else "  (got %s)" % detail)


## Stands in for PlayerManager just enough for _send_state_to_server to pack and
## "send" one update_state frame.
class FakeRoot extends Node:
	var ws: FakeWS = null
	var local_skin_name: String = ""
	var _last_server_position: Vector3 = Vector3.ZERO

	func send_xp_update() -> void:
		pass


## Captures the packed frame instead of putting it on a socket.
class FakeWS:
	var last_message: PackedByteArray = PackedByteArray()

	func get_ready_state() -> int:
		return WebSocketPeer.STATE_OPEN

	func send(bytes: PackedByteArray) -> void:
		last_message = bytes
