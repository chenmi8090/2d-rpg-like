class_name RegionDefinition
extends Resource

@export var id: StringName
@export var display_name := ""
@export var default_map_id: StringName
@export var default_checkpoint_id: StringName
@export var map_ids: Array[StringName] = []


func is_valid() -> bool:
	if id == &"" or display_name.is_empty() or default_map_id == &"":
		return false
	if default_map_id not in map_ids:
		return false
	var seen: Dictionary = {}
	for map_id in map_ids:
		if map_id == &"" or seen.has(map_id):
			return false
		seen[map_id] = true
	return true
