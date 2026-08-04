class_name EquipmentDefinition
extends Resource

@export var id: StringName
@export var display_name := ""
@export var slot: StringName
@export var weapon_type: StringName
@export var light_attack_profile: PlayerBasicAttackProfile
@export var heavy_attack_profile: PlayerBasicAttackProfile
@export var modifiers: Array[StatModifier] = []


func is_weapon() -> bool:
	return slot == EquipmentSlot.WEAPON


func is_valid() -> bool:
	if id == &"" or display_name.is_empty() or not EquipmentSlot.is_valid(slot):
		return false
	if is_weapon():
		return WeaponType.is_valid(weapon_type)
	return weapon_type == &""


func get_modifiers() -> Array[StatModifier]:
	return modifiers.duplicate()
