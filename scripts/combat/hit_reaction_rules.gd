class_name HitReactionRules
extends RefCounted


static func damage_ratio(damage: int, maximum_health: int) -> float:
	return float(maxi(damage, 0)) / float(maxi(maximum_health, 1))


static func qualifies_for_knockback(
	damage: int,
	maximum_health: int,
	damage_ratio_threshold: float,
	metadata: Dictionary = {}
) -> bool:
	if damage <= 0:
		return false
	if bool(metadata.get("force_knockback", false)):
		return true
	if bool(metadata.get("is_critical", false)):
		return true
	return damage_ratio(damage, maximum_health) >= maxf(damage_ratio_threshold, 0.0)


static func resolve_knockback_speed(default_speed: float, metadata: Dictionary = {}) -> float:
	return maxf(
		maxf(default_speed, 0.0),
		maxf(float(metadata.get("minimum_knockback_speed", 0.0)), 0.0)
	)
