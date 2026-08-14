class_name PortalDefinition
extends Resource

@export var id: StringName
@export var position := Vector2.ZERO
@export_range(24.0, 240.0, 1.0) var interaction_radius := 72.0
@export var target_map_id: StringName
@export var target_entry_id: StringName
@export var interaction_prompt := ""
@export var condition_id: StringName
@export var locked_message := ""


func is_valid() -> bool:
	return (
		id != &""
		and not position.is_equal_approx(Vector2.INF)
		and interaction_radius > 0.0
		and target_map_id != &""
		and target_entry_id != &""
	)
