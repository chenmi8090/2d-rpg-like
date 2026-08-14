class_name CheckpointDefinition
extends Resource

@export var id: StringName
@export var display_name := ""
@export var map_id: StringName
@export var entry_id: StringName
@export var position := Vector2.ZERO
@export_range(24.0, 240.0, 1.0) var interaction_radius := 72.0


func is_valid() -> bool:
	return (
		id != &""
		and not display_name.is_empty()
		and map_id != &""
		and entry_id != &""
		and not position.is_equal_approx(Vector2.INF)
		and interaction_radius > 0.0
	)
