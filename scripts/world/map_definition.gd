class_name MapDefinition
extends Resource

@export var id: StringName
@export var region_id: StringName
@export var display_name := ""
@export_file("*.tscn") var scene_path := ""
@export var default_entry_id: StringName
@export var allow_continue := true
@export var camera_bounds := Rect2(-400.0, -200.0, 3800.0, 920.0)
@export var encounter_definition: EncounterDefinition
@export var entries: Array[MapEntryDefinition] = []
@export var portals: Array[PortalDefinition] = []
@export var checkpoints: Array[CheckpointDefinition] = []


func get_entry(entry_id: StringName) -> MapEntryDefinition:
	for entry in entries:
		if entry != null and entry.id == entry_id:
			return entry
	return null


func get_portal(portal_id: StringName) -> PortalDefinition:
	for portal in portals:
		if portal != null and portal.id == portal_id:
			return portal
	return null


func get_checkpoint(checkpoint_id: StringName) -> CheckpointDefinition:
	for checkpoint in checkpoints:
		if checkpoint != null and checkpoint.id == checkpoint_id:
			return checkpoint
	return null


func is_valid() -> bool:
	if (
		id == &""
		or region_id == &""
		or display_name.is_empty()
		or scene_path.is_empty()
		or default_entry_id == &""
	):
		return false
	var entry_ids: Dictionary = {}
	for entry in entries:
		if entry == null or not entry.is_valid() or entry_ids.has(entry.id):
			return false
		entry_ids[entry.id] = true
	if not entry_ids.has(default_entry_id):
		return false
	var portal_ids: Dictionary = {}
	for portal in portals:
		if portal == null or not portal.is_valid() or portal_ids.has(portal.id):
			return false
		portal_ids[portal.id] = true
	var checkpoint_ids: Dictionary = {}
	for checkpoint in checkpoints:
		if (
			checkpoint == null
			or not checkpoint.is_valid()
			or checkpoint.map_id != id
			or not entry_ids.has(checkpoint.entry_id)
			or checkpoint_ids.has(checkpoint.id)
		):
			return false
		checkpoint_ids[checkpoint.id] = true
	return true
