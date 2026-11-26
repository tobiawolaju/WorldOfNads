class_name StormDamageComponent
extends Component
## Applies storm damage when the entity is outside the storm eye radius.
##
## Reads storm zone from the entity (`storm_center`, `storm_radius`,
## `storm_damage_per_second`, `_storm_eye`) so existing scene exports stay valid.

const CHECK_INTERVAL: float = 0.1

var _check_timer: float = 0.0
var _damage_accumulator: float = 0.0


func tick(delta: float) -> void:
	if entity == null:
		return
	if bool(entity.get("_is_dead")):
		_damage_accumulator = 0.0
		return
	_check_timer += delta
	if _check_timer < CHECK_INTERVAL:
		return
	_check_timer = 0.0
	if entity.has_method("_refresh_storm_zone"):
		entity.call("_refresh_storm_zone")
	var storm_radius: float = float(entity.get("storm_radius"))
	var storm_center: Vector2 = entity.get("storm_center")
	var dps: float = float(entity.get("storm_damage_per_second"))
	var player_pos_2d := Vector2(entity.global_position.x, entity.global_position.z)
	if player_pos_2d.distance_to(storm_center) > storm_radius:
		_damage_accumulator += dps * CHECK_INTERVAL
		if _damage_accumulator >= 1.0:
			var dmg := int(_damage_accumulator)
			_damage_accumulator -= dmg
			if entity.has_method("take_damage"):
				entity.call("take_damage", dmg, entity)
	else:
		_damage_accumulator = 0.0


func reset() -> void:
	_check_timer = 0.0
	_damage_accumulator = 0.0