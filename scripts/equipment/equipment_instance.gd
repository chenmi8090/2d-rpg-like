class_name EquipmentInstance
extends RefCounted

var instance_id := ""
var definition: EquipmentDefinition
var quality := EquipmentQuality.COMMON
var modifiers: Array[StatModifier] = []


static func create(
	id: String,
	template: EquipmentDefinition,
	item_quality: StringName,
	actual_modifiers: Array[StatModifier]
) -> EquipmentInstance:
	var instance := EquipmentInstance.new()
	instance.instance_id = id
	instance.definition = template
	instance.quality = item_quality if EquipmentQuality.is_valid(item_quality) else EquipmentQuality.COMMON
	instance.modifiers = _copy_modifiers(actual_modifiers)
	return instance


static func from_snapshot(snapshot: Dictionary) -> EquipmentInstance:
	var definition := DefinitionRegistry.get_equipment(StringName(String(snapshot.get("definition_id", ""))))
	var parsed_modifiers: Array[StatModifier] = []
	var raw_modifiers := snapshot.get("modifiers", []) as Array
	for raw_modifier in raw_modifiers:
		if not raw_modifier is Dictionary:
			continue
		var modifier := StatModifier.new()
		modifier.stat_key = StringName(String(raw_modifier.get("stat_key", "")))
		modifier.flat_bonus = float(raw_modifier.get("flat_bonus", 0.0))
		modifier.percent_bonus = float(raw_modifier.get("percent_bonus", 0.0))
		parsed_modifiers.append(modifier)
	return create(
		String(snapshot.get("instance_id", "")),
		definition,
		StringName(String(snapshot.get("quality", EquipmentQuality.COMMON))),
		parsed_modifiers
	)


func to_snapshot() -> Dictionary:
	var serialized_modifiers: Array[Dictionary] = []
	for modifier in modifiers:
		if modifier == null:
			continue
		serialized_modifiers.append({
			"stat_key": String(modifier.stat_key),
			"flat_bonus": modifier.flat_bonus,
			"percent_bonus": modifier.percent_bonus,
		})
	return {
		"instance_id": instance_id,
		"definition_id": String(definition.id) if definition != null else "",
		"quality": String(quality),
		"modifiers": serialized_modifiers,
	}


func is_valid() -> bool:
	return not instance_id.is_empty() and definition != null and definition.is_valid() and EquipmentQuality.is_valid(quality)


func is_weapon() -> bool:
	return definition != null and definition.is_weapon()


func get_display_name() -> String:
	return definition.display_name if definition != null else ""


func get_slot() -> StringName:
	return definition.slot if definition != null else &""


func get_weapon_type() -> StringName:
	return definition.weapon_type if definition != null else &""


func get_light_attack_profile() -> PlayerBasicAttackProfile:
	return definition.light_attack_profile if definition != null else null


func get_heavy_attack_profile() -> PlayerBasicAttackProfile:
	return definition.heavy_attack_profile if definition != null else null


func get_modifiers() -> Array[StatModifier]:
	return _copy_modifiers(modifiers)


static func create_template_instance(id: String, template: EquipmentDefinition) -> EquipmentInstance:
	return create(id, template, EquipmentQuality.COMMON, template.get_modifiers() if template != null else [])


static func _copy_modifiers(source: Array[StatModifier]) -> Array[StatModifier]:
	var result: Array[StatModifier] = []
	for source_modifier in source:
		if source_modifier == null:
			continue
		var modifier := StatModifier.new()
		modifier.stat_key = source_modifier.stat_key
		modifier.flat_bonus = source_modifier.flat_bonus
		modifier.percent_bonus = source_modifier.percent_bonus
		result.append(modifier)
	return result
