extends RefCounted
class_name ChogEligibility

## Deny-by-default ownership state for the CHOG reveal/power-up.
##
## The eligibility verdict comes from the backend (`GET
## /api/nft/chog-genesis/ownership`), which verifies the authenticated wallet on
## Monad mainnet. This class only remembers that verdict so gameplay code can
## distinguish "not checked yet" from "checked and ineligible" and can reject a
## late response that belongs to a previous account.
##
## Only ELIGIBLE authorises the CHOG input, and only in a CHOG room. `UNKNOWN`
## (not checked), `INELIGIBLE` and `ERROR` all deny.

## Keep in sync with `CHOG_ROOM` in backend-rust/src/net.rs.
const CHOG_ROOM_ID: String = "match-chog-world-order"
## How long an ownership result may authorise the input before it is re-read.
const RESULT_TTL_MS: int = 15 * 60 * 1000

enum State { UNKNOWN, ELIGIBLE, INELIGIBLE, ERROR }

var _state: int = State.UNKNOWN
## The identity key the current verdict belongs to (wallet address, or a hash of
## the web Privy token). Never an empty string while a result is held.
var _identity: String = ""
var _checked_at_ms: int = 0

## Drops the verdict and returns to deny-by-default.
func reset() -> void:
	_state = State.UNKNOWN
	_identity = ""
	_checked_at_ms = 0

func state() -> int:
	return _state

func identity() -> String:
	return _identity

## True when a verdict exists for this identity and is still within the TTL.
func has_fresh_result(identity_key: String, now_ms: int) -> bool:
	if _state == State.UNKNOWN or _checked_at_ms <= 0:
		return false
	var key := identity_key.strip_edges()
	if key == "" or key != _identity:
		return false
	return now_ms - _checked_at_ms <= RESULT_TTL_MS

## True when the caller should start a new ownership request.
func needs_check(identity_key: String, now_ms: int) -> bool:
	var key := identity_key.strip_edges()
	if key == "":
		return false
	if _state == State.UNKNOWN:
		return true
	if key != _identity:
		return true
	return now_ms - _checked_at_ms > RESULT_TTL_MS

## Stores the outcome of one check. `checked_identity` is the identity that was
## current when the request was *sent*, so a response for account A can never
## silently become account B's result: `can_activate` compares against B.
func resolve(status_code: int, has_nft: bool, checked_identity: String, now_ms: int) -> bool:
	var key := checked_identity.strip_edges()
	if key == "":
		reset()
		return false
	_identity = key
	_checked_at_ms = now_ms
	if status_code == 200:
		_state = State.ELIGIBLE if has_nft else State.INELIGIBLE
	else:
		_state = State.ERROR
	return true

## The single gate used by player.gd. Everything except a fresh ELIGIBLE verdict
## for the current identity inside a CHOG room is a denial.
func can_activate(in_chog_room: bool, identity_key: String, now_ms: int) -> bool:
	if not in_chog_room:
		return false
	if _state != State.ELIGIBLE:
		return false
	return has_fresh_result(identity_key, now_ms)
