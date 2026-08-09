class_name EquipmentLootRoller
extends RefCounted

const MODIFIER_ROLL_STEP := 0.1
const MINIMUM_ROLLED_BONUS := 0.1

const ALLOWED_STATS: Array[StringName] = [
	PlayerStats.STRENGTH,
	PlayerStats.SPIRIT,
	PlayerStats.VITALITY,
	PlayerStats.TECHNIQUE,
	PlayerStats.MAX_HEALTH,
	PlayerStats.PHYSICAL_ATTACK,
	PlayerStats.MAGIC_ATTACK,
	PlayerStats.PHYSICAL_DEFENSE,
]


static func roll_quality(
	rng: RandomNumberGenerator,
	common_weight: float,
	uncommon_weight: float,
	rare_weight: float
) -> StringName:
	var common := maxf(common_weight, 0.0)
	var uncommon := maxf(uncommon_weight, 0.0)
	var rare := maxf(rare_weight, 0.0)
	var total := common + uncommon + rare
	if total <= 0.0:
		return EquipmentQuality.COMMON
	var roll := rng.randf() * total
	if roll < common:
		return EquipmentQuality.COMMON
	if roll < common + uncommon:
		return EquipmentQuality.UNCOMMON
	if rare > 0.0:
		return EquipmentQuality.RARE
	return EquipmentQuality.UNCOMMON if uncommon > 0.0 else EquipmentQuality.COMMON


static func create_instance(
	definition: EquipmentDefinition,
	quality: StringName,
	instance_id: String,
	rng: RandomNumberGenerator
) -> EquipmentInstance:
	return EquipmentInstance.create(instance_id, definition, quality, roll_modifiers(definition, quality, rng))


static func roll_modifiers(
	definition: EquipmentDefinition,
	quality: StringName,
	rng: RandomNumberGenerator
) -> Array[StatModifier]:
	var result: Array[StatModifier] = []
	if definition == null:
		return result
	var bounds := _scale_bounds(quality)
	for source in definition.get_modifiers():
		if source == null or source.stat_key not in ALLOWED_STATS:
			continue
		if source.flat_bonus <= 0.0 or not is_finite(source.flat_bonus):
			continue
		var scale := rng.randf_range(bounds.x, bounds.y)
		var rolled := snappedf(source.flat_bonus * scale, MODIFIER_ROLL_STEP)
		rolled = maxf(rolled, MINIMUM_ROLLED_BONUS)
		var modifier := StatModifier.new()
		modifier.stat_key = source.stat_key
		modifier.flat_bonus = rolled
		modifier.percent_bonus = 0.0
		result.append(modifier)
	return result


static func is_valid_rolled_modifier(modifier: StatModifier) -> bool:
	return (
		modifier != null
		and modifier.stat_key in ALLOWED_STATS
		and is_finite(modifier.flat_bonus)
		and modifier.flat_bonus > 0.0
		and is_zero_approx(modifier.percent_bonus)
	)


static func _scale_bounds(quality: StringName) -> Vector2:
	match quality:
		EquipmentQuality.UNCOMMON:
			return Vector2(1.15, 1.35)
		EquipmentQuality.RARE:
			return Vector2(1.45, 1.70)
	return Vector2(0.90, 1.10)
