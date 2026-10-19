extends RefCounted
class_name WONQRProvider

## Interface for turning a login URL into a scannable QR image.
##
## This exists as a seam on purpose: the project has no QR addon installed, and
## the authentication logic must not depend on one. `WONQRGenerator` (the
## built-in, dependency-free implementation) can be swapped for a native plugin
## later by implementing the same three methods, with no change to DeviceLogin,
## Login.gd or AuthManager.
##
## Any implementation must return a crisp, high-contrast image: QR scanning fails
## outright on a soft or low-resolution render.

## Produces a QR texture for `text`. Return null to let the caller fall back.
## (`_text`/`_target_px` are unused by the no-op base; implementations use them.)
func generate(_text: String, _target_px: int = 512) -> ImageTexture:
	return null

## Whether this provider can actually render (false = dependency missing).
func is_available() -> bool:
	return false

## Human-readable name, surfaced in debug output only.
func provider_name() -> String:
	return "none"