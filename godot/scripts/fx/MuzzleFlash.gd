class_name MuzzleFlash
extends GPUParticles3D
## Muzzle flash that rides a weapon's muzzle Marker3D.
##
## One of these is created per player, on the first shot, and reused for every
## shot after that: `flash()` only restarts an already-built burst. That is the
## whole point - the old flash parented an OmniLight3D and a new billboard per
## shot, and creating/deleting lights is what stalled the GL Compatibility
## renderer at high fire rates. Nothing is allocated here after the first shot and
## there is no light at all: the flash is pure additive geometry.
##
## The look is the shader's job (res://assets/shaders/muzzle_flash.gdshader).
## Swap `texture_albedo` for a sprite sheet and set the h/v frame uniforms to
## animate it; with the default 1x1 gradient it is a soft additive burst.

## Called once per shot, right after the projectile leaves the muzzle.
func flash() -> void:
	visible = true
	emitting = true
	# Clears any particle still alive from the previous shot, so a fast trigger
	# shows one burst per shot instead of a smeared trail.
	restart()


func _ready() -> void:
	# Nothing shows until the first real shot.
	emitting = false
