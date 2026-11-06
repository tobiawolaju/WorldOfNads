# Checks the HUD Action button caption: PUMP while nothing is in reach, the
# authored GRAB once something is, and a held power-up still winning over both.
# The caption text is always plain white; only its alpha encodes state (half while
# the hands are empty, full while carrying or running a pickup).
#   Godot_v4.8-beta1_win64_console.exe --headless --path godot --script res://tools/_test_action_caption.gd
extends SceneTree

const BUTTONS_SCRIPT := "res://scripts/ui/buttons.gd"

## The caption's idle/active alphas, mirrored from buttons.gd so the test fails
## loudly if one side changes without the other.
const IDLE_ALPHA := 0.5
const ACTIVE_ALPHA := 1.0

var failures: int = 0


## Stands in for the local player: only the one HUD method under test.
class FakePlayer extends Node:
	var pickable: bool = false

	func has_pickable_in_range() -> bool:
		return pickable


func _initialize() -> void:
	var player := FakePlayer.new()
	player.name = "FakePlayer"
	player.add_to_group("local_player")
	root.add_child(player)

	# The Action button as the scene authors it: an "action" Label child holding the
	# stacked GRAB, which is what the HUD captures as the default caption.
	var buttons: Node = (load(BUTTONS_SCRIPT) as GDScript).new()
	var button := Button.new()
	button.name = "Action"
	var caption := Label.new()
	caption.name = "action"
	caption.text = "G\nR\nA\nB"
	button.add_child(caption)
	buttons.add_child(button)
	# Before entering the tree, so _ready() captures it.
	buttons.set("action_button", button)
	root.add_child(buttons)

	await _frames(3)
	_check("PUMP while nothing is in reach", caption.text == "P\nU\nM\nP", caption.text)
	_check_white("PUMP is white at half opacity", caption, IDLE_ALPHA)

	player.pickable = true
	_force_poll(buttons)
	await _frames(3)
	_check("GRAB once something is in reach", caption.text == "G\nR\nA\nB", caption.text)
	_check_white("GRAB is white at half opacity", caption, IDLE_ALPHA)

	# A held power-up owns the caption whatever is lying around.
	player.pickable = false
	_force_poll(buttons)
	buttons.call("show_power_up", "RUSH", Color(1.0, 0.0, 0.0), 5.0)
	await _frames(3)
	_check("a held power-up wins over PUMP", caption.text == "R\nU\nS\nH", caption.text)
	_check_white("a held power-up turns the caption white", caption, ACTIVE_ALPHA)

	# The power-up's own colour still identifies it on the ground; it no longer
	# tints the caption.
	var smog: Color = LocalPickup.POWER_UP_COLORS[LocalPickup.PowerUpMode.SMOKE_GRENADE]
	var twin: Color = LocalPickup.POWER_UP_COLORS[LocalPickup.PowerUpMode.TWIN]
	_check("SMOG is yellow on the pickup", smog.r > 0.9 and smog.g > 0.7 and smog.b < 0.3, str(smog))
	_check("TWIN is green on the pickup", twin.g > twin.r and twin.g > twin.b, str(twin))

	buttons.call("show_power_up", "", Color.WHITE, 0.0)
	_force_poll(buttons)
	await _frames(3)
	_check("PUMP returns when the power-up is gone", caption.text == "P\nU\nM\nP", caption.text)
	_check_white("PUMP drops back to half opacity", caption, IDLE_ALPHA)

	print("action caption selftest: %d failure(s)" % failures)
	quit(1 if failures > 0 else 0)


## The reach check is polled every PICKABLE_POLL_SECONDS; zeroing the countdown
## makes the next frame poll, so the test does not have to wait out real time.
func _force_poll(buttons: Node) -> void:
	buttons.set("_pickable_poll", 0.0)


## The caption must be pure white with the given alpha, in both R/G/B and alpha.
func _check_white(what: String, caption: Label, alpha: float) -> void:
	var got := caption.get_theme_color("font_color")
	_check(what, is_equal_approx(got.r, 1.0) and is_equal_approx(got.g, 1.0) \
			and is_equal_approx(got.b, 1.0) and is_equal_approx(got.a, alpha), str(got))


func _frames(count: int) -> void:
	for _i in count:
		await process_frame


func _check(what: String, ok: bool, detail: String = "") -> void:
	if ok:
		print("PASS  ", what)
		return
	failures += 1
	print("FAIL  ", what, "" if detail == "" else "  (got %s)" % detail)
