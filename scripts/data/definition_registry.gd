class_name DefinitionRegistry
extends RefCounted


const PROFESSION_PATHS := {
	&"traveler": "res://resources/professions/traveler.tres",
	&"star_seeker": "res://resources/professions/star_seeker.tres",
}

const EQUIPMENT_PATHS := {
	&"hunter_bow": "res://resources/equipment/hunter_bow.tres",
	&"iron_guard_coat": "res://resources/equipment/iron_guard_coat.tres",
	&"star_staff": "res://resources/equipment/star_staff.tres",
	&"tempered_sword": "res://resources/equipment/tempered_sword.tres",
	&"traveler_boots": "res://resources/equipment/traveler_boots.tres",
	&"traveler_cap": "res://resources/equipment/traveler_cap.tres",
	&"traveler_coat": "res://resources/equipment/traveler_coat.tres",
	&"traveler_gloves": "res://resources/equipment/traveler_gloves.tres",
	&"traveler_ring": "res://resources/equipment/traveler_ring.tres",
	&"traveler_sword": "res://resources/equipment/traveler_sword.tres",
	&"traveler_trousers": "res://resources/equipment/traveler_trousers.tres",
}


static func get_profession(profession_id: StringName) -> ProfessionDefinition:
	var path := String(PROFESSION_PATHS.get(profession_id, ""))
	if path.is_empty():
		return null
	return load(path) as ProfessionDefinition


static func get_professions() -> Array[ProfessionDefinition]:
	var definitions: Array[ProfessionDefinition] = []
	for profession_id in [&"traveler", &"star_seeker"]:
		var definition := get_profession(profession_id)
		if definition != null:
			definitions.append(definition)
	return definitions


static func get_equipment(equipment_id: StringName) -> EquipmentDefinition:
	var path := String(EQUIPMENT_PATHS.get(equipment_id, ""))
	if path.is_empty():
		return null
	return load(path) as EquipmentDefinition
