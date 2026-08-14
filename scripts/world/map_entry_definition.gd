class_name MapEntryDefinition
extends Resource

@export var id: StringName
@export var position := Vector2.ZERO
@export_range(-1.0, 1.0, 2.0) var facing_direction := 1.0
@export var allow_continue_fallback := true


func is_valid() -> bool:
	return id != &"" and not position.is_equal_approx(Vector2.INF)
