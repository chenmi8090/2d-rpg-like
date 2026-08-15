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

const MAP_PATHS := {
	&"test_level": "res://resources/world/maps/test_level.tres",
	&"field_passage_1": "res://resources/world/maps/field_passage_1.tres",
	&"field_passage_2": "res://resources/world/maps/field_passage_2.tres",
	&"field_passage_3": "res://resources/world/maps/field_passage_3.tres",
}

const MAP_IDS: Array[StringName] = [
	&"test_level",
	&"field_passage_1",
	&"field_passage_2",
	&"field_passage_3",
]

const REGION_PATHS := {
	&"first_region": "res://resources/world/regions/first_region.tres",
}

const REGION_IDS: Array[StringName] = [
	&"first_region",
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


static func get_map(map_id: StringName) -> MapDefinition:
	var path := String(MAP_PATHS.get(map_id, ""))
	if path.is_empty():
		return null
	var definition := load(path) as MapDefinition
	if definition == null or definition.id != map_id or not definition.is_valid():
		return null
	return definition


static func get_maps() -> Array[MapDefinition]:
	var definitions: Array[MapDefinition] = []
	for map_id in MAP_IDS:
		var definition := get_map(map_id)
		if definition != null:
			definitions.append(definition)
	return definitions


static func get_region(region_id: StringName) -> RegionDefinition:
	var path := String(REGION_PATHS.get(region_id, ""))
	if path.is_empty():
		return null
	var definition := load(path) as RegionDefinition
	if definition == null or definition.id != region_id or not definition.is_valid():
		return null
	return definition


static func get_regions() -> Array[RegionDefinition]:
	var definitions: Array[RegionDefinition] = []
	for region_id in REGION_IDS:
		var definition := get_region(region_id)
		if definition != null:
			definitions.append(definition)
	return definitions


static func get_checkpoint(checkpoint_id: StringName) -> CheckpointDefinition:
	for definition in get_maps():
		var checkpoint := definition.get_checkpoint(checkpoint_id)
		if checkpoint != null:
			return checkpoint
	return null


static func validate_world() -> Dictionary:
	var regions := get_regions()
	var maps := get_maps()
	if regions.size() != REGION_IDS.size() or maps.size() != MAP_IDS.size():
		return {"ok": false, "message": "世界定义无法完整载入"}
	for region in regions:
		var default_map := get_map(region.default_map_id)
		if default_map == null or default_map.region_id != region.id:
			return {"ok": false, "message": "地区默认地图无效"}
		if region.default_checkpoint_id != &"":
			var default_checkpoint := get_checkpoint(region.default_checkpoint_id)
			if default_checkpoint == null or default_checkpoint.map_id not in region.map_ids:
				return {"ok": false, "message": "地区默认复活点无效"}
		for map_id in region.map_ids:
			var map_definition := get_map(map_id)
			if map_definition == null or map_definition.region_id != region.id:
				return {"ok": false, "message": "地区地图引用无效"}
	for map_definition in maps:
		var region := get_region(map_definition.region_id)
		if region == null or map_definition.id not in region.map_ids:
			return {"ok": false, "message": "地图地区引用无效"}
		for portal in map_definition.portals:
			var target_map := get_map(portal.target_map_id)
			if target_map == null or target_map.get_entry(portal.target_entry_id) == null:
				return {"ok": false, "message": "传送门目标无效"}
			if not portal.condition_id.is_empty() and portal.locked_message.is_empty():
				return {"ok": false, "message": "条件传送门缺少锁定提示"}
		if not ResourceLoader.exists(map_definition.scene_path, "PackedScene"):
			return {"ok": false, "message": "地图场景不存在"}
		var encounter_validation := _validate_encounter(map_definition.encounter_definition)
		if not encounter_validation.ok:
			return encounter_validation
	return {"ok": true, "message": ""}


static func _validate_encounter(encounter: EncounterDefinition) -> Dictionary:
	if encounter == null:
		return {"ok": true, "message": ""}
	for group in encounter.groups:
		if group == null:
			return {"ok": false, "message": "遭遇包含无效敌人组"}
		for spawn in group.spawns:
			if (
				spawn == null
				or spawn.enemy_definition == null
				or not spawn.local_position.is_finite()
				or is_zero_approx(spawn.facing_direction)
			):
				return {"ok": false, "message": "遭遇包含无效敌人出生点"}
	return {"ok": true, "message": ""}


static func get_equipment(equipment_id: StringName) -> EquipmentDefinition:
	var path := String(EQUIPMENT_PATHS.get(equipment_id, ""))
	if path.is_empty():
		return null
	return load(path) as EquipmentDefinition
