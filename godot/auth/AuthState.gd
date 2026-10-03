extends RefCounted
class_name WONAuthState

## Immutable-ish snapshot of the authenticated player.
##
## Deliberately a plain value object rather than a bag of globals: AuthManager
## holds one of these and hands out copies, so a caller can never mutate the
## live session by accident.
##
## Identity is split three ways on purpose:
##   user_id       -> stable, immutable WON account id (the database identity)
##   privy_user_id -> Privy DID (the authentication identity)
##   wallet_address -> blockchain address (NOT used as a database key)
##
## Nothing here is a credential except access_token / refresh_token, which is why
## `to_dict()` (used for persistence) and `describe()` (used for logs) are
## separate: only to_dict() ever carries the tokens.

const STATE_UNKNOWN := "unknown"
const STATE_SIGNED_OUT := "signed_out"
const STATE_RESTORING := "restoring"
const STATE_WAITING_FOR_APPROVAL := "waiting_for_approval"
const STATE_AUTHENTICATED := "authenticated"

var state: String = STATE_SIGNED_OUT
var user_id: String = ""
var username: String = ""
var privy_user_id: String = ""
var wallet_address: String = ""
## Privy-linked avatar URL (may be empty). Display data only, never an identity.
var profile_picture_url: String = ""
var access_token: String = ""
var refresh_token: String = ""
var access_token_expires_at: int = 0
var platform: String = ""
var device_id: String = ""
var profile: Dictionary = {}

func is_authenticated() -> bool:
	return state == STATE_AUTHENTICATED and not user_id.is_empty()

func is_expiring(within_seconds: int) -> bool:
	if access_token_expires_at <= 0:
		return false
	return access_token_expires_at <= (Time.get_unix_time_from_system() + within_seconds)

func is_expired() -> bool:
	return access_token_expires_at <= 0 or access_token_expires_at <= Time.get_unix_time_from_system()

## Seconds until the access token expires. 0 when unknown or already expired.
func seconds_until_expiry() -> int:
	if access_token_expires_at <= 0:
		return 0
	return maxi(0, access_token_expires_at - Time.get_unix_time_from_system())

## Payload for the refresh call. Includes the device id so the backend can
## detect a refresh token replayed from a different machine.
func to_refresh_request() -> Dictionary:
	return {
		"refresh_token": refresh_token,
		"device_id": device_id
	}

## Only shape that may be written to disk. Everything else is derivable.
func to_persisted_dict() -> Dictionary:
	return {
		"version": 1,
		"user_id": user_id,
		"username": username,
		"privy_user_id": privy_user_id,
		"wallet_address": wallet_address,
		"profile_picture_url": profile_picture_url,
		"access_token": access_token,
		"refresh_token": refresh_token,
		"access_token_expires_at": access_token_expires_at,
		"platform": platform,
		"device_id": device_id,
		"saved_at": Time.get_unix_time_from_system()
	}

## Safe for logs and error messages: tokens are reduced to a presence flag.
func describe() -> String:
	if user_id.is_empty():
		return "signed out"
	return "%s (%s) platform=%s token=%s" % [
		username if not username.is_empty() else user_id,
		user_id,
		platform if not platform.is_empty() else "?",
		"present" if not access_token.is_empty() else "none"
	]

static func from_exchange_payload(payload: Dictionary) -> WONAuthState:
	var state := WONAuthState.new()
	var user: Dictionary = payload.get("user", {}) if payload.get("user") is Dictionary else {}
	var expires_in := int(payload.get("expires_in", payload.get("token_expires_in", 0)))

	state.state = WONAuthState.STATE_AUTHENTICATED
	state.user_id = str(user.get("id", ""))
	state.username = str(user.get("username", ""))
	state.privy_user_id = str(user.get("privy_user_id", ""))
	state.wallet_address = str(user.get("wallet_address", ""))
	state.profile_picture_url = str(user.get("profile_picture_url", ""))
	state.access_token = str(payload.get("access_token", ""))
	state.refresh_token = str(payload.get("refresh_token", ""))
	state.access_token_expires_at = (
		Time.get_unix_time_from_system() + expires_in if expires_in > 0 else 0
	)
	state.profile = user.duplicate(true)
	return state

static func from_persisted_dict(data: Dictionary) -> WONAuthState:
	var state := WONAuthState.new()
	state.state = WONAuthState.STATE_RESTORING
	state.user_id = str(data.get("user_id", ""))
	state.username = str(data.get("username", ""))
	state.privy_user_id = str(data.get("privy_user_id", ""))
	state.wallet_address = str(data.get("wallet_address", ""))
	state.profile_picture_url = str(data.get("profile_picture_url", ""))
	state.access_token = str(data.get("access_token", ""))
	state.refresh_token = str(data.get("refresh_token", ""))
	state.access_token_expires_at = int(data.get("access_token_expires_at", 0))
	state.platform = str(data.get("platform", ""))
	state.device_id = str(data.get("device_id", ""))
	return state

## Drops every credential while keeping the (non-sensitive) identity fields.
func clear_tokens() -> void:
	access_token = ""
	refresh_token = ""
	access_token_expires_at = 0
	state = STATE_SIGNED_OUT