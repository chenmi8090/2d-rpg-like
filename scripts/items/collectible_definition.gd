class_name CollectibleDefinition
extends Resource

@export var id: StringName
@export var display_name := ""
@export_multiline var description := ""
@export var category: StringName = BackpackCategory.OTHER
@export_range(1, 999999, 1) var stack_limit := 99
@export var color := Color("f3d66b")


func is_valid() -> bool:
	return (
		id != &""
		and not display_name.is_empty()
		and BackpackCategory.is_stackable(category)
		and stack_limit > 0
	)
