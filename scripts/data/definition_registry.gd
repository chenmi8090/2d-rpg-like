class_name DefinitionRegistry
extends RefCounted


const PROFESSION_PATHS := {
	&"traveler": "res://resources/professions/traveler.tres",
	&"star_seeker": "res://resources/professions/star_seeker.tres",
}

const SKILL_PATHS := {
	&"astral_spirit": "res://resources/skills/astral_spirit.tres",
	&"blade_wave": "res://resources/skills/blade_wave.tres",
	&"meteor_burst": "res://resources/skills/meteor_burst.tres",
	&"power_strike": "res://resources/skills/power_strike.tres",
	&"star_bolt": "res://resources/skills/star_bolt.tres",
	&"traveler_vitality": "res://resources/skills/traveler_vitality.tres",
}

const SKILL_IDS: Array[StringName] = [
	&"blade_wave",
	&"power_strike",
	&"traveler_vitality",
	&"star_bolt",
	&"meteor_burst",
	&"astral_spirit",
]

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


static func get_skills() -> Array[SkillDefinition]:
	var definitions: Array[SkillDefinition] = []
	for skill_id in SKILL_IDS:
		var definition := get_skill(skill_id)
		if definition != null:
			definitions.append(definition)
	return definitions


static func get_skill(skill_id: StringName) -> SkillDefinition:
	var path := String(SKILL_PATHS.get(skill_id, ""))
	if path.is_empty():
		return null
	var definition := load(path) as SkillDefinition
	if definition == null or definition.id != skill_id or not definition.is_valid():
		return null
	return definition


static func get_equipment(equipment_id: StringName) -> EquipmentDefinition:
	var path := String(EQUIPMENT_PATHS.get(equipment_id, ""))
	if path.is_empty():
		return null
	return load(path) as EquipmentDefinition
