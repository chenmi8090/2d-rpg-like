class_name PlayerStats
extends RefCounted

const STRENGTH := &"strength"
const SPIRIT := &"spirit"
const VITALITY := &"vitality"
const TECHNIQUE := &"technique"
const MAX_HEALTH := &"max_health"
const PHYSICAL_ATTACK := &"physical_attack"
const MAGIC_ATTACK := &"magic_attack"
const PHYSICAL_DEFENSE := &"physical_defense"
const CRITICAL_CHANCE := &"critical_chance"
const CRITICAL_DAMAGE := &"critical_damage"

var definition: PlayerProgressionDefinition
var level := 1
var experience := 0
var rng := RandomNumberGenerator.new()
var _modifier_sources: Dictionary = {}


func initialize(stats_definition: PlayerProgressionDefinition) -> void:
	definition = stats_definition
	if definition == null:
		definition = PlayerProgressionDefinition.new()
	level = clampi(definition.starting_level, 1, definition.maximum_level)
	experience = maxi(definition.starting_experience, 0)
	if level >= definition.maximum_level:
		experience = 0


func set_modifier_source(source_id: StringName, modifiers: Array[StatModifier]) -> void:
	_modifier_sources[source_id] = modifiers.duplicate()


func remove_modifier_source(source_id: StringName) -> void:
	_modifier_sources.erase(source_id)


func get_modifier_sources_copy() -> Dictionary:
	var copy: Dictionary = {}
	for source_id in _modifier_sources:
		var modifiers: Array = _modifier_sources[source_id]
		copy[source_id] = modifiers.duplicate()
	return copy


func set_modifier_sources(sources: Dictionary) -> void:
	_modifier_sources.clear()
	for source_id in sources:
		var modifiers: Array = sources[source_id]
		_modifier_sources[source_id] = modifiers.duplicate()


func get_stat(stat_key: StringName) -> float:
	if stat_key == STRENGTH or stat_key == SPIRIT or stat_key == VITALITY or stat_key == TECHNIQUE:
		return _attribute_value(stat_key)
	var raw := _base_or_derived_value(stat_key)
	return _apply_direct_modifiers(stat_key, raw)


func get_attribute(stat_key: StringName) -> float:
	return _attribute_value(stat_key)


func _attribute_value(stat_key: StringName) -> float:
	var level_offset := maxi(level - 1, 0)
	var raw := 0.0
	match stat_key:
		STRENGTH:
			raw = definition.starting_strength + definition.strength_per_level * level_offset
		SPIRIT:
			raw = definition.starting_spirit + definition.spirit_per_level * level_offset
		VITALITY:
			raw = definition.starting_vitality + definition.vitality_per_level * level_offset
		TECHNIQUE:
			raw = definition.starting_technique + definition.technique_per_level * level_offset
	return _apply_direct_modifiers(stat_key, raw)


func _base_or_derived_value(stat_key: StringName) -> float:
	if stat_key == STRENGTH or stat_key == SPIRIT or stat_key == VITALITY or stat_key == TECHNIQUE:
		return _attribute_value(stat_key)
	var strength := _attribute_value(STRENGTH)
	var spirit := _attribute_value(SPIRIT)
	var vitality := _attribute_value(VITALITY)
	var technique := _attribute_value(TECHNIQUE)
	match stat_key:
		MAX_HEALTH:
			return 4.0 + vitality * 2.0
		PHYSICAL_ATTACK:
			return 1.5 + strength * 0.5
		MAGIC_ATTACK:
			return 1.5 + spirit * 0.5
		PHYSICAL_DEFENSE:
			return vitality * 2.0 + strength
		CRITICAL_CHANCE:
			return clampf(0.05 + technique * 0.01, 0.0, 0.60)
		CRITICAL_DAMAGE:
			return clampf(1.35 + technique * 0.06, 1.35, 2.50)
	return 0.0


func _apply_direct_modifiers(stat_key: StringName, base_value: float) -> float:
	var flat_total := 0.0
	var percent_total := 0.0
	for source_id in _modifier_sources:
		var modifiers: Array = _modifier_sources[source_id]
		for modifier in modifiers:
			if modifier is StatModifier and modifier.stat_key == stat_key:
				flat_total += modifier.flat_bonus
				percent_total += modifier.percent_bonus
	return maxf((base_value + flat_total) * (1.0 + percent_total), 0.0)


func add_experience(amount: int) -> Dictionary:
	var old_level := level
	if amount <= 0 or definition == null:
		return {"old_level": old_level, "new_level": level, "levels_gained": 0}
	if level >= definition.maximum_level:
		experience = 0
		return {"old_level": old_level, "new_level": level, "levels_gained": 0}

	experience += amount
	while level < definition.maximum_level:
		var required := get_experience_requirement()
		if required <= 0 or experience < required:
			break
		experience -= required
		level += 1
	if level >= definition.maximum_level:
		experience = 0
	return {"old_level": old_level, "new_level": level, "levels_gained": level - old_level}


func get_experience_requirement() -> int:
	return definition.experience_to_next_level(level) if definition != null else 0


func is_max_level() -> bool:
	return definition != null and level >= definition.maximum_level


func roll_critical() -> bool:
	return rng.randf() < get_stat(CRITICAL_CHANCE)


func calculate_attack_damage(stat_key: StringName, multiplier: float, critical: bool) -> int:
	var damage := get_stat(stat_key) * maxf(multiplier, 0.0)
	if critical:
		damage *= get_stat(CRITICAL_DAMAGE)
	return maxi(floori(damage + 0.5), 1)


func calculate_physical_damage(multiplier: float, critical: bool) -> int:
	return calculate_attack_damage(PHYSICAL_ATTACK, multiplier, critical)


func calculate_magic_damage(multiplier: float, critical: bool) -> int:
	return calculate_attack_damage(MAGIC_ATTACK, multiplier, critical)


func mitigate_physical_damage(raw_damage: int) -> int:
	if raw_damage <= 0:
		return 0
	var defense := maxf(get_stat(PHYSICAL_DEFENSE), 0.0)
	var mitigated := float(raw_damage) * 100.0 / (100.0 + defense)
	return maxi(floori(mitigated + 0.5), 1)
