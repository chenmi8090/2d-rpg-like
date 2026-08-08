class_name Hurtbox
extends Area2D

signal damaged(amount: int, source: Node, hit_direction: float)

@export var enabled := true


func receive_hit(amount: int, source: Node, hit_direction: float, metadata: Dictionary = {}) -> bool:
	if not enabled:
		return false

	var actor := owner
	if actor != null and actor.has_method("receive_hit"):
		var result: Variant
		if _method_accepts_argument_count(actor, "receive_hit", 4):
			result = actor.receive_hit(amount, source, hit_direction, metadata)
		else:
			result = actor.receive_hit(amount, source, hit_direction)
		if result is bool and not result:
			return false
	damaged.emit(amount, source, hit_direction)
	return true


func _method_accepts_argument_count(target: Object, method_name: StringName, argument_count: int) -> bool:
	for method in target.get_method_list():
		if StringName(String(method.get("name", ""))) != method_name:
			continue
		var args: Array = method.get("args", [])
		var default_args: Array = method.get("default_args", [])
		var flags := int(method.get("flags", 0))
		var accepts_vararg := (flags & METHOD_FLAG_VARARG) != 0
		return argument_count >= args.size() - default_args.size() and (accepts_vararg or argument_count <= args.size())
	return false
