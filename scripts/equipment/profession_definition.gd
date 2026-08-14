class_name ProfessionDefinition
extends Resource

@export var id: StringName
@export var display_name := ""
@export var allowed_weapon_types: Array[StringName] = []
@export var skill_ids: Array[StringName] = []
@export var starting_equipment: Array[EquipmentDefinition] = []


func can_equip(definition: EquipmentDefinition) -> bool:
	if definition == null or not definition.is_valid():
		return false
	if not definition.is_weapon():
		return true
	return definition.weapon_type in allowed_weapon_types
