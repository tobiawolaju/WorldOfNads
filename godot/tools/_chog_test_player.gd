# Test double for player.gd: a real player script with the authenticated
# identity stubbed, so the CHOG gate can be exercised headlessly.
extends "res://scripts/player.gd"

var test_identity: String = "won:test"


func _chog_identity_key() -> String:
	return test_identity
