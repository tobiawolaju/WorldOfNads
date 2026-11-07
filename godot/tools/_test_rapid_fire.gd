# Checks rapid fire: mashing the Action button while a shot clip is still playing
# must fire every press (bullet + flash + charge spent) instead of dropping them,
# and the old clip's timer must not put the gun away under the newest shot.
#   Godot_v4.8-beta1_win64_console.exe --headless --path godot --script res://tools/_test_rapid_fire.gd
extends SceneTree

const SKIN_SCENE := "res://scenes/skin.tscn"
const GLOCK := 3

var failures: int = 0
var _started: bool = false


func _process(_delta: float) -> bool:
	if _started:
		return false
	_started = true
	_run()  # async, not awaited: _process must keep running for timers to tick
	return false


func _run() -> void:
	var world := Node3D.new()
	root.add_child(world)
	current_scene = world

	var player: Node = (load(SKIN_SCENE) as PackedScene).instantiate()
	world.add_child(player)
	await process_frame

	player.set("is_local", true)
	player.set("held_weapon_kind", GLOCK)
	player.set("held_weapon_max_uses", 10)
	player.set("held_weapon_uses", 10)
	var hand := player.get_node_or_null("Skeleton3D/BoneAttachment3D") as Node3D
	var marker := player.get_node_or_null("Skeleton3D/Marker3D") as Node3D

	# Three presses in the same frame: the first starts the clip, the other two
	# arrive while it is still playing.
	for _i in 3:
		player.call("_use_held_weapon")

	var bullets := 0
	for child in world.get_children():
		if child.has_method("launch"):
			bullets += 1
	_check("every press while the clip runs fires a bullet", bullets == 3, str(bullets))
	_check("every press spends a charge",
			int(player.get("held_weapon_uses")) == 7, str(player.get("held_weapon_uses")))
	_check("the shot clip restarts for every press",
			int(player.get("_weapon_action_generation")) == 3,
			str(player.get("_weapon_action_generation")))

	var flash: Node = player.get("_muzzle_flash")
	var flashes := 0
	if marker != null:
		for child in marker.get_children():
			if child.has_method("flash"):
				flashes += 1
	_check("rapid fire still reuses one flash", flashes == 1, str(flashes))
	_check("the flash hangs off the muzzle marker", flash != null and flash.get_parent() == marker)

	# Long enough for the newest clip (shot length + SHOOT_END_HOLD) to finish.
	await create_timer(0.7).timeout
	_check("the lock is released once the newest clip ends",
			not bool(player.get("_weapon_action_active")))
	_check("the weapon is put away after the newest clip", hand != null and not hand.visible)

	_finish()


func _finish() -> void:
	print("rapid fire selftest: %d failure(s)" % failures)
	quit(1 if failures > 0 else 0)


func _check(what: String, ok: bool, detail: String = "") -> void:
	if ok:
		print("PASS  ", what)
		return
	failures += 1
	print("FAIL  ", what, "" if detail == "" else "  (got %s)" % detail)
